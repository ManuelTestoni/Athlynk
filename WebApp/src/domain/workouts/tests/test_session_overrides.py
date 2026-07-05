"""In-session exercise add/remove/substitute (session-only overrides) and the
history-based progress endpoints (trend by exercise name)."""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.workouts.models import (
    Exercise, MuscleGroup, WorkoutPlan, WorkoutDay, WorkoutExercise,
    WorkoutAssignment, WorkoutSession, WorkoutSetLog,
)


class SessionOverridesTests(TestCase):
    def setUp(self):
        self.coach_user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'), role='COACH')
        self.coach = CoachProfile.objects.create(
            user=self.coach_user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE')
        self.client_user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'), role='CLIENT')
        self.client_profile = ClientProfile.objects.create(
            user=self.client_user, first_name='Luca', last_name='Bianchi')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.client_profile, status='ACTIVE',
            start_date=timezone.now().date())

        self.mg, _ = MuscleGroup.objects.get_or_create(
            name='Spalle', defaults={'slug': 'spalle'})
        self.ex_alzate = Exercise.objects.create(
            name='Alzate Laterali', slug='alzate-laterali', primary_muscle='Spalle')
        self.ex_spinte = Exercise.objects.create(
            name='Spinte Manubri', slug='spinte-manubri', primary_muscle='Spalle')
        self.ex_squat = Exercise.objects.create(
            name='Squat', slug='squat', primary_muscle='Quadricipiti')

        self.plan = WorkoutPlan.objects.create(coach=self.coach, title='Full', status='ACTIVE')
        self.day = WorkoutDay.objects.create(workout_plan=self.plan, day_order=1, day_name='A')
        self.we_alzate = WorkoutExercise.objects.create(
            workout_day=self.day, exercise=self.ex_alzate, order_index=1, set_count=3)
        self.we_squat = WorkoutExercise.objects.create(
            workout_day=self.day, exercise=self.ex_squat, order_index=2, set_count=3)
        self.assignment = WorkoutAssignment.objects.create(
            workout_plan=self.plan, client=self.client_profile, coach=self.coach,
            start_date=timezone.now().date(), status='ACTIVE')
        self.session = WorkoutSession.objects.create(
            assignment=self.assignment, workout_day=self.day, client=self.client_profile)

        s = self.client.session
        s['user_id'] = self.client_user.id
        s.save()

    def _post(self, url, payload):
        return self.client.post(url, data=json.dumps(payload),
                                content_type='application/json')

    # -- catalog search -----------------------------------------------------

    def test_search_by_name(self):
        res = self.client.get('/api/allenamenti/esercizi/ricerca/?q=spinte')
        self.assertEqual(res.status_code, 200)
        names = [r['name'] for r in res.json()['results']]
        self.assertEqual(names, ['Spinte Manubri'])

    def test_search_by_muscle_group(self):
        res = self.client.get('/api/allenamenti/esercizi/ricerca/?muscle_group=Spalle&include_groups=1')
        data = res.json()
        names = {r['name'] for r in data['results']}
        self.assertEqual(names, {'Alzate Laterali', 'Spinte Manubri'})
        self.assertIn('Spalle', {g['name'] for g in data['muscle_groups']})

    def test_search_similar_to(self):
        res = self.client.get(
            f'/api/allenamenti/esercizi/ricerca/?similar_to={self.ex_alzate.id}')
        names = [r['name'] for r in res.json()['results']]
        self.assertEqual(names, ['Spinte Manubri'])  # same primary, excludes itself

    # -- overrides ----------------------------------------------------------

    def test_overrides_roundtrip_in_session_start(self):
        res = self._post(f'/api/sessioni/{self.session.id}/modifiche/', {
            'removed': [self.we_squat.id],
            'substituted': {str(self.we_alzate.id): self.ex_spinte.id},
            'added': [{'exercise_id': self.ex_squat.id, 'order': 0}],
        })
        self.assertEqual(res.status_code, 200)

        res = self._post('/api/sessioni/avvia/', {
            'assignment_id': self.assignment.id, 'day_id': self.day.id})
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data['session_id'], self.session.id)
        by_we = {e['workout_exercise_id']: e for e in data['exercises']}
        self.assertTrue(by_we[self.we_squat.id]['removed'])
        self.assertEqual(by_we[self.we_alzate.id]['substituted_with']['id'],
                         self.ex_spinte.id)
        added = [e for e in data['exercises'] if e.get('added')]
        self.assertEqual(len(added), 1)
        self.assertEqual(added[0]['exercise_id'], self.ex_squat.id)

    def test_overrides_reject_foreign_slot(self):
        other_day = WorkoutDay.objects.create(workout_plan=self.plan, day_order=2)
        other_we = WorkoutExercise.objects.create(
            workout_day=other_day, exercise=self.ex_squat, order_index=1)
        res = self._post(f'/api/sessioni/{self.session.id}/modifiche/',
                         {'removed': [other_we.id]})
        self.assertEqual(res.status_code, 400)

    # -- logging sets -------------------------------------------------------

    def test_log_set_added_exercise(self):
        payload = {'exercise_id': self.ex_spinte.id, 'set_number': 1,
                   'reps_done': 10, 'load_used': 12.5}
        res = self._post(f'/api/sessioni/{self.session.id}/serie/', payload)
        self.assertEqual(res.status_code, 200)
        res = self._post(f'/api/sessioni/{self.session.id}/serie/',
                         {**payload, 'reps_done': 12})
        self.assertEqual(res.status_code, 200)

        logs = WorkoutSetLog.objects.filter(session=self.session)
        self.assertEqual(logs.count(), 1)  # update, not duplicate
        log = logs.get()
        self.assertIsNone(log.workout_exercise)
        self.assertEqual(log.actual_exercise, self.ex_spinte)
        self.assertTrue(log.is_extra_set)
        self.assertEqual(log.reps_done, 12)

    def test_log_set_substituted(self):
        res = self._post(f'/api/sessioni/{self.session.id}/serie/', {
            'workout_exercise_id': self.we_alzate.id, 'set_number': 1,
            'reps_done': 10, 'load_used': 8,
            'exercise_substituted': True, 'actual_exercise_id': self.ex_spinte.id,
        })
        self.assertEqual(res.status_code, 200)
        log = WorkoutSetLog.objects.get(session=self.session)
        self.assertTrue(log.exercise_substituted)
        self.assertEqual(log.actual_exercise, self.ex_spinte)

    # -- history-based progress ----------------------------------------------

    def _log(self, we, set_number, reps, load, substituted_with=None, added=None):
        WorkoutSetLog.objects.create(
            session=self.session, workout_exercise=we, set_number=set_number,
            reps_done=reps, load_used=load, load_unit='KG', completed=True,
            exercise_substituted=substituted_with is not None,
            actual_exercise=substituted_with or added,
            is_extra_set=added is not None,
        )

    def test_trend_by_name_counts_substituted_under_actual(self):
        self._log(self.we_alzate, 1, 10, 8, substituted_with=self.ex_spinte)
        self._log(self.we_alzate, 2, 10, 8, substituted_with=self.ex_spinte)

        res = self.client.get(
            '/api/allenamenti/esercizi/andamento-per-nome/?name=Spinte Manubri')
        data = res.json()
        self.assertTrue(data['has_data'])
        self.assertEqual(data['sessions'][0]['volume'], 160.0)

        res = self.client.get(
            '/api/allenamenti/esercizi/andamento-per-nome/?name=Alzate Laterali')
        self.assertFalse(res.json()['has_data'])

    def test_trend_by_name_includes_added_exercise(self):
        self._log(None, 1, 8, 100, added=self.ex_squat)
        res = self.client.get(
            '/api/allenamenti/esercizi/andamento-per-nome/?name=Squat')
        data = res.json()
        self.assertTrue(data['has_data'])
        self.assertEqual(data['sessions'][0]['volume'], 800.0)

    def test_progress_exercises_lists_history_names(self):
        self._log(self.we_alzate, 1, 10, 8)                              # planned
        self._log(self.we_squat, 1, 8, 100, substituted_with=self.ex_spinte)
        self._log(None, 1, 12, 20, added=self.ex_squat)

        res = self.client.get('/api/allenamenti/esercizi/storico/')
        names = {e['name'] for e in res.json()['exercises']}
        self.assertEqual(names, {'Alzate Laterali', 'Spinte Manubri', 'Squat'})

    # -- mobile parity -------------------------------------------------------

    def test_old_slot_trend_endpoint_still_works(self):
        self._log(self.we_alzate, 1, 10, 8)
        res = self.client.get(
            f'/api/allenamenti/esercizio/{self.we_alzate.id}/andamento/')
        data = res.json()
        self.assertTrue(data['has_data'])
        self.assertEqual(data['exercise']['workout_exercise_id'], self.we_alzate.id)
