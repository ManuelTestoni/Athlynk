"""Password-reset flow primitives.

Responsibilities:
- generate a cryptographically-random one-time token,
- persist only its SHA-256 hash + expiry,
- validate / consume it without leaking timing information about user existence,
- rate-limit requests per email and per IP.

Token policy:
    length:      48 url-safe bytes (~64 chars)
    expiry:      30 minutes
    single-use:  enforced by `used_at`
    invalidate:  consuming one token invalidates every other active token for the same user

This module is intentionally email/HTTP-agnostic — callers wire it to views and mailers.
"""
import hashlib
import logging
import secrets
from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from domain.accounts.models import PasswordResetToken, User

logger = logging.getLogger(__name__)

TOKEN_TTL_MINUTES = 30
RATE_LIMIT_WINDOW_MINUTES = 60
RATE_LIMIT_MAX_PER_EMAIL = 5
RATE_LIMIT_MAX_PER_IP = 10


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def is_rate_limited(email: str, ip: str | None) -> bool:
    """True if either the email or the IP has issued too many requests recently.

    Counts tokens created in the last RATE_LIMIT_WINDOW_MINUTES window.
    """
    since = timezone.now() - timedelta(minutes=RATE_LIMIT_WINDOW_MINUTES)
    email_norm = (email or '').strip().lower()

    if email_norm:
        email_count = PasswordResetToken.objects.filter(
            user__email=email_norm,
            created_at__gte=since,
        ).count()
        if email_count >= RATE_LIMIT_MAX_PER_EMAIL:
            return True

    if ip:
        ip_count = PasswordResetToken.objects.filter(
            request_ip=ip,
            created_at__gte=since,
        ).count()
        if ip_count >= RATE_LIMIT_MAX_PER_IP:
            return True

    return False


def issue_token(user: User, ip: str | None = None, user_agent: str = '') -> str:
    """Create a new reset token for `user`. Returns the plaintext token to email.

    Invalidates every previously-active token for the same user before issuing the new one
    so that only the most recent link in the user's mailbox can ever be used.
    """
    plaintext = secrets.token_urlsafe(48)
    token_hash = _hash_token(plaintext)
    now = timezone.now()

    with transaction.atomic():
        PasswordResetToken.objects.filter(
            user=user,
            used_at__isnull=True,
        ).update(used_at=now)

        PasswordResetToken.objects.create(
            user=user,
            token_hash=token_hash,
            expires_at=now + timedelta(minutes=TOKEN_TTL_MINUTES),
            request_ip=ip,
            request_user_agent=(user_agent or '')[:512],
        )

    logger.info('password_reset.token_issued user_id=%s ip=%s', user.id, ip)
    return plaintext


def validate_token(plaintext: str) -> PasswordResetToken | None:
    """Return the token row if `plaintext` matches a non-used, non-expired token."""
    if not plaintext:
        return None
    try:
        token = PasswordResetToken.objects.select_related('user').get(
            token_hash=_hash_token(plaintext),
        )
    except PasswordResetToken.DoesNotExist:
        return None

    if token.used_at is not None:
        return None
    if token.expires_at <= timezone.now():
        return None
    return token


def consume_token(plaintext: str) -> PasswordResetToken | None:
    """Validate + mark token used atomically. Also invalidates any other live token
    of the same user so a leaked second link cannot be replayed.
    """
    token = validate_token(plaintext)
    if not token:
        return None

    now = timezone.now()
    with transaction.atomic():
        updated = PasswordResetToken.objects.filter(
            pk=token.pk,
            used_at__isnull=True,
        ).update(used_at=now)

        if updated == 0:
            return None

        PasswordResetToken.objects.filter(
            user_id=token.user_id,
            used_at__isnull=True,
        ).update(used_at=now)

        token.used_at = now

    logger.info('password_reset.token_consumed user_id=%s', token.user_id)
    return token
