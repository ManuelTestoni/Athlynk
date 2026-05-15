"""Tests for the password-reset flow.

Cover the security-critical paths:
- happy path (request → email → reset → login with new password),
- token reuse is rejected,
- expired token is rejected,
- request with unknown email returns the same generic response (no enumeration),
- rate limiting kicks in after the per-email cap,
- consuming a token invalidates other live tokens for the same user.
"""
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth.hashers import check_password, make_password
from django.core import mail
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from domain.accounts.models import PasswordResetToken, User
from config.services import password_reset as svc


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class PasswordResetFlowTests(TestCase):
    def setUp(self):
        self.email = 'atleta@example.com'
        self.old_password = 'oldpassword123'
        self.new_password = 'brandNewPass!9'
        self.user = User.objects.create(
            email=self.email,
            password_hash=make_password(self.old_password),
            role='CLIENT',
            is_active=True,
            is_verified=True,
        )

    # ---- forgot endpoint ----------------------------------------------------

    def test_forgot_password_known_email_sends_email_and_creates_token(self):
        resp = self.client.post(reverse('forgot_password'), {'email': self.email})
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'indirizzo')
        self.assertContains(resp, 'registrato')

        self.assertEqual(PasswordResetToken.objects.filter(user=self.user).count(), 1)
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('reset-password', mail.outbox[0].body)

    def test_forgot_password_unknown_email_returns_generic_no_token(self):
        resp = self.client.post(reverse('forgot_password'), {'email': 'unknown@example.com'})
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'indirizzo')
        self.assertContains(resp, 'registrato')
        self.assertEqual(PasswordResetToken.objects.count(), 0)
        self.assertEqual(len(mail.outbox), 0)

    # ---- reset endpoint -----------------------------------------------------

    def _issue(self):
        return svc.issue_token(self.user, ip='127.0.0.1', user_agent='pytest')

    def test_reset_with_valid_token_changes_password(self):
        token = self._issue()
        resp = self.client.post(reverse('reset_password'), {
            'token': token,
            'new_password': self.new_password,
            'confirm_password': self.new_password,
        })
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'Password aggiornata')

        self.user.refresh_from_db()
        self.assertTrue(check_password(self.new_password, self.user.password_hash))
        self.assertFalse(check_password(self.old_password, self.user.password_hash))

    def test_reset_token_is_single_use(self):
        token = self._issue()
        self.client.post(reverse('reset_password'), {
            'token': token,
            'new_password': self.new_password,
            'confirm_password': self.new_password,
        })
        # second attempt with the same token must fail
        resp = self.client.post(reverse('reset_password'), {
            'token': token,
            'new_password': 'anotherPass99',
            'confirm_password': 'anotherPass99',
        })
        self.assertEqual(resp.status_code, 400)
        self.assertContains(resp, 'Link non valido', status_code=400)

    def test_expired_token_rejected(self):
        token = self._issue()
        # force-expire the token
        PasswordResetToken.objects.filter(user=self.user).update(
            expires_at=timezone.now() - timedelta(minutes=1),
        )
        resp = self.client.get(reverse('reset_password') + f'?token={token}')
        self.assertEqual(resp.status_code, 400)
        self.assertContains(resp, 'Link non valido', status_code=400)

    def test_invalid_token_rejected(self):
        resp = self.client.get(reverse('reset_password') + '?token=garbage')
        self.assertEqual(resp.status_code, 400)
        self.assertContains(resp, 'Link non valido', status_code=400)

    def test_password_mismatch_rejected_and_token_still_valid(self):
        token = self._issue()
        resp = self.client.post(reverse('reset_password'), {
            'token': token,
            'new_password': self.new_password,
            'confirm_password': 'different',
        })
        self.assertEqual(resp.status_code, 400)
        self.assertContains(resp, 'non coincidono', status_code=400)
        # token still consumable
        self.assertIsNotNone(svc.validate_token(token))

    def test_short_password_rejected(self):
        token = self._issue()
        resp = self.client.post(reverse('reset_password'), {
            'token': token,
            'new_password': 'short',
            'confirm_password': 'short',
        })
        self.assertEqual(resp.status_code, 400)
        self.assertContains(resp, 'almeno 8 caratteri', status_code=400)

    # ---- service-level invariants ------------------------------------------

    def test_issuing_new_token_invalidates_previous_active_tokens(self):
        first = self._issue()
        second = self._issue()
        self.assertIsNone(svc.validate_token(first))
        self.assertIsNotNone(svc.validate_token(second))

    def test_consuming_invalidates_other_live_tokens_for_same_user(self):
        t1 = self._issue()
        # bypass the invalidate-on-issue by creating another token by hand on the same user
        t2_plain = 'aaa'
        from hashlib import sha256
        PasswordResetToken.objects.create(
            user=self.user,
            token_hash=sha256(t2_plain.encode()).hexdigest(),
            expires_at=timezone.now() + timedelta(minutes=30),
        )
        # ensure t1 was invalidated by issuing logic above; create a fresh t3 manually
        # actually we need two live tokens — recreate t1 manually too:
        t1_plain = 'bbb'
        PasswordResetToken.objects.create(
            user=self.user,
            token_hash=sha256(t1_plain.encode()).hexdigest(),
            expires_at=timezone.now() + timedelta(minutes=30),
        )
        # consume one
        self.assertIsNotNone(svc.consume_token(t1_plain))
        # the other must now be invalid
        self.assertIsNone(svc.validate_token(t2_plain))

    def test_rate_limit_blocks_after_threshold(self):
        for _ in range(svc.RATE_LIMIT_MAX_PER_EMAIL):
            self.client.post(reverse('forgot_password'), {'email': self.email})

        outbox_before = len(mail.outbox)
        resp = self.client.post(reverse('forgot_password'), {'email': self.email})
        self.assertEqual(resp.status_code, 200)
        self.assertContains(resp, 'indirizzo')
        self.assertContains(resp, 'registrato')
        # rate-limited request must not send an email
        self.assertEqual(len(mail.outbox), outbox_before)
