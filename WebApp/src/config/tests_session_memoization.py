"""Regression: get_session_client/coach must hit the DB once per request, not
once per caller (middleware + context processor + view each call these)."""
from django.contrib.auth.hashers import make_password
from django.test import RequestFactory, TestCase

from domain.accounts.models import User, ClientProfile, CoachProfile
from config.session_utils import get_session_client, get_session_coach


class SessionMemoizationTests(TestCase):
    def _request_for(self, user_id):
        request = RequestFactory().get('/')
        request.session = self.client.session
        request.session['user_id'] = user_id
        return request

    def test_get_session_client_hits_db_once(self):
        u = User.objects.create(email='c@e.com', password_hash=make_password('x'), role='CLIENT', is_verified=True)
        client = ClientProfile.objects.create(user=u, first_name='A', last_name='B')
        request = self._request_for(u.id)

        with self.assertNumQueries(2):  # User lookup + ClientProfile lookup
            first = get_session_client(request)
        with self.assertNumQueries(0):
            second = get_session_client(request)
        self.assertEqual(first.id, client.id)
        self.assertEqual(second.id, client.id)

    def test_get_session_coach_hits_db_once(self):
        u = User.objects.create(email='co@e.com', password_hash=make_password('x'), role='COACH', is_verified=True)
        coach = CoachProfile.objects.create(user=u, first_name='A', last_name='B', professional_type='COACH')
        request = self._request_for(u.id)

        with self.assertNumQueries(2):
            first = get_session_coach(request)
        with self.assertNumQueries(0):
            second = get_session_coach(request)
        self.assertEqual(first.id, coach.id)
        self.assertEqual(second.id, coach.id)
