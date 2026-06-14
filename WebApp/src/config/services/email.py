"""Email sending helpers — text + HTML alternatives.

All addresses default to settings.DEFAULT_FROM_EMAIL.
Templates expected under templates/emails/<name>.txt and <name>.html.
"""
import logging
from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.urls import reverse

logger = logging.getLogger(__name__)


def send_html_mail(to, subject, template_base, context=None, from_email=None):
    """Render emails/<template_base>.txt and .html and send."""
    context = dict(context or {})
    context.setdefault('site_url', settings.SITE_URL)
    text_body = render_to_string(f'emails/{template_base}.txt', context)
    html_body = render_to_string(f'emails/{template_base}.html', context)
    msg = EmailMultiAlternatives(
        subject=subject,
        body=text_body,
        from_email=from_email or settings.DEFAULT_FROM_EMAIL,
        to=[to] if isinstance(to, str) else list(to),
    )
    msg.attach_alternative(html_body, 'text/html')
    try:
        msg.send(fail_silently=False)
        return True
    except Exception as e:
        logger.exception('Email send failed to %s: %s', to, e)
        return False


def send_welcome_verify(user, token):
    """Welcome email with email verification link."""
    verify_url = f"{settings.SITE_URL}{reverse('verify_email', args=[token])}"
    return send_html_mail(
        to=user.email,
        subject='Conferma il tuo account Athlynk',
        template_base='welcome_verify',
        context={'user': user, 'verify_url': verify_url},
    )


def send_account_activation(user, token, coach_name=''):
    """Invite a coach-created athlete to set their own password. The emailed link
    proves mailbox ownership (the coach typed the address), so no separate email
    confirmation is needed — the athlete just creates a password and logs in."""
    activate_url = f"{settings.SITE_URL}{reverse('activate_account')}?token={token}"
    return send_html_mail(
        to=user.email,
        subject='Attiva il tuo account Athlynk',
        template_base='account_activation',
        context={'user': user, 'activate_url': activate_url, 'coach_name': coach_name, 'ttl_days': 7},
    )


def send_password_reset(user, token):
    """Password-reset link email. `token` is the plaintext token (not the hash)."""
    reset_url = f"{settings.SITE_URL}{reverse('reset_password')}?token={token}"
    return send_html_mail(
        to=user.email,
        subject='Reimposta la tua password Athlynk',
        template_base='password_reset',
        context={'user': user, 'reset_url': reset_url, 'ttl_minutes': 30},
    )


def send_password_changed(user):
    """Notify user that their password was just changed."""
    return send_html_mail(
        to=user.email,
        subject='La tua password Athlynk è stata modificata',
        template_base='password_changed',
        context={'user': user},
    )


def _client_display_name(client_profile):
    """Best-effort first name for greeting; falls back to email local-part."""
    if client_profile is None:
        return ''
    fn = (getattr(client_profile, 'first_name', '') or '').strip()
    if fn:
        return fn
    user = getattr(client_profile, 'user', None)
    if user and user.email:
        return user.email.split('@', 1)[0]
    return ''


def _coach_display_name(coach_profile):
    if coach_profile is None:
        return ''
    fn = (getattr(coach_profile, 'first_name', '') or '').strip()
    ln = (getattr(coach_profile, 'last_name', '') or '').strip()
    full = (fn + ' ' + ln).strip()
    return full or '—'


def send_workout_assigned(client_profile, coach_profile, plan, plan_url):
    """Notify a client that a new workout plan has been assigned by their coach.
    Honors User.email_prefs['workout_assigned'] (default True)."""
    user = getattr(client_profile, 'user', None)
    if not user or not user.email:
        return False
    if not user.email_pref('workout_assigned', True):
        return False
    settings_url = f"{settings.SITE_URL}{reverse('settings_notifications')}"
    return send_html_mail(
        to=user.email,
        subject='Nuovo piano di allenamento · Athlynk',
        template_base='workout_assigned',
        context={
            'client_name': _client_display_name(client_profile),
            'coach_name': _coach_display_name(coach_profile),
            'plan_title': getattr(plan, 'title', '') or '',
            'plan_url': plan_url,
            'settings_url': settings_url,
        },
    )


def send_nutrition_assigned(client_profile, coach_profile, plan, plan_url):
    """Notify a client that a new nutrition plan has been assigned."""
    user = getattr(client_profile, 'user', None)
    if not user or not user.email:
        return False
    if not user.email_pref('nutrition_assigned', True):
        return False
    settings_url = f"{settings.SITE_URL}{reverse('settings_notifications')}"
    role_map = {
        'NUTRIZIONISTA': 'nutrizionista',
        'COACH': 'coach',
        'ALLENATORE': 'allenatore',
    }
    coach_role = role_map.get(getattr(coach_profile, 'professional_type', ''), 'coach')
    return send_html_mail(
        to=user.email,
        subject='Nuovo piano nutrizionale · Athlynk',
        template_base='nutrition_assigned',
        context={
            'client_name': _client_display_name(client_profile),
            'coach_name': _coach_display_name(coach_profile),
            'coach_role': coach_role,
            'plan_title': getattr(plan, 'title', '') or '',
            'plan_url': plan_url,
            'settings_url': settings_url,
        },
    )


def send_macro_reminder(client_profile, plan, plan_url):
    """Remind a client to complete their macro log before midnight."""
    user = getattr(client_profile, 'user', None)
    if not user or not user.email:
        return False
    if not user.email_pref('macro_reminder', True):
        return False
    settings_url = f"{settings.SITE_URL}{reverse('settings_notifications')}"
    return send_html_mail(
        to=user.email,
        subject='Ricordati di compilare il diario alimentare oggi · Athlynk',
        template_base='macro_reminder',
        context={
            'client_name': _client_display_name(client_profile),
            'plan_title': getattr(plan, 'title', '') or '',
            'plan_url': plan_url,
            'settings_url': settings_url,
        },
    )


def send_newsletter_confirm(subscriber):
    """Double opt-in confirmation email."""
    confirm_url = f"{settings.SITE_URL}{reverse('newsletter_confirm', args=[subscriber.confirm_token])}"
    unsubscribe_url = f"{settings.SITE_URL}{reverse('newsletter_unsubscribe', args=[subscriber.unsubscribe_token])}"
    return send_html_mail(
        to=subscriber.email,
        subject='Conferma la tua iscrizione alla newsletter Athlynk',
        template_base='newsletter_confirm',
        context={
            'subscriber': subscriber,
            'confirm_url': confirm_url,
            'unsubscribe_url': unsubscribe_url,
        },
    )


def send_platform_purchase_confirmation(purchase):
    """Subscription confirmation for a platform purchase, carrying the access code."""
    amount_display = f"{purchase.amount_total / 100:.2f} {purchase.currency.upper()} / mese"
    return send_html_mail(
        to=purchase.email,
        subject='Abbonamento attivo · il tuo codice di accesso Athlynk',
        template_base='platform_purchase',
        context={
            'code': purchase.code,
            'amount_display': amount_display,
            'plan_name': purchase.get_plan_display(),
            'has_chiron': purchase.has_chiron,
        },
    )
