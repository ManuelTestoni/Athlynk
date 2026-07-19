"""Cache-key module invariants: per-user isolation (no cross-user leakage),
invalidation on write, generation-bump invalidation for catalog searches."""
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase

from domain.accounts.models import User, CoachProfile
from domain.chat.models import Notification
from domain.workouts.models import Exercise

from .services import cachekeys


class CacheKeyBuilderTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_keys_are_scoped_per_owner(self):
        self.assertNotEqual(cachekeys.unread_count(1), cachekeys.unread_count(2))
        self.assertNotEqual(cachekeys.coach_dashboard(1, 'web'),
                            cachekeys.coach_dashboard(2, 'web'))
        self.assertNotEqual(cachekeys.coach_dashboard(1, 'web'),
                            cachekeys.coach_dashboard(1, 'api'))
        self.assertNotEqual(cachekeys.client_dashboard(1), cachekeys.client_dashboard(2))
        self.assertNotEqual(cachekeys.exercise_search('coach:1', 'squat'),
                            cachekeys.exercise_search('coach:2', 'squat'))

    def test_invalidate_coach_plans_deletes_both_lists(self):
        cache.set(cachekeys.coach_workout_plans(7), 'w', 300)
        cache.set(cachekeys.coach_nutrition_plans(7), 'n', 300)
        cachekeys.invalidate_coach_plans(7)
        self.assertIsNone(cache.get(cachekeys.coach_workout_plans(7)))
        self.assertIsNone(cache.get(cachekeys.coach_nutrition_plans(7)))

    def test_catalog_generation_bump_rotates_search_keys(self):
        before = cachekeys.exercise_search('coach:1', 'squat')
        cachekeys.invalidate_exercise_catalog()
        after = cachekeys.exercise_search('coach:1', 'squat')
        self.assertNotEqual(before, after)
        # Food generation is independent.
        food_before = cachekeys.food_search('web', 'pollo')
        cachekeys.invalidate_exercise_catalog()
        self.assertEqual(food_before, cachekeys.food_search('web', 'pollo'))


class SessionBase(TestCase):
    def _login(self, user):
        s = self.client.session
        s['user_id'] = user.id
        s['user_role'] = user.role
        s.save()


class UnreadCountCacheTests(SessionBase):
    def setUp(self):
        cache.clear()
        self.u1 = User.objects.create(
            email='a@example.com', password_hash=make_password('x'), role='COACH')
        self.u2 = User.objects.create(
            email='b@example.com', password_hash=make_password('x'), role='COACH')
        CoachProfile.objects.create(user=self.u1, first_name='A', last_name='A',
                                    professional_type='COACH')
        CoachProfile.objects.create(user=self.u2, first_name='B', last_name='B',
                                    professional_type='COACH')
        Notification.objects.create(target_user=self.u1, notification_type='CHECK_SUBMITTED',
                                    title='n1', body='')
        Notification.objects.create(target_user=self.u1, notification_type='CHECK_SUBMITTED',
                                    title='n2', body='')
        Notification.objects.create(target_user=self.u2, notification_type='CHECK_SUBMITTED',
                                    title='n3', body='')

    def test_counts_are_per_user_even_when_cached(self):
        self._login(self.u1)
        self.assertEqual(self.client.get('/api/notifications/unread-count/').json()['count'], 2)
        self._login(self.u2)
        self.assertEqual(self.client.get('/api/notifications/unread-count/').json()['count'], 1)

    def test_mark_all_read_clears_badge_immediately(self):
        self._login(self.u1)
        self.assertEqual(self.client.get('/api/notifications/unread-count/').json()['count'], 2)
        self.client.post('/api/notifications/read-all/', data='{}',
                         content_type='application/json')
        # No 15s staleness allowed: invalidation must bypass the TTL.
        self.assertEqual(self.client.get('/api/notifications/unread-count/').json()['count'], 0)


class CustomExerciseSearchIsolationTests(SessionBase):
    def setUp(self):
        cache.clear()
        self.ua = User.objects.create(
            email='ca@example.com', password_hash=make_password('x'), role='COACH')
        self.ub = User.objects.create(
            email='cb@example.com', password_hash=make_password('x'), role='COACH')
        self.ca = CoachProfile.objects.create(user=self.ua, first_name='A', last_name='A',
                                              professional_type='COACH')
        self.cb = CoachProfile.objects.create(user=self.ub, first_name='B', last_name='B',
                                              professional_type='COACH')
        Exercise.objects.create(name='Panca piana', slug='panca-piana')
        Exercise.objects.create(name='Panca segreta A', slug='panca-a',
                                is_custom=True, created_by=self.ca)

    def test_cached_search_never_leaks_other_coach_customs(self):
        self._login(self.ua)
        names_a = [e['name'] for e in self.client.get('/api/exercises/search/?q=Panca').json()]
        self.assertIn('Panca segreta A', names_a)
        self._login(self.ub)
        names_b = [e['name'] for e in self.client.get('/api/exercises/search/?q=Panca').json()]
        self.assertNotIn('Panca segreta A', names_b)
        self.assertIn('Panca piana', names_b)

    def test_custom_create_invalidates_cached_search(self):
        self._login(self.ua)
        first = [e['name'] for e in self.client.get('/api/exercises/search/?q=Trazioni').json()]
        self.assertEqual(first, [])
        muscle_id = self._any_muscle_id()
        resp = self.client.post(
            '/api/exercises/custom/',
            data={'name': 'Trazioni zavorrate', 'primary_muscle_ids': [muscle_id]},
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 201)
        second = [e['name'] for e in self.client.get('/api/exercises/search/?q=Trazioni').json()]
        self.assertIn('Trazioni zavorrate', second)

    def _any_muscle_id(self):
        from domain.workouts.models import MuscleGroup
        m = MuscleGroup.objects.first()  # taxonomy is seeded by migration
        if m is None:
            m = MuscleGroup.objects.create(name='Dorsali', slug='dorsali', region='BACK')
        return m.id
