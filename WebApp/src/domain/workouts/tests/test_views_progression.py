import json

from django.test import TestCase, Client

from domain.accounts.models import User, CoachProfile
from domain.workouts.models import (
    Exercise, ProgressionRule, WeeklyValue, WeekDefinition, WorkoutPlan,
)


class ProgressionSaveFlowTest(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@x.com',
            password_hash='x',
            role='COACH',
        )
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='C', last_name='X',
            professional_type='COACH',
        )
        self.exercise = Exercise.objects.create(name='Squat', slug='squat')
        self.client_app = Client()
        # Custom session-based auth: set `user_id` in session.
        session = self.client_app.session
        session['user_id'] = self.user.id
        session.save()

    def _save_payload(self, payload, plan_id=None):
        url = f'/api/allenamenti/{plan_id}/save/' if plan_id else '/api/allenamenti/save/'
        return self.client_app.post(
            url, data=json.dumps(payload), content_type='application/json'
        )

    def test_full_flow_with_progression(self):
        # Step 1: create plan
        r1 = self._save_payload({
            'title': 'Blocco 4 sett',
            'frequency_per_week': 1,
            'duration_weeks': 4,
            'last_step': 1,
            'days': [],
        })
        self.assertEqual(r1.status_code, 200)
        plan_id = r1.json()['plan']['id']

        # Step 2: add a day + exercise
        r2 = self._save_payload({
            'title': 'Blocco 4 sett',
            'frequency_per_week': 1,
            'duration_weeks': 4,
            'last_step': 2,
            'days': [{
                'pk': None,
                'local_id': 'day-1',
                'order': 1,
                'name': 'Push',
                'exercises': [{
                    'pk': None,
                    'local_id': 'ex-1',
                    'exercise_id': self.exercise.id,
                    'order': 1,
                    'sets': 4,
                    'reps': '8',
                    'load_value': 80,
                    'load_unit': 'KG',
                    'recovery_seconds': 120,
                    'notes': '',
                    'superset_group_id': None,
                }],
            }],
        }, plan_id=plan_id)
        self.assertEqual(r2.status_code, 200)
        plan = r2.json()['plan']
        self.assertEqual(len(plan['days']), 1)
        self.assertEqual(len(plan['days'][0]['exercises']), 1)
        ex_pk = plan['days'][0]['exercises'][0]['pk']

        # Week definitions auto-created.
        self.assertEqual(WeekDefinition.objects.filter(workout_plan_id=plan_id).count(), 4)

        # WeeklyValue rows for week 1..4 with base values.
        wvs = WeeklyValue.objects.filter(workout_exercise_id=ex_pk).order_by('week_number')
        self.assertEqual(wvs.count(), 4)
        for wv in wvs:
            self.assertEqual(float(wv.load_value), 80.0)

        # Step 3: add progression — LOAD_LINEAR +2.5
        r3 = self._save_payload({
            'title': 'Blocco 4 sett',
            'frequency_per_week': 1,
            'duration_weeks': 4,
            'last_step': 3,
            'days': plan['days'],  # round-trip
            'progression': {
                'weeks': [
                    {'week_number': 1, 'week_type': 'STANDARD'},
                    {'week_number': 2, 'week_type': 'STANDARD'},
                    {'week_number': 3, 'week_type': 'STANDARD'},
                    {'week_number': 4, 'week_type': 'DELOAD'},
                ],
                'rules': [{
                    'workout_exercise_id': ex_pk,
                    'order_index': 0,
                    'family': 'LOAD',
                    'subtype': 'LOAD_LINEAR',
                    'target_metric': 'load',
                    'application_mode': 'FIXED_INCREMENT',
                    'start_week': 1,
                    'end_week': 4,
                    'parameters': {'delta': 2.5, 'unit': 'KG', 'every_n_weeks': 1},
                    'stackable': True,
                    'conflict_strategy': 'LAST_WINS',
                }],
                'overrides': [],
            },
        }, plan_id=plan_id)
        self.assertEqual(r3.status_code, 200, r3.content)

        prog = r3.json()['plan']['progression']
        self.assertEqual(len(prog['rules']), 1)
        computed = prog['computed'][str(ex_pk)]
        self.assertEqual(float(computed['1']['load_value']), 80.0)
        self.assertEqual(float(computed['2']['load_value']), 82.5)
        self.assertEqual(float(computed['3']['load_value']), 85.0)
        # Week 4 is deload — load_factor 0.6 applied after rule output (87.5 * 0.6 = 52.5).
        self.assertTrue(computed['4']['is_deload'])
        self.assertAlmostEqual(float(computed['4']['load_value']), 52.5, places=2)

        # Step 4: shrink duration → rules truncated.
        r4 = self._save_payload({
            'title': 'Blocco 4 sett',
            'frequency_per_week': 1,
            'duration_weeks': 2,
            'last_step': 3,
            'days': plan['days'],
            'progression': prog,
        }, plan_id=plan_id)
        self.assertEqual(r4.status_code, 200)
        new_prog = r4.json()['plan']['progression']
        self.assertEqual(len(new_prog['weeks']), 2)
        self.assertEqual(WeeklyValue.objects.filter(workout_exercise_id=ex_pk).count(), 2)
        rule = ProgressionRule.objects.get(workout_exercise_id=ex_pk)
        self.assertEqual(rule.end_week, 2)
