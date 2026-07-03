"""Image utilities: convert any uploaded image to WebP, preserving high quality.

WebP is supported by all modern browsers and yields ~25-35% smaller files than
JPEG/PNG at visually identical quality. We force WebP on every image upload
(profile photos, progress photos, future media) so storage + bandwidth stay low
and the frontend can serve a single format.
"""
from __future__ import annotations

import io
import logging
import os

from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)


WEBP_QUALITY = 90  # high-efficiency setting; visually lossless for photos
MAX_DIM = 2000     # cap longest side to keep files reasonable

# Cap total pixels Pillow will decode. Defends against "decompression bomb"
# images (tiny file, enormous dimensions) that exhaust RAM on decode. 50 MP
# comfortably covers modern phone cameras (~48 MP) while blocking absurd inputs.
MAX_IMAGE_PIXELS = 50_000_000

# Raster formats we accept and re-encode. Anything Pillow can't parse, or that
# parses as something off-list (SVG, PDF, ICO, animated multi-frame oddities),
# is rejected even when the filename/Content-Type claim ".jpg". The stored file
# is always a freshly Pillow-encoded WebP, so no original bytes survive.
ALLOWED_INPUT_FORMATS = frozenset({'JPEG', 'PNG', 'WEBP', 'GIF', 'BMP', 'TIFF'})


def _load_pillow():
    try:
        from PIL import Image, ImageOps
        # Hard ceiling on decoded pixels — raises DecompressionBombError above 2x.
        Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
        return Image, ImageOps
    except ImportError as e:  # pragma: no cover
        raise RuntimeError(
            "Pillow is required for image processing. Install with: pip install Pillow"
        ) from e


def to_webp(uploaded_file, *, max_dim: int = MAX_DIM, quality: int = WEBP_QUALITY) -> ContentFile:
    """Convert an uploaded image file (Django UploadedFile / file-like) to WebP.

    Returns a Django ContentFile with the original name's stem and ``.webp`` ext.
    Preserves EXIF rotation, transparency, and color profile. Caps longest side
    to ``max_dim`` (keeps aspect ratio) so absurdly large originals don't bloat storage.
    """
    Image, ImageOps = _load_pillow()

    # Read into memory once; we may need to rewind.
    if hasattr(uploaded_file, 'seek'):
        try:
            uploaded_file.seek(0)
        except Exception:
            logger.exception('to_webp.seek_reset failed, reading from current position')

    img = Image.open(uploaded_file)
    img = ImageOps.exif_transpose(img)  # honor camera rotation

    has_alpha = img.mode in ('RGBA', 'LA', 'P') and 'transparency' in img.info
    if img.mode == 'P':
        img = img.convert('RGBA' if has_alpha else 'RGB')
    elif img.mode not in ('RGB', 'RGBA'):
        img = img.convert('RGB')

    # Downscale if needed (preserve aspect).
    w, h = img.size
    longest = max(w, h)
    if longest > max_dim:
        scale = max_dim / float(longest)
        img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

    buf = io.BytesIO()
    save_kwargs = {'format': 'WEBP', 'quality': quality, 'method': 6}
    # method=6 = slower encode, smaller file. Worth it on user-uploaded photos.
    img.save(buf, **save_kwargs)
    buf.seek(0)

    base = os.path.splitext(getattr(uploaded_file, 'name', 'image') or 'image')[0]
    return ContentFile(buf.read(), name=f'{base}.webp')


def is_image(uploaded_file) -> bool:
    """True only when the bytes really are a raster image in our allowlist.

    Sniffs the actual format from the content (not the filename/Content-Type,
    both attacker-controlled) and runs Pillow's integrity ``verify()`` to reject
    truncated or crafted payloads. A non-image renamed to ``.jpg`` returns False.
    """
    Image, _ = _load_pillow()
    try:
        if hasattr(uploaded_file, 'seek'):
            uploaded_file.seek(0)
        with Image.open(uploaded_file) as probe:
            fmt = (probe.format or '').upper()
            probe.verify()  # detects truncated / corrupt payloads
        uploaded_file.seek(0)
        return fmt in ALLOWED_INPUT_FORMATS
    except Exception:
        try:
            uploaded_file.seek(0)
        except Exception:
            logger.exception('is_image.seek_reset failed after rejecting upload')
        return False
