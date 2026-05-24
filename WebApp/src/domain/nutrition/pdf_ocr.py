"""OCR condizionale sulle sole pagine candidate.

Interfaccia astratta (OcrProvider) per poter sostituire pytesseract con un
provider esterno (es. cloud OCR) senza toccare la pipeline.
"""

from __future__ import annotations

import io
from typing import Protocol

from domain.nutrition.pdf_ingestion import PdfPage, render_page_image


# Soglia: pagine con meno di N caratteri di testo nativo sono candidate OCR
OCR_TEXT_THRESHOLD = 60


class OcrProvider(Protocol):
    def recognize(self, image_bytes: bytes, lang: str = 'ita+eng') -> str: ...


class TesseractProvider:
    """Provider OCR locale via pytesseract. Richiede Tesseract + language pack."""

    def __init__(self, lang: str = 'ita+eng'):
        self.lang = lang

    def recognize(self, image_bytes: bytes, lang: str | None = None) -> str:
        try:
            import pytesseract
            from PIL import Image
        except ImportError:
            return ''  # OCR non disponibile → fallback silenzioso
        try:
            img = Image.open(io.BytesIO(image_bytes))
            return pytesseract.image_to_string(img, lang=lang or self.lang) or ''
        except Exception:
            return ''


_default_provider: OcrProvider | None = None


def get_default_provider() -> OcrProvider:
    global _default_provider
    if _default_provider is None:
        _default_provider = TesseractProvider()
    return _default_provider


def ocr_page_if_needed(file_bytes: bytes, page: PdfPage,
                       provider: OcrProvider | None = None) -> PdfPage:
    """Esegue OCR sulla pagina se il testo nativo è troppo scarso."""
    if len((page.native_text or '').strip()) >= OCR_TEXT_THRESHOLD:
        return page  # testo nativo sufficiente, niente OCR
    prov = provider or get_default_provider()
    try:
        img = render_page_image(file_bytes, page.page_number, dpi=200)
    except Exception:
        return page
    text = prov.recognize(img)
    if text and text.strip():
        page.ocr_text = text.strip()
        page.used_ocr = True
    return page
