"""Content-based upload validation for non-image attachments (chat, checks).

A file's extension and ``Content-Type`` are attacker-controlled: a hostile
payload renamed to ``clip.mp4`` would otherwise be stored and later served. We
sniff the real type from leading magic bytes so only genuine media is accepted.
Images are handled separately by ``services.images`` (Pillow re-encode to WebP),
which strips any non-image payload outright; this module covers videos, which
can't be cheaply re-encoded, plus a safe-filename helper for stored objects.
"""
from __future__ import annotations

import os
import re

from django.conf import settings

from .images import is_image, to_webp


def _video_max_bytes() -> int:
    limits = getattr(settings, 'SANITIZE_LIMITS', {}) or {}
    return int(limits.get('video_mb', 100)) * 1024 * 1024


def _read_head(f, n: int = 16) -> bytes:
    """Read the first ``n`` bytes, restoring the stream position."""
    can_seek = hasattr(f, 'seek')
    if can_seek:
        try:
            f.seek(0)
        except Exception:
            can_seek = False
    head = f.read(n) or b''
    if can_seek:
        try:
            f.seek(0)
        except Exception:
            pass
    return head


def looks_like_video(f) -> bool:
    """True when the leading bytes match a video container we accept.

    Covers ISO base-media (MP4 / MOV / M4V — ``ftyp`` box at offset 4) and
    Matroska / WebM (EBML signature). Audio-only or unknown containers fail.
    """
    head = _read_head(f, 16)
    if len(head) >= 12 and head[4:8] == b'ftyp':
        return True
    if head[:4] == b'\x1aE\xdf\xa3':  # EBML (Matroska / WebM)
        return True
    if len(head) >= 8 and head[4:8] in (b'moov', b'mdat', b'free', b'wide'):
        return True  # older QuickTime layouts
    return False


def is_valid_video(f) -> bool:
    """True when ``f`` is a genuine video within the configured size cap."""
    if f is None:
        return False
    size = getattr(f, 'size', 0) or 0
    if size <= 0 or size > _video_max_bytes():
        return False
    return looks_like_video(f)


_SAFE_NAME_RE = re.compile(r'[^A-Za-z0-9._-]+')


def safe_filename(name: str, *, default_stem: str = 'file', default_ext: str = 'mp4') -> str:
    """Strip any directory components and reduce to a conservative charset.

    Defends storage keys against path traversal and odd bytes. Keeps a single
    extension; falls back to ``default_ext`` when the original has none.
    """
    base = os.path.basename(name or '')
    stem, ext = os.path.splitext(base)
    stem = _SAFE_NAME_RE.sub('-', stem).strip('-._') or default_stem
    ext = _SAFE_NAME_RE.sub('', ext.lstrip('.')).lower() or default_ext
    return f'{stem[:80]}.{ext[:8]}'


def store_attachment(f, *, dir_prefix: str):
    """Validate a check/chat attachment and persist it via default_storage.

    Images are re-encoded to WebP (any non-image payload is dropped); videos are
    accepted only when the magic bytes match a real container and the size cap
    holds. Anything else is rejected. ``dir_prefix`` should already carry the
    uniqueness (e.g. ``check_attachments/<id>/<q>_<ts>_``); the validated file
    name is appended.

    Returns ``(saved_storage_path, kind)`` with kind ``'image'``/``'video'``,
    or ``(None, None)`` when the upload is neither and must be skipped.
    """
    from django.core.files.storage import default_storage
    if is_image(f):
        webp = to_webp(f)
        saved = default_storage.save(f'{dir_prefix}{safe_filename(webp.name, default_ext="webp")}', webp)
        return saved, 'image'
    if is_valid_video(f):
        saved = default_storage.save(f'{dir_prefix}{safe_filename(getattr(f, "name", ""))}', f)
        return saved, 'video'
    return None, None
