"""Unit tests for the Stripe Connect fulfilment/webhook handlers in
views_connect.py: invoice/subscription lifecycle + the emails they trigger.
Calls the internal handlers directly (constructed Stripe-shaped dicts) to
avoid needing a real webhook signature."""
from django.contrib.auth.hashers import make_password
from django.core import mail
from django.test import TestCase

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.billing.models import Bundle, ClientSubscription, ConnectCheckoutIntent, SubscriptionPlan
from domain.coaching.models import CoachingRelationship
from config import views_connect


def make_coach(email, ptype='COACH'):
    u = User.objects.create(email=email, password_hash=make_password('x'), role='COACH', is_verified=True)
    return CoachProfile.objects.create(
        user=u, first_name='Pro', last_name=ptype.title(),
        professional_type=ptype, platform_subscription_status='ACTIVE',
        stripe_connect_account_id='acct_test123',
    )


def make_client(email='atleta@example.com'):
    u = User.objects.create(email=email, password_hash=make_password('password1'), role='CLIENT', is_verified=True)
    return ClientProfile.objects.create(user=u, first_name='Marco', last_name='Atleta')


class ConnectCheckoutFulfilmentTests(TestCase):
    def test_fulfil_sends_confirmation_and_coach_notification_emails(self):
        coach = make_coach('coach@e.com')
        client = make_client()
        CoachingRelationship.objects.create(
            coach=coach, client=client, status='ACTIVE', relationship_type='FULL',
            start_date='2026-01-01',
        )
        plan = SubscriptionPlan.objects.create(coach=coach, name='Piano Base', price=50, duration_days=30)
        intent = ConnectCheckoutIntent.objects.create(
            stripe_checkout_session_id='sess_abc', coach=coach, client=client, plan=plan,
        )

        session = {
            'id': 'sess_abc', 'amount_total': 5000, 'currency': 'eur',
            'subscription': '', 'payment_intent': '',
        }
        views_connect._fulfil_connect_checkout(session)

        self.assertTrue(ClientSubscription.objects.filter(client=client, subscription_plan=plan, status='ACTIVE').exists())
        intent.refresh_from_db()
        self.assertEqual(intent.status, ConnectCheckoutIntent.STATUS_FULFILLED)

        self.assertEqual(len(mail.outbox), 2)
        subjects = {m.subject for m in mail.outbox}
        self.assertIn('Pagamento confermato · Athlynk', subjects)
        self.assertIn('Nuovo abbonamento ricevuto · Athlynk', subjects)

    def test_fulfil_is_idempotent_on_replay(self):
        coach = make_coach('coach2@e.com')
        client = make_client('atleta2@example.com')
        CoachingRelationship.objects.create(
            coach=coach, client=client, status='ACTIVE', relationship_type='FULL',
            start_date='2026-01-01',
        )
        plan = SubscriptionPlan.objects.create(coach=coach, name='Piano Base', price=50, duration_days=30)
        intent = ConnectCheckoutIntent.objects.create(
            stripe_checkout_session_id='sess_replay', coach=coach, client=client, plan=plan,
            status=ConnectCheckoutIntent.STATUS_FULFILLED,
        )
        session = {'id': 'sess_replay', 'amount_total': 5000, 'currency': 'eur'}
        views_connect._fulfil_connect_checkout(session)
        self.assertEqual(len(mail.outbox), 0)  # already fulfilled -> no-op, no duplicate emails


class InvoicePaymentFailedTests(TestCase):
    def test_sends_failure_email_to_athlete(self):
        coach = make_coach('coach3@e.com')
        client = make_client('atleta3@example.com')
        plan = SubscriptionPlan.objects.create(coach=coach, name='Piano Base', price=50, duration_days=30)
        ClientSubscription.objects.create(
            client=client, subscription_plan=plan, status='ACTIVE', payment_status='PAID',
            start_date='2026-01-01', stripe_subscription_id='sub_123',
        )
        views_connect._handle_invoice_payment_failed({'subscription': 'sub_123'})
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].subject, 'Pagamento non riuscito · Athlynk')
        self.assertEqual(mail.outbox[0].to, [client.user.email])

    def test_no_match_does_not_error(self):
        views_connect._handle_invoice_payment_failed({'subscription': 'sub_unknown'})
        self.assertEqual(len(mail.outbox), 0)


class SubscriptionDeletedTests(TestCase):
    def test_marks_client_subscription_cancelled(self):
        coach = make_coach('coach4@e.com')
        client = make_client('atleta4@example.com')
        plan = SubscriptionPlan.objects.create(coach=coach, name='Piano Base', price=50, duration_days=30)
        sub = ClientSubscription.objects.create(
            client=client, subscription_plan=plan, status='ACTIVE', payment_status='PAID',
            start_date='2026-01-01', stripe_subscription_id='sub_456', auto_renew=True,
        )
        views_connect._handle_subscription_deleted({'id': 'sub_456'})
        sub.refresh_from_db()
        self.assertEqual(sub.status, 'CANCELLED')
        self.assertFalse(sub.auto_renew)
        # No email — invoice.payment_failed already notified the athlete.
        self.assertEqual(len(mail.outbox), 0)
