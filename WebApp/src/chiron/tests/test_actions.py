"""CHIRON action proposals and execution.

The contract these tests defend: the model can only ever *propose*, and every id
in a confirmed proposal is re-resolved against the coach in session. The hostile
cases are the point — a descriptor arrives from the browser, so a coach who
edits one must not be able to reach another coach's athlete, plan or template.
"""

from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from chiron.actions import ACTION_TYPES, build_proposal, execute_action
from domain.accounts.models import ClientProfile, CoachProfile, User
from domain.calendar.models import Appointment
from domain.checks.models import AssignedCheck, QuestionnaireTemplate
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import NutritionAssignment, NutritionPlan
from domain.workouts.models import (
    Exercise, WorkoutAssignment, WorkoutDay, WorkoutExercise, WorkoutPlan,
)


def _coach(email, first='Marco'):
    user = User.objects.create(email=email, password_hash=make_password('x'),
                               role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=user, first_name=first, last_name='Rossi',
        professional_type='COACH', platform_subscription_status='ACTIVE')


def _client_of(coach, email, first='Luca'):
    user = User.objects.create(email=email, password_hash=make_password('x'),
                               role='CLIENT', is_verified=True)
    client = ClientProfile.objects.create(user=user, first_name=first, last_name='Bianchi')
    CoachingRelationship.objects.create(
        coach=coach, client=client, status='ACTIVE',
        start_date=timezone.localdate())
    return client


def _workout_plan(coach, title='Push Pull Legs', with_exercises=True):
    plan = WorkoutPlan.objects.create(coach=coach, title=title, status='DRAFT')
    if with_exercises:
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='A')
        exercise = Exercise.objects.create(
            name=f'squat-{plan.id}', slug=f'squat-{plan.id}')
        WorkoutExercise.objects.create(workout_day=day, exercise=exercise, order_index=1)
    return plan


class ChironActionTestCase(TestCase):
    def setUp(self):
        self.coach = _coach('coach@e.com')
        self.client_profile = _client_of(self.coach, 'athlete@e.com')

        self.other_coach = _coach('rival@e.com', first='Rival')
        self.other_client = _client_of(self.other_coach, 'theirs@e.com', first='Estraneo')


class ProposalScopeTests(ChironActionTestCase):
    def test_unknown_action_is_refused(self):
        proposal, error = build_proposal(self.coach, 'delete_everything',
                                         self.client_profile.id)
        self.assertIsNone(proposal)
        self.assertIn('non valida', error)

    def test_cannot_propose_against_another_coachs_athlete(self):
        proposal, error = build_proposal(self.coach, 'send_message',
                                         self.other_client.id, message='ciao')
        self.assertIsNone(proposal)
        self.assertIn('non trovato', error)

    def test_cannot_propose_another_coachs_plan(self):
        theirs = _workout_plan(self.other_coach, 'Non mia')
        proposal, error = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=theirs.id)
        self.assertIsNone(proposal)
        self.assertIn('non trovata', error)

    def test_every_declared_action_has_a_builder(self):
        from chiron.actions import _BUILDERS, _EXECUTORS
        self.assertEqual(set(ACTION_TYPES), set(_BUILDERS))
        self.assertEqual(set(ACTION_TYPES), set(_EXECUTORS))


class AssignWorkoutPlanTests(ChironActionTestCase):
    def setUp(self):
        super().setUp()
        self.plan = _workout_plan(self.coach)

    def test_proposal_describes_what_will_happen(self):
        proposal, error = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=self.plan.id, duration_value=8)
        self.assertIsNone(error)
        self.assertEqual(proposal['payload']['plan_id'], self.plan.id)
        self.assertEqual(proposal['payload']['duration_value'], 8)
        self.assertIn('Push Pull Legs', proposal['title'])
        # Nothing may have been created by merely proposing.
        self.assertEqual(WorkoutAssignment.objects.count(), 0)

    def test_empty_plan_cannot_be_assigned(self):
        empty = _workout_plan(self.coach, 'Vuota', with_exercises=False)
        proposal, error = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=empty.id)
        self.assertIsNone(proposal)
        self.assertIn('esercizi', error)

    def test_execute_creates_the_assignment_and_notifies(self):
        proposal, _ = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=self.plan.id, duration_value=6)
        ok, message, link = execute_action(self.coach, proposal)
        self.assertTrue(ok, message)
        assignment = WorkoutAssignment.objects.get()
        self.assertEqual(assignment.client, self.client_profile)
        self.assertEqual(assignment.duration_value, 6)
        self.assertIsNotNone(assignment.end_date)
        self.assertTrue(self.client_profile.user.notifications
                        .filter(notification_type='WORKOUT_ASSIGNED').exists())
        self.assertIsNotNone(link)

    def test_previous_active_plan_is_closed(self):
        old = _workout_plan(self.coach, 'Vecchia')
        first, _ = build_proposal(self.coach, 'assign_workout_plan',
                                  self.client_profile.id, plan_id=old.id)
        execute_action(self.coach, first)
        second, _ = build_proposal(self.coach, 'assign_workout_plan',
                                   self.client_profile.id, plan_id=self.plan.id)
        execute_action(self.coach, second)
        self.assertEqual(
            WorkoutAssignment.objects.filter(status='ACTIVE').count(), 1)

    def test_tampered_plan_id_is_rejected_at_execution(self):
        """The descriptor round-trips through the browser, so execution cannot
        trust it — even though the proposal it came from was legitimate."""
        theirs = _workout_plan(self.other_coach, 'Non mia')
        proposal, _ = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=self.plan.id)
        proposal['payload']['plan_id'] = theirs.id
        ok, message, _ = execute_action(self.coach, proposal)
        self.assertFalse(ok)
        self.assertEqual(WorkoutAssignment.objects.count(), 0)

    def test_tampered_client_id_is_rejected_at_execution(self):
        proposal, _ = build_proposal(
            self.coach, 'assign_workout_plan', self.client_profile.id,
            plan_id=self.plan.id)
        proposal['client_id'] = self.other_client.id
        ok, _, _ = execute_action(self.coach, proposal)
        self.assertFalse(ok)
        self.assertEqual(WorkoutAssignment.objects.count(), 0)


class AssignNutritionPlanTests(ChironActionTestCase):
    def test_assigns_and_cancels_the_previous_plan(self):
        first = NutritionPlan.objects.create(coach=self.coach, title='Cut', status='DRAFT')
        second = NutritionPlan.objects.create(coach=self.coach, title='Bulk', status='DRAFT')
        for plan in (first, second):
            proposal, error = build_proposal(
                self.coach, 'assign_nutrition_plan', self.client_profile.id,
                plan_id=plan.id)
            self.assertIsNone(error)
            ok, message, _ = execute_action(self.coach, proposal)
            self.assertTrue(ok, message)
        self.assertEqual(
            NutritionAssignment.objects.filter(status='ACTIVE').count(), 1)
        self.assertEqual(
            NutritionAssignment.objects.get(status='ACTIVE').nutrition_plan, second)


class AssignCheckTests(ChironActionTestCase):
    def setUp(self):
        super().setUp()
        self.template = QuestionnaireTemplate.objects.create(
            coach=self.coach, title='Check settimanale', questionnaire_type='WEEKLY',
            questions_config=[{'id': 'q1', 'label': 'Come va?'}])

    def test_weekly_recurrence_requires_a_day(self):
        proposal, error = build_proposal(
            self.coach, 'assign_check', self.client_profile.id,
            template_id=self.template.id, recurrence_type='weekly')
        self.assertIsNone(proposal)
        self.assertIn('giorno', error)

    def test_weekly_recurrence_is_described_in_words(self):
        proposal, error = build_proposal(
            self.coach, 'assign_check', self.client_profile.id,
            template_id=self.template.id, recurrence_type='weekly', weekly_day=0)
        self.assertIsNone(error)
        self.assertIn('lunedì', proposal['description'])

    def test_once_assignment_creates_an_instance_immediately(self):
        proposal, _ = build_proposal(
            self.coach, 'assign_check', self.client_profile.id,
            template_id=self.template.id, recurrence_type='once')
        ok, message, _ = execute_action(self.coach, proposal)
        self.assertTrue(ok, message)
        assignment = AssignedCheck.objects.get()
        self.assertEqual(assignment.instances.count(), 1)

    def test_questions_are_snapshotted_at_assignment(self):
        proposal, _ = build_proposal(
            self.coach, 'assign_check', self.client_profile.id,
            template_id=self.template.id)
        execute_action(self.coach, proposal)
        self.template.questions_config = [{'id': 'q2', 'label': 'Cambiata'}]
        self.template.save(update_fields=['questions_config'])
        assignment = AssignedCheck.objects.get()
        self.assertEqual(assignment.snapshot_config, [{'id': 'q1', 'label': 'Come va?'}])


class ScheduleAppointmentTests(ChironActionTestCase):
    def test_requires_a_parseable_datetime(self):
        proposal, error = build_proposal(
            self.coach, 'schedule_appointment', self.client_profile.id,
            start_datetime='giovedì prossimo')
        self.assertIsNone(proposal)
        self.assertIn('formato', error)

    def test_creates_the_appointment(self):
        when = (timezone.now() + timedelta(days=3)).replace(microsecond=0)
        proposal, error = build_proposal(
            self.coach, 'schedule_appointment', self.client_profile.id,
            start_datetime=when.isoformat(), title='Consulenza',
            duration_minutes=45)
        self.assertIsNone(error)
        ok, message, _ = execute_action(self.coach, proposal)
        self.assertTrue(ok, message)
        appointment = Appointment.objects.get()
        self.assertEqual(appointment.duration_minutes, 45)
        self.assertEqual(appointment.client, self.client_profile)
        self.assertEqual(appointment.status, 'SCHEDULED')


class SendMessageTests(ChironActionTestCase):
    def test_drafted_text_survives_into_the_proposal(self):
        """The old schema declared no `message` field, so pydantic dropped the
        text the model had written and the coach saw an empty box."""
        proposal, error = build_proposal(
            self.coach, 'send_message', self.client_profile.id,
            message='Ottimo lavoro questa settimana.')
        self.assertIsNone(error)
        self.assertEqual(proposal['payload']['message'],
                         'Ottimo lavoro questa settimana.')

        from chiron.schemas import PendingAction
        parsed = PendingAction(**proposal)
        self.assertEqual(parsed.payload['message'],
                         'Ottimo lavoro questa settimana.')
        self.assertEqual(parsed.fields[0].key, 'message')

    def test_empty_message_is_refused(self):
        proposal, error = build_proposal(
            self.coach, 'send_message', self.client_profile.id, message='   ')
        self.assertIsNone(proposal)
        self.assertIn('messaggio', error)
