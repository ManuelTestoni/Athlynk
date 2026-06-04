"""Mobile API: the chat messages endpoint and its ?since= cursor.

The open chat polls ?since=<last_id> so it fetches only newer messages (empty
when nothing changed). These tests pin that behaviour and backward compat.
"""
from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.urls import reverse

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.chat.models import Conversation, Message
from config.api import issue_token


class ApiMessagesSinceTests(TestCase):
    def setUp(self):
        self.coach_user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_active=True, is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.coach_user, first_name='Marco', last_name='Rossi')

        self.client_user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'),
            role='CLIENT', is_active=True, is_verified=True)
        self.client_profile = ClientProfile.objects.create(
            user=self.client_user, first_name='Luca', last_name='Bianchi')

        self.conv = Conversation.objects.create(coach=self.coach, client=self.client_profile)
        self.m1 = Message.objects.create(conversation=self.conv, sender_user=self.coach_user,
                                         body='uno', message_type='TEXT')
        self.m2 = Message.objects.create(conversation=self.conv, sender_user=self.coach_user,
                                         body='due', message_type='TEXT')

        self.token = issue_token(self.client_user)

    def _get(self, since=None):
        url = reverse('api_v1_messages', args=[self.conv.id])
        if since is not None:
            url += f'?since={since}'
        return self.client.get(url, HTTP_AUTHORIZATION=f'Bearer {self.token}')

    def test_no_since_returns_all(self):
        resp = self._get()
        self.assertEqual(resp.status_code, 200)
        ids = [m['id'] for m in resp.json()['messages']]
        self.assertEqual(ids, [self.m1.id, self.m2.id])

    def test_since_returns_only_newer(self):
        resp = self._get(since=self.m1.id)
        self.assertEqual([m['id'] for m in resp.json()['messages']], [self.m2.id])

    def test_since_latest_returns_empty(self):
        resp = self._get(since=self.m2.id)
        self.assertEqual(resp.json()['messages'], [])

    def test_since_non_numeric_ignored(self):
        resp = self._get(since='abc')
        self.assertEqual(len(resp.json()['messages']), 2)

    def test_requires_auth(self):
        url = reverse('api_v1_messages', args=[self.conv.id])
        self.assertEqual(self.client.get(url).status_code, 401)

    def test_other_athletes_conversation_blocked(self):
        other = User.objects.create(email='x@e.com', password_hash=make_password('x'),
                                    role='CLIENT', is_active=True, is_verified=True)
        ClientProfile.objects.create(user=other, first_name='A', last_name='B')
        url = reverse('api_v1_messages', args=[self.conv.id])
        resp = self.client.get(url, HTTP_AUTHORIZATION=f'Bearer {issue_token(other)}')
        self.assertEqual(resp.status_code, 404)
