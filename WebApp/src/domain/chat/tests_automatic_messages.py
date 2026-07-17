"""Tests for coach → athlete automatic chat messages.

Covers the lifecycle signals (welcome on new ACTIVE relationship, goodbye on
transition to INACTIVE) and the subscription-expiry management command, including
the opt-in gate, token personalization, and idempotency.
"""
from datetime import timedelta
from io import StringIO

from django.contrib.auth.hashers import make_password
from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship
from domain.billing.models import SubscriptionPlan, ClientSubscription
from domain.chat.models import Conversation, Message, AutomaticMessageTemplate


class AutomaticMessageTests(TestCase):
    def setUp(self):
        self.coach_user = User.objects.create(
            email='coach@example.com', password_hash=make_password('x'), role='COACH')
        self.coach = CoachProfile.objects.create(
            user=self.coach_user, first_name='Marco', last_name='Rossi',
            platform_subscription_status='ACTIVE')

        self.client_user = User.objects.create(
            email='atleta@example.com', password_hash=make_password('x'), role='CLIENT')
        self.client_profile = ClientProfile.objects.create(
            user=self.client_user, first_name='Luca', last_name='Bianchi')

    def _template(self, event_type, body, enabled=True):
        return AutomaticMessageTemplate.objects.create(
            coach=self.coach, event_type=event_type, body=body, is_enabled=enabled)

    def _create_active_relationship(self):
        with self.captureOnCommitCallbacks(execute=True):
            return CoachingRelationship.objects.create(
                coach=self.coach, client=self.client_profile,
                status='ACTIVE', start_date=timezone.now().date())

    # ---- welcome ------------------------------------------------------------

    def test_welcome_sent_on_new_active_relationship(self):
        self._template('WELCOME', 'Ciao {nome} {cognome}!')
        self._create_active_relationship()

        conv = Conversation.objects.get(coach=self.coach, client=self.client_profile)
        msg = conv.messages.get()
        self.assertEqual(msg.body, 'Ciao Luca Bianchi!')
        self.assertEqual(msg.sender_user_id, self.coach_user.id)
        self.assertEqual(msg.message_type, 'TEXT')
        self.assertEqual(conv.last_message_at, msg.sent_at)

    def test_no_welcome_when_template_disabled(self):
        self._template('WELCOME', 'Ciao!', enabled=False)
        self._create_active_relationship()
        self.assertEqual(Message.objects.count(), 0)

    def test_no_welcome_when_no_template(self):
        self._create_active_relationship()
        self.assertEqual(Message.objects.count(), 0)

    def test_welcome_sent_with_default_body_when_enabled_and_empty(self):
        # Enabling the event with no custom text must still send a generic
        # default message, matching how PLAN_DELETED already behaves.
        from domain.chat.services import DEFAULT_WELCOME_BODY
        self._template('WELCOME', '', enabled=True)
        self._create_active_relationship()
        msg = Message.objects.get()
        self.assertEqual(msg.body, DEFAULT_WELCOME_BODY.replace('{nome}', 'Luca'))

    # ---- goodbye ------------------------------------------------------------

    def test_goodbye_sent_on_transition_to_inactive(self):
        self._template('GOODBYE', 'Arrivederci {nome}!')
        rel = self._create_active_relationship()  # no WELCOME template → no message yet
        self.assertEqual(Message.objects.count(), 0)

        rel.status = 'INACTIVE'
        with self.captureOnCommitCallbacks(execute=True):
            rel.save(update_fields=['status'])

        msg = Message.objects.get()
        self.assertEqual(msg.body, 'Arrivederci Luca!')

    def test_goodbye_not_resent_when_already_inactive(self):
        self._template('GOODBYE', 'Arrivederci!')
        rel = self._create_active_relationship()
        rel.status = 'INACTIVE'
        with self.captureOnCommitCallbacks(execute=True):
            rel.save(update_fields=['status'])
        self.assertEqual(Message.objects.count(), 1)

        # saving again while already inactive must not resend
        with self.captureOnCommitCallbacks(execute=True):
            rel.save(update_fields=['status'])
        self.assertEqual(Message.objects.count(), 1)

    # ---- settings page (view + template) -----------------------------------

    def _login_coach(self):
        session = self.client.session
        session['user_id'] = self.coach_user.id
        session.save()

    def test_settings_page_renders_for_coach(self):
        self._login_coach()
        # The standalone page redirects to the settings dashboard tab.
        resp = self.client.get('/impostazioni/messaggi-automatici/', follow=True)
        self.assertEqual(resp.status_code, 200)
        self.assertTemplateUsed(resp, 'pages/impostazioni/dashboard.html')
        self.assertContains(resp, 'Benvenuto')
        self.assertContains(resp, 'Arrivederci')
        self.assertContains(resp, 'Scheda eliminata')

    def test_settings_post_saves_template(self):
        self._login_coach()
        resp = self.client.post('/impostazioni/messaggi-automatici/', {
            'body_WELCOME': 'Ciao {nome}!',
            'enabled_WELCOME': 'on',
            'body_GOODBYE': '',
            'body_SUBSCRIPTION_EXPIRING': '',
        })
        self.assertRedirects(resp, '/impostazioni/?saved=messaggi_auto')
        tpl = AutomaticMessageTemplate.objects.get(coach=self.coach, event_type='WELCOME')
        self.assertTrue(tpl.is_enabled)
        self.assertEqual(tpl.body, 'Ciao {nome}!')

    # ---- subscription expiry command ---------------------------------------

    def test_expiry_command_sends_once_and_is_idempotent(self):
        self._template('SUBSCRIPTION_EXPIRING', 'Scade presto {nome}!')
        plan = SubscriptionPlan.objects.create(
            coach=self.coach, name='Base', plan_type='monthly', price=50)
        sub = ClientSubscription.objects.create(
            client=self.client_profile, subscription_plan=plan,
            status='ACTIVE', payment_status='PAID',
            start_date=timezone.now().date(),
            end_date=timezone.now().date() + timedelta(days=3))

        call_command('send_expiry_reminders', '--days', '7', stdout=StringIO())
        sub.refresh_from_db()
        self.assertTrue(sub.expiry_reminder_sent)
        self.assertEqual(Message.objects.filter(body='Scade presto Luca!').count(), 1)

        # second run: flag already set → no duplicate
        call_command('send_expiry_reminders', '--days', '7', stdout=StringIO())
        self.assertEqual(Message.objects.filter(body='Scade presto Luca!').count(), 1)
