"""Stripe Connect (Express) helpers — coaches connect their own account to
receive athlete payments for their SubscriptionPlan/Bundle catalog.

Distinct from services used by views_payments.py (platform billing, coach
pays Athlynk): stripe.api_key stays the platform secret key for every call
here too, Connect calls differ only via the `stripe_account=` kwarg pointing
at the coach's connected account id.
"""
import logging

import stripe
from django.conf import settings

logger = logging.getLogger(__name__)


def create_connect_account(coach):
    """Create the coach's Express account once and persist its id. No-op if
    the coach already has one."""
    if coach.stripe_connect_account_id:
        return coach.stripe_connect_account_id

    stripe.api_key = settings.STRIPE_SECRET_KEY
    account = stripe.Account.create(
        type='express',
        country='IT',
        email=coach.user.email,
        capabilities={
            'card_payments': {'requested': True},
            'transfers': {'requested': True},
        },
    )
    coach.stripe_connect_account_id = account['id']
    coach.save(update_fields=['stripe_connect_account_id', 'updated_at'])
    return account['id']


def create_account_link(account_id, refresh_url, return_url):
    """Return a fresh, single-use hosted onboarding URL for this account."""
    stripe.api_key = settings.STRIPE_SECRET_KEY
    link = stripe.AccountLink.create(
        account=account_id,
        refresh_url=refresh_url,
        return_url=return_url,
        type='account_onboarding',
    )
    return link['url']


def sync_plan_to_stripe(plan):
    """Create/refresh the Stripe Product+Price for this SubscriptionPlan on
    its coach's connected account. No-op if the coach hasn't connected Stripe
    yet — the plan still saves locally and stays cash-assignable.

    Prices are immutable once created: if one already exists, this creates a
    *new* Price for the current name/amount/kind and archives the old one
    (existing subscribers keep paying their original price until renewal —
    correct Stripe behavior), rather than mutating in place.
    """
    from domain.billing.models import SubscriptionPlan, to_stripe_amount

    coach = plan.coach
    if not coach.stripe_connect_account_id or not coach.stripe_connect_charges_enabled:
        return

    stripe.api_key = settings.STRIPE_SECRET_KEY
    if not plan.stripe_product_id:
        product = stripe.Product.create(name=plan.name, stripe_account=coach.stripe_connect_account_id)
        plan.stripe_product_id = product['id']
    else:
        stripe.Product.modify(
            plan.stripe_product_id, name=plan.name,
            stripe_account=coach.stripe_connect_account_id,
        )

    recurring = None
    if plan.kind == SubscriptionPlan.KIND_SUBSCRIPTION:
        interval, interval_count = SubscriptionPlan.STRIPE_INTERVAL_BY_BILLING.get(
            plan.billing_interval, ('month', 1),
        )
        recurring = {'interval': interval, 'interval_count': interval_count}
    price = stripe.Price.create(
        product=plan.stripe_product_id,
        unit_amount=to_stripe_amount(plan.price, plan.currency),
        currency=plan.currency.lower(),
        recurring=recurring,
        stripe_account=coach.stripe_connect_account_id,
    )

    old_price_id = plan.stripe_price_id
    if old_price_id and old_price_id != price['id']:
        try:
            stripe.Price.modify(old_price_id, active=False, stripe_account=coach.stripe_connect_account_id)
        except Exception:
            logger.exception('stripe_connect.archive_old_price_failed plan=%s price=%s', plan.id, old_price_id)

    plan.stripe_price_id = price['id']
    plan.is_online_purchasable = True
    plan.save(update_fields=['stripe_product_id', 'stripe_price_id', 'is_online_purchasable', 'updated_at'])


def cancel_subscription(client_subscription):
    """Cancel the Stripe Connect subscription behind a ClientSubscription, if
    any. Cash/manual rows (external_payment_provider='manual', no
    stripe_subscription_id) are a no-op — the caller still updates the local
    status. Stripe errors are logged, not raised: a remote hiccup shouldn't
    block the athlete/coach from ending the relationship locally."""
    if not client_subscription.stripe_subscription_id:
        return
    coach = client_subscription.subscription_plan.coach
    if not coach.stripe_connect_account_id:
        return

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        stripe.Subscription.delete(
            client_subscription.stripe_subscription_id,
            stripe_account=coach.stripe_connect_account_id,
        )
    except stripe.error.StripeError:
        logger.exception(
            'stripe_connect.cancel_subscription_failed subscription=%s',
            client_subscription.id,
        )


def sync_account_status(coach, account):
    """Update the coach's cached Connect status flags from a Stripe Account
    object (webhook payload or a fresh retrieve)."""
    from django.utils import timezone

    charges_enabled = bool(account.get('charges_enabled'))
    was_enabled = coach.stripe_connect_charges_enabled

    coach.stripe_connect_charges_enabled = charges_enabled
    coach.stripe_connect_details_submitted = bool(account.get('details_submitted'))
    coach.stripe_connect_payouts_enabled = bool(account.get('payouts_enabled'))
    if charges_enabled and not was_enabled:
        coach.stripe_connect_onboarded_at = timezone.now()
    coach.save(update_fields=[
        'stripe_connect_charges_enabled', 'stripe_connect_details_submitted',
        'stripe_connect_payouts_enabled', 'stripe_connect_onboarded_at', 'updated_at',
    ])
