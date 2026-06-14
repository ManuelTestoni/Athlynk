from django.shortcuts import render, redirect
from django.contrib.auth.hashers import make_password, check_password
from django.utils import timezone
import logging

from domain.accounts.models import User, CoachProfile
from .services.tokens import generate_token, is_expired, get_client_ip
from .services.email import send_welcome_verify, send_password_reset, send_password_changed
from .services import password_reset as pwd_reset
from .services import ratelimit
from .session_utils import enforce_client_access
from .services.sanitize import (
    InvalidInput, clean_email, clean_password, clean_short_text,
)

logger = logging.getLogger(__name__)


# "Ricordami": persist the session for 30 days (and skip the absolute-timeout
# flush in SessionSecurityMiddleware). Unchecked → cookie expires at browser close.
REMEMBER_ME_AGE = 30 * 24 * 60 * 60

# Minimum gap between two verification-email sends to the same account.
RESEND_COOLDOWN_SECONDS = 120

LOGIN_RATE_LIMIT = 5
LOGIN_RATE_WINDOW_SECONDS = 15 * 60
# Per-account ceiling: protects a single account from credential-stuffing
# attacks even when the attacker rotates source IPs.
LOGIN_EMAIL_RATE_LIMIT = 10
LOGIN_EMAIL_RATE_WINDOW_SECONDS = 15 * 60
LOGIN_BLOCKED_MESSAGE = (
    'Troppi tentativi di accesso. Riprova tra qualche minuto.'
)


def login_view(request):
    if request.method == 'POST':
        try:
            email = clean_email(request.POST.get('email'))
            password = clean_password(request.POST.get('password'), min_chars=1)
        except InvalidInput as exc:
            return render(request, 'pages/auth/login.html', {'error': str(exc)}, status=400)

        remember = request.POST.get('remember') == 'on'

        ip = ratelimit.client_ip(request)
        ip_allowed, _ = ratelimit.hit(
            'login_ip', ip, LOGIN_RATE_LIMIT, LOGIN_RATE_WINDOW_SECONDS,
        )
        email_allowed, _ = ratelimit.hit(
            'login_email', email, LOGIN_EMAIL_RATE_LIMIT, LOGIN_EMAIL_RATE_WINDOW_SECONDS,
        ) if email else (True, LOGIN_EMAIL_RATE_LIMIT)
        if not ip_allowed or not email_allowed:
            logger.warning('login.rate_limited ip=%s email=%s ip_ok=%s email_ok=%s',
                           ip, email, ip_allowed, email_allowed)
            return render(request, 'pages/auth/login.html', {
                'error': LOGIN_BLOCKED_MESSAGE,
            }, status=429)

        try:
            user = User.objects.get(email=email)
            if not check_password(password, user.password_hash):
                return render(request, 'pages/auth/login.html', {'error': 'Password non corretta'})
            if not user.is_verified:
                return render(request, 'pages/auth/email_not_verified.html', {'email': user.email})
            # Rotate the session id on privilege change to defeat fixation, then
            # stamp the login time for the absolute-timeout enforced in middleware.
            request.session.cycle_key()
            request.session['user_id'] = user.id
            request.session['user_role'] = user.role
            request.session['auth_at'] = timezone.now().timestamp()
            # "Ricordami": keep the session for 30 days across browser restarts;
            # otherwise expire it when the browser closes.
            if remember:
                request.session.set_expiry(REMEMBER_ME_AGE)
                request.session['remember'] = True
            else:
                request.session.set_expiry(0)
            # Suspend athletes whose subscription lapsed before they even reach a page.
            if user.role == 'CLIENT':
                enforce_client_access(getattr(user, 'client_profile', None))
            user.last_login_at = timezone.now()
            user.save(update_fields=['last_login_at'])
            ratelimit.reset('login_ip', ip, LOGIN_RATE_WINDOW_SECONDS)
            ratelimit.reset('login_email', email, LOGIN_EMAIL_RATE_WINDOW_SECONDS)
            return redirect('dashboard')
        except User.DoesNotExist:
            return render(request, 'pages/auth/login.html', {'error': 'Email non trovata. Registrati!'})

    return render(request, 'pages/auth/login.html')


def signup_view(request):
    if request.method == 'POST':
        try:
            email = clean_email(request.POST.get('email'))
            first_name = clean_short_text(request.POST.get('first_name'), field='nome')
            last_name = clean_short_text(request.POST.get('last_name'), field='cognome')
            password = clean_password(request.POST.get('password'))
            confirm_password = clean_password(request.POST.get('confirm_password'))
        except InvalidInput as exc:
            return render(request, 'pages/auth/signup.html', {'error': str(exc)}, status=400)

        # Registration is for professionals only. Athletes never self-register —
        # they are created/added by a Coach, Allenatore or Nutrizionista.
        role = (request.POST.get('role') or 'COACH').strip().upper()
        if role == 'CLIENT':
            return render(request, 'pages/auth/signup.html', {
                'error': 'La registrazione è riservata ai professionisti. '
                         'Gli atleti vengono aggiunti dal proprio coach.',
            }, status=400)
        role = 'COACH'
        professional_type = (request.POST.get('professional_type') or 'COACH').strip().upper()
        if professional_type not in ('COACH', 'ALLENATORE', 'NUTRIZIONISTA'):
            professional_type = 'COACH'
        newsletter_optin = request.POST.get('newsletter_optin') == 'on'

        if password != confirm_password:
            return render(request, 'pages/auth/signup.html', {'error': 'Le password non coincidono.'})
        if User.objects.filter(email__iexact=email).exists():
            return render(request, 'pages/auth/signup.html', {'error': 'Email già in uso. Accedi.'})

        token = generate_token()
        user = User.objects.create(
            email=email,
            password_hash=make_password(password),
            role=role,
            is_active=True,
            is_verified=False,
            email_verification_token=token,
            email_verification_sent_at=timezone.now(),
        )

        CoachProfile.objects.create(
            user=user,
            first_name=first_name,
            last_name=last_name,
            professional_type=professional_type,
            platform_subscription_status='ACTIVE',
        )

        send_welcome_verify(user, token)

        if newsletter_optin:
            _subscribe_newsletter(request, email)

        return render(request, 'pages/auth/check_email.html', {'email': user.email, 'just_sent': True})

    return render(request, 'pages/auth/signup.html')


def _subscribe_newsletter(request, email):
    """Create a PENDING subscriber and send confirm email. Imported lazily to avoid
    coupling auth to newsletter app initialization order."""
    try:
        from domain.newsletter.models import Subscriber, SubscriptionEvent
        from .services.email import send_newsletter_confirm
        from django.conf import settings

        sub, created = Subscriber.objects.get_or_create(
            email=email,
            defaults={
                'status': 'PENDING',
                'confirm_token': generate_token(),
                'unsubscribe_token': generate_token(),
                'consent_version': settings.CONSENT_VERSION,
                'consent_text_snapshot': 'Iscrizione newsletter Athlynk: tips di allenamento e nutrizione.',
                'subscribed_ip': get_client_ip(request),
                'subscribed_user_agent': (request.META.get('HTTP_USER_AGENT') or '')[:512],
            },
        )
        if not created and sub.status == 'UNSUBSCRIBED':
            sub.status = 'PENDING'
            sub.confirm_token = generate_token()
            sub.save(update_fields=['status', 'confirm_token'])
        SubscriptionEvent.objects.create(
            subscriber=sub,
            event_type='SIGNUP',
            ip=get_client_ip(request),
            user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        )
        if sub.status == 'PENDING':
            send_newsletter_confirm(sub)
    except Exception:
        logger.exception('Newsletter signup failed for %s', email)


def verify_email_view(request, token):
    """Confirm email via token link."""
    try:
        user = User.objects.get(email_verification_token=token)
    except User.DoesNotExist:
        return render(request, 'pages/auth/verify_invalid.html', status=400)

    if user.is_verified:
        return render(request, 'pages/auth/verified_success.html', {'already': True, 'email': user.email})

    if is_expired(user.email_verification_sent_at, days=7):
        return render(request, 'pages/auth/verify_invalid.html', {'expired': True, 'email': user.email}, status=400)

    user.is_verified = True
    user.email_verification_token = ''
    user.save(update_fields=['is_verified', 'email_verification_token'])
    return render(request, 'pages/auth/verified_success.html', {'email': user.email})


def resend_verification_view(request):
    """Generate a new token and email it."""
    if request.method != 'POST':
        return redirect('login')
    try:
        email = clean_email(request.POST.get('email'))
    except InvalidInput:
        return redirect('login')
    try:
        user = User.objects.get(email=email)
    except User.DoesNotExist:
        return render(request, 'pages/auth/check_email.html', {'email': email})

    if user.is_verified:
        return redirect('login')

    # Anti-spam: at most one verification email every RESEND_COOLDOWN_SECONDS.
    sent_at = user.email_verification_sent_at
    if sent_at:
        elapsed = (timezone.now() - sent_at).total_seconds()
        if elapsed < RESEND_COOLDOWN_SECONDS:
            return render(request, 'pages/auth/check_email.html', {
                'email': email,
                'too_soon': True,
                'wait_seconds': int(RESEND_COOLDOWN_SECONDS - elapsed) + 1,
            })

    user.email_verification_token = generate_token()
    user.email_verification_sent_at = timezone.now()
    user.save(update_fields=['email_verification_token', 'email_verification_sent_at'])
    send_welcome_verify(user, user.email_verification_token)
    return render(request, 'pages/auth/check_email.html', {'email': email, 'resent': True})


def logout_view(request):
    request.session.flush()
    return redirect('login')


# ---------------------------------------------------------------------------
# Password reset flow
# ---------------------------------------------------------------------------

GENERIC_RESET_NOTICE = (
    "Se l'indirizzo è registrato riceverai a breve un'email con le istruzioni "
    "per reimpostare la password."
)


def forgot_password_view(request):
    """Public 'I forgot my password' form. Anonymous endpoint.

    Never reveals whether an email is registered.
    """
    if request.method == 'POST':
        try:
            email = clean_email(request.POST.get('email'))
        except InvalidInput:
            # Stay generic: never reveal whether the email was missing/malformed.
            return render(request, 'pages/auth/forgot_password.html', {
                'notice': GENERIC_RESET_NOTICE,
                'submitted': True,
            })
        ip = get_client_ip(request)
        ua = (request.META.get('HTTP_USER_AGENT') or '')[:512]

        _maybe_issue_reset(email, ip, ua)

        return render(request, 'pages/auth/forgot_password.html', {
            'notice': GENERIC_RESET_NOTICE,
            'submitted': True,
        })

    return render(request, 'pages/auth/forgot_password.html')


def request_password_reset_view(request):
    """Logged-in user requests a reset link to their own email (from settings)."""
    if request.method != 'POST':
        return redirect('impostazioni_dashboard')

    from .session_utils import get_session_user
    user = get_session_user(request)
    if not user:
        return redirect('login')

    ip = get_client_ip(request)
    ua = (request.META.get('HTTP_USER_AGENT') or '')[:512]
    _maybe_issue_reset(user.email, ip, ua)

    request.session['reset_request_sent'] = True
    return redirect('impostazioni_dashboard')


def _maybe_issue_reset(email: str, ip: str | None, user_agent: str):
    """Issue + email a reset token if user exists and rate limits allow.
    Silent on failure: never leaks user existence.
    """
    if not email:
        return
    if pwd_reset.is_rate_limited(email, ip):
        logger.warning('password_reset.rate_limited email=%s ip=%s', email, ip)
        return
    try:
        user = User.objects.get(email=email)
    except User.DoesNotExist:
        logger.info('password_reset.unknown_email email=%s ip=%s', email, ip)
        return

    token = pwd_reset.issue_token(user, ip=ip, user_agent=user_agent)
    send_password_reset(user, token)


def reset_password_view(request):
    """Validate reset token (GET) and apply new password (POST).

    GET  /reset-password/?token=<plaintext>     -> show form OR error page
    POST /reset-password/  (token + new_password + confirm_password)
    """
    if request.method == 'POST':
        token_plain = (request.POST.get('token') or '').strip()
        # Token is opaque hex/base64 — cap it to a sane length to block oversized
        # garbage and skip Unicode normalization (would corrupt the hash lookup).
        if len(token_plain) > 256 or '\x00' in token_plain:
            return render(request, 'pages/auth/reset_password.html', {'token_invalid': True}, status=400)
        try:
            new_pw = clean_password(request.POST.get('new_password'))
            confirm_pw = clean_password(request.POST.get('confirm_password'))
        except InvalidInput as exc:
            return render(request, 'pages/auth/reset_password.html', {
                'token': token_plain,
                'error': str(exc),
            }, status=400)

        token = pwd_reset.validate_token(token_plain)
        if not token:
            return render(request, 'pages/auth/reset_password.html', {
                'token_invalid': True,
            }, status=400)

        if new_pw != confirm_pw:
            return render(request, 'pages/auth/reset_password.html', {
                'token': token_plain,
                'error': 'Le due password non coincidono.',
            }, status=400)

        consumed = pwd_reset.consume_token(token_plain)
        if not consumed:
            return render(request, 'pages/auth/reset_password.html', {
                'token_invalid': True,
            }, status=400)

        user = consumed.user
        user.password_hash = make_password(new_pw)
        user.save(update_fields=['password_hash'])

        # Best-effort confirmation; failure should not block the success page.
        try:
            send_password_changed(user)
        except Exception:
            logger.exception('password_reset.confirm_mail_failed user_id=%s', user.id)

        # Hard-invalidate any active session belonging to the user we know about
        # (current visitor is anonymous here, but we still flush to be safe).
        request.session.flush()

        return render(request, 'pages/auth/reset_password.html', {'success': True})

    # GET
    token_plain = (request.GET.get('token') or '').strip()
    token = pwd_reset.validate_token(token_plain)
    if not token:
        return render(request, 'pages/auth/reset_password.html', {
            'token_invalid': True,
        }, status=400)

    return render(request, 'pages/auth/reset_password.html', {
        'token': token_plain,
    })
