"""Apple Push Notifications (APNs) sender.

Fully guarded by design: when no APNs credentials are configured every call is a
silent no-op, so the rest of the app keeps working untouched until the real
Apple key lands. Nothing here ever raises into the caller — failures are logged
and swallowed.

Activate by setting the APNS_* values in settings (see config/settings.py). The
provider JWT is signed locally with `cryptography` (ES256 over the .p8 EC key),
and pushes go out over HTTP/2 via `httpx` — both already in requirements.
"""
from __future__ import annotations

import base64
import json
import logging
import time

from django.conf import settings

logger = logging.getLogger(__name__)

# Provider tokens are valid ~1h; Apple rejects regenerating them too often.
# Cache and reuse for 30 minutes.
_jwt_cache = {'token': None, 'ts': 0.0}
_JWT_TTL = 1800


def _load_key() -> str | None:
    raw = settings.APNS_AUTH_KEY
    if not raw and settings.APNS_AUTH_KEY_PATH:
        try:
            with open(settings.APNS_AUTH_KEY_PATH, 'r') as f:
                raw = f.read()
        except OSError:
            logger.warning("APNS_AUTH_KEY_PATH set but unreadable")
            return None
    return raw or None


def is_configured() -> bool:
    """True only when enough is set to actually sign and address a push."""
    return bool(_load_key() and settings.APNS_KEY_ID and settings.APNS_TEAM_ID)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def _provider_jwt() -> str:
    now = time.time()
    if _jwt_cache['token'] and (now - _jwt_cache['ts']) < _JWT_TTL:
        return _jwt_cache['token']

    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    key = load_pem_private_key(_load_key().encode(), password=None)
    header = {'alg': 'ES256', 'kid': settings.APNS_KEY_ID}
    payload = {'iss': settings.APNS_TEAM_ID, 'iat': int(now)}
    signing_input = (
        _b64url(json.dumps(header, separators=(',', ':')).encode())
        + '.'
        + _b64url(json.dumps(payload, separators=(',', ':')).encode())
    )
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    raw_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')  # JOSE wants raw r||s
    token = signing_input + '.' + _b64url(raw_sig)
    _jwt_cache.update(token=token, ts=now)
    return token


def send_push_to_user(user, title, body, data=None, badge=None) -> None:
    """Best-effort push to every active iOS device token of `user`. Never raises."""
    try:
        if not is_configured():
            return
        from domain.accounts.models import DeviceToken
        tokens = list(
            DeviceToken.objects
            .filter(user=user, is_active=True, platform='ios')
            .values_list('token', flat=True)
        )
        if not tokens:
            return
        _dispatch(tokens, title, body, data or {}, badge)
    except Exception:
        logger.exception("APNs push failed (ignored)")


def _dispatch(tokens, title, body, data, badge) -> None:
    import httpx

    jwt = _provider_jwt()
    host = 'api.sandbox.push.apple.com' if settings.APNS_USE_SANDBOX else 'api.push.apple.com'
    aps = {'alert': {'title': title, 'body': body}, 'sound': 'default'}
    if badge is not None:
        aps['badge'] = badge
    payload = json.dumps({'aps': aps, **(data or {})}).encode()
    headers = {
        'authorization': f'bearer {jwt}',
        'apns-topic': settings.APNS_BUNDLE_ID,
        'apns-push-type': 'alert',
    }

    with httpx.Client(http2=True, base_url=f'https://{host}', timeout=10) as client:
        for tok in tokens:
            try:
                resp = client.post(f'/3/device/{tok}', content=payload, headers=headers)
                # 410 Gone / 400 BadDeviceToken → token is dead, stop using it.
                if resp.status_code == 410 or (
                    resp.status_code == 400 and 'BadDeviceToken' in resp.text
                ):
                    _deactivate(tok)
            except Exception:
                logger.exception("APNs send to one device failed (ignored)")


def _deactivate(token) -> None:
    try:
        from domain.accounts.models import DeviceToken
        DeviceToken.objects.filter(token=token).update(is_active=False)
    except Exception:
        pass
