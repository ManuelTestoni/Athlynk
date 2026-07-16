"""api_coach_client_activity_feed: single-day, type-filtered, paginated
athlete-activity feed behind the coach client-detail page's day/domain picker."""
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
class CoachActivityFeedTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='c@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(user=cu, first_name='C', last_name='O',
                                                 professional_type='COACH')
        au = User.objects.create(email='a@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.athlete = ClientProfile.objects.create(user=au, first_name='A', last_name='T')
        CoachingRelationship.objects.create(coach=self.coach, client=self.athlete,
                                            status='ACTIVE', start_date=date.today() - timedelta(days=30))

        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='Push')
        assignment = WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                                       coach=self.coach, status='ACTIVE',
                                                       start_date=date.today())
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=timezone.now(), completed=True)
        # yesterday: must not show up when querying today
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=timezone.now() - timedelta(days=1), completed=True)

        tpl = QuestionnaireTemplate.objects.create(coach=self.coach, title='Check',
                                                    questionnaire_type='CHECK')
        QuestionnaireResponse.objects.create(questionnaire_template=tpl, client=self.athlete,
                                             coach=self.coach, status='SUBMITTED',
                                             submitted_at=timezone.now())

        session = self.client.session
        session['user_id'] = cu.id
        session.save()

    def _url(self, **params):
        qs = '&'.join(f'{k}={v}' for k, v in params.items())
        return f'/api/coach/clienti/{self.athlete.id}/attivita/?{qs}'

    def test_returns_only_todays_events(self):
        r = self.client.get(self._url(date=date.today().isoformat()))
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertEqual(data['total'], 2)  # 1 session + 1 check, yesterday's session excluded

    def test_type_filter_scopes_to_one_domain(self):
        r = self.client.get(self._url(date=date.today().isoformat(), type='allenamento_fatto'))
        data = r.json()
        self.assertEqual(data['total'], 1)
        self.assertEqual(data['items'][0]['type'], 'allenamento_fatto')

    def test_pagination_has_more_flag(self):
        r = self.client.get(self._url(date=date.today().isoformat(), offset=0)
                            + '')
        # limit is 10, only 2 events exist -> has_more False
        data = r.json()
        self.assertFalse(data['has_more'])

    def test_unauthenticated_coach_rejected(self):
        self.client.session.flush()
        r = self.client.get(self._url(date=date.today().isoformat()))
        self.assertEqual(r.status_code, 401)

    def test_other_coachs_client_not_found(self):
        other_cu = User.objects.create(email='other@e.com', password_hash=make_password('x'),
                                       role='COACH', is_verified=True)
        CoachProfile.objects.create(user=other_cu, first_name='O', last_name='C',
                                    professional_type='COACH')
        session = self.client.session
        session['user_id'] = other_cu.id
        session.save()
        r = self.client.get(self._url(date=date.today().isoformat()))
        self.assertEqual(r.status_code, 404)
