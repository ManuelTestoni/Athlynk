"""Mobile wizard parity: the iOS coach app drives the same web save/finalize/
delete endpoints (via Bearer dual auth) and the builder GET projections, plus
the role-filtered login that keeps each app to its own user role."""
from django.contrib.auth.hashers import make_password
from django.test import TestCase

from config.api import issue_token
from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.workouts.models import WorkoutPlan, Exercise, ProgressionRule
from domain.nutrition.models import NutritionPlan, Food


class RoleFilteredLoginTests(TestCase):
    def setUp(self):
        self.coach_user = User.objects.create(
            email='coach@example.com', password_hash=make_password('pw'),
            role='COACH', is_verified=True)
        self.client_user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('pw'),
            role='CLIENT', is_verified=True)

    def _login(self, email, role=None):
        body = {'email': email, 'password': 'pw'}
        if role:
            body['role'] = role
        return self.client.post('/api/v1/auth/login', body,
                                content_type='application/json')

    def test_coach_cannot_login_on_athlete_app(self):
        self.assertEqual(self._login('coach@example.com', role='CLIENT').status_code, 401)

    def test_client_cannot_login_on_coach_app(self):
        self.assertEqual(self._login('atleta@example.com', role='COACH').status_code, 401)

    def test_matching_role_logs_in(self):
        self.assertEqual(self._login('coach@example.com', role='COACH').status_code, 200)
        self.assertEqual(self._login('atleta@example.com', role='CLIENT').status_code, 200)

    def test_login_without_role_still_works(self):
        self.assertEqual(self._login('coach@example.com').status_code, 200)


class MobileWorkoutWizardTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}
        self.squat = Exercise.objects.create(name='Back Squat', slug='back-squat')

    def _save(self, payload, plan_id=None):
        path = f'/api/allenamenti/{plan_id}/save/' if plan_id else '/api/allenamenti/save/'
        return self.client.post(path, payload, content_type='application/json', **self.auth)

    def test_program_save_with_progression_via_bearer(self):
        res = self._save({
            'title': 'Programmazione Forza',
            'plan_kind': 'PROGRAM',
            'frequency_per_week': 3,
            'duration_weeks': 6,
            'days': [{
                'name': 'Giorno 1',
                'exercises': [{
                    'local_id': 'loc-1', 'exercise_id': self.squat.id,
                    'sets': 5, 'reps': '5', 'recovery_seconds': 180,
                    'load_value': 100, 'load_unit': 'KG',
                }],
            }],
            'progression': {
                'weeks': [],
                'rules': [{
                    'workout_exercise_local_id': 'loc-1',
                    'family': 'LOAD', 'subtype': 'LOAD_LINEAR',
                    'target_metric': 'load', 'application_mode': 'FIXED_INCREMENT',
                    'start_week': 1,
                    'parameters': {'delta': 2.5, 'every_n_weeks': 1},
                    'stackable': True,
                }],
                'overrides': [],
            },
        })
        self.assertEqual(res.status_code, 200)
        plan = WorkoutPlan.objects.get(id=res.json()['plan']['id'])
        self.assertEqual(plan.plan_kind, 'PROGRAM')
        self.assertEqual(plan.duration_weeks, 6)
        rule = ProgressionRule.objects.get(workout_plan=plan)
        self.assertEqual(rule.subtype, 'LOAD_LINEAR')
        # The engine has computed weekly values for the progression grid.
        we = plan.days.get().exercises.get()
        values = {wv.week_number: float(wv.load_value) for wv in we.weekly_values.all()}
        self.assertEqual(values[1], 100.0)
        self.assertEqual(values[6], 112.5)

    def test_builder_payload_and_finalize_and_delete(self):
        res = self._save({
            'title': 'Settimanale', 'plan_kind': 'WEEKLY',
            'days': [{'name': 'Full body', 'exercises': [{
                'exercise_id': self.squat.id, 'sets': 3, 'reps': '8-10',
                'recovery_seconds': 120,
            }]}],
        })
        plan_id = res.json()['plan']['id']

        builder = self.client.get(f'/api/v1/coach/workouts/{plan_id}/builder', **self.auth)
        self.assertEqual(builder.status_code, 200)
        day = builder.json()['plan']['days'][0]
        self.assertEqual(day['exercises'][0]['exercise_id'], self.squat.id)

        fin = self.client.post(f'/api/allenamenti/{plan_id}/finalize/',
                               {'action': 'template'},
                               content_type='application/json', **self.auth)
        self.assertEqual(fin.status_code, 200)
        self.assertEqual(WorkoutPlan.objects.get(id=plan_id).status, 'TEMPLATE')

        deleted = self.client.post(f'/api/allenamenti/{plan_id}/elimina/',
                                   content_type='application/json', **self.auth)
        self.assertEqual(deleted.status_code, 200)
        self.assertFalse(WorkoutPlan.objects.filter(id=plan_id).exists())

    def test_client_token_is_rejected(self):
        outsider = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'),
            role='CLIENT', is_verified=True)
        ClientProfile.objects.create(user=outsider, first_name='A', last_name='B')
        auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(outsider)}'}
        res = self.client.post('/api/allenamenti/save/', {'title': 'Nope', 'days': []},
                               content_type='application/json', **auth)
        self.assertEqual(res.status_code, 403)


class MobileNutritionWizardTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='Giulia', last_name='Bianchi',
            platform_subscription_status='ACTIVE', professional_type='NUTRIZIONISTA')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}
        self.pollo = Food.objects.create(
            nome_alimento='Pollo, petto', energia_kcal=110,
            proteine_g=23, carboidrati_g=0, lipidi_g=1.5)

    def test_food_weekly_create_edit_delete_via_bearer(self):
        res = self.client.post('/nutrizione/piani/crea/', {
            'title': 'Dieta settimanale',
            'plan_kind': 'WEEKLY', 'plan_mode': 'FOOD',
            'meals': [{
                'name': 'Pranzo', 'day_of_week': 'LUN',
                'items': [{'food_id': self.pollo.id, 'quantity_g': 150}],
            }],
        }, content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 200)
        plan_id = res.json()['plan_id']
        plan = NutritionPlan.objects.get(id=plan_id)
        self.assertEqual(plan.plan_kind, 'WEEKLY')
        self.assertEqual(plan.meals.get().day.day_of_week, 'MONDAY')

        builder = self.client.get(f'/api/v1/coach/nutrition/{plan_id}/builder', **self.auth)
        self.assertEqual(builder.status_code, 200)
        meal = builder.json()['plan']['meals'][0]
        self.assertEqual(meal['day_of_week'], 'LUN')
        self.assertEqual(meal['items'][0]['food_id'], self.pollo.id)

        edit = self.client.post(f'/nutrizione/piani/{plan_id}/modifica/', {
            'title': 'Dieta settimanale v2',
            'plan_kind': 'WEEKLY', 'plan_mode': 'FOOD',
            'meals': [{
                'name': 'Cena', 'day_of_week': 'MAR',
                'items': [{'food_id': self.pollo.id, 'quantity_g': 200}],
            }],
        }, content_type='application/json', **self.auth)
        self.assertEqual(edit.status_code, 200)
        plan.refresh_from_db()
        self.assertEqual(plan.title, 'Dieta settimanale v2')
        self.assertEqual(plan.meals.get().day.day_of_week, 'TUESDAY')

        deleted = self.client.post(f'/api/nutrizione/piani/{plan_id}/elimina/',
                                   content_type='application/json', **self.auth)
        self.assertEqual(deleted.status_code, 200)
        self.assertFalse(NutritionPlan.objects.filter(id=plan_id).exists())

    def test_macro_weekly_create_via_bearer(self):
        res = self.client.post('/nutrizione/piani/crea/', {
            'title': 'Macro settimanali',
            'plan_kind': 'WEEKLY', 'plan_mode': 'MACRO',
            'meals': [],
            'day_targets': [
                {'day_of_week': 'LUN', 'kcal': 2200, 'protein': 160, 'carb': 250, 'fat': 60},
                {'day_of_week': 'DOM', 'kcal': 2600},
            ],
        }, content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 200)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.plan_mode, 'MACRO')
        self.assertEqual(plan.days.count(), 2)
        lun = plan.days.get(day_of_week='MONDAY')
        self.assertEqual(lun.target_kcal, 2200)

        builder = self.client.get(f'/api/v1/coach/nutrition/{plan.id}/builder', **self.auth)
        targets = {t['day_of_week']: t for t in builder.json()['plan']['day_targets']}
        self.assertEqual(targets['LUN']['protein'], 160)
        self.assertEqual(targets['DOM']['kcal'], 2600)

    def test_macro_daily_create_via_bearer(self):
        res = self.client.post('/nutrizione/piani/crea/', {
            'title': 'Macro giornalieri',
            'plan_kind': 'DAILY', 'plan_mode': 'MACRO',
            'meals': [],
            'daily_kcal': 2000, 'protein_target_g': 150,
            'carb_target_g': 220, 'fat_target_g': 55,
        }, content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 200)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        self.assertEqual(plan.daily_kcal, 2000)
        self.assertEqual(plan.protein_target_g, 150)
        detail = self.client.get(f'/api/v1/coach/nutrition/{plan.id}', **self.auth)
        self.assertEqual(detail.json()['plan']['protein_target_g'], 150)
