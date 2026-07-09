import json
import logging

from django.conf import settings
from .session_utils import build_identity_context, get_session_user

logger = logging.getLogger(__name__)

_NOTIF_SECTION = {
    'CHECK_SUBMITTED': 'check',
    'CHECK_REVIEWED': 'check',
    'WORKOUT_ASSIGNED': 'allenamenti',
    'NUTRITION_ASSIGNED': 'nutrizione',
    'SUPPLEMENT_ASSIGNED': 'nutrizione',
    'MESSAGE': 'chat',
    'APPOINTMENT_REQUEST': 'chat',
    'APPOINTMENT_ACCEPTED': 'chat',
    'APPOINTMENT_REJECTED': 'chat',
}


def _get_current_section(path):
    if path == '/':
        return 'dashboard'
    if path.startswith('/clienti'):
        return 'clienti'
    if path.startswith('/allenamenti'):
        return 'allenamenti'
    if path.startswith('/nutrizione'):
        return 'nutrizione'
    if path.startswith('/agenda'):
        return 'agenda'
    if path.startswith('/chat'):
        return 'chat'
    if path.startswith('/check'):
        return 'check'
    if path.startswith('/abbonamenti'):
        return 'abbonamenti'
    if path.startswith('/analisi'):
        return 'analisi'
    if path.startswith('/il-mio-percorso'):
        return 'percorso'
    if path.startswith('/impostazioni'):
        return 'impostazioni'
    return ''


def identity_context(request):
    ctx = build_identity_context(request)
    ctx['current_section'] = _get_current_section(request.path)

    from domain.chat.models import Notification
    user = get_session_user(request)
    sidebar_notifications = {}
    if user:
        for ntype in Notification.objects.filter(target_user=user, is_read=False).values_list('notification_type', flat=True):
            sec = _NOTIF_SECTION.get(ntype)
            if sec:
                sidebar_notifications[sec] = sidebar_notifications.get(sec, 0) + 1
    ctx['sidebar_notifications'] = sidebar_notifications
    ctx['CONSENT_VERSION'] = getattr(settings, 'CONSENT_VERSION', '')
    ctx['cookie_consent_needed'] = _cookie_consent_needed(request, user)
    ctx['ASSET_VERSION'] = _asset_version()
    ctx['SITE_URL'] = getattr(settings, 'SITE_URL', '').rstrip('/')
    return ctx


def posthog(request):
    """Expose PostHog config + the identify payload to templates.

    The snippet (templates/partials/posthog.html) only initialises when
    ``posthog_enabled`` is true (a key is set) AND the user granted analytics
    consent. Internal/test users are tagged via super-properties so they can be
    filtered/excluded downstream. Everything is empty/false when unconfigured,
    so the app ships dark until keys are added.
    """
    key = getattr(settings, 'POSTHOG_KEY', '')
    ctx = {
        'posthog_enabled': bool(key),
        'posthog_key': key,
        'posthog_host': getattr(settings, 'POSTHOG_HOST', 'https://eu.i.posthog.com'),
        'posthog_identify': None,
    }
    if not key:
        return ctx

    user = get_session_user(request)
    if user is None:
        return ctx

    from domain.analytics.events import EVENT_VERSION
    from domain.analytics.services.identity import current_environment, resolve_flags
    flags = resolve_flags(user)
    coach = getattr(user, 'coach_profile', None)
    ctx['posthog_identify'] = {
        'distinct_id': f'user:{user.id}',
        'props': {
            'event_version': EVENT_VERSION,
            'environment': current_environment(),
            'platform': 'web',
            'app_version': getattr(settings, 'ANALYTICS_APP_VERSION', 'web'),
            'role': user.role,
            'coach_id': coach.id if coach else None,
            'is_internal_user': flags['is_internal_user'],
            'is_test_account': flags['is_test_account'],
        },
    }
    return ctx


_asset_version_cache = None
def _asset_version():
    """Returns max mtime across all bundled CSS+JS as cache-buster.

    Watching every asset (not just athlynk.css) ensures that editing a
    JS file forces every browser — Safari included — to refetch. Cached
    for the process lifetime in DEBUG=False; re-read every call in DEBUG.
    """
    global _asset_version_cache
    if settings.DEBUG or _asset_version_cache is None:
        import os
        latest = 0
        static_root = os.path.join(settings.BASE_DIR.parent, 'static')
        for sub in ('css', 'js'):
            d = os.path.join(static_root, sub)
            try:
                for name in os.listdir(d):
                    if not (name.endswith('.css') or name.endswith('.js')):
                        continue
                    try:
                        m = int(os.path.getmtime(os.path.join(d, name)))
                        if m > latest:
                            latest = m
                    except OSError:
                        pass
            except OSError:
                pass
        if not settings.DEBUG:
            _asset_version_cache = latest
        return latest
    return _asset_version_cache


def _cookie_consent_needed(request, user):
    """Return True if the banner must be shown.

    Rules:
      - If browser cookie 'cookie_consent' missing or its version differs from
        settings.CONSENT_VERSION → needed.
      - If user is logged in and has no CookieConsentRecord for the current
        version → needed (even if a stale cookie exists from another browser).
    """
    target_version = getattr(settings, 'CONSENT_VERSION', '')
    raw = request.COOKIES.get('cookie_consent')
    cookie_ok = False
    if raw:
        try:
            data = json.loads(raw)
            if data.get('version') == target_version:
                cookie_ok = True
        except (ValueError, TypeError):
            cookie_ok = False

    if not cookie_ok:
        return True

    if user is not None:
        try:
            from domain.consent.models import CookieConsentRecord
            exists = CookieConsentRecord.objects.filter(
                user=user, consent_version=target_version,
            ).exists()
            if not exists:
                return True
        except Exception:
            logger.exception('cookie_consent_check.failed user_id=%s', user.id)

    return False
