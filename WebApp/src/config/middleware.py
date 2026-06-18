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
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect

from .services.sanitize import _CONTROL_RE, _SKIP_CLEAN_KEYS


logger = logging.getLogger(__name__)

# Form keys whose values pass through with only a null-byte scrub: secrets where
# trimming/normalizing would corrupt the value (passwords, tokens) plus Django's
# CSRF field. Mirrors the JSON API's sanitize._SKIP_CLEAN_KEYS.
_FORM_SKIP_KEYS = _SKIP_CLEAN_KEYS | {'csrfmiddlewaretoken'}


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
        # "Ricordami" sessions opt out of the absolute ceiling: the 30-day sliding
        # cookie (renewed via SESSION_SAVE_EVERY_REQUEST) is the only bound.
        if (self.max_age and request.session.get('user_id')
                and not request.session.get('remember')):
            auth_at = request.session.get('auth_at')
            if auth_at and (time.time() - float(auth_at)) > self.max_age:
                logger.info('session.absolute_timeout user_id=%s', request.session.get('user_id'))
                request.session.flush()
        return self.get_response(request)


class ClientAccessMiddleware:
    """Gate athlete (CLIENT) browser sessions.

    An athlete may use the app only while they have at least one active
    professional collaboration (see config.session_utils.client_has_active_access).
    With none — never added, collaboration ended, or subscription lapsed — every
    page redirects to the 'accesso sospeso' landing. Coaches, anonymous visitors
    and the mobile Bearer API (which has its own gate in config.api.api_view) are
    untouched: this only fires for sessions carrying our custom CLIENT identity.
    """

    # Paths an athlete may always reach, even while blocked: the landing page
    # itself, logout, account/settings, password flows and AJAX endpoints (the
    # pages that call them are themselves gated, so the data stays unreachable).
    ALLOW_PREFIXES = (
        '/accesso-sospeso/',
        '/logout/',
        '/impostazioni/',
        '/profilo/',
        '/reset-password/',
        '/password-dimenticata/',
        '/api/',
        '/privacy/', '/cookie/', '/ai-trasparenza/',
    )

    def __init__(self, get_response):
        self.get_response = get_response
        self._media_url = getattr(settings, 'MEDIA_URL', '/media/') or '/media/'
        self._static_url = getattr(settings, 'STATIC_URL', '/static/') or '/static/'

    def _is_allowed(self, path):
        if self._media_url and path.startswith(self._media_url):
            return True
        if self._static_url and path.startswith(self._static_url):
            return True
        return any(path.startswith(p) for p in self.ALLOW_PREFIXES)

    def __call__(self, request):
        if (request.session.get('user_id')
                and request.session.get('user_role') == 'CLIENT'
                and not self._is_allowed(request.path or '')):
            from .session_utils import get_session_client, client_has_active_access
            if not client_has_active_access(get_session_client(request)):
                return redirect('client_blocked')
        return self.get_response(request)


# Endpoints that send `application/x-www-form-urlencoded` or multipart even
# though they live under /api/. Listed here to keep the JSON gate strict for
# everything else. Extend deliberately, not by accident.
_API_FORM_EXEMPT_PREFIXES = (
    '/api/nutrizione/import/excel/',
    '/api/nutrizione/import/pdf/',
    '/api/allenamenti/import/excel/',
    '/api/allenamenti/import/pdf/',
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
    """Sanitize all string values in a Django QueryDict in place.

    Strips ASCII control characters (NUL, the rest of 0x00-0x1F except tab/
    newline, DEL and the C1 range) from every value — the same blanket pass the
    JSON API applies via sanitize.clean_payload, so form input is normalized
    too. Secret-bearing keys (passwords, tokens, CSRF) get only a null-byte
    scrub so their bytes stay intact. Tabs and newlines are preserved (textarea
    content). Operates in place by toggling `_mutable`; returns the dict.
    """
    if not qd:
        return qd
    was_mutable = getattr(qd, '_mutable', True)
    qd._mutable = True
    try:
        for key in list(qd.keys()):
            skip = isinstance(key, str) and key.lower() in _FORM_SKIP_KEYS
            cleaned = []
            for v in qd.getlist(key):
                if not isinstance(v, str):
                    cleaned.append(v)
                elif skip:
                    cleaned.append(v.replace('\x00', ''))
                else:
                    cleaned.append(_CONTROL_RE.sub('', v))
            qd.setlist(key, cleaned)
    finally:
        qd._mutable = was_mutable
    return qd


class SanitizationMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        limits = getattr(settings, 'SANITIZE_LIMITS', {}) or {}
        self._json_body_cap = int(limits.get('json_body_mb', 1)) * 1024 * 1024

    def __call__(self, request):
        # Control-char scrub on every request (null bytes + the rest of the C0/C1
        # ranges, tabs/newlines kept). QueryDicts are normally immutable after
        # parsing; we flip the flag for the rewrite and flip it back.
        _scrub_querydict(request.GET)
        _scrub_querydict(request.POST)

        path = request.path or ''
        method = request.method or ''

        if path.startswith('/api/') and method in ('POST', 'PUT', 'PATCH'):
            if not _is_form_exempt(path):
                ctype = (request.META.get('CONTENT_TYPE') or '').lower().split(';')[0].strip()
                # I fetch() senza body (es. delete/duplicate) non hanno nulla da
                # parsare ma Chromium li marca comunque text/plain: con body
                # vuoto il Content-Type è irrilevante, quindi non va bloccato.
                try:
                    _body_len = int(request.META.get('CONTENT_LENGTH') or 0)
                except (TypeError, ValueError):
                    _body_len = 0
                if _body_len and ctype and ctype != 'application/json':
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


class GlobalRateLimitMiddleware:
    """Coarse per-IP request cap covering *every* endpoint.

    A blanket backstop so endpoints without their own limiter (most web views)
    still can't be hammered. The granular limiters — login, mobile API,
    password reset, checkout — stay stricter and run independently inside their
    views/decorators; this only catches volume those don't see. Static and media
    requests are exempt. Returns 429 (JSON under /api/, else plain text) with a
    Retry-After header once the per-IP bucket for the window is exhausted.

    Tune via settings.GLOBAL_RATE_LIMIT; set per_min to 0 to disable.
    """

    def __init__(self, get_response):
        self.get_response = get_response
        from .services import ratelimit
        self._rl = ratelimit
        conf = getattr(settings, 'GLOBAL_RATE_LIMIT', {}) or {}
        self.limit = int(conf.get('per_min', 300))
        self.window = int(conf.get('window_seconds', 60))
        self.enabled = self.limit > 0
        self._static = getattr(settings, 'STATIC_URL', '/static/') or '/static/'
        self._media = getattr(settings, 'MEDIA_URL', '/media/') or '/media/'

    def __call__(self, request):
        if self.enabled:
            path = request.path or ''
            if not path.startswith(self._static) and not path.startswith(self._media):
                ip = self._rl.client_ip(request)
                allowed, _ = self._rl.hit('global_ip', ip, self.limit, self.window)
                if not allowed:
                    logger.warning('global.rate_limited ip=%s path=%s', ip, path)
                    if path.startswith('/api/'):
                        resp = JsonResponse(
                            {'error': 'Troppe richieste. Riprova tra poco.'}, status=429)
                    else:
                        resp = HttpResponse(
                            'Troppe richieste. Riprova tra poco.',
                            status=429, content_type='text/plain; charset=utf-8')
                    resp['Retry-After'] = str(self.window)
                    return resp
        return self.get_response(request)
