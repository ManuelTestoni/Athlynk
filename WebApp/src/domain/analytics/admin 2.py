from django.contrib import admin

from .models import (
    AutomationLog, CoachBusinessMetricsDaily, DailyFeatureStore, LeadPipeline,
    ModelVersion, RiskScoreDaily, Task,
)


@admin.register(RiskScoreDaily)
class RiskScoreDailyAdmin(admin.ModelAdmin):
    list_display = ('client', 'coach', 'snapshot_date', 'risk_class',
                    'risk_score_rule_based', 'risk_probability_ml', 'environment')
    list_filter = ('risk_class', 'environment', 'is_test_account', 'is_internal_user')
    date_hierarchy = 'snapshot_date'


@admin.register(CoachBusinessMetricsDaily)
class CoachBusinessMetricsDailyAdmin(admin.ModelAdmin):
    list_display = ('coach', 'snapshot_date', 'active_clients_count', 'at_risk_clients_count',
                    'avg_risk_score', 'monthly_revenue', 'environment')
    list_filter = ('environment',)
    date_hierarchy = 'snapshot_date'


@admin.register(ModelVersion)
class ModelVersionAdmin(admin.ModelAdmin):
    list_display = ('target', 'version', 'is_bootstrap', 'is_active', 'n_train', 'trained_at')
    list_filter = ('target', 'is_bootstrap', 'is_active')


admin.site.register(DailyFeatureStore)
admin.site.register(Task)
admin.site.register(AutomationLog)
admin.site.register(LeadPipeline)
