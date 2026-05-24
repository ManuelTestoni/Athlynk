"""Orchestratore della pipeline import dieta da PDF.

Step:
  1. Apertura PDF + testo nativo
  2. Classificazione pagine (deterministica)
  3. OCR condizionale sulle candidate
  4. Riclassificazione (post-OCR può cambiare punteggi)
  5. Selezione pagine rilevanti
  6. Chunking
  7. Estrazione LLM chunk-by-chunk
  8. Merge → DietExtraction dict
  9. normalize_and_match (riuso da excel_importer) + compute_confidence

Espone run_pdf_pipeline(file_bytes, plan_title, progress_cb) -> (dict, ConfidenceSummary).
progress_cb(phase: str, percent: int) chiamato ai checkpoint per polling.
"""

from __future__ import annotations

from typing import Callable, Optional

from domain.nutrition.excel_importer import normalize_and_match, compute_confidence
from domain.nutrition.pdf_chunker import chunk_pages
from domain.nutrition.pdf_extractor import extract_all_chunks, AIExtractionError
from domain.nutrition.pdf_ingestion import open_pdf, PdfParseError
from domain.nutrition.pdf_merger import merge_chunks
from domain.nutrition.pdf_ocr import ocr_page_if_needed
from domain.nutrition.pdf_page_classifier import classify_pages, select_relevant
from domain.nutrition.schemas import ConfidenceSummary


ProgressCb = Callable[[str, int], None]


# Fasi nominate (devono corrispondere agli step del frontend)
PHASE_ANALYZE = 'analyze'         # "Analisi del PDF..."
PHASE_CLASSIFY = 'classify'       # "Identificazione pagine rilevanti..."
PHASE_OCR = 'ocr'                 # "OCR delle pagine necessarie..."
PHASE_EXTRACT = 'extract'         # "Estrazione AI della dieta..."
PHASE_FINALIZE = 'finalize'       # "Preparazione revisione finale..."


def _emit(cb: Optional[ProgressCb], phase: str, percent: int) -> None:
    if cb is None:
        return
    try:
        cb(phase, max(0, min(100, percent)))
    except Exception:
        pass


def run_pdf_pipeline(file_bytes: bytes, plan_title: str = '',
                     progress_cb: Optional[ProgressCb] = None
                     ) -> tuple[dict, ConfidenceSummary]:
    """End-to-end. Solleva PdfParseError o AIExtractionError."""

    # Step 1 — apertura + testo nativo
    _emit(progress_cb, PHASE_ANALYZE, 5)
    pages = open_pdf(file_bytes)
    total_pages = len(pages)
    _emit(progress_cb, PHASE_ANALYZE, 20)

    # Step 2 — classificazione preliminare
    _emit(progress_cb, PHASE_CLASSIFY, 25)
    metas = classify_pages(pages)

    # Step 3 — OCR condizionale sulle pagine candidate
    _emit(progress_cb, PHASE_OCR, 35)
    ocr_pages_count = 0
    # Esegui OCR solo su pagine candidate (non scartate dalla classificazione)
    for p, m in zip(pages, metas):
        if m.page_type == 'decorative_or_irrelevant':
            continue
        if len((p.native_text or '').strip()) >= 60:
            continue
        ocr_page_if_needed(file_bytes, p)
        if p.used_ocr:
            ocr_pages_count += 1

    # Step 4 — riclassifica dopo OCR (combined_text può essere migliorato)
    metas = classify_pages(pages)
    relevant = select_relevant(pages, metas)
    relevant_page_numbers = [p.page_number for p, _ in relevant]

    if not relevant:
        raise PdfParseError(
            "Il documento non sembra contenere una dieta riconoscibile."
        )

    # Step 5 — chunking
    _emit(progress_cb, PHASE_EXTRACT, 50)
    chunks = chunk_pages(relevant)
    if not chunks:
        raise PdfParseError("Nessun contenuto utile estratto dalle pagine.")

    # Step 6 — estrazione chunk-by-chunk
    def _chunk_progress(done: int, total: int):
        # 50% → 85% durante l'estrazione
        pct = 50 + int(35 * done / max(total, 1))
        _emit(progress_cb, PHASE_EXTRACT, pct)

    parts, llm_notes = extract_all_chunks(chunks, progress_cb=_chunk_progress)

    # Step 7 — merge
    _emit(progress_cb, PHASE_FINALIZE, 88)
    document_summary = {
        'total_pages': total_pages,
        'pages_processed': len(relevant),
        'pages_skipped': total_pages - len(relevant),
        'ocr_pages': ocr_pages_count,
        'relevant_pages': relevant_page_numbers,
    }
    merged = merge_chunks(parts, document_summary=document_summary,
                          extra_notes=llm_notes, diet_name=plan_title or None)

    if not merged.get('days'):
        raise AIExtractionError(
            "L'AI non ha estratto alcun giorno utile dal PDF."
        )

    # Step 8 — normalize + match + confidence (riuso pipeline Excel)
    normalized = normalize_and_match(merged)
    # Preserva campi extra non-pydantic (document_summary)
    normalized['document_summary'] = document_summary
    # Reinietta source_page/source_chunk perduti se la normalizzazione li droppa
    _reattach_source_meta(merged, normalized)

    confidence = compute_confidence(normalized)
    _emit(progress_cb, PHASE_FINALIZE, 100)
    return normalized, confidence


def _reattach_source_meta(merged: dict, normalized: dict) -> None:
    """Garantisce che source_page/source_chunk arrivino al frontend.

    Pydantic li valida via FoodEntry (opzionali) ma se la versione di Pydantic
    li droppa per qualche reason, li reinietta dal merged.
    """
    def _key(d: str, m: str, name: str) -> str:
        return f"{d}|{m}|{(name or '').strip().lower()}"

    src_map: dict[str, dict] = {}
    for day in merged.get('days', []) or []:
        for meal in day.get('meals', []) or []:
            for food in meal.get('foods', []) or []:
                src_map[_key(day.get('day_of_week'), meal.get('meal_type'), food.get('name'))] = food

    for day in normalized.get('days', []) or []:
        for meal in day.get('meals', []) or []:
            for food in meal.get('foods', []) or []:
                k = _key(day.get('day_of_week'), meal.get('meal_type'), food.get('name'))
                src = src_map.get(k)
                if not src:
                    continue
                if food.get('source_page') is None and src.get('source_page') is not None:
                    food['source_page'] = src['source_page']
                if not food.get('source_chunk') and src.get('source_chunk'):
                    food['source_chunk'] = src['source_chunk']
