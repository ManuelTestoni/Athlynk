"""Token helpers for email verification / newsletter confirm / unsubscribe."""
import secrets
from datetime import timedelta
from django.utils import timezone


def generate_token() -> str:
    """URL-safe random token (~64 chars)."""
    return secrets.token_urlsafe(48)


def is_expired(created_at, days: int) -> bool:
    """True if `created_at` is older than `days` from now (or missing)."""
    if not created_at:
        return True
    return timezone.now() > created_at + timedelta(days=days)


def get_client_ip(request):
    """Best-effort client IP (respects X-Forwarded-For)."""
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    if xff:
        return xff.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')
