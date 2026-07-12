"""Athlete-facing Stripe Checkout for coach subscription plans/bundles
("abbonamenti" — coach->athlete payments). Distinct audience/trust boundary
from views_payments.py (platform billing) and views_connect.py (coach
onboarding).

Charge model: **direct charges** — the Checkout Session is created directly
on the coach's connected account (`stripe_account=` kwarg), matching where
the plan's Stripe Product/Price actually lives (see
services.stripe_connect.sync_plan_to_stripe, which creates them with the same
`stripe_account=` kwarg). Athlynk's cut is taken via
`application_fee_amount`/`application_fee_percent` on the same charge — no
`transfer_data`/destination-charge indirection needed, since the money is
already landing on the connected account directly.

Never fulfils on the browser return leg (same doctrine as
views_payments.checkout_return / views_connect.connect_onboarding_return_view)
— fulfilment happens only in views_connect.stripe_connect_webhook, on a
signature-verified checkout.session.completed.
"""
import logging

import stripe
from django.conf import settings
from django.http import Http404
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_GET, require_POST

from domain.billing.models import Bundle, ConnectCheckoutIntent, SubscriptionPlan, to_stripe_amount
from .session_utils import get_active_relationship, get_session_client

logger = logging.getLogger(__name__)


def _unavailable(request, message):
    return render(request, 'pages/checkout/error.html', {
        'error_title': 'Pagamento non disponibile',
        'error_heading': 'Non riusciamo ad avviare il pagamento.',
        'error_message': message,
        'website_url': settings.WEBSITE_URL,
        'cta_url': settings.SITE_URL + '/abbonamenti/',
    }, status=502)


def _client_and_relationship(request):
    client = get_session_client(request)
    if not client:
        return None, None
    relationship = get_active_relationship(client)
    if not relationship:
        return client, None
    return client, relationship


@require_POST
def athlete_checkout_start_view(request, plan_id):
    client, relationship = _client_and_relationship(request)
    if not client:
        return redirect('login')
    if not relationship:
        return redirect('client_blocked')

    plan = get_object_or_404(
        SubscriptionPlan, id=plan_id, coach=relationship.coach,
        is_active=True, is_online_purchasable=True,
    )
    coach = relationship.coach
    if not settings.STRIPE_SECRET_KEY:
        return _unavailable(request, 'Il servizio di pagamento non è al momento raggiungibile. Riprova tra poco.')

    mode = 'subscription' if plan.kind == SubscriptionPlan.KIND_SUBSCRIPTION else 'payment'
    fee_kwargs = {}
    if mode == 'subscription':
        fee_kwargs['subscription_data'] = {'application_fee_percent': settings.PLATFORM_FEE_PERCENT}
    else:
        fee_kwargs['payment_intent_data'] = {
            'application_fee_amount': int(to_stripe_amount(plan.price, plan.currency) * settings.PLATFORM_FEE_PERCENT / 100),
        }

    # "Richiedi fattura": let Stripe's own hosted Checkout collect fiscal
    # details and issue the invoice — no custom billing form/PDF generation.
    # Subscriptions get an invoice automatically at every renewal already;
    # invoice_creation is only for one-off (mode='payment') sessions.
    if request.POST.get('wants_invoice') == 'on':
        fee_kwargs['tax_id_collection'] = {'enabled': True}
        if mode == 'payment':
            fee_kwargs['invoice_creation'] = {'enabled': True}

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        session = stripe.checkout.Session.create(
            mode=mode,
            line_items=[{'price': plan.stripe_price_id, 'quantity': 1}],
            stripe_account=coach.stripe_connect_account_id,
            success_url=f'{settings.SITE_URL}/abbonamenti/checkout/success/?session_id={{CHECKOUT_SESSION_ID}}',
            cancel_url=f'{settings.SITE_URL}/abbonamenti/checkout/annullato/',
            **fee_kwargs,
        )
    except Exception:
        logger.exception('stripe_checkout.plan_session_create_failed plan=%s', plan.id)
        return _unavailable(request, 'Nessun importo è stato addebitato. Riprova tra poco.')

    ConnectCheckoutIntent.objects.create(
        stripe_checkout_session_id=session['id'],
        coach=coach, client=client, plan=plan,
    )
    return redirect(session['url'])


@require_POST
def athlete_checkout_bundle_start_view(request, bundle_id):
    client, relationship = _client_and_relationship(request)
    if not client:
        return redirect('login')
    if not relationship:
        return redirect('client_blocked')

    bundle = get_object_or_404(Bundle, id=bundle_id, coach=relationship.coach, is_active=True)
    coach = relationship.coach
    items = list(bundle.items.select_related('plan'))
    if not items or any(not item.plan.is_online_purchasable for item in items):
        return _unavailable(request, 'Questo pacchetto non è al momento acquistabile online.')

    if not settings.STRIPE_SECRET_KEY:
        return _unavailable(request, 'Il servizio di pagamento non è al momento raggiungibile. Riprova tra poco.')

    line_items = [{'price': item.plan.stripe_price_id, 'quantity': item.quantity} for item in items]
    subtotal_units = sum(
        to_stripe_amount(item.price_override if item.price_override is not None else item.plan.price, bundle.currency) * item.quantity
        for item in items
    )

    stripe.api_key = settings.STRIPE_SECRET_KEY
    discounts = None
    try:
        if bundle.discount_percent:
            coupon = stripe.Coupon.create(
                percent_off=float(bundle.discount_percent), duration='once',
                stripe_account=coach.stripe_connect_account_id,
            )
            discounts = [{'coupon': coupon['id']}]
        elif bundle.discount_amount:
            coupon = stripe.Coupon.create(
                amount_off=to_stripe_amount(bundle.discount_amount, bundle.currency), currency=bundle.currency.lower(), duration='once',
                stripe_account=coach.stripe_connect_account_id,
            )
            discounts = [{'coupon': coupon['id']}]

        session_kwargs = dict(
            mode='payment',
            line_items=line_items,
            stripe_account=coach.stripe_connect_account_id,
            success_url=f'{settings.SITE_URL}/abbonamenti/checkout/success/?session_id={{CHECKOUT_SESSION_ID}}',
            cancel_url=f'{settings.SITE_URL}/abbonamenti/checkout/annullato/',
            payment_intent_data={
                'application_fee_amount': int(subtotal_units * settings.PLATFORM_FEE_PERCENT / 100),
            },
        )
        if discounts:
            session_kwargs['discounts'] = discounts
        if request.POST.get('wants_invoice') == 'on':
            session_kwargs['tax_id_collection'] = {'enabled': True}
            session_kwargs['invoice_creation'] = {'enabled': True}
        session = stripe.checkout.Session.create(**session_kwargs)
    except Exception:
        logger.exception('stripe_checkout.bundle_session_create_failed bundle=%s', bundle.id)
        return _unavailable(request, 'Nessun importo è stato addebitato. Riprova tra poco.')

    ConnectCheckoutIntent.objects.create(
        stripe_checkout_session_id=session['id'],
        coach=coach, client=client, bundle=bundle,
    )
    return redirect(session['url'])


@require_GET
def athlete_checkout_success_view(request):
    """Display the outcome after Stripe returns the athlete. Never fulfils
    (the webhook does); only reads the session status to show success or
    still-processing (webhooks can lag slightly behind the redirect)."""
    session_id = request.GET.get('session_id') or ''
    intent = ConnectCheckoutIntent.objects.filter(stripe_checkout_session_id=session_id).first() if session_id else None
    if not intent:
        raise Http404

    status = None
    if settings.STRIPE_SECRET_KEY:
        stripe.api_key = settings.STRIPE_SECRET_KEY
        try:
            session = stripe.checkout.Session.retrieve(session_id, stripe_account=intent.coach.stripe_connect_account_id)
            status = session.get('status')
        except Exception:
            logger.exception('stripe_checkout.success_retrieve_failed session=%s', session_id)

    return render(request, 'pages/abbonamenti/checkout_success.html', {
        'intent': intent,
        'stripe_status': status,
        'fulfilled': intent.status == ConnectCheckoutIntent.STATUS_FULFILLED,
    })


@require_GET
def athlete_checkout_cancel_view(request):
    """Stripe bounces here when the athlete backs out of Checkout (no charge
    was made). Just a reassuring interstitial — no session to verify."""
    return render(request, 'pages/abbonamenti/checkout_cancel.html')
