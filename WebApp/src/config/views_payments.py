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
from django.db import transaction
from django.http import HttpResponse, HttpResponseBadRequest
from django.shortcuts import render
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from domain.accounts.models import User
from domain.billing.models import PlatformPurchase
from .services import ratelimit
from .services.codes import generate_platform_code
from .services.email import send_platform_purchase_confirmation, send_platform_reactivated

logger = logging.getLogger(__name__)

CHECKOUT_RATE_LIMIT = 10
CHECKOUT_RATE_WINDOW_SECONDS = 15 * 60

PLAN_LABELS = {
    PlatformPurchase.PLAN_ATHENA: 'Athena',
    PlatformPurchase.PLAN_APOLLO: 'Apollo',
    PlatformPurchase.PLAN_ZEUS: 'Zeus',
}


def _plan_prices(billing):
    """Map of plan slug -> recurring price ID for the given billing interval."""
    if billing == PlatformPurchase.BILLING_ANNUAL:
        return {
            PlatformPurchase.PLAN_ATHENA: settings.STRIPE_PRICE_ATHENA_ANNUALE,
            PlatformPurchase.PLAN_APOLLO: settings.STRIPE_PRICE_APOLLO_ANNUALE,
            PlatformPurchase.PLAN_ZEUS: settings.STRIPE_PRICE_ZEUS_ANNUALE,
        }
    return {
        PlatformPurchase.PLAN_ATHENA: settings.STRIPE_PRICE_ATHENA,
        PlatformPurchase.PLAN_APOLLO: settings.STRIPE_PRICE_APOLLO,
        PlatformPurchase.PLAN_ZEUS: settings.STRIPE_PRICE_ZEUS,
    }


def _chiron_price(billing):
    if billing == PlatformPurchase.BILLING_ANNUAL:
        return settings.STRIPE_PRICE_CHIRON_ANNUALE
    return settings.STRIPE_PRICE_CHIRON

# Distinct, actionable copy per failure reason — never a stack trace or
# internal detail, just enough for the buyer to understand what to do next.
# Rendered through the same branded error.html used for checkout_return.
_ERROR_COPY = {
    'not_configured': {
        'error_title': 'Pagamenti non disponibili',
        'error_heading': 'Pagamenti temporaneamente non disponibili.',
        'error_message': 'Il servizio di pagamento non è al momento raggiungibile. Riprova tra poco o scrivici a supporto@athlynk.it.',
    },
    'invalid_plan': {
        'error_title': 'Piano non valido',
        'error_heading': 'Il piano selezionato non esiste.',
        'error_message': 'Torna alla pagina dei prezzi e scegli un piano disponibile.',
    },
    'rate_limited': {
        'error_title': 'Troppi tentativi',
        'error_heading': 'Troppi tentativi di pagamento.',
        'error_message': 'Attendi qualche minuto e riprova.',
    },
    'create_failed': {
        'error_title': 'Pagamento non avviato',
        'error_heading': 'Non siamo riusciti ad avviare il pagamento.',
        'error_message': 'Nessun importo è stato addebitato. Riprova tra poco; se il problema persiste scrivici a supporto@athlynk.it.',
    },
}


def _unavailable(request, reason, status):
    copy = _ERROR_COPY[reason]
    return render(request, 'pages/checkout/error.html', {
        **copy,
        'website_url': settings.WEBSITE_URL,
        'cta_url': f'{settings.WEBSITE_URL}/acquista.html',
    }, status=status)


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
        return _unavailable(request, 'not_configured', 503)

    plan = (request.GET.get('plan') or '').strip().lower()
    billing = (request.GET.get('billing') or '').strip().lower()
    if billing not in (PlatformPurchase.BILLING_MONTHLY, PlatformPurchase.BILLING_ANNUAL):
        billing = PlatformPurchase.BILLING_MONTHLY

    price_id = _plan_prices(billing).get(plan)
    if not price_id:
        logger.error('stripe.checkout.invalid_plan plan=%s billing=%s', plan, billing)
        return _unavailable(request, 'invalid_plan', 404)

    # The marketing page forces an explicit Sì/No choice before building this
    # URL — a missing/invalid value means it was reached some other way, so
    # treat it the same as an invalid plan rather than silently defaulting.
    returning = (request.GET.get('returning') or '').strip()
    if returning not in ('0', '1'):
        logger.error('stripe.checkout.missing_returning_flag plan=%s', plan)
        return _unavailable(request, 'invalid_plan', 404)

    wants_chiron = request.GET.get('chiron') == '1'
    chiron_price = _chiron_price(billing)
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
        return _unavailable(request, 'rate_limited', 429)

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
            # plan/add-on/interval without re-deriving them from price IDs.
            metadata={
                'plan': plan, 'chiron': '1' if wants_chiron else '0', 'billing': billing,
                'returning_customer': returning,
            },
            return_url=(
                f'{settings.SITE_URL}/acquista/esito/?session_id={{CHECKOUT_SESSION_ID}}'
            ),
        )
    except Exception:
        logger.exception('stripe.checkout.create_failed')
        return _unavailable(request, 'create_failed', 502)

    return render(request, 'pages/checkout/checkout.html', {
        'publishable_key': settings.STRIPE_PUBLISHABLE_KEY,
        'client_secret': session.client_secret,
        'plan_label': PLAN_LABELS.get(plan, 'Athlynk'),
        'has_chiron': wants_chiron,
        'billing_label': 'Fatturazione annuale' if billing == PlatformPurchase.BILLING_ANNUAL else 'Fatturazione mensile',
        'returning_customer': returning == '1',
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

    if status == 'expired':
        copy = {
            'error_title': 'Sessione scaduta',
            'error_heading': 'La sessione di pagamento è scaduta.',
            'error_message': 'Nessun importo è stato addebitato. Ripeti l\'acquisto dalla pagina dei prezzi.',
        }
    elif status == 'open':
        copy = {
            'error_title': 'Pagamento non completato',
            'error_heading': 'Il pagamento non è stato completato.',
            'error_message': 'Nessun importo è stato addebitato. Puoi riprovare quando vuoi.',
        }
    else:
        # Missing/invalid session_id or the Stripe lookup itself failed —
        # don't imply anything about whether a charge went through.
        copy = {
            'error_title': 'Verifica non riuscita',
            'error_heading': 'Non siamo riusciti a verificare il pagamento.',
            'error_message': 'Se hai completato il pagamento riceverai comunque il codice via email a breve. Altrimenti riprova dalla pagina dei prezzi.',
        }

    return render(request, 'pages/checkout/error.html', {
        **copy,
        'website_url': settings.WEBSITE_URL,
        'cta_url': f'{settings.WEBSITE_URL}/acquista.html',
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
    billing = meta.get('billing') or PlatformPurchase.BILLING_MONTHLY
    if billing not in (PlatformPurchase.BILLING_MONTHLY, PlatformPurchase.BILLING_ANNUAL):
        billing = PlatformPurchase.BILLING_MONTHLY
    returning_customer = meta.get('returning_customer') == '1'
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
    # `code` is always generated (the field is unique/non-null) even on the
    # returning-customer path, where it's simply never emailed or used.
    purchase, created = PlatformPurchase.objects.get_or_create(
        stripe_session_id=session_id,
        defaults={
            'email': email,
            'code': generate_platform_code(),
            'plan': plan,
            'billing_interval': billing,
            'has_chiron': has_chiron,
            'status': status,
            'stripe_subscription_id': subscription_id,
            'stripe_customer_id': session.get('customer') or '',
            'amount_total': session.get('amount_total') or 0,
            'currency': session.get('currency') or 'eur',
            'current_period_end': period_end,
            'returning_customer': returning_customer,
        },
    )
    if not created:
        return

    if returning_customer:
        # Ticking "returning customer" is only a signal, not a guarantee — if no
        # verified account matches this email, fall back to the normal new-code
        # path so the payer still has a way in, and log it for support follow-up.
        existing_user = (
            User.objects.filter(email__iexact=email, role='COACH', is_verified=True)
            .select_related('coach_profile').first()
        )
        if existing_user and hasattr(existing_user, 'coach_profile'):
            with transaction.atomic():
                purchase.redeemed_at = timezone.now()
                purchase.redeemed_by = existing_user
                purchase.save(update_fields=['redeemed_at', 'redeemed_by', 'updated_at'])
                existing_user.coach_profile.platform_purchase = purchase
                existing_user.coach_profile.save(update_fields=['platform_purchase', 'updated_at'])

            if send_platform_reactivated(purchase):
                purchase.email_sent = True
                purchase.save(update_fields=['email_sent'])
            return

        logger.warning('stripe.webhook.returning_customer_no_match email=%s session=%s', email, session_id)

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

    # A `cancel_at_period_end` subscription is still paid and active until
    # `current_period_end` — only the terminal Stripe status ends access now;
    # duration enforcement (config.session_utils.coach_has_active_platform_access)
    # relies on current_period_end lapsing naturally, not on an early flip here.
    stripe_status = subscription.get('status')
    if stripe_status == 'canceled':
        purchase.status = PlatformPurchase.STATUS_CANCELED
    elif stripe_status in _ACTIVE_STRIPE_STATUSES:
        purchase.status = PlatformPurchase.STATUS_ACTIVE
    else:
        purchase.status = PlatformPurchase.STATUS_PAST_DUE

    purchase.current_period_end = _period_end_dt(subscription) or purchase.current_period_end
    purchase.save(update_fields=['status', 'current_period_end', 'updated_at'])
