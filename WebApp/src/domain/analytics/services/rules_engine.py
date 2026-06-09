"""Cold-start risk engine: a weighted, fully explainable rule set.

No training data needed — this is the floor the dashboard always shows, and the
source of the bootstrap pseudo-labels for the XGBoost pipeline. Every rule that
fires contributes its weight and its reason code, so the UI can explain *why* a
client is at risk, not just that they are.

Score is capped at 100 and bucketed: 0–24 low, 25–49 medium, 50+ high.
"""

from django.conf import settings

# Human-readable labels for the reason codes (served to the dashboard).
REASON_LABELS = {
    'no_login_7d': 'Nessun accesso da 7+ giorni',
    'no_checkin_10d': 'Nessun check da 10+ giorni',
    'payment_failed': 'Pagamento fallito',
    'sla_breach': 'Tempo di risposta oltre lo SLA',
    'engagement_drop_40': 'Calo di engagement oltre il 40%',
    'renewal_close_no_activity': 'Rinnovo vicino senza attività recente',
    'ignored_reminders': 'Promemoria ignorati ripetutamente',
}


def _sla_minutes():
    return getattr(settings, 'ANALYTICS_SLA_MINUTES', 1440)


# Each rule: (reason_code, predicate(features)->bool, weight). Predicates must be
# total — never raise on missing/None features (they coalesce to neutral values).
def _rules():
    sla = _sla_minutes()
    return [
        ('no_login_7d',               lambda f: (f.get('days_since_last_login') or 0) >= 7,            15),
        ('no_checkin_10d',            lambda f: (f.get('days_since_last_checkin') or 0) >= 10,          20),
        ('payment_failed',            lambda f: (f.get('payment_failures_30d') or 0) > 0,               25),
        ('sla_breach',                lambda f: (f.get('avg_coach_response_minutes_30d') or 0) > sla,   10),
        ('engagement_drop_40',        lambda f: (f.get('engagement_delta_7d_vs_30d') or 0) <= -0.40,    15),
        ('renewal_close_no_activity', lambda f: _renewal_close_no_activity(f),                          15),
        ('ignored_reminders',         lambda f: (f.get('ignored_reminders_30d') or 0) >= 3,             10),
    ]


def _renewal_close_no_activity(f):
    days = f.get('days_to_renewal')
    if days is None or not (0 <= days <= 5):
        return False
    return (f.get('messages_7d') or 0) == 0 and (f.get('login_count_7d') or 0) == 0


def score(features):
    """Return ``(score:int 0-100, reason_codes:list[str])``."""
    total = 0
    codes = []
    for code, predicate, weight in _rules():
        try:
            if predicate(features):
                total += weight
                codes.append(code)
        except Exception:
            # A malformed feature must never break scoring for a whole batch.
            continue
    return min(total, 100), codes


def classify(value):
    """Bucket a 0–100 score: low (0–24) / medium (25–49) / high (50+)."""
    if value < 25:
        return 'low'
    if value < 50:
        return 'medium'
    return 'high'


def label_for(code):
    return REASON_LABELS.get(code, code)
