"""Thin server-side PostHog capture wrapper.

Hard rule: **no-op when ``POSTHOG_KEY`` is empty** (the app must run untouched
before keys exist) and when the ``posthog`` package isn't installed. Used only
for server-originated events (renewals, payment failures, automations); product
behaviour is captured client-side by the iOS/web SDKs.

Every event is stamped with the global properties from ``events.py`` and the
governance flags, so server and client streams share one schema.
"""

import logging

from django.conf import settings

from ..events import EVENT_VERSION
from .identity import current_environment, resolve_flags

logger = logging.getLogger(__name__)

_client = None
_initialised = False


def _get_client():
    """Lazily build a PostHog client, or None if disabled/unavailable."""
    global _client, _initialised
    if _initialised:
        return _client
    _initialised = True

    key = getattr(settings, 'POSTHOG_KEY', '')
    if not key:
        _client = None
        return None
    try:
        from posthog import Posthog
        _client = Posthog(
            project_api_key=key,
            host=getattr(settings, 'POSTHOG_HOST', 'https://eu.i.posthog.com'),
        )
    except Exception as exc:  # package missing or bad config → stay dark
        logger.info('PostHog server capture disabled: %s', exc)
        _client = None
    return _client


def _global_props(user=None, coach=None, client=None, extra=None):
    props = {
        'event_version': EVENT_VERSION,
        'environment': current_environment(),
        'platform': 'server',
        'app_version': getattr(settings, 'ANALYTICS_APP_VERSION', 'web'),
        'role': getattr(user, 'role', None) if user else None,
        'coach_id': getattr(coach, 'id', None),
        'client_id': getattr(client, 'id', None),
    }
    flags = resolve_flags(user)
    props.update(flags)
    if extra:
        props.update(extra)
    return {k: v for k, v in props.items() if v is not None}


def capture(distinct_id, event, *, user=None, coach=None, client=None, properties=None):
    """Send one server-side event. Silently does nothing when disabled."""
    ph = _get_client()
    if ph is None or not distinct_id:
        return
    try:
        ph.capture(
            distinct_id=str(distinct_id),
            event=event,
            properties=_global_props(user=user, coach=coach, client=client, extra=properties),
        )
    except Exception as exc:
        logger.warning('PostHog capture failed for %s: %s', event, exc)
