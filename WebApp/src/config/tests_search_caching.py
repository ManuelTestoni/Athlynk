"""Exercise/food catalog search caching (60s TTL, keyed by query params) must
never return stale/wrong results across different queries — a global cache
key collision here would leak one search's results into another's. See
project plan phase 10 (web app performance pass)."""
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase

from domain.accounts.models import User, CoachProfile
from domain.workouts.models import Exercise
from domain.nutrition.models import Food


class ExerciseSearchCacheTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'), role='COACH')
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='M', last_name='R', professional_type='COACH')
        Exercise.objects.create(name='Back Squat', slug='back-squat')
        Exercise.objects.create(name='Bench Press', slug='bench-press')
        self.client.force_login = None  # session-based, not Django auth

    def _login(self):
        s = self.client.session
        s['user_id'] = self.user.id
        s['user_role'] = self.user.role
        s.save()

    def test_different_queries_are_not_confused_by_cache(self):
        self._login()
        squat = self.client.get('/api/exercises/search/?q=Squat').json()
        bench = self.client.get('/api/exercises/search/?q=Bench').json()
        self.assertEqual(len(squat), 1)
        self.assertEqual(squat[0]['name'], 'Back Squat')
        self.assertEqual(len(bench), 1)
        self.assertEqual(bench[0]['name'], 'Bench Press')

    def test_cache_hit_returns_identical_result(self):
        self._login()
        first = self.client.get('/api/exercises/search/?q=Squat').json()
        second = self.client.get('/api/exercises/search/?q=Squat').json()
        self.assertEqual(first, second)


class FoodSearchCacheTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'), role='CLIENT')
        Food.objects.create(nome_alimento='Pollo petto')
        Food.objects.create(nome_alimento='Riso bianco')

    def _login(self):
        s = self.client.session
        s['user_id'] = self.user.id
        s['user_role'] = self.user.role
        s.save()

    def test_different_queries_are_not_confused_by_cache(self):
        self._login()
        pollo = self.client.get('/api/nutrizione/alimenti/?q=Pollo').json()
        riso = self.client.get('/api/nutrizione/alimenti/?q=Riso').json()
        self.assertEqual(len(pollo['results']), 1)
        self.assertEqual(pollo['results'][0]['name'], 'Pollo petto')
        self.assertEqual(len(riso['results']), 1)
        self.assertEqual(riso['results'][0]['name'], 'Riso bianco')
