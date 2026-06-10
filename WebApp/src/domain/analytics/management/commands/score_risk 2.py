from django.core.management.base import BaseCommand
from django.utils import timezone
from django.utils.dateparse import parse_date

from domain.analytics.models import DailyFeatureStore, RiskScoreDaily
from domain.analytics.services import rules_engine as rules


def _row_to_features(row):
    return {
        'days_since_last_login': row.days_since_last_login,
        'days_since_last_checkin': row.days_since_last_checkin,
        'payment_failures_30d': row.payment_failures_30d,
        'avg_coach_response_minutes_30d': row.avg_coach_response_minutes_30d,
        'engagement_delta_7d_vs_30d': row.engagement_delta_7d_vs_30d,
        'days_to_renewal': row.days_to_renewal,
        'messages_7d': row.messages_7d,
        'login_count_7d': row.login_count_7d,
        'ignored_reminders_30d': row.ignored_reminders_30d,
    }


class Command(BaseCommand):
    help = ("Score churn risk for a snapshot date: rule engine always; the ML "
            "probability is layered on when an active model exists.")

    def add_arguments(self, parser):
        parser.add_argument('--date', type=str, default=None, help='YYYY-MM-DD (default today).')
        parser.add_argument('--ml-target', type=str, default='churn_30d',
                            help='Active model target to use for risk_probability_ml.')

    def handle(self, *args, **options):
        snapshot = parse_date(options['date']) if options['date'] else timezone.now().date()
        rows = DailyFeatureStore.objects.filter(snapshot_date=snapshot)

        scored = 0
        for row in rows.iterator():
            value, codes = rules.score(_row_to_features(row))
            RiskScoreDaily.objects.update_or_create(
                client_id=row.client_id, snapshot_date=snapshot,
                defaults={
                    'coach_id': row.coach_id,
                    'risk_score_rule_based': value,
                    'risk_class': rules.classify(value),
                    'top_reason_codes': codes,
                    'is_internal_user': row.is_internal_user,
                    'is_test_account': row.is_test_account,
                    'environment': row.environment,
                },
            )
            scored += 1
        self.stdout.write(self.style.SUCCESS(f'Rule-based risk scored for {snapshot}: {scored}'))

        # Optional ML overlay — advisory, never blocks the rule-based signal.
        try:
            from domain.analytics.ml import score as ml_score
            n = ml_score.score_day(snapshot, target=options['ml_target'])
            if n:
                self.stdout.write(self.style.SUCCESS(f'ML probability written: {n}'))
            else:
                self.stdout.write('No active ML model — rule-based only.')
        except Exception as exc:
            self.stdout.write(self.style.WARNING(f'ML scoring skipped: {exc}'))
