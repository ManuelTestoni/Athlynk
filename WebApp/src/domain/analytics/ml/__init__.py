"""XGBoost churn/renewal/risk pipeline.

Heavy deps (pandas, xgboost, scikit-learn) are imported lazily *inside* the
functions that need them, so importing this package — and therefore loading the
Django app — never requires them. The management commands surface a clear error
if they are missing.
"""

FEATURE_COLUMNS = [
    'days_since_last_login', 'login_count_7d', 'login_count_30d',
    'days_since_last_checkin', 'checkins_completed_7d', 'checkins_missed_30d',
    'messages_7d', 'ignored_reminders_30d', 'feature_usage_count_7d',
    'plan_updates_30d', 'engagement_delta_7d_vs_30d',
    'avg_coach_response_minutes_30d', 'avg_review_duration_seconds_30d',
    'days_to_renewal', 'payment_failures_30d', 'relationship_age_days',
    'active_package_price',
]

TARGETS = ('churn_30d', 'renewal_7d', 'risk_class')
