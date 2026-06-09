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
        parser.add_argument('--ml-target', type=str, default='auto',
                            help="Active model target for risk_probability_ml. 'auto' "
                                 "(default) uses the best available active model, "
                                 "preferring real labels (churn_30d > renewal_7d > risk_class).")

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
        target = self._resolve_ml_target(options['ml_target'])
        if target is None:
            self.stdout.write('No active ML model — rule-based only.')
            return
        try:
            from domain.analytics.ml import score as ml_score
            n = ml_score.score_day(snapshot, target=target)
            if n:
                self.stdout.write(self.style.SUCCESS(f'ML probability written ({target}): {n}'))
            else:
                self.stdout.write('No active ML model — rule-based only.')
        except Exception as exc:
            self.stdout.write(self.style.WARNING(f'ML scoring skipped: {exc}'))

    @staticmethod
    def _resolve_ml_target(requested):
        """Pick which model target to score with. 'auto' prefers real labels
        over the bootstrap pseudo-label; an explicit target is honoured if a
        model for it is active. Returns None when nothing is trained yet."""
        from domain.analytics.models import ModelVersion
        active = set(ModelVersion.objects.filter(is_active=True).values_list('target', flat=True))
        if not active:
            return None
        if requested != 'auto':
            return requested if requested in active else None
        for t in ('churn_30d', 'renewal_7d', 'risk_class'):
            if t in active:
                return t
        return None
