"""Generic PDF pipeline primitives shared across import features (nutrition, workouts).

Public surface:
- PdfPage, PdfParseError, open_pdf, render_page_image
- OcrProvider, TesseractProvider, ocr_page_if_needed
- Chunk, chunk_pages, MAX_CHUNK_CHARS, MAX_CHUNKS_PER_DOC
"""
from .ingestion import PdfPage, PdfParseError, open_pdf, render_page_image
from .ocr import OcrProvider, TesseractProvider, ocr_page_if_needed, OCR_TEXT_THRESHOLD
from .chunker import Chunk, chunk_pages, MAX_CHUNK_CHARS, MAX_CHUNKS_PER_DOC, CHUNK_OVERLAP_CHARS
from .classification import PageMeta

__all__ = [
    'PdfPage', 'PdfParseError', 'open_pdf', 'render_page_image',
    'OcrProvider', 'TesseractProvider', 'ocr_page_if_needed', 'OCR_TEXT_THRESHOLD',
    'Chunk', 'chunk_pages', 'MAX_CHUNK_CHARS', 'MAX_CHUNKS_PER_DOC', 'CHUNK_OVERLAP_CHARS',
    'PageMeta',
]
