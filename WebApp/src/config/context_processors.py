import json
from django.conf import settings
from .session_utils import build_identity_context, get_session_user

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
    if path.startswith('/il-mio-coach') or path.startswith('/il-mio-specialista'):
        return 'specialista'
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
    return ctx


_asset_version_cache = None
def _asset_version():
    """Returns mtime of athlynk.css as cache-buster.

    Cached for the process lifetime in DEBUG=False; re-read every call in DEBUG.
    """
    global _asset_version_cache
    if settings.DEBUG or _asset_version_cache is None:
        import os
        try:
            p = os.path.join(settings.BASE_DIR.parent, 'static', 'css', 'athlynk.css')
            mtime = int(os.path.getmtime(p))
        except OSError:
            mtime = 0
        if not settings.DEBUG:
            _asset_version_cache = mtime
        return mtime
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
            pass

    return False
