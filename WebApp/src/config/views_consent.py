"""Cookie consent persistence endpoint."""
import json
import secrets
from django.conf import settings
from django.http import JsonResponse
from django.views.decorators.http import require_POST

from domain.consent.models import CookieConsentRecord
from .services.tokens import get_client_ip
from .session_utils import get_session_user


COOKIE_NAME = 'cookie_consent'
COOKIE_MAX_AGE = 60 * 60 * 24 * 180  # 6 months


@require_POST
def consent_api(request):
    try:
        data = json.loads(request.body.decode('utf-8') or '{}')
    except json.JSONDecodeError:
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    prefs = {
        'necessary': True,
        'preferences': bool(data.get('preferences', False)),
        'analytics': bool(data.get('analytics', False)),
        'marketing': bool(data.get('marketing', False)),
    }
    consent_id = (data.get('consent_id') or '').strip() or secrets.token_urlsafe(16)
    user = get_session_user(request)

    CookieConsentRecord.objects.create(
        consent_id=consent_id,
        user=user,
        necessary=prefs['necessary'],
        preferences=prefs['preferences'],
        analytics=prefs['analytics'],
        marketing=prefs['marketing'],
        consent_version=settings.CONSENT_VERSION,
        ip=get_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
    )

    payload = {
        'consent_id': consent_id,
        'version': settings.CONSENT_VERSION,
        'prefs': prefs,
    }
    resp = JsonResponse({'status': 'ok', 'consent': payload})
    resp.set_cookie(
        COOKIE_NAME,
        value=json.dumps(payload, separators=(',', ':')),
        max_age=COOKIE_MAX_AGE,
        samesite='Lax',
        secure=not settings.DEBUG,
        httponly=False,  # readable by JS for the banner state machine
    )
    return resp
