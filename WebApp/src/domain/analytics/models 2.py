"""Analytics + churn-prediction data layer.

Two kinds of tables live here:

* **Operational** (`Task`, `AutomationLog`, `LeadPipeline`) — coach-facing state
  that the app will write to as those features ship. Created now so the feature
  store and event schema have a stable target; empty until the flows are wired.
* **Aggregate / scoring** (`DailyFeatureStore`, `RiskScoreDaily`,
  `CoachBusinessMetricsDaily`, `ModelVersion`) — derived, recomputed nightly by
  the management commands. PostgreSQL stays the source of truth; PostHog only
  enriches behavioural columns.

Every derived row carries governance columns (`is_internal_user`,
`is_test_account`, `environment`) so dashboards and the ML dataset can keep
test/internal traffic out of production numbers.
"""

from django.db import models


# ---------------------------------------------------------------------------
# Operational tables (written by app flows; empty in V1)
# ---------------------------------------------------------------------------

class Task(models.Model):
    """A coach to-do, optionally about a specific client."""
    STATUS_CHOICES = [('OPEN', 'Aperto'), ('COMPLETED', 'Completato')]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='tasks')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.SET_NULL,
                               null=True, blank=True, related_name='coach_tasks')
    task_type = models.CharField(max_length=50, blank=True, default='')
    title = models.CharField(max_length=255)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='OPEN')
    due_date = models.DateField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['coach', 'status']),
            models.Index(fields=['client', 'status']),
        ]

    def __str__(self):
        return f'{self.title} [{self.status}]'


class AutomationLog(models.Model):
    """One row per automation that fired (welcome msg, reminder, follow-up …)."""
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='automation_logs')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.SET_NULL,
                               null=True, blank=True, related_name='automation_logs')
    automation_type = models.CharField(max_length=60)
    trigger_event = models.CharField(max_length=60, blank=True, default='')
    status = models.CharField(max_length=30, blank=True, default='SENT')
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=['coach', '-created_at'])]

    def __str__(self):
        return f'{self.automation_type} ({self.coach_id})'


class LeadPipeline(models.Model):
    """A prospect the coach is working before they become a paying client."""
    STAGE_CHOICES = [
        ('NEW', 'Nuovo'), ('CONTACTED', 'Contattato'), ('QUALIFIED', 'Qualificato'),
        ('WON', 'Acquisito'), ('LOST', 'Perso'),
    ]
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='leads')
    email = models.EmailField(blank=True, default='')
    name = models.CharField(max_length=200, blank=True, default='')
    source = models.CharField(max_length=80, blank=True, default='')
    stage = models.CharField(max_length=20, choices=STAGE_CHOICES, default='NEW')
    value_estimate = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [models.Index(fields=['coach', 'stage'])]

    def __str__(self):
        return f'{self.name or self.email} [{self.stage}]'


# ---------------------------------------------------------------------------
# Aggregate / scoring tables (recomputed nightly)
# ---------------------------------------------------------------------------

class DailyFeatureStore(models.Model):
    """One engineered feature row per (client, snapshot_date).

    Flat by design: this is the single table the XGBoost pipeline trains on.
    Behavioural counts (`login_count_*`, `feature_usage_count_*`) are PostHog
    enriched when a personal API key is configured, else DB activity proxies.
    """
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='feature_rows')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='client_feature_rows')
    snapshot_date = models.DateField()

    # Engagement / recency
    days_since_last_login = models.IntegerField(null=True, blank=True)
    login_count_7d = models.IntegerField(default=0)
    login_count_30d = models.IntegerField(default=0)
    days_since_last_checkin = models.IntegerField(null=True, blank=True)
    checkins_completed_7d = models.IntegerField(default=0)
    checkins_missed_30d = models.IntegerField(default=0)
    messages_7d = models.IntegerField(default=0)
    ignored_reminders_30d = models.IntegerField(default=0)
    feature_usage_count_7d = models.IntegerField(default=0)
    plan_updates_30d = models.IntegerField(default=0)
    engagement_delta_7d_vs_30d = models.FloatField(null=True, blank=True)

    # Coach service quality
    avg_coach_response_minutes_30d = models.FloatField(null=True, blank=True)
    avg_review_duration_seconds_30d = models.FloatField(null=True, blank=True)

    # Commercial
    days_to_renewal = models.IntegerField(null=True, blank=True)
    payment_failures_30d = models.IntegerField(default=0)
    relationship_age_days = models.IntegerField(null=True, blank=True)
    active_package_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    # Governance (keep test/internal out of production numbers)
    is_internal_user = models.BooleanField(default=False)
    is_test_account = models.BooleanField(default=False)
    environment = models.CharField(max_length=20, default='development')

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = [('client', 'snapshot_date')]
        indexes = [
            models.Index(fields=['coach', 'snapshot_date']),
            models.Index(fields=['snapshot_date', 'environment']),
        ]

    def __str__(self):
        return f'features client={self.client_id} @ {self.snapshot_date}'


class RiskScoreDaily(models.Model):
    """Daily churn-risk score per client. Rule-based always present; ML optional."""
    RISK_CLASSES = [('low', 'Basso'), ('medium', 'Medio'), ('high', 'Alto')]

    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='risk_scores')
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='client_risk_scores')
    snapshot_date = models.DateField()

    risk_score_rule_based = models.IntegerField(default=0)
    risk_probability_ml = models.FloatField(null=True, blank=True)
    risk_class = models.CharField(max_length=10, choices=RISK_CLASSES, default='low')
    top_reason_codes = models.JSONField(default=list, blank=True)
    model_version = models.CharField(max_length=80, blank=True, default='')
    scored_at = models.DateTimeField(auto_now=True)

    is_internal_user = models.BooleanField(default=False)
    is_test_account = models.BooleanField(default=False)
    environment = models.CharField(max_length=20, default='development')

    class Meta:
        unique_together = [('client', 'snapshot_date')]
        indexes = [
            models.Index(fields=['coach', 'snapshot_date', 'risk_class']),
            models.Index(fields=['snapshot_date', 'risk_class']),
        ]

    def __str__(self):
        return f'risk client={self.client_id} {self.risk_class} ({self.risk_score_rule_based})'


class CoachBusinessMetricsDaily(models.Model):
    """Dashboard-ready KPI rollup per coach per day."""
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='business_metrics')
    snapshot_date = models.DateField()

    active_clients_count = models.IntegerField(default=0)
    renewals_due_7d = models.IntegerField(default=0)
    renewals_completed_30d = models.IntegerField(default=0)
    churn_rate_30d = models.FloatField(default=0.0)
    avg_first_response_minutes = models.FloatField(null=True, blank=True)
    sla_adherence_rate = models.FloatField(default=0.0)
    backlog_open_reviews = models.IntegerField(default=0)
    payment_failure_rate = models.FloatField(default=0.0)
    at_risk_clients_count = models.IntegerField(default=0)
    avg_risk_score = models.FloatField(default=0.0)
    monthly_revenue = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    revenue_per_active_client = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    environment = models.CharField(max_length=20, default='development')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = [('coach', 'snapshot_date')]
        indexes = [models.Index(fields=['coach', '-snapshot_date'])]

    def __str__(self):
        return f'metrics coach={self.coach_id} @ {self.snapshot_date}'


class ModelVersion(models.Model):
    """Registry row for a trained (or bootstrap) model artifact on disk."""
    TARGETS = [('churn_30d', 'churn_30d'), ('renewal_7d', 'renewal_7d'), ('risk_class', 'risk_class')]

    target = models.CharField(max_length=20, choices=TARGETS)
    version = models.CharField(max_length=80, unique=True)
    path = models.CharField(max_length=500, blank=True, default='')
    trained_at = models.DateTimeField(auto_now_add=True)
    metrics = models.JSONField(default=dict, blank=True)
    n_train = models.IntegerField(default=0)
    n_valid = models.IntegerField(default=0)
    is_bootstrap = models.BooleanField(default=True)
    is_active = models.BooleanField(default=False)

    class Meta:
        indexes = [models.Index(fields=['target', 'is_active'])]

    def __str__(self):
        flag = 'bootstrap' if self.is_bootstrap else 'trained'
        return f'{self.target} {self.version} ({flag})'
