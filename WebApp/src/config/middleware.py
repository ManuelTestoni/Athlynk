"""Project middleware.

`SanitizationMiddleware` runs before view code and applies cheap, blanket
defenses that we don't want to repeat in every view:

  * Strip null bytes (0x00) from POST and GET values. Null bytes are a classic
    truncation / path-traversal trick that some C-extension code paths still
    mishandle; there is no legitimate reason for them in form input.

  * On JSON API endpoints we enforce a `Content-Type: application/json` header
    and a body size cap. Browsers that POST forms to `/api/*` are almost
    certainly bugs or attacks.

Views remain responsible for per-field length caps and domain validation —
this middleware only catches the universally-hostile cases.
"""

import logging
import time

from django.conf import settings
from django.http import JsonResponse


logger = logging.getLogger(__name__)


class SessionSecurityMiddleware:
    """Enforce an *absolute* lifetime on authenticated browser sessions.

    Django's SESSION_COOKIE_AGE only gives an idle (sliding) timeout: an active
    user could in principle stay logged in forever. This caps total session age
    at SESSION_ABSOLUTE_TIMEOUT seconds from the recorded login time, flushing
    the session once exceeded. Only sessions that carry our custom `user_id`
    are touched, so the iOS Bearer-token API (which never sets it) is unaffected.
    """

    def __init__(self, get_response):
        self.get_response = get_response
        self.max_age = int(getattr(settings, 'SESSION_ABSOLUTE_TIMEOUT', 0) or 0)

    def __call__(self, request):
        if self.max_age and request.session.get('user_id'):
            auth_at = request.session.get('auth_at')
            if auth_at and (time.time() - float(auth_at)) > self.max_age:
                logger.info('session.absolute_timeout user_id=%s', request.session.get('user_id'))
                request.session.flush()
        return self.get_response(request)


# Endpoints that send `application/x-www-form-urlencoded` or multipart even
# though they live under /api/. Listed here to keep the JSON gate strict for
# everything else. Extend deliberately, not by accident.
_API_FORM_EXEMPT_PREFIXES = (
    '/api/nutrizione/import/excel/',
    '/api/nutrizione/import/pdf/',
)


def _is_form_exempt(path):
    """True for /api/ endpoints that legitimately accept form/multipart bodies."""
    if any(path.startswith(p) for p in _API_FORM_EXEMPT_PREFIXES):
        return True
    # Chat message send is multipart: text body + optional image/video attachment.
    if path.startswith('/api/chat/') and path.endswith('/send/'):
        return True
    return False


def _scrub_querydict(qd):
    """Remove ASCII NUL bytes from all values in a Django QueryDict.

    Operates in place by toggling `_mutable`. Returns the dict for chaining.
    """
    if not qd:
        return qd
    was_mutable = getattr(qd, '_mutable', True)
    qd._mutable = True
    try:
        for key in list(qd.keys()):
            cleaned = [v.replace('\x00', '') for v in qd.getlist(key) if isinstance(v, str)]
            non_str = [v for v in qd.getlist(key) if not isinstance(v, str)]
            qd.setlist(key, cleaned + non_str)
    finally:
        qd._mutable = was_mutable
    return qd


class SanitizationMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        limits = getattr(settings, 'SANITIZE_LIMITS', {}) or {}
        self._json_body_cap = int(limits.get('json_body_mb', 1)) * 1024 * 1024

    def __call__(self, request):
        # Null-byte scrub on every request. QueryDicts are normally immutable
        # after parsing; we flip the flag for the rewrite and flip it back.
        _scrub_querydict(request.GET)
        _scrub_querydict(request.POST)

        path = request.path or ''
        method = request.method or ''

        if path.startswith('/api/') and method in ('POST', 'PUT', 'PATCH'):
            if not _is_form_exempt(path):
                ctype = (request.META.get('CONTENT_TYPE') or '').lower().split(';')[0].strip()
                if ctype and ctype != 'application/json':
                    logger.warning('sanitize.bad_content_type path=%s ctype=%s', path, ctype)
                    return JsonResponse(
                        {'error': 'Content-Type deve essere application/json'},
                        status=415,
                    )

            # CONTENT_LENGTH is set by gunicorn/Django for buffered bodies. If
            # missing we let Django's own DATA_UPLOAD_MAX_MEMORY_SIZE catch
            # oversized streamed bodies later.
            try:
                length = int(request.META.get('CONTENT_LENGTH') or 0)
            except (TypeError, ValueError):
                length = 0
            if length and length > self._json_body_cap:
                logger.warning('sanitize.body_too_large path=%s length=%s', path, length)
                return JsonResponse(
                    {'error': f'Body troppo grande (max {self._json_body_cap // 1024}KB)'},
                    status=413,
                )

        return self.get_response(request)
