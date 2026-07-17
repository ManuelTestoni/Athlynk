"""Regression tests for coach platform-purchase code redemption, returning-
customer checkout reactivation, and subscription-duration/Chiron gating.
"""
from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile
from domain.billing.models import PlatformPurchase
from config.session_utils import coach_has_active_platform_access, coach_has_chiron_access
from config.tests_access_gating import make_coach, make_purchase
from config.views_payments import _fulfil_checkout, _sync_subscription


class SignupCodeRedemptionTests(TestCase):
    def setUp(self):
        # Each test drives multiple /registrati/ POSTs from the same test-client
        # IP; clear the cache-backed rate limiters so one test's attempts don't
        # trip another's (SIGNUP_RATE_LIMIT/SIGNUP_CODE_RATE_LIMIT share a cache).
        cache.clear()

    def _post(self, email, code, extra=None):
        data = {
            'role': 'COACH', 'professional_type': 'COACH',
            'first_name': 'A', 'last_name': 'B',
            'email': email, 'password': 'V0lt!Athlynk#9', 'confirm_password': 'V0lt!Athlynk#9',
            'accept_terms': 'on', 'code': code,
        }
        data.update(extra or {})
        return self.client.post('/registrati/', data)

    def test_missing_code_rejected(self):
        resp = self._post('a@e.com', '')
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(User.objects.filter(email='a@e.com').exists())

    def test_unknown_code_rejected(self):
        resp = self._post('a@e.com', 'ATHLYNK-NOPE-NOPE')
        self.assertEqual(resp.status_code, 400)

    def test_already_redeemed_code_rejected(self):
        purchase = make_purchase('a@e.com', code='ATHLYNK-USED-0001', redeemed_at=timezone.now())
        resp = self._post('a@e.com', purchase.code)
        self.assertEqual(resp.status_code, 400)

    def test_canceled_purchase_code_rejected(self):
        purchase = make_purchase('a@e.com', code='ATHLYNK-CANC-0001', status=PlatformPurchase.STATUS_CANCELED)
        resp = self._post('a@e.com', purchase.code)
        self.assertEqual(resp.status_code, 400)

    def test_email_mismatch_rejected(self):
        purchase = make_purchase('buyer@e.com', code='ATHLYNK-MISM-0001')
        resp = self._post('other@e.com', purchase.code)
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(User.objects.filter(email='other@e.com').exists())
        purchase.refresh_from_db()
        self.assertIsNone(purchase.redeemed_at)

    def test_code_cannot_be_reused(self):
        purchase = make_purchase('a@e.com', code='ATHLYNK-ONCE-0001')
        resp1 = self._post('a@e.com', purchase.code)
        self.assertEqual(resp1.status_code, 200)
        resp2 = self._post('a2@e.com', purchase.code)
        self.assertEqual(resp2.status_code, 400)
        self.assertFalse(User.objects.filter(email='a2@e.com').exists())


class ReturningCustomerFulfilmentTests(TestCase):
    def _fake_session(self, email, returning, session_id='sess_1'):
        return {
            'id': session_id,
            'customer_details': {'email': email},
            'metadata': {'plan': 'apollo', 'chiron': '0', 'billing': 'mensile',
                         'returning_customer': '1' if returning else '0'},
            'subscription': '',  # no live Stripe lookup in tests
            'customer': 'cus_1',
            'amount_total': 5990,
            'currency': 'eur',
        }

    def test_new_customer_gets_code(self):
        _fulfil_checkout(self._fake_session('new@e.com', returning=False))
        purchase = PlatformPurchase.objects.get(stripe_session_id='sess_1')
        self.assertFalse(purchase.returning_customer)
        self.assertIsNone(purchase.redeemed_at)

    def test_returning_customer_reactivates_existing_account(self):
        coach = make_coach('existing@e.com', 'COACH')
        _fulfil_checkout(self._fake_session('existing@e.com', returning=True, session_id='sess_2'))
        purchase = PlatformPurchase.objects.get(stripe_session_id='sess_2')
        self.assertIsNotNone(purchase.redeemed_at)
        self.assertEqual(purchase.redeemed_by, coach.user)
        coach.refresh_from_db()
        self.assertEqual(coach.platform_purchase_id, purchase.id)

    def test_returning_customer_no_match_falls_back_to_code(self):
        _fulfil_checkout(self._fake_session('ghost@e.com', returning=True, session_id='sess_3'))
        purchase = PlatformPurchase.objects.get(stripe_session_id='sess_3')
        self.assertIsNone(purchase.redeemed_at)
        self.assertTrue(purchase.returning_customer)


class SyncSubscriptionTests(TestCase):
    def test_cancel_at_period_end_does_not_immediately_cancel(self):
        purchase = make_purchase('c@e.com', code='ATHLYNK-SYNC-0001',
                                  stripe_subscription_id='sub_1', status=PlatformPurchase.STATUS_ACTIVE)
        _sync_subscription({'id': 'sub_1', 'status': 'active', 'cancel_at_period_end': True,
                             'current_period_end': int(timezone.now().timestamp()) + 86400})
        purchase.refresh_from_db()
        self.assertEqual(purchase.status, PlatformPurchase.STATUS_ACTIVE)

    def test_terminal_canceled_status_cancels(self):
        purchase = make_purchase('c@e.com', code='ATHLYNK-SYNC-0002',
                                  stripe_subscription_id='sub_2', status=PlatformPurchase.STATUS_ACTIVE)
        _sync_subscription({'id': 'sub_2', 'status': 'canceled', 'cancel_at_period_end': True})
        purchase.refresh_from_db()
        self.assertEqual(purchase.status, PlatformPurchase.STATUS_CANCELED)


class CoachPlatformAccessTests(TestCase):
    def _login(self, user):
        s = self.client.session
        s['user_id'] = user.id
        s['user_role'] = user.role
        s.save()

    def test_no_purchase_is_grandfathered_in(self):
        # Accounts created before this feature have no linked PlatformPurchase
        # at all — they must not be locked out on deploy (see coach_has_active_
        # platform_access docstring). Only a canceled/lapsed purchase blocks.
        coach = make_coach('nopur@e.com', 'COACH')
        self.assertTrue(coach_has_active_platform_access(coach))

    def test_canceled_purchase_blocks_access(self):
        coach = make_coach('cancd@e.com', 'COACH')
        purchase = make_purchase('cancd@e.com', code='ATHLYNK-CAN2-0001',
                                  status=PlatformPurchase.STATUS_CANCELED)
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self.assertFalse(coach_has_active_platform_access(coach))

    def test_active_purchase_within_period_allows_access(self):
        coach = make_coach('ok@e.com', 'COACH')
        purchase = make_purchase('ok@e.com', code='ATHLYNK-OK01-0001',
                                  current_period_end=timezone.now() + timedelta(days=10))
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self.assertTrue(coach_has_active_platform_access(coach))

    def test_lapsed_period_end_blocks_access(self):
        coach = make_coach('lapsed@e.com', 'COACH')
        purchase = make_purchase('lapsed@e.com', code='ATHLYNK-LAP1-0001',
                                  current_period_end=timezone.now() - timedelta(days=1))
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self.assertFalse(coach_has_active_platform_access(coach))

    def test_chiron_requires_addon_flag(self):
        coach = make_coach('chiron@e.com', 'COACH')
        purchase = make_purchase('chiron@e.com', code='ATHLYNK-CHR1-0001',
                                  current_period_end=timezone.now() + timedelta(days=10), has_chiron=False)
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self.assertTrue(coach_has_active_platform_access(coach))
        self.assertFalse(coach_has_chiron_access(coach))

        purchase.has_chiron = True
        purchase.save(update_fields=['has_chiron'])
        self.assertTrue(coach_has_chiron_access(coach))

    def test_lapsed_coach_redirected_by_middleware(self):
        coach = make_coach('mw@e.com', 'COACH')
        purchase = make_purchase('mw@e.com', code='ATHLYNK-MW01-0001',
                                  current_period_end=timezone.now() - timedelta(days=1))
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self._login(coach.user)
        resp = self.client.get('/')
        self.assertRedirects(resp, '/abbonamento-scaduto/', fetch_redirect_response=False)

    def test_active_coach_not_redirected(self):
        coach = make_coach('mw2@e.com', 'COACH')
        purchase = make_purchase('mw2@e.com', code='ATHLYNK-MW02-0001',
                                  current_period_end=timezone.now() + timedelta(days=10))
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self._login(coach.user)
        resp = self.client.get('/')
        self.assertEqual(resp.status_code, 200)


class ChironImportGatingTests(TestCase):
    """AI import (workout/diet, Excel/PDF) requires the has_chiron add-on,
    same as the Chiron chat endpoints — see [[reference_middleware_multipart_gate]]."""

    IMPORT_URLS = [
        '/api/allenamenti/import/excel/', '/api/allenamenti/import/pdf/',
        '/api/nutrizione/import/excel/', '/api/nutrizione/import/pdf/',
    ]

    def _login(self, user):
        s = self.client.session
        s['user_id'] = user.id
        s['user_role'] = user.role
        s.save()

    def test_import_blocked_without_chiron(self):
        coach = make_coach('noaddon@e.com', 'COACH')
        purchase = make_purchase('noaddon@e.com', code='ATHLYNK-IMP1-0001',
                                  current_period_end=timezone.now() + timedelta(days=10), has_chiron=False)
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self._login(coach.user)
        for url in self.IMPORT_URLS:
            resp = self.client.post(url, data={})
            self.assertEqual(resp.status_code, 403, url)
            self.assertEqual(resp.json()['error'], 'Il tuo piano non include Chiron.', url)

    def test_import_allowed_with_chiron(self):
        coach = make_coach('addon@e.com', 'COACH')
        purchase = make_purchase('addon@e.com', code='ATHLYNK-IMP2-0001',
                                  current_period_end=timezone.now() + timedelta(days=10), has_chiron=True)
        coach.platform_purchase = purchase
        coach.save(update_fields=['platform_purchase'])
        self._login(coach.user)
        for url in self.IMPORT_URLS:
            # No file attached: the chiron gate must be passed, next failure is
            # the view's own "missing file" validation, never the 403 above.
            resp = self.client.post(url, data={})
            self.assertEqual(resp.status_code, 422, url)
