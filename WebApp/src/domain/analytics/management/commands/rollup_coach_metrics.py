from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db.models import Avg, Count, Q, Sum
from django.utils import timezone
from django.utils.dateparse import parse_date

from domain.accounts.models import CoachProfile
from domain.analytics.models import CoachBusinessMetricsDaily, DailyFeatureStore, RiskScoreDaily
from domain.analytics.services.identity import current_environment
from domain.billing.models import ClientSubscription
from domain.checks.models import QuestionnaireResponse
from domain.coaching.models import CoachingRelationship

_FAILED = {'FAILED', 'OVERDUE', 'PAST_DUE', 'UNPAID'}


class Command(BaseCommand):
    help = "Roll up dashboard-ready KPIs into CoachBusinessMetricsDaily."

    def add_arguments(self, parser):
        parser.add_argument('--date', type=str, default=None, help='YYYY-MM-DD (default today).')

    def handle(self, *args, **options):
        snapshot = parse_date(options['date']) if options['date'] else timezone.now().date()
        sla = getattr(settings, 'ANALYTICS_SLA_MINUTES', 1440)
        env = current_environment()
        win30 = snapshot - timedelta(days=30)
        win7 = snapshot + timedelta(days=7)

        coach_ids = (CoachingRelationship.objects.filter(status='ACTIVE')
                     .values_list('coach_id', flat=True).distinct())
        written = 0
        for coach in CoachProfile.objects.filter(id__in=list(coach_ids)):
            active_clients = CoachingRelationship.objects.filter(coach=coach, status='ACTIVE').count()
            active_subs = ClientSubscription.objects.filter(
                subscription_plan__coach=coach, status='ACTIVE')

            renewals_due_7d = active_subs.filter(
                end_date__isnull=False, end_date__gte=snapshot, end_date__lte=win7).count()
            renewals_completed_30d = ClientSubscription.objects.filter(
                subscription_plan__coach=coach, start_date__gte=win30, start_date__lte=snapshot).count()

            ended_30d = ClientSubscription.objects.filter(
                subscription_plan__coach=coach, end_date__gte=win30, end_date__lte=snapshot,
            ).exclude(status='ACTIVE').count()
            denom = active_clients + ended_30d
            churn_rate = round(100.0 * ended_30d / denom, 1) if denom else 0.0

            feats = DailyFeatureStore.objects.filter(coach=coach, snapshot_date=snapshot)
            resp_rows = feats.exclude(avg_coach_response_minutes_30d__isnull=True)
            avg_first_response = resp_rows.aggregate(v=Avg('avg_coach_response_minutes_30d'))['v']
            within = resp_rows.filter(avg_coach_response_minutes_30d__lte=sla).count()
            sla_rate = round(100.0 * within / resp_rows.count(), 1) if resp_rows.count() else 0.0

            backlog = QuestionnaireResponse.objects.filter(
                coach=coach, submitted_at__isnull=False,
            ).filter(Q(coach_feedback__isnull=True) | Q(coach_feedback='')).count()

            total_active = active_subs.count()
            failed = active_subs.filter(payment_status__in=_FAILED).count()
            payment_failure_rate = round(100.0 * failed / total_active, 1) if total_active else 0.0

            risk = RiskScoreDaily.objects.filter(coach=coach, snapshot_date=snapshot)
            at_risk = risk.filter(risk_class__in=['medium', 'high']).count()
            avg_risk = risk.aggregate(v=Avg('risk_score_rule_based'))['v'] or 0.0

            revenue = active_subs.aggregate(v=Sum('subscription_plan__price'))['v'] or 0
            rev_per_client = round(float(revenue) / active_clients, 2) if active_clients else 0.0

            CoachBusinessMetricsDaily.objects.update_or_create(
                coach=coach, snapshot_date=snapshot,
                defaults={
                    'active_clients_count': active_clients,
                    'renewals_due_7d': renewals_due_7d,
                    'renewals_completed_30d': renewals_completed_30d,
                    'churn_rate_30d': churn_rate,
                    'avg_first_response_minutes': round(avg_first_response, 1) if avg_first_response else None,
                    'sla_adherence_rate': sla_rate,
                    'backlog_open_reviews': backlog,
                    'payment_failure_rate': payment_failure_rate,
                    'at_risk_clients_count': at_risk,
                    'avg_risk_score': round(float(avg_risk), 1),
                    'monthly_revenue': revenue,
                    'revenue_per_active_client': rev_per_client,
                    'environment': env,
                },
            )
            written += 1
        self.stdout.write(self.style.SUCCESS(f'Coach metrics rolled up for {snapshot}: {written}'))
