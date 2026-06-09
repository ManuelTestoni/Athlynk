"""Smoke tests: migrations apply on SQLite, the rule engine scores/explains, and
the feature store + scoring round-trips for a seeded client.
"""

from datetime import date, timedelta

from django.core.management import call_command
from django.test import TestCase, override_settings
from django.utils import timezone

from domain.accounts.models import ClientProfile, CoachProfile, User
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.coaching.models import CoachingRelationship

from .models import (
    CoachBusinessMetricsDaily, DailyFeatureStore, ModelVersion, RiskScoreDaily,
)
from .services import features as feat
from .services import rules_engine as rules
from .services.identity import resolve_flags


class RulesEngineTests(TestCase):
    def test_low_risk_when_quiet(self):
        score, codes = rules.score({})
        self.assertEqual(score, 0)
        self.assertEqual(codes, [])
        self.assertEqual(rules.classify(score), 'low')

    def test_weights_and_reason_codes(self):
        f = {'days_since_last_login': 9, 'payment_failures_30d': 1}
        score, codes = rules.score(f)
        self.assertEqual(score, 40)  # 15 + 25
        self.assertEqual(rules.classify(score), 'medium')
        self.assertIn('no_login_7d', codes)
        self.assertIn('payment_failed', codes)

    def test_score_capped_at_100(self):
        f = {'days_since_last_login': 99, 'days_since_last_checkin': 99,
             'payment_failures_30d': 5, 'avg_coach_response_minutes_30d': 99999,
             'engagement_delta_7d_vs_30d': -0.9, 'ignored_reminders_30d': 9,
             'days_to_renewal': 2, 'messages_7d': 0, 'login_count_7d': 0}
        score, _ = rules.score(f)  # raw 110 -> capped
        self.assertEqual(score, 100)
        self.assertEqual(rules.classify(score), 'high')


@override_settings(TEST_ACCOUNT_EMAILS=['t@x.com'], INTERNAL_EMAIL_DOMAINS=['athlynk.com'])
class IdentityTests(TestCase):
    def test_env_allowlists(self):
        u1 = User.objects.create(email='t@x.com', password_hash='x', role='client')
        u2 = User.objects.create(email='dev@athlynk.com', password_hash='x', role='coach')
        u3 = User.objects.create(email='real@gmail.com', password_hash='x', role='client')
        self.assertTrue(resolve_flags(u1)['is_test_account'])
        self.assertTrue(resolve_flags(u2)['is_internal_user'])
        self.assertFalse(resolve_flags(u3)['is_internal_user'])
        self.assertFalse(resolve_flags(u3)['is_test_account'])


class FeatureStoreTests(TestCase):
    def setUp(self):
        cu = User.objects.create(email='coach@demo.com', password_hash='x', role='coach')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Demo',
                                                 platform_subscription_status='active')
        clu = User.objects.create(email='client@demo.com', password_hash='x', role='client',
                                  last_login_at=timezone.now() - timedelta(days=10))
        self.client_p = ClientProfile.objects.create(user=clu, first_name='Cli', last_name='Ent')
        CoachingRelationship.objects.create(coach=self.coach, client=self.client_p,
                                            status='ACTIVE', start_date=date.today() - timedelta(days=120))
        plan = SubscriptionPlan.objects.create(coach=self.coach, name='Base', plan_type='M', price=80)
        ClientSubscription.objects.create(client=self.client_p, subscription_plan=plan,
                                          status='ACTIVE', payment_status='FAILED',
                                          start_date=date.today() - timedelta(days=120),
                                          end_date=date.today() + timedelta(days=3))

    def test_build_features_round_trip(self):
        f = feat.build_features_for(self.client_p, date.today(), enrich=False)
        self.assertEqual(f['coach_id'], self.coach.id)
        self.assertGreaterEqual(f['days_since_last_login'], 9)
        self.assertEqual(f['payment_failures_30d'], 1)
        self.assertEqual(f['days_to_renewal'], 3)
        self.assertEqual(f['relationship_age_days'], 120)

    def test_build_and_store_and_score(self):
        n = feat.build_and_store(date.today(), enrich=False)
        self.assertEqual(n, 1)
        row = DailyFeatureStore.objects.get(client=self.client_p, snapshot_date=date.today())
        score, codes = rules.score({
            'days_since_last_login': row.days_since_last_login,
            'payment_failures_30d': row.payment_failures_30d,
            'days_to_renewal': row.days_to_renewal,
            'messages_7d': row.messages_7d, 'login_count_7d': row.login_count_7d,
        })
        # payment_failed (25) + no_login_7d (15) + renewal_close_no_activity (15)
        self.assertGreaterEqual(score, 40)
        self.assertIn('payment_failed', codes)
        RiskScoreDaily.objects.create(
            client=self.client_p, coach=self.coach, snapshot_date=date.today(),
            risk_score_rule_based=score, risk_class=rules.classify(score), top_reason_codes=codes,
        )
        self.assertEqual(RiskScoreDaily.objects.count(), 1)


@override_settings(ANALYTICS_ENVIRONMENT='production', TEST_ACCOUNT_EMAILS=['test@demo.com'])
class PipelineIntegrationTests(TestCase):
    """End-to-end: features -> rule scoring -> KPI rollup -> bootstrap ML -> ML score,
    plus the governance guard that keeps a test account out of the ML dataset."""

    def setUp(self):
        cu = User.objects.create(email='coach2@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Coach', last_name='Two',
                                                 platform_subscription_status='active')
        self.plan = SubscriptionPlan.objects.create(coach=self.coach, name='Pro', plan_type='M', price=120)
        self.today = date.today()

        # High-risk real client: stale login, failed payment, renewal imminent.
        self._make_client('high@demo.com', login_days_ago=20, pay='FAILED',
                          end_offset=2, rel_age=200)
        # Low-risk real client: fresh login, paid, renewal far off.
        self._make_client('low@demo.com', login_days_ago=1, pay='PAID',
                          end_offset=200, rel_age=200)
        # Test account (flagged via env allowlist) — must be excluded from ML.
        self._make_client('test@demo.com', login_days_ago=30, pay='FAILED',
                          end_offset=1, rel_age=200)

    def _make_client(self, email, login_days_ago, pay, end_offset, rel_age):
        u = User.objects.create(email=email, password_hash='x', role='CLIENT',
                                last_login_at=timezone.now() - timedelta(days=login_days_ago))
        c = ClientProfile.objects.create(user=u, first_name=email.split('@')[0], last_name='C')
        CoachingRelationship.objects.create(coach=self.coach, client=c, status='ACTIVE',
                                            start_date=self.today - timedelta(days=rel_age))
        ClientSubscription.objects.create(client=c, subscription_plan=self.plan, status='ACTIVE',
                                          payment_status=pay,
                                          start_date=self.today - timedelta(days=rel_age),
                                          end_date=self.today + timedelta(days=end_offset))
        return c

    def test_daily_pipeline(self):
        d = self.today.isoformat()
        call_command('compute_daily_features', date=d, no_enrich=True)
        call_command('score_risk', date=d)
        call_command('rollup_coach_metrics', date=d)

        # 3 feature rows; the test account is flagged.
        self.assertEqual(DailyFeatureStore.objects.count(), 3)
        test_row = DailyFeatureStore.objects.get(client__user__email='test@demo.com')
        self.assertTrue(test_row.is_test_account)

        # Risk scored for all, with reason codes; the high-risk client is high.
        self.assertEqual(RiskScoreDaily.objects.count(), 3)
        high = RiskScoreDaily.objects.get(client__user__email='high@demo.com')
        self.assertIn(high.risk_class, ('medium', 'high'))
        self.assertTrue(high.top_reason_codes)
        low = RiskScoreDaily.objects.get(client__user__email='low@demo.com')
        self.assertEqual(low.risk_class, 'low')

        # KPI rollup exists and counts only real-but-here clients (rollup is not
        # environment-filtered at write time; dashboards filter on read).
        metrics = CoachBusinessMetricsDaily.objects.get(coach=self.coach, snapshot_date=self.today)
        self.assertEqual(metrics.active_clients_count, 3)
        self.assertGreaterEqual(metrics.at_risk_clients_count, 1)

    def test_ml_dataset_excludes_test_account_and_bootstrap_trains(self):
        d = self.today.isoformat()
        call_command('compute_daily_features', date=d, no_enrich=True)
        call_command('score_risk', date=d)

        from .ml.dataset import load_dataset
        df, cols = load_dataset('risk_class', environment='production')
        # Only the two real clients enter the ML frame; the test account is gone.
        self.assertEqual(len(df), 2)

        from .ml.train import train
        mv = train('risk_class', bootstrap=True)
        self.assertTrue(mv.is_bootstrap)
        self.assertTrue(mv.is_active)
        self.assertEqual(ModelVersion.objects.filter(target='risk_class', is_active=True).count(), 1)

        from .ml.score import score_day
        n = score_day(self.today, target='risk_class')
        self.assertEqual(n, 3)  # writes probability onto every scored row for the day
        self.assertIsNotNone(
            RiskScoreDaily.objects.get(client__user__email='high@demo.com').risk_probability_ml)


class AnalyticsAPITests(TestCase):
    """The dual-auth read endpoints serialize the rollups for the dashboard."""

    def setUp(self):
        cu = User.objects.create(email='apicoach@demo.com', password_hash='x', role='COACH')
        self.coach = CoachProfile.objects.create(user=cu, first_name='Api', last_name='Coach',
                                                 platform_subscription_status='active')
        self.user = cu
        today = date.today()
        CoachBusinessMetricsDaily.objects.create(
            coach=self.coach, snapshot_date=today, active_clients_count=5,
            at_risk_clients_count=2, monthly_revenue=600, environment='production')
        clu = User.objects.create(email='apiclient@demo.com', password_hash='x', role='CLIENT')
        client_p = ClientProfile.objects.create(user=clu, first_name='Api', last_name='Cli')
        CoachingRelationship.objects.create(coach=self.coach, client=client_p,
                                            status='ACTIVE', start_date=today)
        RiskScoreDaily.objects.create(client=client_p, coach=self.coach, snapshot_date=today,
                                      risk_score_rule_based=55, risk_class='high',
                                      top_reason_codes=['no_login_7d', 'payment_failed'])

    def _login(self):
        s = self.client.session
        s['user_id'] = self.user.id
        s['user_role'] = 'COACH'
        s.save()

    def test_business_endpoint(self):
        self._login()
        r = self.client.get('/api/v1/coach/analytics/business')
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body['kpis']['active_clients_count'], 5)
        self.assertTrue(body['snapshot_date'])

    def test_risk_endpoint_with_reasons(self):
        self._login()
        r = self.client.get('/api/v1/coach/analytics/risk?class=high')
        self.assertEqual(r.status_code, 200)
        clients = r.json()['clients']
        self.assertEqual(len(clients), 1)
        self.assertEqual(clients[0]['risk_class'], 'high')
        labels = [x['label'] for x in clients[0]['reasons']]
        self.assertIn('Pagamento fallito', labels)

    def test_requires_auth(self):
        r = self.client.get('/api/v1/coach/analytics/business')
        self.assertEqual(r.status_code, 401)


class AnalyticsPageRenderTests(TestCase):
    """The dashboard page renders (base.html + posthog partial + page template)."""

    def setUp(self):
        cu = User.objects.create(email='pagecoach@demo.com', password_hash='x', role='COACH')
        CoachProfile.objects.create(user=cu, first_name='Page', last_name='Coach',
                                    platform_subscription_status='active')
        self.user = cu

    def test_renders_for_coach(self):
        s = self.client.session
        s['user_id'] = self.user.id
        s['user_role'] = 'COACH'
        s.save()
        r = self.client.get('/analisi/')
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, 'coachBusinessAnalytics')

    def test_redirects_anonymous(self):
        r = self.client.get('/analisi/')
        self.assertEqual(r.status_code, 302)
