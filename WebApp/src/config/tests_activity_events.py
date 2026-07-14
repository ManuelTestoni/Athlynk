"""_build_activity_events: athlete activity feed (agenda), not coach assignments.

Distinct from _build_percorso_events (tests_coach_timeline.py) — this tracks
what the athlete actually did: completed workouts, submitted checks, logged
food — grouped into one "macro" event per day."""
from datetime import date, timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse
from domain.nutrition.models import (
    Food, NutritionPlan, NutritionAssignment, ClientMacroLogEntry,
)
from domain.workouts.models import (
    WorkoutPlan, WorkoutDay, WorkoutAssignment, WorkoutSession,
)

from .views_client import _build_activity_events


class ActivityEventsTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='c@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(user=cu, first_name='C', last_name='O',
                                                 professional_type='COACH')
        au = User.objects.create(email='a@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.athlete = ClientProfile.objects.create(user=au, first_name='A', last_name='T')
        self.today = date.today()
        self.window_start = self.today - timedelta(days=30)
        self.window_end = self.today

    def _events(self):
        return _build_activity_events(self.athlete, self.window_start, self.window_end)

    def test_completed_session_included_abandoned_excluded(self):
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='Push')
        assignment = WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                                       coach=self.coach, status='ACTIVE',
                                                       start_date=self.today)
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=timezone.now(), completed=True)
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=timezone.now(), completed=False)

        events = self._events()
        workout_events = [e for e in events if e['type'] == 'allenamento_fatto']
        self.assertEqual(len(workout_events), 1)
        self.assertEqual(workout_events[0]['title'], 'Push')

    def test_draft_check_excluded_submitted_check_included(self):
        tpl = QuestionnaireTemplate.objects.create(coach=self.coach, title='Check',
                                                    questionnaire_type='CHECK')
        QuestionnaireResponse.objects.create(questionnaire_template=tpl, client=self.athlete,
                                             coach=self.coach, status='DRAFT', submitted_at=None)
        QuestionnaireResponse.objects.create(questionnaire_template=tpl, client=self.athlete,
                                             coach=self.coach, status='SUBMITTED',
                                             submitted_at=timezone.now())

        events = self._events()
        check_events = [e for e in events if e['type'] == 'check']
        self.assertEqual(len(check_events), 1)

    def test_macro_entries_group_into_one_event_per_day(self):
        plan = NutritionPlan.objects.create(coach=self.coach, title='Diet', plan_mode='MACRO')
        assignment = NutritionAssignment.objects.create(nutrition_plan=plan, client=self.athlete,
                                                         coach=self.coach, status='ACTIVE')
        chicken = Food.objects.create(nome_alimento='Petto di pollo', energia_kcal=120)
        rice = Food.objects.create(nome_alimento='Riso', energia_kcal=130)
        ClientMacroLogEntry.objects.create(assignment=assignment, food=chicken, quantity_g=150,
                                           log_date=self.today)
        ClientMacroLogEntry.objects.create(assignment=assignment, food=rice, quantity_g=80,
                                           log_date=self.today)
        # legacy row with no log_date must not crash grouping / must be excluded
        ClientMacroLogEntry.objects.create(assignment=assignment, food=rice, quantity_g=50,
                                           log_date=None)

        events = self._events()
        macro_events = [e for e in events if e['type'] == 'macro']
        self.assertEqual(len(macro_events), 1)
        self.assertEqual(macro_events[0]['count'], 2)
        self.assertEqual({item['name'] for item in macro_events[0]['items']},
                         {'Petto di pollo', 'Riso'})

    def test_events_outside_window_excluded(self):
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Plan', status='PUBLISHED')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='Push')
        assignment = WorkoutAssignment.objects.create(workout_plan=plan, client=self.athlete,
                                                       coach=self.coach, status='ACTIVE',
                                                       start_date=self.today)
        old_date = timezone.now() - timedelta(days=90)
        WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=self.athlete,
                                      started_at=old_date, completed=True)

        events = self._events()
        self.assertEqual(len(events), 0)
