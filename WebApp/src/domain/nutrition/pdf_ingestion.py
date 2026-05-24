"""Apertura PDF + estrazione testo nativo pagina-per-pagina + render immagini.

Usa PyMuPDF (fitz) per testo veloce e rendering. Restituisce strutture leggere
consumate dagli step successivi (classifier, OCR, chunker).
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from typing import Optional

try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover
    fitz = None  # type: ignore


class PdfParseError(Exception):
    """PDF non leggibile, vuoto o corrotto."""


@dataclass
class PdfPage:
    page_number: int            # 1-indexed
    native_text: str
    ocr_text: str = ''
    used_ocr: bool = False
    text_density: float = 0.0   # char/area normalizzati
    likely_has_table: bool = False
    width: float = 0.0
    height: float = 0.0

    @property
    def combined_text(self) -> str:
        # Preferisce nativo se denso, altrimenti OCR.
        if self.used_ocr and len(self.ocr_text) > len(self.native_text):
            return self.ocr_text
        return self.native_text or self.ocr_text


def _normalize_ws(text: str) -> str:
    text = text.replace('\r', ' ').replace('\t', ' ')
    text = re.sub(r'[  ]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def open_pdf(file_bytes: bytes) -> list[PdfPage]:
    """Apre il PDF e ritorna la lista pagine con testo nativo già estratto.

    Solleva PdfParseError se il file non è apribile o è vuoto.
    """
    if fitz is None:
        raise PdfParseError("PyMuPDF non installato (pip install pymupdf).")

    try:
        doc = fitz.open(stream=file_bytes, filetype='pdf')
    except Exception as e:
        raise PdfParseError(f"PDF non leggibile: {e}") from e

    if doc.page_count == 0:
        doc.close()
        raise PdfParseError("PDF vuoto.")

    pages: list[PdfPage] = []
    for idx in range(doc.page_count):
        page = doc.load_page(idx)
        raw_text = page.get_text('text') or ''
        text = _normalize_ws(raw_text)
        rect = page.rect
        area = max((rect.width * rect.height) / 1_000_000.0, 0.001)  # mln di unità
        density = len(text) / area
        # Indizio tabella: presenza di molte sequenze di numeri allineati
        table_hint = bool(re.search(r'(\d+[,.]?\d*\s+){3,}', text))
        pages.append(PdfPage(
            page_number=idx + 1,
            native_text=text,
            text_density=round(density, 2),
            likely_has_table=table_hint,
            width=rect.width,
            height=rect.height,
        ))
    doc.close()
    return pages


def render_page_image(file_bytes: bytes, page_number: int, dpi: int = 200) -> bytes:
    """Renderizza una pagina come PNG (per OCR). page_number 1-indexed."""
    if fitz is None:
        raise PdfParseError("PyMuPDF non installato.")
    try:
        doc = fitz.open(stream=file_bytes, filetype='pdf')
    except Exception as e:
        raise PdfParseError(f"PDF non renderizzabile: {e}") from e
    try:
        if page_number < 1 or page_number > doc.page_count:
            raise PdfParseError(f"Pagina {page_number} fuori range.")
        page = doc.load_page(page_number - 1)
        zoom = dpi / 72.0
        mat = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat, alpha=False)
        return pix.tobytes('png')
    finally:
        doc.close()
