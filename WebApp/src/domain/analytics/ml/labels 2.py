"""Label generation for the three targets.

Real labels come from billing history (`churn_30d`, `renewal_7d`). Until enough
history exists, `risk_class` provides a *bootstrap* pseudo-label derived from the
rule engine — only ever used to exercise the pipeline, never as ground truth.
"""

from datetime import timedelta

from domain.billing.models import ClientSubscription

from ..services import rules_engine as rules


def churn_30d(client_id, snapshot_date):
    """1 if the client had an active sub at snapshot that lapsed within 30 days
    and was not replaced by a new active subscription; else 0; None if unknown."""
    window_end = snapshot_date + timedelta(days=30)
    sub = (ClientSubscription.objects
           .filter(client_id=client_id, start_date__lte=snapshot_date)
           .order_by('-start_date').first())
    if sub is None or sub.end_date is None:
        return None
    if not (snapshot_date < sub.end_date <= window_end):
        return 0
    # Lapsed in window — churn unless a later active sub exists.
    has_successor = ClientSubscription.objects.filter(
        client_id=client_id, start_date__gt=sub.start_date, status='ACTIVE',
    ).exists()
    return 0 if has_successor else 1


def renewal_7d(client_id, snapshot_date):
    """1 if a subscription renewal/new active sub started within 7 days."""
    window_end = snapshot_date + timedelta(days=7)
    renewed = ClientSubscription.objects.filter(
        client_id=client_id, start_date__gt=snapshot_date, start_date__lte=window_end,
    ).exists()
    return 1 if renewed else 0


def risk_class_bootstrap(feature_row):
    """Pseudo-label from the rule engine: 1 if medium/high risk, else 0."""
    score, _ = rules.score(_row_to_dict(feature_row))
    return 1 if rules.classify(score) in ('medium', 'high') else 0


def _row_to_dict(row):
    """Accept either a DailyFeatureStore instance or a plain dict."""
    if isinstance(row, dict):
        return row
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


def label_for(target, row, snapshot_date):
    if target == 'churn_30d':
        return churn_30d(row.client_id, snapshot_date)
    if target == 'renewal_7d':
        return renewal_7d(row.client_id, snapshot_date)
    if target == 'risk_class':
        return risk_class_bootstrap(row)
    raise ValueError(f'unknown target {target}')
