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
    """Best-effort client IP. Delegates to ratelimit.client_ip, which only
    honors X-Forwarded-For when settings.TRUSTED_PROXY_COUNT > 0 — otherwise
    the header is attacker-controlled and trivially spoofed."""
    from config.services.ratelimit import client_ip
    return client_ip(request)
