"""Orchestrator: PDF → AI extraction → DB-matched workout JSON.

Pipeline phases (mirror nutrition):
  1. analyze   — open PDF + native text
  2. classify  — keyword-based page scoring
  3. ocr       — conditional OCR on candidate pages
  4. extract   — chunk-by-chunk LLM extraction
  5. finalize  — merge + normalize_and_match + compute_confidence

Public:
  run_pdf_pipeline(file_bytes, plan_title, progress_cb, coach)
    -> (normalized_dict, ConfidenceSummary)
"""

from __future__ import annotations

from typing import Callable, Optional

from domain.shared.pdf.chunker import chunk_pages
from domain.shared.pdf.ingestion import open_pdf, PdfParseError
from domain.shared.pdf.ocr import ocr_page_if_needed
from domain.workouts.imports.excel_importer import (
    normalize_and_match, compute_confidence,
)
from domain.workouts.imports.pdf_extractor import (
    extract_all_chunks, AIExtractionError,
)
from domain.workouts.imports.pdf_merger import merge_chunks
from domain.workouts.imports.pdf_page_classifier import classify_pages, select_relevant
from domain.workouts.imports.schemas import ConfidenceSummary


ProgressCb = Callable[[str, int], None]


PHASE_ANALYZE = 'analyze'
PHASE_CLASSIFY = 'classify'
PHASE_OCR = 'ocr'
PHASE_EXTRACT = 'extract'
PHASE_FINALIZE = 'finalize'


def _emit(cb: Optional[ProgressCb], phase: str, percent: int) -> None:
    if cb is None:
        return
    try:
        cb(phase, max(0, min(100, percent)))
    except Exception:
        pass


def run_pdf_pipeline(
    file_bytes: bytes,
    plan_title: str = '',
    progress_cb: Optional[ProgressCb] = None,
    coach=None,
) -> tuple[dict, ConfidenceSummary]:
    """End-to-end. Raises PdfParseError or AIExtractionError."""

    _emit(progress_cb, PHASE_ANALYZE, 5)
    pages = open_pdf(file_bytes)
    total_pages = len(pages)
    _emit(progress_cb, PHASE_ANALYZE, 20)

    _emit(progress_cb, PHASE_CLASSIFY, 25)
    metas = classify_pages(pages)

    _emit(progress_cb, PHASE_OCR, 35)
    ocr_pages_count = 0
    for p, m in zip(pages, metas):
        if m.page_type == 'decorative_or_irrelevant':
            continue
        if len((p.native_text or '').strip()) >= 60:
            continue
        ocr_page_if_needed(file_bytes, p)
        if p.used_ocr:
            ocr_pages_count += 1

    metas = classify_pages(pages)
    relevant = select_relevant(pages, metas)
    relevant_page_numbers = [p.page_number for p, _ in relevant]

    if not relevant:
        raise PdfParseError(
            "Il documento non sembra contenere una scheda di allenamento riconoscibile."
        )

    _emit(progress_cb, PHASE_EXTRACT, 50)
    chunks = chunk_pages(relevant)
    if not chunks:
        raise PdfParseError("Nessun contenuto utile estratto dalle pagine.")

    def _chunk_progress(done: int, total: int):
        pct = 50 + int(35 * done / max(total, 1))
        _emit(progress_cb, PHASE_EXTRACT, pct)

    parts, llm_notes = extract_all_chunks(chunks, progress_cb=_chunk_progress)

    _emit(progress_cb, PHASE_FINALIZE, 88)
    document_summary = {
        'total_pages': total_pages,
        'pages_processed': len(relevant),
        'pages_skipped': total_pages - len(relevant),
        'ocr_pages': ocr_pages_count,
        'relevant_pages': relevant_page_numbers,
    }
    merged = merge_chunks(
        parts,
        document_summary=document_summary,
        extra_notes=llm_notes,
        plan_name=plan_title or None,
    )

    if not merged.get('sessions'):
        raise AIExtractionError("L'AI non ha estratto alcuna sessione utile dal PDF.")

    normalized = normalize_and_match(merged, coach=coach)
    normalized['document_summary'] = document_summary
    _reattach_source_meta(merged, normalized)

    confidence = compute_confidence(normalized)
    _emit(progress_cb, PHASE_FINALIZE, 100)
    return normalized, confidence


def _reattach_source_meta(merged: dict, normalized: dict) -> None:
    """Ensure source_page / source_chunk survive pydantic round-trip."""

    def _key(session_label: str, block_name: str, raw_name: str) -> str:
        return f'{(session_label or "").lower()}|{(block_name or "").lower()}|{(raw_name or "").strip().lower()}'

    src_map: dict[str, dict] = {}
    for sess in merged.get('sessions', []) or []:
        for block in sess.get('blocks', []) or []:
            for ex in block.get('exercises', []) or []:
                k = _key(sess.get('day_label') or sess.get('day_of_week') or '',
                         block.get('block_name') or '',
                         ex.get('raw_name') or '')
                src_map[k] = ex

    for sess in normalized.get('sessions', []) or []:
        for block in sess.get('blocks', []) or []:
            for ex in block.get('exercises', []) or []:
                k = _key(sess.get('day_label') or sess.get('day_of_week') or '',
                         block.get('block_name') or '',
                         ex.get('raw_name') or '')
                src = src_map.get(k)
                if not src:
                    continue
                if ex.get('source_page') is None and src.get('source_page') is not None:
                    ex['source_page'] = src['source_page']
                if not ex.get('source_chunk') and src.get('source_chunk'):
                    ex['source_chunk'] = src['source_chunk']
