"""Il coach crea un atleta dall'app mobile: account + relazione + abbonamento +
email di attivazione, come nella web app."""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings
from django.core import mail

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.billing.models import SubscriptionPlan
from domain.coaching.models import CoachingRelationship
from .api import issue_token

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


@override_settings(CACHES=LOCMEM)
class CoachCreateClientTests(TestCase):
    def setUp(self):
        u = User.objects.create(email='coach@e.com', password_hash=make_password('x'),
                                role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=u, first_name='Pro', last_name='Coach',
            professional_type='COACH', platform_subscription_status='ACTIVE')
        self.plan = SubscriptionPlan.objects.create(
            coach=self.coach, name='Base', price=50, duration_days=30, is_active=True)
        self.token = issue_token(u)

    def _auth(self):
        return {'HTTP_AUTHORIZATION': f'Bearer {self.token}'}

    def test_create_client_full_flow(self):
        resp = self.client.post(
            '/api/v1/coach/clients/create',
            data=json.dumps({
                'first_name': 'Mario', 'last_name': 'Rossi',
                'email': 'mario@e.com', 'subscription_plan_id': self.plan.id,
            }),
            content_type='application/json', **self._auth())
        self.assertEqual(resp.status_code, 201)
        client = ClientProfile.objects.get(user__email='mario@e.com')
        self.assertTrue(CoachingRelationship.objects.filter(
            coach=self.coach, client=client, status='ACTIVE').exists())
        self.assertTrue(client.subscriptions.filter(status='ACTIVE').exists())
        self.assertEqual(len(mail.outbox), 1)  # activation email

    def test_duplicate_email_rejected(self):
        User.objects.create(email='dupe@e.com', password_hash=make_password('x'), role='CLIENT')
        resp = self.client.post(
            '/api/v1/coach/clients/create',
            data=json.dumps({
                'first_name': 'A', 'last_name': 'B',
                'email': 'dupe@e.com', 'subscription_plan_id': self.plan.id,
            }),
            content_type='application/json', **self._auth())
        self.assertEqual(resp.status_code, 400)

    def test_subscription_plans_listed(self):
        resp = self.client.get('/api/v1/coach/subscription-plans', **self._auth())
        self.assertEqual(resp.status_code, 200)
        plans = resp.json()['plans']
        self.assertEqual(len(plans), 1)
        self.assertEqual(plans[0]['name'], 'Base')
