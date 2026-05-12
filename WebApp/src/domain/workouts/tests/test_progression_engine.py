from decimal import Decimal

from django.test import TestCase

from domain.accounts.models import User, CoachProfile
from domain.workouts.models import (
    Exercise,
    ProgressionRule,
    WeekDefinition,
    WeeklyOverride,
    WorkoutDay,
    WorkoutExercise,
    WorkoutPlan,
)
from domain.workouts import progression_engine


def _plan_with_exercise(weeks=4, load=Decimal('80'), sets=4, rep_range='8', rpe=None,
                        load_unit='KG', rest=120):
    user = User.objects.create(email=f't{User.objects.count()}@x.com', password_hash='x', role='COACH')
    coach = CoachProfile.objects.create(user=user, first_name='C', last_name='X', professional_type='COACH')
    plan = WorkoutPlan.objects.create(coach=coach, title='Test', duration_weeks=weeks)
    day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='G1')
    ex_def = Exercise.objects.create(name=f'Squat{Exercise.objects.count()}', slug=f'squat-{Exercise.objects.count()}')
    ex = WorkoutExercise.objects.create(
        workout_day=day, exercise=ex_def, order_index=1,
        set_count=sets, rep_range=rep_range, load_value=load, load_unit=load_unit,
        recovery_seconds=rest, rpe=rpe,
    )
    return plan, ex


class LoadLinearTest(TestCase):
    def test_linear_load_4_weeks_plus_2_5(self):
        plan, ex = _plan_with_exercise(weeks=4, load=Decimal('80'))
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='LOAD', subtype='LOAD_LINEAR', target_metric='load',
            application_mode='FIXED_INCREMENT', start_week=1,
            parameters={'delta': 2.5, 'unit': 'KG', 'every_n_weeks': 1},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        loads = [float(result['computed'][ex.id][w]['load_value']) for w in range(1, 5)]
        self.assertEqual(loads, [80.0, 82.5, 85.0, 87.5])


class DoubleProgressionTest(TestCase):
    def test_vol_double_8_to_12_then_load_bump(self):
        # rep_low=8, rep_high=12 → cycle length 5. Weeks 1..5 fill the cycle; week 6 wraps.
        plan, ex = _plan_with_exercise(weeks=6, load=Decimal('100'))
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='VOLUME', subtype='VOL_DOUBLE', target_metric='reps',
            application_mode='RULE_BASED', start_week=1,
            parameters={'rep_low': 8, 'rep_high': 12, 'load_step': 2.5},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        cells = result['computed'][ex.id]
        self.assertEqual(cells[1]['rep_range'], '8')
        self.assertEqual(cells[5]['rep_range'], '12')
        self.assertEqual(cells[6]['rep_range'], '8')
        self.assertEqual(float(cells[5]['load_value']), 100.0)
        self.assertEqual(float(cells[6]['load_value']), 102.5)


class WupTest(TestCase):
    def test_wup_overrides_rep_range_and_rpe_per_week(self):
        plan, ex = _plan_with_exercise(weeks=4)
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='UNDULATION', subtype='UND_WUP', target_metric='rep_range',
            application_mode='EXPLICIT_VALUES', start_week=1,
            parameters={'by_week': {'1': 'HYPERTROPHY', '2': 'STRENGTH', '3': 'POWER', '4': 'DELOAD'}},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        cells = result['computed'][ex.id]
        self.assertEqual(cells[1]['rep_range'], '8-12')
        self.assertEqual(cells[2]['rep_range'], '3-5')
        self.assertEqual(cells[3]['rep_range'], '2-4')
        self.assertTrue(cells[4]['is_deload'])


class DeloadAutoTest(TestCase):
    def test_del_auto_marks_deload_and_cuts_load(self):
        plan, ex = _plan_with_exercise(weeks=8, load=Decimal('100'))
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='DELOAD', subtype='DEL_AUTO', target_metric='load',
            application_mode='RULE_BASED', start_week=1,
            parameters={'on_weeks': [4, 8], 'load_factor': 0.6, 'volume_factor': 0.5, 'rpe_cap': 6},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        cells = result['computed'][ex.id]
        self.assertAlmostEqual(float(cells[4]['load_value']), 60.0, places=2)
        self.assertAlmostEqual(float(cells[8]['load_value']), 60.0, places=2)
        self.assertTrue(cells[4]['is_deload'])
        self.assertEqual(float(cells[1]['load_value']), 100.0)
        self.assertFalse(cells[1]['is_deload'])


class OverrideWinsTest(TestCase):
    def test_override_overrides_rule_output(self):
        plan, ex = _plan_with_exercise(weeks=4, load=Decimal('80'))
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='LOAD', subtype='LOAD_LINEAR', target_metric='load',
            application_mode='FIXED_INCREMENT', start_week=1,
            parameters={'delta': 2.5, 'every_n_weeks': 1},
        )
        WeeklyOverride.objects.create(
            workout_exercise=ex, week_number=3, metric='load',
            value_json={'value': 90, 'unit': 'KG'},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        cells = result['computed'][ex.id]
        # Rule alone would yield 85 at week 3; override forces 90.
        self.assertEqual(float(cells[3]['load_value']), 90.0)
        self.assertTrue(cells[3]['is_override'])
        # Week 2 untouched.
        self.assertEqual(float(cells[2]['load_value']), 82.5)


class ConflictDetectionTest(TestCase):
    def test_two_error_rules_same_metric_surface_conflict(self):
        plan, ex = _plan_with_exercise(weeks=4)
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='LOAD', subtype='LOAD_LINEAR', target_metric='load',
            application_mode='FIXED_INCREMENT', start_week=1, order_index=0,
            parameters={'delta': 2.5, 'every_n_weeks': 1},
            conflict_strategy='ERROR',
        )
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='LOAD', subtype='LOAD_LINEAR', target_metric='load',
            application_mode='FIXED_INCREMENT', start_week=1, order_index=1,
            parameters={'delta': 5.0, 'every_n_weeks': 1},
            conflict_strategy='ERROR',
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        self.assertGreaterEqual(len(result['conflicts']), 4)  # one per active week
        # LAST_WINS-style ordering: order_index=1 wins.
        cells = result['computed'][ex.id]
        self.assertEqual(float(cells[2]['load_value']), 85.0)


class DensityRestTest(TestCase):
    def test_rest_reduces_with_floor(self):
        plan, ex = _plan_with_exercise(weeks=5, rest=120)
        ProgressionRule.objects.create(
            workout_plan=plan, workout_exercise=ex,
            family='DENSITY', subtype='DEN_REST', target_metric='rest',
            application_mode='FIXED_INCREMENT', start_week=1,
            parameters={'delta_seconds': -15, 'min_seconds': 60, 'every_n_weeks': 1},
        )
        progression_engine.sync_week_definitions(plan)
        result = progression_engine.compute_weekly_values(plan)
        cells = result['computed'][ex.id]
        self.assertEqual(cells[1]['recovery_seconds'], 120)
        self.assertEqual(cells[2]['recovery_seconds'], 105)
        self.assertEqual(cells[5]['recovery_seconds'], 60)  # clamped to floor
