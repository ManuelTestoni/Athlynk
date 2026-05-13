from django.shortcuts import render, redirect
from django.contrib.auth.hashers import make_password, check_password
from django.utils import timezone
import logging

from domain.accounts.models import User, CoachProfile, ClientProfile
from .services.tokens import generate_token, is_expired, get_client_ip
from .services.email import send_welcome_verify

logger = logging.getLogger(__name__)


def login_view(request):
    if request.method == 'POST':
        email = request.POST.get('email')
        password = request.POST.get('password')

        try:
            user = User.objects.get(email=email)
            if not check_password(password, user.password_hash):
                return render(request, 'pages/auth/login.html', {'error': 'Password non corretta'})
            if not user.is_verified:
                return render(request, 'pages/auth/email_not_verified.html', {'email': user.email})
            request.session['user_id'] = user.id
            request.session['user_role'] = user.role
            user.last_login_at = timezone.now()
            user.save(update_fields=['last_login_at'])
            return redirect('dashboard')
        except User.DoesNotExist:
            return render(request, 'pages/auth/login.html', {'error': 'Email non trovata. Registrati!'})

    return render(request, 'pages/auth/login.html')


def signup_view(request):
    if request.method == 'POST':
        email = request.POST.get('email', '').strip().lower()
        first_name = request.POST.get('first_name', '').strip()
        last_name = request.POST.get('last_name', '').strip()
        password = request.POST.get('password', '')
        confirm_password = request.POST.get('confirm_password', '')
        role = request.POST.get('role')
        professional_type = request.POST.get('professional_type', 'COACH')
        newsletter_optin = request.POST.get('newsletter_optin') == 'on'

        if password != confirm_password:
            return render(request, 'pages/auth/signup.html', {'error': 'Le password non coincidono.'})
        if len(password) < 8:
            return render(request, 'pages/auth/signup.html', {'error': 'La password deve essere di almeno 8 caratteri.'})
        if User.objects.filter(email=email).exists():
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

        if role == 'COACH':
            CoachProfile.objects.create(
                user=user,
                first_name=first_name,
                last_name=last_name,
                professional_type=professional_type,
                platform_subscription_status='ACTIVE',
            )
        elif role == 'CLIENT':
            ClientProfile.objects.create(
                user=user,
                first_name=first_name,
                last_name=last_name,
            )

        send_welcome_verify(user, token)

        if newsletter_optin:
            _subscribe_newsletter(request, email)

        return render(request, 'pages/auth/check_email.html', {'email': user.email})

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
    email = (request.POST.get('email') or '').strip().lower()
    try:
        user = User.objects.get(email=email)
    except User.DoesNotExist:
        return render(request, 'pages/auth/check_email.html', {'email': email})

    if user.is_verified:
        return redirect('login')

    user.email_verification_token = generate_token()
    user.email_verification_sent_at = timezone.now()
    user.save(update_fields=['email_verification_token', 'email_verification_sent_at'])
    send_welcome_verify(user, user.email_verification_token)
    return render(request, 'pages/auth/check_email.html', {'email': email, 'resent': True})


def logout_view(request):
    request.session.flush()
    return redirect('login')
