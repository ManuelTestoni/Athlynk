"""Stripe checkout + webhook for platform subscriptions (coach -> Athlynk).

The marketing site (static, Vercel) links to `checkout_page?plan=<plan>` (with an
optional `&chiron=1` add-on). That page renders Stripe **embedded** Checkout in
`subscription` mode, so the buyer enters email + billing on our own branded page
(no redirect to stripe.com, card data never touches our server). On completion
Stripe sends them to `checkout_return`, which only displays status. Initial
fulfilment — creating the PlatformPurchase, generating the access code, sending
the confirmation email — happens only in `stripe_webhook`, on a
signature-verified `checkout.session.completed`, never on the browser return
(which can be skipped, replayed, or forged). The subscription's lifecycle
(renewals, lapses, cancellations) is kept in sync via
`customer.subscription.updated/deleted`.
"""
import logging
from datetime import datetime, timezone as dt_timezone

import stripe
from django.conf import settings
from django.http import HttpResponse, HttpResponseBadRequest
from django.shortcuts import render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from domain.billing.models import PlatformPurchase
from .services import ratelimit
from .services.codes import generate_platform_code
from .services.email import send_platform_purchase_confirmation

logger = logging.getLogger(__name__)

CHECKOUT_RATE_LIMIT = 10
CHECKOUT_RATE_WINDOW_SECONDS = 15 * 60

PLAN_LABELS = {
    PlatformPurchase.PLAN_ATHENA: 'Athena',
    PlatformPurchase.PLAN_APOLLO: 'Apollo',
    PlatformPurchase.PLAN_ZEUS: 'Zeus',
}


def _plan_prices():
    """Map of plan slug -> recurring price ID, skipping plans with no price set."""
    return {
        PlatformPurchase.PLAN_ATHENA: settings.STRIPE_PRICE_ATHENA,
        PlatformPurchase.PLAN_APOLLO: settings.STRIPE_PRICE_APOLLO,
        PlatformPurchase.PLAN_ZEUS: settings.STRIPE_PRICE_ZEUS,
    }

# Shown when Stripe is not configured / temporarily failing. Dark, on-brand,
# self-contained so it needs no template or base layout.
_UNAVAILABLE_HTML = (
    '<!doctype html><html lang="it"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<title>Pagamenti non disponibili · Athlynk</title></head>'
    '<body style="background:#0b0a08;color:#f4efe4;font-family:system-ui,sans-serif;'
    'display:flex;min-height:100vh;align-items:center;justify-content:center;'
    'text-align:center;padding:24px;margin:0">'
    '<div><h1 style="font-weight:400;font-size:22px">Pagamenti temporaneamente non disponibili</h1>'
    '<p style="color:#9b9181">Riprova tra poco o scrivici a supporto@athlynk.it.</p>'
    '<p><a href="https://athlynk.it" style="color:#c9a96a;text-decoration:none">&larr; Torna al sito</a></p>'
    '</div></body></html>'
)


def _unavailable(status):
    return HttpResponse(_UNAVAILABLE_HTML, status=status)


@require_GET
def checkout_page(request):
    """Render the branded embedded-Checkout page for the chosen plan.

    `?plan=athena|apollo|zeus` selects the monthly plan; `&chiron=1` adds the
    Chiron add-on as a second recurring line item. Creates an embedded Checkout
    Session server-side and hands its client_secret to the template, which mounts
    Stripe's secure form (email + billing collected there).
    """
    if not settings.STRIPE_SECRET_KEY or not settings.STRIPE_PUBLISHABLE_KEY:
        logger.error('stripe.checkout.not_configured')
        return _unavailable(503)

    plan = (request.GET.get('plan') or '').strip().lower()
    price_id = _plan_prices().get(plan)
    if not price_id:
        logger.error('stripe.checkout.invalid_plan plan=%s', plan)
        return _unavailable(503)

    wants_chiron = request.GET.get('chiron') == '1'
    chiron_price = settings.STRIPE_PRICE_CHIRON
    if wants_chiron and not chiron_price:
        # Chiron requested but not configured: fall back to the plan alone
        # rather than failing the whole checkout.
        logger.warning('stripe.checkout.chiron_unconfigured')
        wants_chiron = False

    ip = ratelimit.client_ip(request)
    allowed, _ = ratelimit.hit(
        'platform_checkout', ip, CHECKOUT_RATE_LIMIT, CHECKOUT_RATE_WINDOW_SECONDS,
    )
    if not allowed:
        logger.warning('stripe.checkout.rate_limited ip=%s', ip)
        return _unavailable(429)

    line_items = [{'price': price_id, 'quantity': 1}]
    if wants_chiron:
        line_items.append({'price': chiron_price, 'quantity': 1})

    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        session = stripe.checkout.Session.create(
            ui_mode='embedded',
            mode='subscription',
            line_items=line_items,
            # Carried back on checkout.session.completed so fulfilment knows the
            # plan/add-on without re-deriving them from price IDs.
            metadata={'plan': plan, 'chiron': '1' if wants_chiron else '0'},
            return_url=(
                f'{settings.SITE_URL}/acquista/esito/?session_id={{CHECKOUT_SESSION_ID}}'
            ),
        )
    except Exception:
        logger.exception('stripe.checkout.create_failed')
        return _unavailable(502)

    return render(request, 'pages/checkout/checkout.html', {
        'publishable_key': settings.STRIPE_PUBLISHABLE_KEY,
        'client_secret': session.client_secret,
        'plan_label': PLAN_LABELS.get(plan, 'Athlynk'),
        'has_chiron': wants_chiron,
    })


@require_GET
def checkout_return(request):
    """Display the outcome after Stripe returns the buyer. Never fulfils (the
    webhook does); only reads the session status to show success or error."""
    session_id = request.GET.get('session_id') or ''
    status = None
    email = ''
    if session_id and settings.STRIPE_SECRET_KEY:
        stripe.api_key = settings.STRIPE_SECRET_KEY
        try:
            session = stripe.checkout.Session.retrieve(session_id)
            status = session.get('status')  # 'complete' | 'open' | 'expired'
            email = (session.get('customer_details') or {}).get('email') or ''
        except Exception:
            logger.exception('stripe.return.retrieve_failed session=%s', session_id)

    if status == 'complete':
        return render(request, 'pages/checkout/success.html', {
            'email': email,
            'login_url': f'{settings.SITE_URL}/login/',
        })

    # Payment not completed (open/expired/unknown) or lookup failed.
    return render(request, 'pages/checkout/error.html', {
        'website_url': settings.WEBSITE_URL,
    }, status=402 if status else 400)


@csrf_exempt
@require_POST
def stripe_webhook(request):
    """Fulfil a completed checkout: create the purchase, generate the code, email it."""
    if not settings.STRIPE_WEBHOOK_SECRET:
        logger.error('stripe.webhook.not_configured')
        return HttpResponse(status=503)

    try:
        event = stripe.Webhook.construct_event(
            request.body,
            request.META.get('HTTP_STRIPE_SIGNATURE', ''),
            settings.STRIPE_WEBHOOK_SECRET,
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        logger.warning('stripe.webhook.bad_signature')
        return HttpResponseBadRequest('invalid signature')

    event_type = event['type']
    if event_type == 'checkout.session.completed':
        _fulfil_checkout(event['data']['object'])
    elif event_type in ('customer.subscription.updated', 'customer.subscription.deleted'):
        _sync_subscription(event['data']['object'])

    # Always 200 for handled-or-ignored events so Stripe stops retrying.
    return HttpResponse(status=200)


# Stripe subscription.status -> our coarse status. Anything not "active"-ish
# and not explicitly canceled is treated as past_due (access withheld).
_ACTIVE_STRIPE_STATUSES = {'active', 'trialing'}


def _period_end_dt(subscription):
    """Convert a subscription's current_period_end (unix) to an aware datetime."""
    ts = subscription.get('current_period_end')
    if not ts:
        return None
    return datetime.fromtimestamp(ts, tz=dt_timezone.utc)


def _fulfil_checkout(session):
    session_id = session.get('id')
    email = (
        (session.get('customer_details') or {}).get('email')
        or session.get('customer_email')
        or ''
    )
    if not session_id or not email:
        logger.error('stripe.webhook.missing_fields session=%s', session_id)
        return

    meta = session.get('metadata') or {}
    plan = (meta.get('plan') or PlatformPurchase.PLAN_APOLLO).lower()
    has_chiron = meta.get('chiron') == '1'
    subscription_id = session.get('subscription') or ''

    # Pull live status + renewal date from the subscription object (the session
    # alone doesn't carry them). Best-effort: fulfilment proceeds regardless.
    status = PlatformPurchase.STATUS_ACTIVE
    period_end = None
    if subscription_id and settings.STRIPE_SECRET_KEY:
        stripe.api_key = settings.STRIPE_SECRET_KEY
        try:
            sub = stripe.Subscription.retrieve(subscription_id)
            status = (
                PlatformPurchase.STATUS_ACTIVE
                if sub.get('status') in _ACTIVE_STRIPE_STATUSES
                else PlatformPurchase.STATUS_PAST_DUE
            )
            period_end = _period_end_dt(sub)
        except Exception:
            logger.exception('stripe.webhook.subscription_retrieve_failed sub=%s', subscription_id)

    # Idempotent on the Stripe session id: a replayed/duplicate webhook reuses
    # the existing row (get_or_create also absorbs the unique-constraint race).
    purchase, created = PlatformPurchase.objects.get_or_create(
        stripe_session_id=session_id,
        defaults={
            'email': email,
            'code': generate_platform_code(),
            'plan': plan,
            'has_chiron': has_chiron,
            'status': status,
            'stripe_subscription_id': subscription_id,
            'stripe_customer_id': session.get('customer') or '',
            'amount_total': session.get('amount_total') or 0,
            'currency': session.get('currency') or 'eur',
            'current_period_end': period_end,
        },
    )
    if not created:
        return

    if send_platform_purchase_confirmation(purchase):
        purchase.email_sent = True
        purchase.save(update_fields=['email_sent'])


def _sync_subscription(subscription):
    """Keep a purchase's status/renewal date in sync with its Stripe subscription."""
    sub_id = subscription.get('id')
    if not sub_id:
        return
    purchase = PlatformPurchase.objects.filter(stripe_subscription_id=sub_id).first()
    if not purchase:
        # Subscription event arrived before (or without) its checkout session.
        logger.info('stripe.webhook.subscription_no_purchase sub=%s', sub_id)
        return

    stripe_status = subscription.get('status')
    if subscription.get('cancel_at_period_end') or stripe_status == 'canceled':
        purchase.status = PlatformPurchase.STATUS_CANCELED
    elif stripe_status in _ACTIVE_STRIPE_STATUSES:
        purchase.status = PlatformPurchase.STATUS_ACTIVE
    else:
        purchase.status = PlatformPurchase.STATUS_PAST_DUE

    purchase.current_period_end = _period_end_dt(subscription) or purchase.current_period_end
    purchase.save(update_fields=['status', 'current_period_end', 'updated_at'])
