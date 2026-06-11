"""Plan deletion: bodyless fetch() POSTs must pass the JSON gate, and deleting
an assigned plan must notify the athletes in chat (PLAN_DELETED auto-message)."""
from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.chat.models import Message, AutomaticMessageTemplate
from domain.chat.services import DEFAULT_PLAN_DELETED_BODY
from domain.workouts.models import (
    WorkoutPlan, WorkoutDay, WorkoutExercise, Exercise,
    WorkoutAssignment, WorkoutSession, WorkoutSetLog,
)
from domain.nutrition.models import NutritionPlan, NutritionAssignment


class PlanDeleteTests(TestCase):
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

        s = self.client.session
        s['user_id'] = self.coach_user.id
        s.save()

    def _delete(self, url):
        # No body, no Content-Type — same shape as the browser fetch() call
        # (Chromium marks it text/plain; the middleware must not 415 it).
        return self.client.generic('POST', url)

    def test_delete_unassigned_plan_sends_no_message(self):
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Libera', status='TEMPLATE')
        res = self._delete(f'/api/allenamenti/{plan.id}/elimina/')
        self.assertEqual(res.status_code, 200)
        self.assertFalse(WorkoutPlan.objects.filter(id=plan.id).exists())
        self.assertEqual(Message.objects.count(), 0)

    def test_delete_assigned_plan_sends_default_message(self):
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Assegnata', status='ACTIVE')
        day = WorkoutDay.objects.create(workout_plan=plan, day_order=1, day_name='A')
        ex = Exercise.objects.create(name='Squat')
        wex = WorkoutExercise.objects.create(workout_day=day, exercise=ex, order_index=1)
        assignment = WorkoutAssignment.objects.create(
            workout_plan=plan, client=self.client_profile, coach=self.coach,
            start_date=timezone.now().date())
        session = WorkoutSession.objects.create(
            assignment=assignment, workout_day=day, client=self.client_profile)
        WorkoutSetLog.objects.create(session=session, workout_exercise=wex, set_number=1)

        with self.captureOnCommitCallbacks(execute=True):
            res = self._delete(f'/api/allenamenti/{plan.id}/elimina/')
        self.assertEqual(res.status_code, 200)
        msg = Message.objects.get()
        self.assertEqual(msg.body, DEFAULT_PLAN_DELETED_BODY.replace('{nome}', 'Luca'))

    def test_delete_assigned_plan_uses_custom_template(self):
        AutomaticMessageTemplate.objects.create(
            coach=self.coach, event_type='PLAN_DELETED',
            body='Scheda via, {nome}!', is_enabled=True)
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Assegnata', status='ACTIVE')
        WorkoutAssignment.objects.create(
            workout_plan=plan, client=self.client_profile, coach=self.coach,
            start_date=timezone.now().date())

        with self.captureOnCommitCallbacks(execute=True):
            res = self._delete(f'/api/allenamenti/{plan.id}/elimina/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(Message.objects.get().body, 'Scheda via, Luca!')

    def test_delete_assigned_plan_respects_disabled_template(self):
        AutomaticMessageTemplate.objects.create(
            coach=self.coach, event_type='PLAN_DELETED', body='', is_enabled=False)
        plan = WorkoutPlan.objects.create(coach=self.coach, title='Assegnata', status='ACTIVE')
        WorkoutAssignment.objects.create(
            workout_plan=plan, client=self.client_profile, coach=self.coach,
            start_date=timezone.now().date())

        with self.captureOnCommitCallbacks(execute=True):
            res = self._delete(f'/api/allenamenti/{plan.id}/elimina/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(Message.objects.count(), 0)

    def test_delete_assigned_nutrition_plan_sends_default_message(self):
        plan = NutritionPlan.objects.create(coach=self.coach, title='Dieta')
        NutritionAssignment.objects.create(
            nutrition_plan=plan, client=self.client_profile, coach=self.coach,
            status='ACTIVE')

        with self.captureOnCommitCallbacks(execute=True):
            res = self._delete(f'/api/nutrizione/piani/{plan.id}/elimina/')
        self.assertEqual(res.status_code, 200)
        self.assertFalse(NutritionPlan.objects.filter(id=plan.id).exists())
        msg = Message.objects.get()
        self.assertEqual(msg.body, DEFAULT_PLAN_DELETED_BODY.replace('{nome}', 'Luca'))
