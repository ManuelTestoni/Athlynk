"""Regression: the plan builder must not persist meals that contain no food
("don't fill the DB with empty meals")."""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from domain.accounts.models import User, CoachProfile
from domain.nutrition.models import Food, NutritionPlan, Meal, MealItem


def _coach():
    u = User.objects.create(email='nutri@e.com', password_hash=make_password('x'),
                            role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=u, first_name='Pro', last_name='Coach',
        professional_type='COACH', platform_subscription_status='ACTIVE',
    )


class EmptyMealSkipTests(TestCase):
    def setUp(self):
        self.coach = _coach()
        self.food = Food.objects.create(nome_alimento='Pollo', energia_kcal=165, proteine_g=31)
        s = self.client.session
        s['user_id'] = self.coach.user.id
        s['user_role'] = 'COACH'
        s.save()

    def _save(self, meals):
        return self.client.post(
            '/nutrizione/piani/crea/',
            data=json.dumps({'title': 'Piano', 'plan_kind': 'DAILY',
                             'plan_mode': 'FOOD', 'meals': meals}),
            content_type='application/json',
        )

    def test_foodless_meals_not_persisted(self):
        resp = self._save([
            {'name': 'Colazione', 'items': [{'food_id': self.food.id, 'quantity_g': 100}]},
            {'name': 'Spuntino vuoto', 'items': []},
            {'name': 'Pranzo senza cibo', 'items': [{'food_id': None, 'quantity_g': 0}]},
        ])
        self.assertEqual(resp.status_code, 200)
        plan = NutritionPlan.objects.get(coach=self.coach)
        # Only the one meal with a real food survives.
        self.assertEqual(plan.meals.count(), 1)
        self.assertEqual(plan.meals.first().name, 'Colazione')
        self.assertEqual(MealItem.objects.filter(meal__plan=plan).count(), 1)
        self.assertEqual(plan.meals_per_day, 1)

    def test_all_empty_yields_no_meals(self):
        resp = self._save([{'name': 'A', 'items': []}, {'name': 'B', 'items': []}])
        self.assertEqual(resp.status_code, 200)
        plan = NutritionPlan.objects.get(coach=self.coach)
        self.assertEqual(plan.meals.count(), 0)
        self.assertIsNone(plan.meals_per_day)
