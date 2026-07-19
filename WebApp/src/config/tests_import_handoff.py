"""Import confirm → real builder handoff.

Importing no longer ends in its own review screen: it saves a DRAFT and sends the
coach into the builder that matches the plan's shape. These tests pin the two
things that can silently break that promise — the redirect target, and the
builder's ability to actually open what the import wrote.

They also pin that an athlete is optional throughout, which is the behaviour the
upload form used to block in JS while the backend allowed it.
"""

import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from domain.accounts.models import User, CoachProfile
from domain.nutrition.models import Food, NutritionPlan
from domain.workouts.models import Exercise, WorkoutPlan


def _coach(email='coach@example.com'):
    user = User.objects.create(
        email=email, password_hash=make_password('x'),
        role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=user, first_name='Marco', last_name='Rossi',
        professional_type='COACH', platform_subscription_status='ACTIVE')


class ImportHandoffTestCase(TestCase):
    def setUp(self):
        self.coach = _coach()
        session = self.client.session
        session['user_id'] = self.coach.user.id
        session['user_role'] = 'COACH'
        session.save()


class WorkoutImportHandoffTests(ImportHandoffTestCase):
    def setUp(self):
        super().setUp()
        self.squat = Exercise.objects.create(name='barbell squat', slug='barbell-squat')
        self.bench = Exercise.objects.create(name='barbell bench press', slug='barbell-bench-press')

    def _confirm(self, **overrides):
        payload = {
            'plan_title': 'Push Pull Legs',
            'plan_kind': 'WEEKLY',
            'workout_json': {
                'sessions': [{
                    'day_label': 'Lower',
                    'blocks': [{
                        'block_type': 'straight',
                        'exercises': [
                            {'raw_name': 'Squat con bilanciere',
                             'matched_exercise_id': self.squat.id, 'sets': 4, 'reps': 6},
                            {'raw_name': 'Panca piana con bilanciere',
                             'matched_exercise_id': self.bench.id, 'sets': 3, 'reps': 8},
                        ],
                    }],
                }],
            },
        }
        payload.update(overrides)
        return self.client.post(
            '/api/allenamenti/import/conferma/',
            data=json.dumps(payload), content_type='application/json')

    def test_saves_without_an_athlete(self):
        res = self._confirm()
        self.assertEqual(res.status_code, 200, res.content)
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.status, WorkoutPlan.STATUS_DRAFT)
        self.assertEqual(plan.days.count(), 1)
        self.assertEqual(plan.days.get().exercises.count(), 2)

    def test_redirects_into_the_wizard(self):
        res = self._confirm()
        plan_id = res.json()['plan_id']
        self.assertEqual(res.json()['redirect_url'], f'/allenamenti/wizard/{plan_id}/')

    def test_wizard_opens_the_imported_plan_on_the_builder_step(self):
        res = self._confirm()
        plan_id = res.json()['plan_id']
        page = self.client.get(f'/allenamenti/wizard/{plan_id}/')
        self.assertEqual(page.status_code, 200)
        # last_step drives which wizard pane opens; step 1 would make the coach
        # walk back through the metadata the import already collected.
        self.assertEqual(WorkoutPlan.objects.get(id=plan_id).last_step, 3)

    def test_program_kind_is_honoured(self):
        res = self._confirm(plan_kind='PROGRAM', duration_weeks=6)
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, WorkoutPlan.KIND_PROGRAM)
        self.assertEqual(plan.duration_weeks, 6)

    def test_unmatched_exercise_is_refused(self):
        res = self._confirm(workout_json={
            'sessions': [{
                'day_label': 'Lower',
                'blocks': [{'block_type': 'straight', 'exercises': [
                    {'raw_name': 'Qualcosa di illeggibile', 'matched_exercise_id': None},
                ]}],
            }],
        })
        self.assertEqual(res.status_code, 400)
        self.assertEqual(res.json()['error'], 'unmatched_exercises')
        self.assertEqual(WorkoutPlan.objects.count(), 0)


class DietImportHandoffTests(ImportHandoffTestCase):
    def setUp(self):
        super().setUp()
        self.food = Food.objects.create(
            nome_alimento='Pollo, petto', energia_kcal=110, proteine_g=23,
            carboidrati_g=0, lipidi_g=1.5)

    def _confirm(self, **overrides):
        payload = {
            'plan_title': 'Cut 1800',
            'diet_json': {
                'days': [{
                    'day_of_week': 'MONDAY',
                    'meals': [{
                        'meal_type': 'LUNCH',
                        'foods': [{'name': 'Pollo', 'quantity': 150,
                                   'food_id': self.food.id}],
                    }],
                }],
            },
        }
        payload.update(overrides)
        return self.client.post(
            '/api/nutrizione/import/conferma/',
            data=json.dumps(payload), content_type='application/json')

    def test_saves_without_a_client(self):
        res = self._confirm()
        self.assertEqual(res.status_code, 200, res.content)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.status, 'DRAFT')

    def test_redirects_into_the_plan_builder(self):
        res = self._confirm()
        plan_id = res.json()['plan_id']
        self.assertEqual(res.json()['redirect_url'],
                         f'/nutrizione/piani/{plan_id}/modifica/')

    def test_explicit_shape_beats_inference(self):
        """One day in the document used to force DAILY/FOOD. The coach's choice
        on the review step decides which of the four builders opens."""
        res = self._confirm(plan_kind='WEEKLY', plan_mode='MACRO')
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, 'WEEKLY')
        self.assertEqual(plan.plan_mode, 'MACRO')

    def test_shape_is_inferred_when_unspecified(self):
        res = self._confirm()
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, 'DAILY')
        self.assertEqual(plan.plan_mode, 'FOOD')

    def test_garbage_shape_falls_back_instead_of_erroring(self):
        res = self._confirm(plan_kind='SIDEWAYS', plan_mode='VIBES')
        self.assertEqual(res.status_code, 200, res.content)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, 'DAILY')
        self.assertEqual(plan.plan_mode, 'FOOD')

    def test_builder_opens_each_imported_shape(self):
        for kind, mode in [('DAILY', 'FOOD'), ('WEEKLY', 'FOOD'),
                           ('DAILY', 'MACRO'), ('WEEKLY', 'MACRO')]:
            with self.subTest(kind=kind, mode=mode):
                res = self._confirm(plan_kind=kind, plan_mode=mode)
                plan_id = res.json()['plan_id']
                page = self.client.get(f'/nutrizione/piani/{plan_id}/modifica/')
                self.assertEqual(page.status_code, 200)


class ImportPageRenderTests(ImportHandoffTestCase):
    """The import screens are Alpine-driven, so a broken include or a stray
    template tag only shows up at render time — compiling is not enough."""

    PAGES = [
        '/allenamenti/importa/',
        '/allenamenti/importa-pdf/',
        '/nutrizione/piani/importa/',
        '/nutrizione/piani/importa-pdf/',
    ]

    def test_every_import_page_renders(self):
        for url in self.PAGES:
            with self.subTest(url=url):
                res = self.client.get(url)
                self.assertEqual(res.status_code, 200, f'{url} -> {res.status_code}')
                body = res.content.decode()
                self.assertIn('imp-steps', body, 'meander stepper missing')
                self.assertIn("Chiron è un'AI", body, 'AI disclaimer missing')


class DocStructureTests(TestCase):
    """Deterministic layout detection that routes prompts and fast paths."""

    def test_multi_week_workout(self):
        from domain.shared.doc_structure import detect_workout_structure
        s = detect_workout_structure(
            'Settimana 1: Panca 4x8 80kg\nSettimana 2: Panca 4x8 82.5\n'
            'Settimana 3: Panca 4x6 85\nSettimana 4: Panca 4x6 87.5')
        self.assertEqual(s.layout, 'multi_week_columns')
        self.assertEqual(s.week_count, 4)

    def test_single_week_workout_with_ss(self):
        from domain.shared.doc_structure import detect_workout_structure
        s = detect_workout_structure('Lunedì\nPanca piana 4x8\nss Croci ai cavi 3x12')
        self.assertEqual(s.layout, 'single_week')
        self.assertTrue(s.has_superset_shorthand)

    def test_diet_shapes(self):
        from domain.shared.doc_structure import detect_diet_structure
        macro_weekly = detect_diet_structure(
            'Lunedì: kcal 2200, proteine 180, carboidrati 220, grassi 60\n'
            'Martedì: kcal 1900, proteine 180, carboidrati 150, grassi 55')
        self.assertEqual(macro_weekly.layout, 'macro_weekly')
        macro_daily = detect_diet_structure(
            'Target: kcal 2100, proteine 170 g, carboidrati 210 g, grassi 60 g')
        self.assertEqual(macro_daily.layout, 'macro_daily')
        food_weekly = detect_diet_structure(
            'Lunedì\nColazione: avena 80 g, latte 200 ml\nPranzo: riso 100 g\n'
            'Martedì\nColazione: pane 60 g, marmellata 30 g')
        self.assertEqual(food_weekly.layout, 'food_weekly')
        food_daily = detect_diet_structure(
            'Colazione: avena 80 g, latte 200 ml\nPranzo: riso 100 g, pollo 150 g')
        self.assertEqual(food_daily.layout, 'food_daily')


class SupersetRegroupTests(TestCase):
    """Deterministic fallback for "ss"/"A1-A2" shorthand the LLM may miss."""

    def _session(self, names):
        return {'blocks': [{'block_type': 'straight',
                            'exercises': [{'raw_name': n} for n in names]}]}

    def test_ss_prefix_groups_with_previous(self):
        from domain.workouts.imports.excel_importer import _regroup_shorthand_supersets
        session = self._session(['Panca piana', 'ss Croci ai cavi', 'Rematore'])
        _regroup_shorthand_supersets(session)
        types = [b['block_type'] for b in session['blocks']]
        self.assertEqual(types[0], 'superset')
        self.assertEqual(len(session['blocks'][0]['exercises']), 2)
        # Prefix stripped before DB matching.
        self.assertEqual(session['blocks'][0]['exercises'][1]['raw_name'], 'Croci ai cavi')
        self.assertEqual(len(session['blocks'][1]['exercises']), 1)

    def test_letter_number_pairs_group(self):
        from domain.workouts.imports.excel_importer import _regroup_shorthand_supersets
        session = self._session(['A1. Trazioni', 'A2. Dip', 'B1. Curl'])
        _regroup_shorthand_supersets(session)
        self.assertEqual(session['blocks'][0]['block_type'], 'superset')
        self.assertEqual(
            [e['raw_name'] for e in session['blocks'][0]['exercises']],
            ['Trazioni', 'Dip'])

    def test_plain_list_untouched(self):
        from domain.workouts.imports.excel_importer import _regroup_shorthand_supersets
        session = self._session(['Squat', 'Panca piana', 'Stacco'])
        _regroup_shorthand_supersets(session)
        self.assertEqual(len(session['blocks']), 1)
        self.assertEqual(session['blocks'][0]['block_type'], 'straight')


class WorkoutProgressionImportTests(ImportHandoffTestCase):
    """week_values → WeeklyOverride rows; set_details → WorkoutExercise.set_details."""

    def setUp(self):
        super().setUp()
        self.squat = Exercise.objects.create(name='barbell squat', slug='barbell-squat')

    def _confirm(self, exercise_extra=None, **overrides):
        ex = {'raw_name': 'Squat', 'matched_exercise_id': self.squat.id,
              'sets': 4, 'reps': 6, 'load': 100, 'load_unit': 'kg'}
        ex.update(exercise_extra or {})
        payload = {
            'plan_title': 'Progression test',
            'plan_kind': 'WEEKLY',
            'workout_json': {'sessions': [{
                'day_label': 'Lower',
                'blocks': [{'block_type': 'straight', 'exercises': [ex]}],
            }]},
        }
        payload.update(overrides)
        return self.client.post(
            '/api/allenamenti/import/conferma/',
            data=json.dumps(payload), content_type='application/json')

    def test_week_values_create_overrides_and_upgrade_to_program(self):
        from domain.workouts.models import WeeklyOverride
        res = self._confirm(exercise_extra={'week_values': [
            {'week': 2, 'load': 105, 'load_unit': 'kg'},
            {'week': 3, 'load': 110, 'load_unit': 'kg', 'reps': '5'},
            {'week': 1, 'load': 999},  # week 1 must never become an override
        ]})
        self.assertEqual(res.status_code, 200, res.content)
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, WorkoutPlan.KIND_PROGRAM)
        self.assertEqual(plan.duration_weeks, 3)
        overrides = WeeklyOverride.objects.filter(
            workout_exercise__workout_day__workout_plan=plan)
        self.assertFalse(overrides.filter(week_number=1).exists())
        w2 = {o.metric: o.value_json for o in overrides.filter(week_number=2)}
        self.assertEqual(w2.get('load_value'), 105.0)
        w3 = {o.metric: o.value_json for o in overrides.filter(week_number=3)}
        self.assertEqual(w3.get('load_value'), 110.0)
        self.assertEqual(w3.get('rep_range'), '5')

    def test_set_details_persisted_via_builder_sanitizer(self):
        res = self._confirm(exercise_extra={'set_details': [
            {'reps': 10, 'load': 80, 'load_unit': 'kg'},
            {'reps': 8, 'load': 85, 'load_unit': 'kg'},
            {'reps': 6, 'load': 90, 'load_unit': 'kg'},
        ]})
        self.assertEqual(res.status_code, 200, res.content)
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        ex = plan.days.get().exercises.get()
        self.assertEqual(len(ex.set_details), 3)
        self.assertEqual(ex.set_details[0]['load_value'], 80)
        self.assertEqual(ex.set_details[2]['reps'], '6')

    def test_no_week_values_stays_weekly(self):
        res = self._confirm()
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, WorkoutPlan.KIND_WEEKLY)
        self.assertEqual(plan.duration_weeks, 1)


class MacroDietImportTests(ImportHandoffTestCase):
    """MACRO plans persist targets and skip the foods path entirely."""

    def _confirm(self, **overrides):
        payload = {
            'plan_title': 'Macro plan',
            'plan_mode': 'MACRO',
            'diet_json': {
                'daily_kcal': 2200, 'protein_target_g': 180,
                'carb_target_g': 220, 'fat_target_g': 60,
                'days': [],
            },
        }
        payload.update(overrides)
        return self.client.post(
            '/api/nutrizione/import/conferma/',
            data=json.dumps(payload), content_type='application/json')

    def test_macro_daily_with_no_days_scaffolds_one_day(self):
        res = self._confirm(plan_kind='DAILY')
        self.assertEqual(res.status_code, 200, res.content)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_mode, 'MACRO')
        self.assertEqual(plan.daily_kcal, 2200)
        self.assertEqual(plan.protein_target_g, 180)
        self.assertEqual(plan.days.count(), 1)
        self.assertEqual(plan.meals.count(), 0)

    def test_macro_weekly_persists_per_day_targets_without_meals(self):
        res = self._confirm(plan_kind='WEEKLY', diet_json={
            'daily_kcal': 2000,
            'days': [
                {'day_of_week': 'MONDAY', 'target_kcal': 2200,
                 'target_protein_g': 180, 'target_carb_g': 220, 'target_fat_g': 60,
                 'meals': [{'meal_type': 'LUNCH', 'foods': [{'name': 'Pollo', 'quantity': 100}]}]},
                {'day_of_week': 'TUESDAY', 'target_kcal': 1800,
                 'target_protein_g': 180, 'target_carb_g': 150, 'target_fat_g': 55},
            ],
        })
        self.assertEqual(res.status_code, 200, res.content)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_kind, 'WEEKLY')
        days = {d.day_of_week: d for d in plan.days.all()}
        self.assertEqual(days['MONDAY'].target_kcal, 2200)
        self.assertEqual(days['TUESDAY'].target_kcal, 1800)
        # MACRO skips the foods path even when the extraction carried meals.
        self.assertEqual(plan.meals.count(), 0)

    def test_food_plan_persists_day_targets_too(self):
        food = Food.objects.create(
            nome_alimento='Riso', energia_kcal=350, proteine_g=7,
            carboidrati_g=78, lipidi_g=1)
        res = self._confirm(plan_mode='FOOD', plan_kind='DAILY', diet_json={
            'days': [{
                'day_of_week': 'MONDAY', 'target_kcal': 2100,
                'meals': [{'meal_type': 'LUNCH',
                           'foods': [{'name': 'Riso', 'quantity': 100, 'food_id': food.id}]}],
            }],
        })
        self.assertEqual(res.status_code, 200, res.content)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.days.get().target_kcal, 2100)
        self.assertEqual(plan.meals.count(), 1)


class PdfMergerWeekValuesTests(TestCase):
    """Chunks that split week columns across pages must union per week."""

    def test_week_values_unioned_by_week_number(self):
        from domain.workouts.imports.pdf_merger import merge_chunks
        part1 = {'sessions': [{'day_label': 'Lower', 'blocks': [{
            'block_type': 'straight',
            'exercises': [{'raw_name': 'Squat', 'sets': 4,
                           'week_values': [{'week': 2, 'load': 105}]}],
        }]}]}
        part2 = {'duration_weeks': 4, 'sessions': [{'day_label': 'Lower', 'blocks': [{
            'block_type': 'straight',
            'exercises': [{'raw_name': 'Squat',
                           'week_values': [{'week': 2, 'load': 999},
                                           {'week': 3, 'load': 110}]}],
        }]}]}
        merged = merge_chunks([part1, part2])
        self.assertEqual(merged['duration_weeks'], 4)
        ex = merged['sessions'][0]['blocks'][0]['exercises'][0]
        weeks = sorted(wv['week'] for wv in ex['week_values'])
        self.assertEqual(weeks, [2, 3])
        # First occurrence wins on conflict.
        w2 = next(wv for wv in ex['week_values'] if wv['week'] == 2)
        self.assertEqual(w2['load'], 105)
