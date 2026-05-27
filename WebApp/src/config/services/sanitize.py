"""Input sanitization helpers.

Centralizes the rules for "what counts as acceptable user input" so views can
validate uniformly. Returns either a cleaned value or raises `InvalidInput`,
which the caller is expected to convert into a 400 response.

Sanitization vs validation: this module trims/normalizes (sanitize) and rejects
clearly hostile or oversized payloads (validate). Domain rules (e.g. password
strength, unique email) stay in the views or models.
"""

import json
import re
import unicodedata
from typing import Iterable

from django.conf import settings


class InvalidInput(Exception):
    """Raised when an input is missing, malformed, or oversized."""


# Strip ASCII control bytes 0x00-0x1F except \t (0x09) and \n (0x0A), plus 0x7F.
# Drops the entire 0x80-0x9F C1 control range too.
_CONTROL_RE = re.compile(r'[\x00-\x08\x0B-\x1F\x7F-\x9F]')
_EMAIL_RE = re.compile(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')


def _limit(key: str, fallback: int) -> int:
    limits = getattr(settings, 'SANITIZE_LIMITS', {}) or {}
    return int(limits.get(key, fallback))


def clean_text(value, max_chars: int | None = None, *, allow_newlines: bool = False, field: str = 'campo') -> str:
    """Normalize a free-text input. Strips null bytes and other control chars,
    collapses leading/trailing whitespace, enforces a length cap.

    Returns '' for None/empty (callers decide whether empty is acceptable).
    """
    if value is None:
        return ''
    if not isinstance(value, str):
        value = str(value)
    # Normalize unicode so visually-identical strings compare equal and length
    # caps are predictable. NFKC also flattens compatibility forms (full-width
    # punctuation, ligatures) that attackers sometimes use to slip past filters.
    value = unicodedata.normalize('NFKC', value)
    if allow_newlines:
        # Preserve \n and \t, drop the rest.
        value = _CONTROL_RE.sub('', value)
    else:
        value = _CONTROL_RE.sub('', value).replace('\r', '').replace('\n', ' ')
    value = value.strip()
    if max_chars is None:
        max_chars = _limit('long_text_chars', 5000)
    if len(value) > max_chars:
        raise InvalidInput(f"{field}: troppo lungo (max {max_chars} caratteri)")
    return value


def clean_short_text(value, *, field: str = 'campo') -> str:
    return clean_text(value, max_chars=_limit('short_text_chars', 200), field=field)


def clean_email(value, *, field: str = 'email') -> str:
    """Lowercase, strip, validate basic shape, enforce length cap."""
    cleaned = clean_text(value, max_chars=_limit('email_chars', 254), field=field).lower()
    if not cleaned:
        raise InvalidInput(f"{field}: obbligatorio")
    if not _EMAIL_RE.match(cleaned):
        raise InvalidInput(f"{field}: formato non valido")
    return cleaned


def clean_password(value, *, min_chars: int = 8, max_chars: int = 128, field: str = 'password') -> str:
    """Trim only \\x00 / weird control bytes — do NOT strip whitespace or
    normalize unicode. Whitespace and unicode are part of the secret."""
    if value is None or not isinstance(value, str):
        raise InvalidInput(f"{field}: obbligatorio")
    # Null bytes inside passwords are a classic database/driver footgun.
    if '\x00' in value:
        raise InvalidInput(f"{field}: contiene caratteri non validi")
    if len(value) < min_chars:
        raise InvalidInput(f"{field}: minimo {min_chars} caratteri")
    if len(value) > max_chars:
        raise InvalidInput(f"{field}: massimo {max_chars} caratteri")
    return value


def safe_json(body: bytes | str, *, max_bytes: int | None = None) -> dict | list:
    """Parse a JSON request body with a hard byte cap and a try/except wrapper."""
    if max_bytes is None:
        max_bytes = _limit('json_body_mb', 1) * 1024 * 1024
    if isinstance(body, str):
        body = body.encode('utf-8', errors='replace')
    if len(body) > max_bytes:
        raise InvalidInput(f"corpo richiesta troppo grande (max {max_bytes // 1024}KB)")
    try:
        data = json.loads(body or b'{}')
    except (ValueError, UnicodeDecodeError):
        raise InvalidInput("JSON non valido")
    return data


def validate_image_upload(uploaded_file, *, max_mb: int | None = None, allowed_mimes: Iterable[str] | None = None, field: str = 'immagine'):
    """Reject files that are too large or have an unexpected MIME.

    `uploaded_file` is a Django `UploadedFile` (or None). Returns the file
    unchanged when valid. The caller is still responsible for further checks
    (e.g. re-encoding via Pillow) before persisting.
    """
    if uploaded_file is None:
        return None
    if max_mb is None:
        max_mb = _limit('image_mb', 10)
    if allowed_mimes is None:
        allowed_mimes = getattr(settings, 'SANITIZE_ALLOWED_IMAGE_MIMES', ('image/jpeg', 'image/png', 'image/webp'))
    size = getattr(uploaded_file, 'size', 0) or 0
    if size > max_mb * 1024 * 1024:
        raise InvalidInput(f"{field}: file troppo grande (max {max_mb} MB)")
    ctype = (getattr(uploaded_file, 'content_type', '') or '').lower().split(';')[0].strip()
    if ctype and ctype not in allowed_mimes:
        raise InvalidInput(f"{field}: tipo file non supportato")
    return uploaded_file


def get_in(d: dict, key: str, default=None):
    """`dict.get` that treats whitespace-only strings as missing."""
    v = d.get(key, default)
    if isinstance(v, str) and not v.strip():
        return default
    return v
