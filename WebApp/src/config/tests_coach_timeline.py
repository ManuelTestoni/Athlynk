"""Repro: coach app sees empty percorso + empty exercise trend even with data."""
from datetime import date, timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.workouts.models import (
    WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment,
    WorkoutSession, WorkoutSetLog, Exercise,
)
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse
from .api import issue_token

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


@override_settings(CACHES=LOCMEM)
class CoachTimelineReproTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='c@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(user=cu, first_name='C', last_name='O',
                                                 professional_type='COACH')
        au = User.objects.create(email='a@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.athlete = ClientProfile.objects.create(user=au, first_name='A', last_name='T')
        CoachingRelationship.objects.create(coach=self.coach, client=self.athlete,
                                            status='ACTIVE', start_date=date.today())
        self.token = issue_token(cu)

        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='A')
        ex = Exercise.objects.create(name='Squat')
        self.we = WorkoutExercise.objects.create(workout_day=day, exercise=ex, order_index=1)
        WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                         coach=self.coach, status='ACTIVE',
                                         start_date=date.today())
        asg = WorkoutAssignment.objects.filter(client=self.athlete).first()
        sess = WorkoutSession.objects.create(assignment=asg, workout_day=day,
                                             client=self.athlete,
                                             started_at=timezone.now() - timedelta(days=1),
                                             ended_at=timezone.now(), completed=True)
        WorkoutSetLog.objects.create(session=sess, workout_exercise=self.we, set_number=1,
                                     reps_done=10, load_used=100, completed=True)

        tpl = QuestionnaireTemplate.objects.create(coach=self.coach, title='Check',
                                                   questionnaire_type='CHECK')
        QuestionnaireResponse.objects.create(questionnaire_template=tpl, client=self.athlete,
                                             coach=self.coach, status='SUBMITTED',
                                             submitted_at=timezone.now())

    def _auth(self):
        return {'HTTP_AUTHORIZATION': f'Bearer {self.token}'}

    def test_percorso_has_events(self):
        r = self.client.get(f'/api/v1/coach/clients/{self.athlete.id}/percorso', **self._auth())
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertTrue(len(data['events']) >= 2)  # workout assignment + check

    def test_exercise_trend_has_data(self):
        r = self.client.get(
            f'/api/v1/coach/clients/{self.athlete.id}/exercises/{self.we.id}/trend',
            **self._auth())
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertTrue(data['has_data'])

    def test_trend_includes_unfinished_sessions(self):
        """Sets logged in a session the athlete never tapped "finish" (completed
        stays False) must still appear in the trend."""
        WorkoutSession.objects.update(completed=False, ended_at=None)
        r = self.client.get(
            f'/api/v1/coach/clients/{self.athlete.id}/exercises/{self.we.id}/trend',
            **self._auth())
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()['has_data'])


@override_settings(CACHES=LOCMEM)
class WebPercorsoReproTests(TestCase):
    """The web percorso route (/api/coach/clienti/<id>/percorso/) is the one
    the coach's client-detail page actually uses. It had its own copy of the
    window-clipping bug that /api/v1/coach/clients/<id>/percorso already had
    fixed — this reproduces it directly against the web route."""

    def setUp(self):
        cu = User.objects.create(email='c2@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(user=cu, first_name='C', last_name='O',
                                                 professional_type='COACH')
        au = User.objects.create(email='a2@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.athlete = ClientProfile.objects.create(user=au, first_name='A', last_name='T')

        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        # created_at (what the timeline plots) lands "now"; start_date is a
        # separate plan-level field the event builder never reads.
        WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                         coach=self.coach, status='ACTIVE',
                                         start_date=date.today())

    def _login(self):
        session = self.client.session
        session['user_id'] = self.coach.user_id
        session.save()

    def test_web_percorso_not_empty_when_relationship_starts_later(self):
        """An athlete who re-signed: the CURRENT relationship's start_date is
        legitimately later than an assignment created under an earlier
        engagement. Before the fix, _percorso_response clipped
        _build_percorso_events to window_start=relationship_start — a
        start_date in a later month than the assignment's created_at silently
        emptied the timeline even though the assignment still exists."""
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.athlete, status='ACTIVE',
            start_date=date.today() + timedelta(days=60))

        self._login()
        r = self.client.get(f'/api/coach/clienti/{self.athlete.id}/percorso/')
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertTrue(len(data['events']) >= 1)

    def test_web_percorso_picks_active_relationship_over_stale_one(self):
        """Two relationship rows for the same coach/client pair (a gap then a
        re-sign): an older INACTIVE row and the current ACTIVE one. Without a
        status filter and explicit ordering, .first() can return either row
        non-deterministically — assert the ACTIVE one wins."""
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.athlete, status='INACTIVE',
            start_date=date.today() - timedelta(days=400))
        active_rel = CoachingRelationship.objects.create(
            coach=self.coach, client=self.athlete, status='ACTIVE',
            start_date=date.today() - timedelta(days=10))

        self._login()
        r = self.client.get(f'/api/coach/clienti/{self.athlete.id}/percorso/')
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertEqual(data['relationship_start'],
                         active_rel.start_date.replace(day=1).isoformat())
