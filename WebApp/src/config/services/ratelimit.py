"""Lightweight cache-backed rate limiter.

Used by auth views to throttle abusive request bursts (login brute-force,
password-reset enumeration). Storage backend is the configured Django cache;
DatabaseCache is recommended in settings.py so counters survive worker restarts
and stay consistent across multiple gunicorn workers.

Each (prefix, identifier) pair gets one fixed-size time bucket. When a bucket
fills past `limit`, subsequent calls return `allowed=False` until the bucket
expires. Counters are not refunded on success — call `reset` explicitly when a
positive event (e.g. correct login) should clear the throttle.
"""

import hashlib
import logging
import time

from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger(__name__)


def _bucket_key(prefix: str, ident: str, window_seconds: int) -> str:
    h = hashlib.sha256(ident.encode('utf-8', errors='ignore')).hexdigest()[:16]
    window = int(time.time() // window_seconds)
    return f"rl:{prefix}:{h}:{window}"


def hit(prefix: str, ident: str, limit: int, window_seconds: int) -> tuple[bool, int]:
    """Register an attempt. Returns (allowed, remaining_attempts_after_this_call).

    `allowed` is False once the counter passes `limit`.
    """
    if not ident:
        return True, limit
    key = _bucket_key(prefix, ident, window_seconds)
    # cache.add returns False if key exists; cache.incr raises if missing on some backends.
    cache.add(key, 0, timeout=window_seconds)
    try:
        count = cache.incr(key)
    except ValueError:
        cache.set(key, 1, timeout=window_seconds)
        count = 1
    if count is None:
        # django-redis + IGNORE_EXCEPTIONS returns None (not a raised error) when
        # Redis is unreachable — fail open like the rest of the cache, don't crash.
        return True, limit
    remaining = max(0, limit - count)
    allowed = count <= limit
    if not allowed:
        logger.warning('ratelimit.blocked prefix=%s count=%s limit=%s', prefix, count, limit)
    return allowed, remaining


def reset(prefix: str, ident: str, window_seconds: int) -> None:
    if not ident:
        return
    cache.delete(_bucket_key(prefix, ident, window_seconds))


def refund(prefix: str, ident: str, window_seconds: int) -> None:
    """Give back a single attempt in the current bucket (floor 0).

    Use when a consumed attempt turned out not to count — e.g. an AI import that
    was charged up-front but then failed. Unlike `reset`, this only returns the
    one attempt, preserving the rest of the window's counter."""
    if not ident:
        return
    key = _bucket_key(prefix, ident, window_seconds)
    try:
        val = cache.decr(key)
    except ValueError:
        # Key missing/expired (or fail-open miss): nothing to refund.
        return
    if val is not None and val < 0:
        cache.set(key, 0, timeout=window_seconds)


def client_ip(request) -> str:
    """Resolve the true client IP.

    `X-Forwarded-For` is client-controlled and trivially spoofed, so we honor it
    only when `settings.TRUSTED_PROXY_COUNT` is greater than zero. In that case
    we pick the entry that many hops from the right (the leftmost hops are
    user-supplied and can lie). Otherwise we always return `REMOTE_ADDR`.
    """
    remote_addr = request.META.get('REMOTE_ADDR', '') or ''
    trusted = getattr(settings, 'TRUSTED_PROXY_COUNT', 0)
    if trusted <= 0:
        return remote_addr

    xff = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if not xff:
        return remote_addr
    parts = [p.strip() for p in xff.split(',') if p.strip()]
    if not parts:
        return remote_addr
    # Pick the hop just before the trusted proxies. If the header is too short
    # (header forged or fewer hops than configured), fall back to REMOTE_ADDR.
    if len(parts) < trusted:
        return remote_addr
    return parts[-trusted]
