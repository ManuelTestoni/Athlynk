"""Eliminazione account: deve fare hard-delete a cascata anche quando esistono
FK PROTECT (ClientSubscription → SubscriptionPlan), sia per coach che atleta."""
from datetime import date

from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.accounts.services import hard_delete_user
from domain.billing.models import SubscriptionPlan, ClientSubscription
from domain.coaching.models import CoachingRelationship
from .api import issue_token

LOCMEM = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}


@override_settings(CACHES=LOCMEM)
class HardDeleteTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach@e.com', password_hash=make_password('x'),
                                 role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=cu, first_name='Pro', last_name='Coach', professional_type='COACH')
        self.plan = SubscriptionPlan.objects.create(
            coach=self.coach, name='Base', price=50, duration_days=30, is_active=True)

        au = User.objects.create(email='atl@e.com', password_hash=make_password('x'),
                                 role='CLIENT', is_verified=True)
        self.client_user = au
        self.athlete = ClientProfile.objects.create(user=au, first_name='Mario', last_name='Rossi')
        CoachingRelationship.objects.create(
            coach=self.coach, client=self.athlete, status='ACTIVE', start_date=date.today())
        ClientSubscription.objects.create(
            client=self.athlete, subscription_plan=self.plan,
            status='ACTIVE', payment_status='PAID', start_date=date.today())

    def test_delete_coach_with_protected_subscription(self):
        """Deleting the coach must clear the PROTECT-blocked subscriptions first."""
        hard_delete_user(self.coach.user)
        self.assertFalse(User.objects.filter(email='coach@e.com').exists())
        self.assertFalse(SubscriptionPlan.objects.exists())
        self.assertFalse(ClientSubscription.objects.exists())

    def test_delete_athlete_cascades(self):
        hard_delete_user(self.client_user)
        self.assertFalse(User.objects.filter(email='atl@e.com').exists())
        self.assertFalse(ClientProfile.objects.exists())
        self.assertFalse(ClientSubscription.objects.exists())
        self.assertTrue(SubscriptionPlan.objects.exists())  # coach's plan survives

    def test_mobile_delete_endpoint(self):
        token = issue_token(self.client_user)
        resp = self.client.delete('/api/v1/account', HTTP_AUTHORIZATION=f'Bearer {token}')
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(User.objects.filter(email='atl@e.com').exists())
