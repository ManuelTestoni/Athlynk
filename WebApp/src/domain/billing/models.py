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
    expiry_reminder_sent = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['client', 'status']),
            models.Index(fields=['subscription_plan', 'status']),
        ]

    def __str__(self):
        return f"Subscription for {self.client}"


class PlatformPurchase(models.Model):
    """A coach's monthly subscription to Athlynk platform access, paid via Stripe
    Checkout from the marketing site. Created only on a signature-verified
    `checkout.session.completed` webhook; its `status` is then kept in sync by
    `customer.subscription.updated/deleted` events. Decoupled from User on
    purpose: the buyer may not have an account yet — they redeem `code` when they
    first sign in to the app (login redemption is future work)."""

    PLAN_ATHENA = 'athena'
    PLAN_APOLLO = 'apollo'
    PLAN_ZEUS = 'zeus'
    PLAN_CHOICES = [
        (PLAN_ATHENA, 'Athena'),
        (PLAN_APOLLO, 'Apollo'),
        (PLAN_ZEUS, 'Zeus'),
    ]

    STATUS_ACTIVE = 'active'
    STATUS_PAST_DUE = 'past_due'
    STATUS_CANCELED = 'canceled'

    BILLING_MONTHLY = 'mensile'
    BILLING_ANNUAL = 'annuale'
    BILLING_CHOICES = [
        (BILLING_MONTHLY, 'Mensile'),
        (BILLING_ANNUAL, 'Annuale'),
    ]

    email = models.EmailField()
    code = models.CharField(max_length=32, unique=True)
    plan = models.CharField(max_length=20, choices=PLAN_CHOICES, default=PLAN_APOLLO)
    billing_interval = models.CharField(max_length=10, choices=BILLING_CHOICES, default=BILLING_MONTHLY)
    has_chiron = models.BooleanField(default=False)
    status = models.CharField(max_length=20, default=STATUS_ACTIVE)
    stripe_session_id = models.CharField(max_length=255, unique=True)
    stripe_subscription_id = models.CharField(max_length=255, blank=True, default='', db_index=True)
    stripe_customer_id = models.CharField(max_length=255, blank=True, default='')
    stripe_payment_intent = models.CharField(max_length=255, blank=True, default='')
    amount_total = models.IntegerField(default=0)  # smallest currency unit (cents)
    currency = models.CharField(max_length=10, default='eur')
    current_period_end = models.DateTimeField(null=True, blank=True)
    email_sent = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PlatformPurchase {self.code} ({self.email}) — {self.plan}/{self.status}"
