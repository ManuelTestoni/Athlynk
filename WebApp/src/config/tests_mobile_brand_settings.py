"""iOS/web settings parity: brand ("aspetto") customization + coach calendar
feed + billing portal, exposed on the mobile profile endpoints — mirrors
views_settings.py's aspetto/calendario/abbonamento tabs. See project plan
phase 9 (settings/profile personalization parity)."""
import json

from django.contrib.auth.hashers import make_password
from django.test import TestCase

from config.api import issue_token
from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.billing.models import PlatformPurchase


class ClientBrandSettingsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'),
            role='CLIENT', is_verified=True)
        ClientProfile.objects.create(user=self.user, first_name='Luca', last_name='Bianchi')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}

    def test_patch_and_get_brand(self):
        res = self.client.patch('/api/v1/profile', json.dumps({
            'brand_name': 'Luca Fit', 'brand_primary': '#112233', 'brand_accent': '#445566',
        }), content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 200)
        body = res.json()['profile']
        self.assertEqual(body['brand_name'], 'Luca Fit')
        self.assertEqual(body['brand_primary'], '#112233')
        self.assertEqual(body['brand_accent'], '#445566')

    def test_invalid_hex_rejected(self):
        res = self.client.patch('/api/v1/profile', json.dumps({'brand_primary': 'not-a-color'}),
                                content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 400)

    def test_reset_clears_brand(self):
        self.client.patch('/api/v1/profile', json.dumps({'brand_name': 'X', 'brand_primary': '#112233'}),
                          content_type='application/json', **self.auth)
        res = self.client.patch('/api/v1/profile', json.dumps({'reset': True}),
                                content_type='application/json', **self.auth)
        body = res.json()['profile']
        self.assertEqual(body['brand_name'], '')
        self.assertEqual(body['brand_primary'], '')


class CoachBrandSettingsTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'),
            role='COACH', is_verified=True)
        self.coach = CoachProfile.objects.create(
            user=self.user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE', professional_type='COACH')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {issue_token(self.user)}'}

    def test_patch_and_get_brand(self):
        res = self.client.patch('/api/v1/coach/profile', json.dumps({
            'brand_name': 'Studio Rossi', 'brand_primary': '#abcdef',
        }), content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 200)
        body = res.json()['profile']
        self.assertEqual(body['brand_name'], 'Studio Rossi')
        self.assertEqual(body['brand_primary'], '#abcdef')

    def test_calendar_feed_get_and_rotate(self):
        res = self.client.get('/api/v1/coach/calendar-feed', **self.auth)
        self.assertEqual(res.status_code, 200)
        self.assertIn('feed_url', res.json())
        self.coach.refresh_from_db()
        token_before = self.coach.calendar_feed_token

        res2 = self.client.post('/api/v1/coach/calendar-feed', json.dumps({'action': 'rotate'}),
                                content_type='application/json', **self.auth)
        self.assertEqual(res2.status_code, 200)
        self.coach.refresh_from_db()
        self.assertNotEqual(self.coach.calendar_feed_token, token_before)

    def test_billing_portal_without_purchase_returns_404(self):
        res = self.client.post('/api/v1/coach/billing-portal', '{}',
                               content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 404)

    def test_billing_portal_without_stripe_customer_returns_404(self):
        purchase = PlatformPurchase.objects.create(
            email=self.user.email, code='ATHLYNK-BRND-0001',
            plan=PlatformPurchase.PLAN_APOLLO, stripe_session_id='sess_brnd',
            status=PlatformPurchase.STATUS_ACTIVE,
        )
        self.coach.platform_purchase = purchase
        self.coach.save(update_fields=['platform_purchase'])
        res = self.client.post('/api/v1/coach/billing-portal', '{}',
                               content_type='application/json', **self.auth)
        self.assertEqual(res.status_code, 404)
