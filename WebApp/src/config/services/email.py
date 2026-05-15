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
