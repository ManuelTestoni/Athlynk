from django.db import models

class SubscriptionPlan(models.Model):
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='subscription_plans')
    name = models.CharField(max_length=200)
    plan_type = models.CharField(max_length=100)
    description = models.TextField(null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=10, default='EUR')
    duration_days = models.IntegerField(null=True, blank=True)
    billing_interval = models.CharField(max_length=50, null=True, blank=True)
    included_services = models.JSONField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

class ClientSubscription(models.Model):
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='subscriptions')
    subscription_plan = models.ForeignKey(SubscriptionPlan, on_delete=models.PROTECT, related_name='client_subscriptions')
    status = models.CharField(max_length=50)
    payment_status = models.CharField(max_length=50)
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    auto_renew = models.BooleanField(default=True)
    external_payment_provider = models.CharField(max_length=100, null=True, blank=True)
    external_reference = models.CharField(max_length=255, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['client', 'status']),
            models.Index(fields=['subscription_plan', 'status']),
        ]

    def __str__(self):
        return f"Subscription for {self.client}"
