"""Coach-side "propose appointment from chat" — mirrors the athlete's existing
request_appointment, reusing the same role-agnostic domain service so the
athlete's existing accept/reject UI works symmetrically against a
coach-initiated request. See project plan phase 6 (coach chat appointments)."""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from config.api import issue_token
from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.calendar.models import Appointment
from domain.chat.models import Conversation, Message


class CoachRequestAppointmentTests(TestCase):
    def setUp(self):
        self.coach_user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.coach_user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        self.client_user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'),
            role='CLIENT', is_verified=True)
        self.client_profile = ClientProfile.objects.create(
            user=self.client_user, first_name='Luca', last_name='Bianchi')
        self.conv = Conversation.objects.create(coach=self.coach, client=self.client_profile)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.coach_user)}'}

    def _request(self, conv_id, **overrides):
        payload = {
            'title': 'Check-in mensile', 'preferred_date': '2026-08-01',
            'time_from': '10:00', 'time_to': '11:00',
        }
        payload.update(overrides)
        return self.client.post(f'/api/v1/coach/conversations/{conv_id}/appointment',
                                json.dumps(payload), content_type='application/json', **self.auth)

    def test_coach_can_propose_appointment(self):
        res = self._request(self.conv.id)
        self.assertEqual(res.status_code, 201)
        appt = Appointment.objects.get()
        self.assertEqual(appt.coach, self.coach)
        self.assertEqual(appt.client, self.client_profile)
        self.assertEqual(appt.status, 'PENDING')
        msg = Message.objects.get()
        self.assertEqual(msg.message_type, 'APPOINTMENT_REQUEST')
        self.assertEqual(msg.sender_user_id, self.coach_user.id)

    def test_cannot_propose_into_someone_elses_conversation(self):
        other_coach_user = User.objects.create(
            email='other@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        other_coach = CoachProfile.objects.create(
            user=other_coach_user, first_name='Altro', last_name='Coach',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        other_conv = Conversation.objects.create(coach=other_coach, client=self.client_profile)

        res = self._request(other_conv.id)
        self.assertEqual(res.status_code, 404)
        self.assertFalse(Appointment.objects.exists())

    def test_missing_time_range_rejected(self):
        res = self._request(self.conv.id, time_from='', time_to='')
        self.assertEqual(res.status_code, 400)
