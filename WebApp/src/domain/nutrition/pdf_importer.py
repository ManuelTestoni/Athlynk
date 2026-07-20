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

from domain.nutrition.excel_importer import (
    normalize_and_match, compute_confidence,
    extract_diet_with_ai, apply_structure_hints,
)
from domain.shared.doc_structure import SESSION_HEADER_RE, detect_diet_structure
from domain.shared.pdf import chunk_pages
from domain.nutrition.pdf_extractor import extract_all_chunks, AIExtractionError
from domain.shared.pdf import open_pdf, PdfParseError
from domain.nutrition.pdf_merger import merge_chunks
from domain.shared.pdf import ocr_page_if_needed
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

    # Step 5 — struttura documento (deterministica) + chunking
    _emit(progress_cb, PHASE_EXTRACT, 50)
    full_text = '\n\n'.join(
        (p.combined_text or '') for p, _ in relevant if (p.combined_text or '').strip()
    )
    structure = detect_diet_structure(full_text)
    is_macro = structure.layout.startswith('macro')

    chunks = chunk_pages(relevant, header_re=SESSION_HEADER_RE)
    if not chunks:
        raise PdfParseError("Nessun contenuto utile estratto dalle pagine.")

    document_summary = {
        'total_pages': total_pages,
        'pages_processed': len(relevant),
        'pages_skipped': total_pages - len(relevant),
        'ocr_pages': ocr_pages_count,
        'relevant_pages': relevant_page_numbers,
    }

    if is_macro or len(chunks) <= 2:
        # Fast path: piano solo-macro o documento piccolo → una singola
        # chiamata LLM sul testo completo, niente chunk/merge/retry.
        merged = extract_diet_with_ai(full_text, plan_title, structure=structure)
        merged.setdefault('days', [])
        if plan_title and not merged.get('diet_name'):
            merged['diet_name'] = plan_title
        merged['document_summary'] = document_summary
        _emit(progress_cb, PHASE_FINALIZE, 88)
    else:
        # Step 6 — estrazione chunk-by-chunk
        def _chunk_progress(done: int, total: int):
            # 50% → 85% durante l'estrazione
            pct = 50 + int(35 * done / max(total, 1))
            _emit(progress_cb, PHASE_EXTRACT, pct)

        parts, llm_notes = extract_all_chunks(chunks, progress_cb=_chunk_progress)

        # Step 6b — retry mirato sui giorni mancanti.
        # Se la prima passata ha rilevato < 7 giorni ma il documento sembra
        # contenere riferimenti settimanali completi, rilancia l'estrazione sui
        # chunk che menzionano i giorni mancanti con un prompt più rigido.
        detected_days = _collect_detected_days(parts)
        expected = _expected_days_from_pages(relevant)
        missing = sorted(expected - detected_days)
        if missing:
            retry_parts, retry_notes = _retry_missing_days(chunks, missing)
            parts.extend(retry_parts)
            llm_notes.extend(retry_notes)

        # Step 7 — merge
        _emit(progress_cb, PHASE_FINALIZE, 88)
        merged = merge_chunks(parts, document_summary=document_summary,
                              extra_notes=llm_notes, diet_name=plan_title or None)

    if not merged.get('days') and not is_macro:
        raise AIExtractionError(
            "L'AI non ha estratto alcun giorno utile dal PDF."
        )

    # Step 8 — normalize + match + confidence (riuso pipeline Excel)
    def _match_progress(done: int, total: int):
        pct = 88 + int(10 * done / max(total, 1))
        _emit(progress_cb, PHASE_FINALIZE, pct)

    normalized = normalize_and_match(merged, progress_cb=_match_progress)
    apply_structure_hints(normalized, structure)
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
                # Riassocia source meta per substitutions per nome
                src_subs = {(s.get('name') or '').strip().lower(): s
                            for s in (src.get('substitutions') or [])}
                for sub in food.get('substitutions', []) or []:
                    s_src = src_subs.get((sub.get('name') or '').strip().lower())
                    if not s_src:
                        continue
                    if sub.get('source_page') is None and s_src.get('source_page') is not None:
                        sub['source_page'] = s_src['source_page']
                    if not sub.get('source_chunk') and s_src.get('source_chunk'):
                        sub['source_chunk'] = s_src['source_chunk']

    # Source meta per integratori
    supp_src_map = {(s.get('name') or '').strip().lower(): s
                    for s in (merged.get('supplements') or [])}
    for supp in normalized.get('supplements', []) or []:
        s_src = supp_src_map.get((supp.get('name') or '').strip().lower())
        if s_src and supp.get('source_page') is None and s_src.get('source_page') is not None:
            supp['source_page'] = s_src['source_page']


# ─── Day detection robustness helpers ──────────────────────────────────────────

_DAY_TOKEN_MAP = {
    # estesi
    'lunedì': 'MONDAY', 'lunedi': 'MONDAY',
    'martedì': 'TUESDAY', 'martedi': 'TUESDAY',
    'mercoledì': 'WEDNESDAY', 'mercoledi': 'WEDNESDAY',
    'giovedì': 'THURSDAY', 'giovedi': 'THURSDAY',
    'venerdì': 'FRIDAY', 'venerdi': 'FRIDAY',
    'sabato': 'SATURDAY', 'domenica': 'SUNDAY',
    # abbreviati
    'lun': 'MONDAY', 'mar': 'TUESDAY', 'mer': 'WEDNESDAY',
    'gio': 'THURSDAY', 'ven': 'FRIDAY', 'sab': 'SATURDAY', 'dom': 'SUNDAY',
    # inglese
    'monday': 'MONDAY', 'tuesday': 'TUESDAY', 'wednesday': 'WEDNESDAY',
    'thursday': 'THURSDAY', 'friday': 'FRIDAY', 'saturday': 'SATURDAY', 'sunday': 'SUNDAY',
}


def _collect_detected_days(parts: list[dict]) -> set[str]:
    found: set[str] = set()
    for part in parts or []:
        for day in (part.get('days') or []):
            dow = day.get('day_of_week')
            if dow in _DAY_TOKEN_MAP.values():
                found.add(dow)
    return found


def _expected_days_from_pages(relevant) -> set[str]:
    """Scansiona il testo grezzo delle pagine rilevanti per giorni menzionati."""
    import re as _re
    expected: set[str] = set()
    pattern = _re.compile(
        r'\b(' + '|'.join(_re.escape(k) for k in _DAY_TOKEN_MAP) + r')\b\.?',
        flags=_re.IGNORECASE,
    )
    for page, _meta in relevant or []:
        text = (page.combined_text or '').lower()
        for m in pattern.findall(text):
            tok = m.lower().rstrip('.')
            if tok in _DAY_TOKEN_MAP:
                expected.add(_DAY_TOKEN_MAP[tok])
    # Anche pattern "giorno N"
    gpat = _re.compile(r'giorno\s*([1-7])', flags=_re.IGNORECASE)
    map_num = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']
    for page, _meta in relevant or []:
        for n in gpat.findall((page.combined_text or '').lower()):
            try:
                expected.add(map_num[int(n) - 1])
            except (ValueError, IndexError):
                pass
    return expected


def _retry_missing_days(chunks, missing: list[str]) -> tuple[list[dict], list[str]]:
    """Rilancia estrazione su chunk che menzionano i giorni mancanti.

    Prompt rinforzato: estrai SOLO i giorni richiesti. Riduce drift su pasti
    già coperti e massimizza recupero giorni saltati.
    """
    from langchain_core.messages import SystemMessage, HumanMessage
    from domain.nutrition.llm_client import build_extraction_llm
    from domain.nutrition.pdf_extractor import CHUNK_SYSTEM_PROMPT
    import json as _json

    if not chunks or not missing:
        return [], []

    # Mappa codice → token cercabili
    code_to_tokens = {
        'MONDAY': ['lunedì', 'lunedi', 'lun', 'monday'],
        'TUESDAY': ['martedì', 'martedi', 'mar', 'tuesday'],
        'WEDNESDAY': ['mercoledì', 'mercoledi', 'mer', 'wednesday'],
        'THURSDAY': ['giovedì', 'giovedi', 'gio', 'thursday'],
        'FRIDAY': ['venerdì', 'venerdi', 'ven', 'friday'],
        'SATURDAY': ['sabato', 'sab', 'saturday'],
        'SUNDAY': ['domenica', 'dom', 'sunday'],
    }
    tokens_needed = []
    for code in missing:
        tokens_needed.extend(code_to_tokens.get(code, []))

    # Seleziona chunk che menzionano almeno uno dei giorni mancanti
    target_chunks = []
    for ch in chunks:
        txt = (ch.text or '').lower()
        if any(tok in txt for tok in tokens_needed):
            target_chunks.append(ch)
    if not target_chunks:
        return [], [f'retry: nessun chunk menziona giorni mancanti ({",".join(missing)})']

    llm = build_extraction_llm(max_tokens=4000, timeout=60)
    extra_instr = (
        f"\n\nFOCUS RETRY: estrai SOLO i seguenti giorni se presenti nel testo: "
        f"{', '.join(missing)}. Ignora gli altri. Sii MASSIMAMENTE esaustivo: "
        f"non saltare alcun pasto né alcun alimento; scorri il testo riga per riga."
    )
    out_parts: list[dict] = []
    notes: list[str] = []
    for ch in target_chunks:
        user_msg = (
            f"Metadata chunk:\n"
            f"- page_number: {ch.page_number}\n"
            f"- chunk_id: {ch.chunk_id}\n\n"
            f"Testo del chunk:\n{ch.text}\n\n"
            f"Restituisci SOLO JSON conforme allo schema."
        )
        try:
            resp = llm.invoke([
                SystemMessage(content=CHUNK_SYSTEM_PROMPT + extra_instr),
                HumanMessage(content=user_msg),
            ])
            content = resp.content if isinstance(resp.content, str) else str(resp.content)
            raw = _json.loads(content)
        except Exception as e:
            notes.append(f'retry chunk {ch.chunk_id}: {e}')
            continue
        # filtra solo giorni mancanti
        raw['days'] = [d for d in (raw.get('days') or [])
                       if d.get('day_of_week') in missing]
        for d in raw['days']:
            for meal in d.get('meals') or []:
                for f in meal.get('foods') or []:
                    f.setdefault('source_page', ch.page_number)
                    f.setdefault('source_chunk', ch.chunk_id)
        if raw.get('days'):
            out_parts.append(raw)
    if not out_parts:
        notes.append(f'retry: nessun giorno recuperato per {",".join(missing)}')
    return out_parts, notes
