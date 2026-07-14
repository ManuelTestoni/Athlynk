"""Athlete agenda merges scheduled appointments with actual activity
(workouts done, checks submitted, macros logged) — views_agenda.py."""
from datetime import date, timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse
from domain.workouts.models import WorkoutPlan, WorkoutDay, WorkoutAssignment, WorkoutSession

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


@override_settings(CACHES=LOCMEM)
class ClientAgendaActivityTests(TestCase):
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

        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='Push')
        assignment = WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                                       coach=self.coach, status='ACTIVE',
                                                       start_date=date.today())
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=timezone.now(), completed=True)

        tpl = QuestionnaireTemplate.objects.create(coach=self.coach, title='Check',
                                                    questionnaire_type='CHECK')
        QuestionnaireResponse.objects.create(questionnaire_template=tpl, client=self.athlete,
                                             coach=self.coach, status='SUBMITTED',
                                             submitted_at=timezone.now())

        session = self.client.session
        session['user_id'] = au.id
        session.save()

    def test_agenda_events_include_activity(self):
        r = self.client.get('/api/agenda/events/')
        self.assertEqual(r.status_code, 200)
        events = r.json()
        types = {e['type'] for e in events}
        self.assertIn('allenamento_fatto', types)
        self.assertIn('check_fatto', types)

    def test_activity_events_do_not_collide_with_appointment_check_type(self):
        """appointment_type='check' (a scheduled check appointment) and the
        submitted-check activity must render as distinct calendar types."""
        r = self.client.get('/api/agenda/events/')
        events = r.json()
        activity_check = [e for e in events if e['type'] == 'check_fatto']
        self.assertEqual(len(activity_check), 1)
        self.assertTrue(activity_check[0]['is_activity'])
