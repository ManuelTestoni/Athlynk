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

        coach_ids = list(CoachingRelationship.objects.filter(status='ACTIVE')
                          .values_list('coach_id', flat=True).distinct())
        if not coach_ids:
            self.stdout.write(self.style.SUCCESS(f'Coach metrics rolled up for {snapshot}: 0'))
            return

        # Bulk-fetch every sub-metric as one grouped query across all coaches
        # (instead of ~12 queries per coach inside the loop below) — turns
        # O(coaches) queries into a fixed ~12 regardless of coach count.
        active_clients_by_coach = dict(
            CoachingRelationship.objects.filter(coach_id__in=coach_ids, status='ACTIVE')
            .values('coach_id').annotate(n=Count('id')).values_list('coach_id', 'n')
        )

        active_subs_qs = ClientSubscription.objects.filter(
            subscription_plan__coach_id__in=coach_ids, status='ACTIVE')

        total_active_by_coach = dict(
            active_subs_qs.values('subscription_plan__coach_id')
            .annotate(n=Count('id')).values_list('subscription_plan__coach_id', 'n')
        )
        renewals_due_by_coach = dict(
            active_subs_qs.filter(end_date__isnull=False, end_date__gte=snapshot, end_date__lte=win7)
            .values('subscription_plan__coach_id').annotate(n=Count('id'))
            .values_list('subscription_plan__coach_id', 'n')
        )
        failed_by_coach = dict(
            active_subs_qs.filter(payment_status__in=_FAILED)
            .values('subscription_plan__coach_id').annotate(n=Count('id'))
            .values_list('subscription_plan__coach_id', 'n')
        )
        revenue_by_coach = dict(
            active_subs_qs.values('subscription_plan__coach_id')
            .annotate(v=Sum('subscription_plan__price')).values_list('subscription_plan__coach_id', 'v')
        )
        renewals_completed_by_coach = dict(
            ClientSubscription.objects.filter(
                subscription_plan__coach_id__in=coach_ids, start_date__gte=win30, start_date__lte=snapshot,
            ).values('subscription_plan__coach_id').annotate(n=Count('id'))
            .values_list('subscription_plan__coach_id', 'n')
        )
        ended_by_coach = dict(
            ClientSubscription.objects.filter(
                subscription_plan__coach_id__in=coach_ids, end_date__gte=win30, end_date__lte=snapshot,
            ).exclude(status='ACTIVE')
            .values('subscription_plan__coach_id').annotate(n=Count('id'))
            .values_list('subscription_plan__coach_id', 'n')
        )

        feats_qs = DailyFeatureStore.objects.filter(coach_id__in=coach_ids, snapshot_date=snapshot)
        resp_qs = feats_qs.exclude(avg_coach_response_minutes_30d__isnull=True)
        avg_response_by_coach = dict(
            resp_qs.values('coach_id').annotate(v=Avg('avg_coach_response_minutes_30d'))
            .values_list('coach_id', 'v')
        )
        resp_count_by_coach = dict(
            resp_qs.values('coach_id').annotate(n=Count('id')).values_list('coach_id', 'n')
        )
        within_by_coach = dict(
            resp_qs.filter(avg_coach_response_minutes_30d__lte=sla)
            .values('coach_id').annotate(n=Count('id')).values_list('coach_id', 'n')
        )

        backlog_by_coach = dict(
            QuestionnaireResponse.objects.filter(coach_id__in=coach_ids, submitted_at__isnull=False)
            .filter(Q(coach_feedback__isnull=True) | Q(coach_feedback=''))
            .values('coach_id').annotate(n=Count('id')).values_list('coach_id', 'n')
        )

        risk_qs = RiskScoreDaily.objects.filter(coach_id__in=coach_ids, snapshot_date=snapshot)
        at_risk_by_coach = dict(
            risk_qs.filter(risk_class__in=['medium', 'high'])
            .values('coach_id').annotate(n=Count('id')).values_list('coach_id', 'n')
        )
        avg_risk_by_coach = dict(
            risk_qs.values('coach_id').annotate(v=Avg('risk_score_rule_based')).values_list('coach_id', 'v')
        )

        written = 0
        for coach in CoachProfile.objects.filter(id__in=coach_ids):
            cid = coach.id
            active_clients = active_clients_by_coach.get(cid, 0)
            renewals_due_7d = renewals_due_by_coach.get(cid, 0)
            renewals_completed_30d = renewals_completed_by_coach.get(cid, 0)

            ended_30d = ended_by_coach.get(cid, 0)
            denom = active_clients + ended_30d
            churn_rate = round(100.0 * ended_30d / denom, 1) if denom else 0.0

            avg_first_response = avg_response_by_coach.get(cid)
            resp_count = resp_count_by_coach.get(cid, 0)
            within = within_by_coach.get(cid, 0)
            sla_rate = round(100.0 * within / resp_count, 1) if resp_count else 0.0

            backlog = backlog_by_coach.get(cid, 0)

            total_active = total_active_by_coach.get(cid, 0)
            failed = failed_by_coach.get(cid, 0)
            payment_failure_rate = round(100.0 * failed / total_active, 1) if total_active else 0.0

            risk_at_risk = at_risk_by_coach.get(cid, 0)
            avg_risk = avg_risk_by_coach.get(cid) or 0.0

            revenue = revenue_by_coach.get(cid) or 0
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
                    'at_risk_clients_count': risk_at_risk,
                    'avg_risk_score': round(float(avg_risk), 1),
                    'monthly_revenue': revenue,
                    'revenue_per_active_client': rev_per_client,
                    'environment': env,
                },
            )
            written += 1
        self.stdout.write(self.style.SUCCESS(f'Coach metrics rolled up for {snapshot}: {written}'))
