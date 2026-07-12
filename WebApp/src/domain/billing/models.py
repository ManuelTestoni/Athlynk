from django.db import models

# Zero-decimal currencies have no cents/subunit — Stripe wants the amount as-is,
# not multiplied by 100. Shared by SubscriptionPlan/Bundle checkout code.
ZERO_DECIMAL_CURRENCIES = {'JPY'}


def to_stripe_amount(amount, currency):
    """Convert a decimal price in `currency` to the integer unit Stripe expects."""
    if (currency or '').upper() in ZERO_DECIMAL_CURRENCIES:
        return int(amount)
    return int(amount * 100)


class SubscriptionPlan(models.Model):
    KIND_SUBSCRIPTION = 'subscription'
    KIND_ONE_TIME = 'one_time'
    KIND_CHOICES = [
        (KIND_SUBSCRIPTION, 'Abbonamento ricorrente'),
        (KIND_ONE_TIME, 'Servizio/Add-on (pagamento singolo)'),
    ]

    PLAN_TYPE_MENSILE = 'mensile'
    PLAN_TYPE_TRIMESTRALE = 'trimestrale'
    PLAN_TYPE_SEMESTRALE = 'semestrale'
    PLAN_TYPE_ANNUALE = 'annuale'
    PLAN_TYPE_UNA_TANTUM = 'una_tantum'
    PLAN_TYPE_CHOICES = [
        (PLAN_TYPE_MENSILE, 'Mensile'),
        (PLAN_TYPE_TRIMESTRALE, 'Trimestrale'),
        (PLAN_TYPE_SEMESTRALE, 'Semestrale'),
        (PLAN_TYPE_ANNUALE, 'Annuale'),
        (PLAN_TYPE_UNA_TANTUM, 'Una Tantum'),
    ]

    # (Stripe interval, interval_count) per billing_interval choice — used to
    # build the recurring Price on sync_plan_to_stripe.
    BILLING_MENSILE = 'mensile'
    BILLING_TRIMESTRALE = 'trimestrale'
    BILLING_SEMESTRALE = 'semestrale'
    BILLING_ANNUALE = 'annuale'
    BILLING_INTERVAL_CHOICES = [
        (BILLING_MENSILE, 'Mensile'),
        (BILLING_TRIMESTRALE, 'Trimestrale'),
        (BILLING_SEMESTRALE, 'Semestrale'),
        (BILLING_ANNUALE, 'Annuale'),
    ]
    STRIPE_INTERVAL_BY_BILLING = {
        BILLING_MENSILE: ('month', 1),
        BILLING_TRIMESTRALE: ('month', 3),
        BILLING_SEMESTRALE: ('month', 6),
        BILLING_ANNUALE: ('year', 1),
    }

    CURRENCY_EUR = 'EUR'
    CURRENCY_GBP = 'GBP'
    CURRENCY_USD = 'USD'
    CURRENCY_JPY = 'JPY'
    CURRENCY_CHOICES = [
        (CURRENCY_EUR, 'Euro (€)'),
        (CURRENCY_GBP, 'Sterlina (£)'),
        (CURRENCY_USD, 'Dollaro USA ($)'),
        (CURRENCY_JPY, 'Yen (¥)'),
    ]

    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='subscription_plans')
    name = models.CharField(max_length=200)
    plan_type = models.CharField(max_length=100, choices=PLAN_TYPE_CHOICES, default=PLAN_TYPE_MENSILE)
    description = models.TextField(null=True, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=10, choices=CURRENCY_CHOICES, default=CURRENCY_EUR)
    duration_days = models.IntegerField(null=True, blank=True)
    billing_interval = models.CharField(max_length=50, choices=BILLING_INTERVAL_CHOICES, null=True, blank=True)
    included_services = models.JSONField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    # Kind drives whether this plan is sold as a Stripe recurring Price
    # (subscription) or a one-off Price (add-on/custom service); duration_days
    # is only meaningful for KIND_SUBSCRIPTION (drives cash-assignment end_date).
    kind = models.CharField(max_length=20, choices=KIND_CHOICES, default=KIND_SUBSCRIPTION)
    stripe_product_id = models.CharField(max_length=255, blank=True, default='')
    stripe_price_id = models.CharField(max_length=255, blank=True, default='')
    # True once synced to a Stripe Product/Price on the coach's connected
    # account. Cash-in-studio assignment works regardless of this flag.
    is_online_purchasable = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name


class Bundle(models.Model):
    """A coach-defined package of >=2 SubscriptionPlan rows (kind=one_time),
    sold as one Checkout Session with N line items. Composition is explicit
    via BundleItem because a bundle's price is derived (sum of components +/-
    discount) rather than a single Stripe Price of its own."""
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='bundles')
    name = models.CharField(max_length=200)
    description = models.TextField(null=True, blank=True)
    discount_percent = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    discount_amount = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    currency = models.CharField(max_length=10, choices=SubscriptionPlan.CURRENCY_CHOICES, default=SubscriptionPlan.CURRENCY_EUR)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name


class BundleItem(models.Model):
    """One line item of a Bundle: a quantity of a component SubscriptionPlan,
    with an optional per-item price override independent of the plan's own
    standalone price."""
    bundle = models.ForeignKey(Bundle, on_delete=models.CASCADE, related_name='items')
    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.PROTECT, related_name='bundle_items')
    quantity = models.PositiveIntegerField(default=1)
    price_override = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    class Meta:
        unique_together = [('bundle', 'plan')]


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
    # Populated only when external_payment_provider='stripe_connect' (an
    # online purchase). Cash-in-studio rows (external_payment_provider=
    # 'manual') never touch these — see assign_plan_to_client_view.
    stripe_checkout_session_id = models.CharField(max_length=255, blank=True, default='')
    stripe_subscription_id = models.CharField(max_length=255, blank=True, default='')
    stripe_payment_intent_id = models.CharField(max_length=255, blank=True, default='')
    bundle = models.ForeignKey(Bundle, null=True, blank=True, on_delete=models.PROTECT, related_name='client_subscriptions')
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
    # Redemption: set when the code is consumed at signup, or when a
    # returning-customer checkout reactivates an existing account directly
    # (no code ever issued in that case). `code` stays unique but is only
    # meaningful while redeemed_at is null.
    redeemed_at = models.DateTimeField(null=True, blank=True)
    redeemed_by = models.ForeignKey(
        'accounts.User', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='platform_purchases_redeemed',
    )
    returning_customer = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PlatformPurchase {self.code} ({self.email}) — {self.plan}/{self.status}"


class StripeConnectEvent(models.Model):
    """Dedup log for Stripe Connect webhook events (distinct from platform
    billing's webhook, which needs no such log because its
    checkout.session.completed handler is naturally idempotent via
    PlatformPurchase.stripe_session_id). account.updated fires repeatedly and
    Connect's checkout.session.completed must update, not get-or-create, an
    existing ConnectCheckoutIntent — a replay here is a no-op lookup."""
    stripe_event_id = models.CharField(max_length=255, unique=True)
    event_type = models.CharField(max_length=100)
    connected_account_id = models.CharField(max_length=255, blank=True, default='')
    processed_at = models.DateTimeField(auto_now_add=True)


class ConnectCheckoutIntent(models.Model):
    """Row created when a Connect Checkout Session is built (before
    redirecting the athlete to Stripe), consumed by the webhook to know what
    to fulfil. Needed because a bundle purchase must reconstruct N line items
    identically at fulfilment time — too much to reliably round-trip through
    Stripe session metadata (500-char limit per value)."""
    STATUS_PENDING = 'pending'
    STATUS_FULFILLED = 'fulfilled'
    STATUS_EXPIRED = 'expired'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_FULFILLED, 'Fulfilled'),
        (STATUS_EXPIRED, 'Expired'),
    ]

    stripe_checkout_session_id = models.CharField(max_length=255, unique=True)
    coach = models.ForeignKey('accounts.CoachProfile', on_delete=models.CASCADE, related_name='connect_checkout_intents')
    client = models.ForeignKey('accounts.ClientProfile', on_delete=models.CASCADE, related_name='connect_checkout_intents')
    plan = models.ForeignKey(SubscriptionPlan, null=True, blank=True, on_delete=models.SET_NULL)
    bundle = models.ForeignKey(Bundle, null=True, blank=True, on_delete=models.SET_NULL)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    created_at = models.DateTimeField(auto_now_add=True)
    fulfilled_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"ConnectCheckoutIntent {self.stripe_checkout_session_id} ({self.status})"
