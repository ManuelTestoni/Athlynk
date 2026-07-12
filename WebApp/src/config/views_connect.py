"""Stripe Connect onboarding + webhook for coach->athlete payments
("abbonamenti"). Distinct trust boundary from views_payments.py (platform
billing, coach pays Athlynk) — separate webhook endpoint/secret, separate
audience (coaches connecting an account, not athletes/coaches checking out).

Onboarding never fulfils anything on the browser return leg (same doctrine as
views_payments.checkout_return): account.updated, verified by webhook
signature, is the only source of truth for charges_enabled/etc.
"""
import logging

import stripe
from django.conf import settings
from django.http import HttpResponse, HttpResponseBadRequest, JsonResponse
from django.shortcuts import redirect
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from domain.accounts.models import CoachProfile
from domain.billing.models import ClientSubscription, ConnectCheckoutIntent, StripeConnectEvent, ZERO_DECIMAL_CURRENCIES
from .services.email import send_coach_new_subscription, send_subscription_payment_confirmed, send_subscription_payment_failed
from .services.stripe_connect import create_account_link, create_connect_account, sync_account_status
from .session_utils import get_session_coach

logger = logging.getLogger(__name__)


@require_POST
def connect_onboarding_start_view(request):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    if not settings.STRIPE_SECRET_KEY:
        return JsonResponse({'error': 'Pagamenti non configurati.'}, status=503)

    try:
        account_id = create_connect_account(coach)
        url = create_account_link(
            account_id,
            refresh_url=f'{settings.SITE_URL}/abbonamenti/connetti/refresh/',
            return_url=f'{settings.SITE_URL}/abbonamenti/connetti/ritorno/',
        )
    except Exception:
        logger.exception('stripe_connect.onboarding_start_failed coach=%s', coach.id)
        return JsonResponse({'error': 'Impossibile avviare il collegamento a Stripe. Riprova.'}, status=502)

    return redirect(url)


@require_GET
def connect_onboarding_return_view(request):
    """Browser return from the Account Link. Re-fetches live status for an
    immediate UI update; account.updated (webhook) remains the source of truth."""
    coach = get_session_coach(request)
    if coach and coach.stripe_connect_account_id and settings.STRIPE_SECRET_KEY:
        stripe.api_key = settings.STRIPE_SECRET_KEY
        try:
            account = stripe.Account.retrieve(coach.stripe_connect_account_id)
            sync_account_status(coach, account)
        except Exception:
            logger.exception('stripe_connect.return_status_refresh_failed coach=%s', coach.id)
    return redirect('abbonamenti_dashboard')


@require_GET
def connect_onboarding_refresh_view(request):
    """Account Link expired/abandoned — Stripe sends the coach back here to
    get a new one."""
    coach = get_session_coach(request)
    if not coach or not coach.stripe_connect_account_id or not settings.STRIPE_SECRET_KEY:
        return redirect('abbonamenti_dashboard')
    try:
        url = create_account_link(
            coach.stripe_connect_account_id,
            refresh_url=f'{settings.SITE_URL}/abbonamenti/connetti/refresh/',
            return_url=f'{settings.SITE_URL}/abbonamenti/connetti/ritorno/',
        )
    except Exception:
        logger.exception('stripe_connect.refresh_link_failed coach=%s', coach.id)
        return redirect('abbonamenti_dashboard')
    return redirect(url)


@csrf_exempt
@require_POST
def stripe_connect_webhook(request):
    if not settings.STRIPE_CONNECT_WEBHOOK_SECRET:
        logger.error('stripe_connect.webhook.not_configured')
        return HttpResponse(status=503)

    try:
        event = stripe.Webhook.construct_event(
            request.body,
            request.META.get('HTTP_STRIPE_SIGNATURE', ''),
            settings.STRIPE_CONNECT_WEBHOOK_SECRET,
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        logger.warning('stripe_connect.webhook.bad_signature')
        return HttpResponseBadRequest('invalid signature')

    if StripeConnectEvent.objects.filter(stripe_event_id=event['id']).exists():
        return HttpResponse(status=200)  # replay, already handled
    StripeConnectEvent.objects.create(
        stripe_event_id=event['id'],
        event_type=event['type'],
        connected_account_id=event.get('account') or '',
    )

    if event['type'] == 'account.updated':
        _handle_account_updated(event['data']['object'])
    elif event['type'] == 'checkout.session.completed':
        _fulfil_connect_checkout(event['data']['object'])
    elif event['type'] == 'invoice.payment_failed':
        _handle_invoice_payment_failed(event['data']['object'])
    elif event['type'] == 'customer.subscription.deleted':
        _handle_subscription_deleted(event['data']['object'])

    # Always 200 for handled-or-ignored events so Stripe stops retrying.
    return HttpResponse(status=200)


def _handle_account_updated(account):
    account_id = account.get('id')
    if not account_id:
        return
    coach = CoachProfile.objects.filter(stripe_connect_account_id=account_id).first()
    if not coach:
        logger.info('stripe_connect.webhook.account_no_coach account=%s', account_id)
        return
    sync_account_status(coach, account)


def _format_stripe_amount(amount, currency):
    currency = (currency or 'eur').upper()
    if currency in ZERO_DECIMAL_CURRENCIES:
        return f"{amount} {currency}"
    return f"{amount / 100:.2f} {currency}"


def _receipt_url_for_session(session, coach_account_id):
    """Best-effort link to Stripe's own hosted receipt/invoice for this
    checkout — never generated in-house. None on any lookup failure; the
    confirmation email still sends without it."""
    stripe.api_key = settings.STRIPE_SECRET_KEY
    try:
        if session.get('invoice'):
            invoice = stripe.Invoice.retrieve(session['invoice'], stripe_account=coach_account_id)
            return invoice.get('hosted_invoice_url')
        if session.get('subscription'):
            invoices = stripe.Invoice.list(subscription=session['subscription'], limit=1, stripe_account=coach_account_id)
            if invoices.data:
                return invoices.data[0].get('hosted_invoice_url')
        if session.get('payment_intent'):
            intent = stripe.PaymentIntent.retrieve(
                session['payment_intent'], expand=['latest_charge'], stripe_account=coach_account_id,
            )
            charge = intent.get('latest_charge')
            if charge:
                return charge.get('receipt_url')
    except Exception:
        logger.exception('stripe_connect.receipt_url_lookup_failed session=%s', session.get('id'))
    return None


def _fulfil_connect_checkout(session):
    """Create/update the ClientSubscription for a completed Connect checkout.
    Looks up the ConnectCheckoutIntent created at session-creation time (see
    views_checkout.py) rather than trusting session metadata alone, so a
    bundle's line items don't need to round-trip through Stripe metadata."""
    session_id = session.get('id')
    if not session_id:
        return

    intent = ConnectCheckoutIntent.objects.filter(stripe_checkout_session_id=session_id).first()
    if not intent:
        logger.error('stripe_connect.webhook.no_intent session=%s', session_id)
        return
    if intent.status == ConnectCheckoutIntent.STATUS_FULFILLED:
        return  # replay, already fulfilled

    from datetime import timedelta
    from django.utils import timezone

    plan = intent.plan or (intent.bundle.items.first().plan if intent.bundle else None)
    if not plan:
        logger.error('stripe_connect.webhook.no_plan_for_intent intent=%s', intent.id)
        return

    end_date = None
    if plan.duration_days:
        end_date = timezone.now().date() + timedelta(days=plan.duration_days)

    ClientSubscription.objects.create(
        client=intent.client,
        subscription_plan=plan,
        bundle=intent.bundle,
        status='ACTIVE',
        payment_status='PAID',
        start_date=timezone.now().date(),
        end_date=end_date,
        auto_renew=bool(session.get('subscription')),
        external_payment_provider='stripe_connect',
        external_reference=session_id,
        stripe_checkout_session_id=session_id,
        stripe_subscription_id=session.get('subscription') or '',
        stripe_payment_intent_id=session.get('payment_intent') or '',
    )
    intent.status = ConnectCheckoutIntent.STATUS_FULFILLED
    intent.fulfilled_at = timezone.now()
    intent.save(update_fields=['status', 'fulfilled_at'])

    item_name = intent.bundle.name if intent.bundle else plan.name
    amount_display = _format_stripe_amount(session.get('amount_total') or 0, session.get('currency'))
    receipt_url = _receipt_url_for_session(session, intent.coach.stripe_connect_account_id)
    send_subscription_payment_confirmed(intent.client, intent.coach, item_name, amount_display, receipt_url)
    send_coach_new_subscription(intent.coach, intent.client, item_name, amount_display)


def _handle_invoice_payment_failed(invoice):
    """A subscription renewal charge failed. Notify the athlete — access
    isn't revoked here (that only happens once Stripe gives up and fires
    customer.subscription.deleted, or the athlete cancels themselves)."""
    subscription_id = invoice.get('subscription')
    if not subscription_id:
        return
    sub = ClientSubscription.objects.filter(
        stripe_subscription_id=subscription_id,
    ).select_related('client', 'subscription_plan__coach').first()
    if not sub:
        logger.info('stripe_connect.webhook.invoice_failed_no_subscription sub=%s', subscription_id)
        return
    send_subscription_payment_failed(sub.client, sub.subscription_plan.coach)


def _handle_subscription_deleted(subscription):
    """Stripe gave up on retrying a failed renewal (or the subscription was
    cancelled directly on Stripe's side): mirror that locally so the athlete
    falls back into the unpaid state — same as an explicit cancel, no
    separate email (payment_failed already notified them)."""
    subscription_id = subscription.get('id')
    if not subscription_id:
        return
    updated = ClientSubscription.objects.filter(
        stripe_subscription_id=subscription_id, status='ACTIVE',
    ).update(status='CANCELLED', auto_renew=False)
    if not updated:
        logger.info('stripe_connect.webhook.subscription_deleted_no_match sub=%s', subscription_id)
