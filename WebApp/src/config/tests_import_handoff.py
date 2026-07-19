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
