"""Newsletter double opt-in views (confirm, unsubscribe, toggle from settings)."""
from django.conf import settings
from django.http import JsonResponse
from django.shortcuts import render, redirect
from django.utils import timezone
from django.views.decorators.http import require_POST

from domain.newsletter.models import Subscriber, SubscriptionEvent
from .services.tokens import generate_token, get_client_ip
from .services.email import send_newsletter_confirm
from .session_utils import get_session_user


def confirm_subscription(request, token):
    """Public link from email: marks subscriber CONFIRMED."""
    try:
        sub = Subscriber.objects.get(confirm_token=token)
    except Subscriber.DoesNotExist:
        return render(request, 'pages/newsletter/invalid.html', status=400)

    if sub.status == Subscriber.STATUS_CONFIRMED:
        return render(request, 'pages/newsletter/confirmed.html', {'subscriber': sub, 'already': True})

    sub.status = Subscriber.STATUS_CONFIRMED
    sub.confirmed_at = timezone.now()
    sub.confirm_token = ''
    sub.save(update_fields=['status', 'confirmed_at', 'confirm_token'])

    SubscriptionEvent.objects.create(
        subscriber=sub,
        event_type=SubscriptionEvent.EVENT_CONFIRM,
        ip=get_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
    )
    return render(request, 'pages/newsletter/confirmed.html', {'subscriber': sub})


def unsubscribe(request, token):
    """Public unsubscribe link from email footer."""
    try:
        sub = Subscriber.objects.get(unsubscribe_token=token)
    except Subscriber.DoesNotExist:
        return render(request, 'pages/newsletter/invalid.html', status=400)

    if sub.status != Subscriber.STATUS_UNSUBSCRIBED:
        sub.status = Subscriber.STATUS_UNSUBSCRIBED
        sub.unsubscribed_at = timezone.now()
        sub.save(update_fields=['status', 'unsubscribed_at'])
        SubscriptionEvent.objects.create(
            subscriber=sub,
            event_type=SubscriptionEvent.EVENT_UNSUBSCRIBE,
            ip=get_client_ip(request),
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        )

    return render(request, 'pages/newsletter/unsubscribed.html', {'subscriber': sub})


@require_POST
def toggle_subscription(request):
    """Settings toggle for logged-in users."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    want_subscribed = request.POST.get('subscribe') == 'on'

    sub = Subscriber.objects.filter(email=user.email).first()

    if want_subscribed:
        if sub and sub.status == Subscriber.STATUS_CONFIRMED:
            return JsonResponse({'status': 'CONFIRMED', 'message': 'Già iscritto.'})
        if not sub:
            sub = Subscriber.objects.create(
                email=user.email,
                status=Subscriber.STATUS_PENDING,
                confirm_token=generate_token(),
                unsubscribe_token=generate_token(),
                consent_version=settings.CONSENT_VERSION,
                consent_text_snapshot='Iscrizione newsletter Athlynk via impostazioni profilo.',
                subscribed_ip=get_client_ip(request),
                subscribed_user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
            )
        else:
            # was UNSUBSCRIBED or PENDING — reset to pending and send new confirm
            sub.status = Subscriber.STATUS_PENDING
            sub.confirm_token = generate_token()
            sub.save(update_fields=['status', 'confirm_token'])

        SubscriptionEvent.objects.create(
            subscriber=sub,
            event_type=SubscriptionEvent.EVENT_RESUBSCRIBE if sub.unsubscribed_at else SubscriptionEvent.EVENT_SIGNUP,
            ip=get_client_ip(request),
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        )
        send_newsletter_confirm(sub)
        return JsonResponse({'status': 'PENDING', 'message': 'Controlla la tua email per confermare.'})

    # Unsubscribe path
    if sub and sub.status != Subscriber.STATUS_UNSUBSCRIBED:
        sub.status = Subscriber.STATUS_UNSUBSCRIBED
        sub.unsubscribed_at = timezone.now()
        sub.save(update_fields=['status', 'unsubscribed_at'])
        SubscriptionEvent.objects.create(
            subscriber=sub,
            event_type=SubscriptionEvent.EVENT_UNSUBSCRIBE,
            ip=get_client_ip(request),
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        )
    return JsonResponse({'status': 'UNSUBSCRIBED', 'message': 'Iscrizione annullata.'})
