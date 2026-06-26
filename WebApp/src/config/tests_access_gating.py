"""Regression tests for the athlete access-gating rework.

Covers: professionals-only signup, suspended-athlete gating (web + mobile),
verification-resend cooldown, add-existing-athlete pairing + reactive section
coach resolution, subscription-expiry deactivation, and coach-side end of
collaboration.
"""
from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.billing.models import SubscriptionPlan, ClientSubscription
from domain.coaching.models import CoachingRelationship
from config.session_utils import (
    client_has_active_access, enforce_client_access,
    get_nutrition_coach, get_workout_coach,
)


def make_coach(email, ptype):
    u = User.objects.create(email=email, password_hash=make_password('x'), role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=u, first_name='Pro', last_name=ptype.title(),
        professional_type=ptype, platform_subscription_status='ACTIVE',
    )


def make_client(email='atleta@example.com'):
    u = User.objects.create(email=email, password_hash=make_password('password1'), role='CLIENT', is_verified=True)
    return ClientProfile.objects.create(user=u, first_name='Marco', last_name='Atleta')


def plan_for(coach, days=30):
    return SubscriptionPlan.objects.create(
        coach=coach, name='Base', plan_type='RECURRING', price=50, duration_days=days,
    )


def active_sub(client, plan, end_offset_days=30):
    today = timezone.now().date()
    return ClientSubscription.objects.create(
        client=client, subscription_plan=plan, status='ACTIVE', payment_status='PAID',
        start_date=today, end_date=today + timedelta(days=end_offset_days),
    )


def rel(coach, client, rtype, status='ACTIVE'):
    return CoachingRelationship.objects.create(
        coach=coach, client=client, status=status,
        start_date=timezone.now().date(), relationship_type=rtype,
    )


class SignupTests(TestCase):
    def test_client_signup_rejected(self):
        resp = self.client.post('/registrati/', {
            'role': 'CLIENT', 'first_name': 'A', 'last_name': 'B',
            'email': 'x@y.com', 'password': 'V0lt!Athlynk#9', 'confirm_password': 'V0lt!Athlynk#9',
        })
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(User.objects.filter(email='x@y.com').exists())

    def test_professional_signup_ok(self):
        resp = self.client.post('/registrati/', {
            'role': 'COACH', 'professional_type': 'ALLENATORE',
            'first_name': 'A', 'last_name': 'B',
            'email': 'pro@y.com', 'password': 'V0lt!Athlynk#9', 'confirm_password': 'V0lt!Athlynk#9',
            'accept_terms': 'on',
        })
        self.assertEqual(resp.status_code, 200)
        u = User.objects.get(email='pro@y.com')
        self.assertEqual(u.role, 'COACH')
        self.assertEqual(u.coach_profile.professional_type, 'ALLENATORE')
        self.assertIsNotNone(u.terms_accepted_at)

    def test_signup_without_terms_rejected(self):
        resp = self.client.post('/registrati/', {
            'role': 'COACH', 'professional_type': 'COACH',
            'first_name': 'A', 'last_name': 'B',
            'email': 'noterms@y.com', 'password': 'V0lt!Athlynk#9', 'confirm_password': 'V0lt!Athlynk#9',
        })
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(User.objects.filter(email='noterms@y.com').exists())


class WebGatingTests(TestCase):
    def _login(self, user):
        s = self.client.session
        s['user_id'] = user.id
        s['user_role'] = user.role
        s.save()

    def test_blocked_athlete_redirected(self):
        client = make_client()
        self._login(client.user)
        resp = self.client.get('/')
        self.assertRedirects(resp, '/accesso-sospeso/', fetch_redirect_response=False)

    def test_active_athlete_allowed(self):
        coach = make_coach('c@e.com', 'ALLENATORE')
        client = make_client()
        rel(coach, client, 'WORKOUT')
        self._login(client.user)
        resp = self.client.get('/')
        self.assertEqual(resp.status_code, 200)

    def test_blocked_page_reachable_while_suspended(self):
        client = make_client()
        self._login(client.user)
        resp = self.client.get('/accesso-sospeso/')
        self.assertEqual(resp.status_code, 200)


class AccessHelperTests(TestCase):
    def test_expiry_deactivates_relationship(self):
        coach = make_coach('c@e.com', 'COACH')
        client = make_client()
        rel(coach, client, 'FULL')
        sub = active_sub(client, plan_for(coach), end_offset_days=30)
        # Backdate the subscription so it is lapsed.
        sub.end_date = timezone.now().date() - timedelta(days=1)
        sub.save(update_fields=['end_date'])

        self.assertTrue(client_has_active_access(client))
        enforce_client_access(client)
        self.assertFalse(client_has_active_access(client))
        sub.refresh_from_db()
        self.assertEqual(sub.status, 'EXPIRED')
        self.assertFalse(CoachingRelationship.objects.filter(client=client, status='ACTIVE').exists())

    def test_section_coach_resolution(self):
        trainer = make_coach('t@e.com', 'ALLENATORE')
        nutri = make_coach('n@e.com', 'NUTRIZIONISTA')
        client = make_client()
        rel(trainer, client, 'WORKOUT')
        self.assertEqual(get_workout_coach(client), trainer)
        self.assertIsNone(get_nutrition_coach(client))
        rel(nutri, client, 'NUTRITION')
        self.assertEqual(get_nutrition_coach(client), nutri)
        self.assertEqual(get_workout_coach(client), trainer)


class AddExistingAthleteTests(TestCase):
    def _login_coach(self, coach):
        s = self.client.session
        s['user_id'] = coach.user.id
        s['user_role'] = 'COACH'
        s.save()

    def test_nutritionist_adds_existing_trainer_athlete(self):
        trainer = make_coach('t@e.com', 'ALLENATORE')
        nutri = make_coach('n@e.com', 'NUTRIZIONISTA')
        client = make_client()
        rel(trainer, client, 'WORKOUT')
        nutri_plan = plan_for(nutri)

        self._login_coach(nutri)
        resp = self.client.post('/clienti/registra/', {
            'mode': 'existing', 'email': client.user.email,
            'subscription_plan_id': str(nutri_plan.id),
        })
        self.assertEqual(resp.status_code, 302)
        self.assertTrue(
            CoachingRelationship.objects.filter(
                coach=nutri, client=client, status='ACTIVE', relationship_type='NUTRITION',
            ).exists()
        )
        self.assertEqual(get_nutrition_coach(client), nutri)

    def test_pairing_conflict_blocks_duplicate(self):
        trainer1 = make_coach('t1@e.com', 'ALLENATORE')
        trainer2 = make_coach('t2@e.com', 'ALLENATORE')
        client = make_client()
        rel(trainer1, client, 'WORKOUT')
        plan2 = plan_for(trainer2)

        s = self.client.session
        s['user_id'] = trainer2.user.id
        s['user_role'] = 'COACH'
        s.save()
        resp = self.client.post('/clienti/registra/', {
            'mode': 'existing', 'email': client.user.email,
            'subscription_plan_id': str(plan2.id),
        })
        # Re-rendered form (200) with an error, no new relationship.
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(
            CoachingRelationship.objects.filter(coach=trainer2, client=client).exists()
        )

    def test_coach_ends_collaboration(self):
        coach = make_coach('c@e.com', 'COACH')
        client = make_client()
        r = rel(coach, client, 'FULL')
        s = self.client.session
        s['user_id'] = coach.user.id
        s['user_role'] = 'COACH'
        s.save()
        resp = self.client.post(f'/clienti/{client.id}/termina/')
        self.assertEqual(resp.status_code, 302)
        r.refresh_from_db()
        self.assertEqual(r.status, 'INACTIVE')


class ResendCooldownTests(TestCase):
    def test_resend_blocked_within_cooldown(self):
        u = User.objects.create(
            email='new@e.com', password_hash=make_password('x'), role='COACH',
            is_verified=False, email_verification_token='tok',
            email_verification_sent_at=timezone.now(),
        )
        resp = self.client.post('/verify/reinvia/', {'email': u.email})
        self.assertEqual(resp.status_code, 200)
        self.assertIn(b'Reinvia tra', resp.content + b'')  # countdown rendered
        u.refresh_from_db()
        self.assertEqual(u.email_verification_token, 'tok')  # token NOT rotated

    def test_resend_allowed_after_cooldown(self):
        u = User.objects.create(
            email='old@e.com', password_hash=make_password('x'), role='COACH',
            is_verified=False, email_verification_token='tok',
            email_verification_sent_at=timezone.now() - timedelta(seconds=200),
        )
        resp = self.client.post('/verify/reinvia/', {'email': u.email})
        self.assertEqual(resp.status_code, 200)
        u.refresh_from_db()
        self.assertNotEqual(u.email_verification_token, 'tok')  # rotated → resent


class ActivationFlowTests(TestCase):
    def _login_coach(self, coach):
        s = self.client.session
        s['user_id'] = coach.user.id
        s['user_role'] = 'COACH'
        s.save()

    def test_new_athlete_no_password_sends_activation(self):
        from django.contrib.auth.hashers import check_password
        from django.core import mail
        from domain.accounts.models import PasswordResetToken

        coach = make_coach('c@e.com', 'COACH')
        plan = plan_for(coach)
        self._login_coach(coach)
        resp = self.client.post('/clienti/registra/', {
            'mode': 'new', 'first_name': 'Neo', 'last_name': 'Atleta',
            'email': 'neo@e.com', 'birth_date': '15-03-1990',
            'subscription_plan_id': str(plan.id),
        })
        self.assertEqual(resp.status_code, 302)
        u = User.objects.get(email='neo@e.com')
        self.assertEqual(u.role, 'CLIENT')
        self.assertTrue(u.is_verified)
        # Unusable password: no login possible until the athlete sets one.
        self.assertFalse(check_password('anything', u.password_hash))
        # Activation token issued + activation email sent.
        self.assertTrue(PasswordResetToken.objects.filter(user=u, used_at__isnull=True).exists())
        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('Attiva', mail.outbox[0].subject)

    def test_activation_page_sets_password(self):
        from django.contrib.auth.hashers import check_password
        from django.test import Client
        from config.services import password_reset as pwd

        u = User.objects.create(
            email='neo@e.com', password_hash=make_password(None), role='CLIENT', is_verified=True,
        )
        ClientProfile.objects.create(user=u, first_name='Neo', last_name='A')
        token = pwd.issue_token(u, ttl_minutes=pwd.ACTIVATION_TTL_MINUTES)

        c = Client()
        g = c.get(f'/attiva-account/?token={token}')
        self.assertEqual(g.status_code, 200)
        self.assertContains(g, 'neo@e.com')

        p = c.post('/attiva-account/', {
            'token': token, 'new_password': 'V0lt!Athlynk#9', 'confirm_password': 'V0lt!Athlynk#9',
            'accept_terms': 'on',
        })
        self.assertEqual(p.status_code, 302)
        self.assertIn('activated=1', p['Location'])
        u.refresh_from_db()
        self.assertTrue(check_password('V0lt!Athlynk#9', u.password_hash))
        self.assertIsNotNone(u.terms_accepted_at)

    def test_activation_invalid_token(self):
        from django.test import Client
        c = Client()
        g = c.get('/attiva-account/?token=bogus')
        self.assertEqual(g.status_code, 400)
        self.assertContains(g, 'Link non valido', status_code=400)


class MobileGateTests(TestCase):
    def test_blocked_client_403_on_data_endpoint(self):
        from config.api import issue_token
        client = make_client()
        token = issue_token(client.user)
        resp = self.client.get('/api/v1/workouts', HTTP_AUTHORIZATION=f'Bearer {token}')
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json().get('error'), 'access_blocked')

    def test_active_client_ok_on_me(self):
        from config.api import issue_token
        coach = make_coach('c@e.com', 'COACH')
        client = make_client()
        rel(coach, client, 'FULL')
        token = issue_token(client.user)
        resp = self.client.get('/api/v1/me', HTTP_AUTHORIZATION=f'Bearer {token}')
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.json().get('access_blocked'))
