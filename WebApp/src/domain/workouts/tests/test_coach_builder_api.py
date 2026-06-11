"""Mobile builder endpoints: full-structure create payloads + DB searches
authenticated with the iOS Bearer token."""
from django.contrib.auth.hashers import make_password
from django.test import TestCase

from config.api import issue_token
from domain.accounts.models import User, CoachProfile
from domain.workouts.models import WorkoutPlan, Exercise
from domain.nutrition.models import NutritionPlan, Food


class CoachBuilderApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}

    def test_workout_create_full_structure(self):
        squat = Exercise.objects.create(name='Back Squat', slug='back-squat')
        panca = Exercise.objects.create(name='Panca piana', slug='panca-piana')
        res = self.client.post('/api/v1/coach/workouts/create', {
            'title': 'Upper Lower',
            'goal': 'Forza',
            'days': [{
                'name': 'Lower A',
                'exercises': [
                    {'exercise_id': squat.id, 'sets': 5, 'reps': 5,
                     'recovery_seconds': 180, 'rir': 2, 'notes': 'fermo in buca'},
                    {'exercise_id': panca.id, 'sets': 3, 'rep_range': '8-12',
                     'recovery_seconds': 90},
                ],
            }],
        }, content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 201)
        plan = WorkoutPlan.objects.get(id=res.json()['plan_id'])
        day = plan.days.get()
        first, second = list(day.exercises.order_by('order_index'))
        self.assertEqual(first.rir, 2)
        self.assertEqual(first.technique_notes, 'fermo in buca')
        self.assertEqual(second.rep_range, '8-12')

    def test_nutrition_create_full_structure(self):
        pollo = Food.objects.create(
            nome_alimento='Pollo, petto', energia_kcal=110,
            proteine_g=23, carboidrati_g=0, lipidi_g=1.5)
        res = self.client.post('/api/v1/coach/nutrition/create', {
            'title': 'Cut 1800',
            'daily_kcal': 1800,
            'meals': [{
                'name': 'Pranzo', 'time_of_day': '13:00',
                'items': [{'food_id': pollo.id, 'quantity_g': 150}],
            }],
        }, content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 201)
        plan = NutritionPlan.objects.get(id=res.json()['plan_id'])
        meal = plan.meals.get()
        self.assertEqual(meal.time_of_day, '13:00')
        item = meal.items.get()
        self.assertEqual(item.food_id, pollo.id)
        self.assertEqual(item.quantity_g, 150)

    def test_search_endpoints_accept_bearer(self):
        Exercise.objects.create(name='Stacco da terra', slug='stacco-da-terra')
        Food.objects.create(nome_alimento='Riso basmati', energia_kcal=350,
                            proteine_g=7, carboidrati_g=78, lipidi_g=1)
        ex = self.client.get('/api/exercises/search/?q=stacco', **self.auth)
        self.assertEqual(ex.status_code, 200)
        self.assertEqual(ex.json()[0]['name'], 'Stacco da terra')
        food = self.client.get('/api/nutrizione/alimenti/?q=riso', **self.auth)
        self.assertEqual(food.status_code, 200)
        self.assertEqual(food.json()['results'][0]['name'], 'Riso basmati')
