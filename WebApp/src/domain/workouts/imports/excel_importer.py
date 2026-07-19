"""Excel → AI extraction → DB-matched workout JSON pipeline.

Public API:
- run_import_pipeline(file_bytes, plan_title) -> (dict, ConfidenceSummary)
- normalize_and_match(raw_json) -> dict
- compute_confidence(normalized) -> ConfidenceSummary
- ExcelParseError, AIExtractionError
"""

from __future__ import annotations

import json
import re
from typing import Optional

from langchain_core.messages import SystemMessage, HumanMessage
from pydantic import ValidationError

from domain.shared.excel_text import excel_to_text, ExcelParseError  # noqa: F401  (re-export)
from domain.shared.extraction import AIExtractionError  # noqa: F401  (re-export)
from domain.shared.llm_extraction import build_extraction_llm
from domain.workouts.imports.exercise_match import best_match
from domain.workouts.imports.prompts import EXCEL_SYSTEM_PROMPT
from domain.workouts.imports.schemas import ConfidenceSummary, WorkoutExtraction


# ─── AI extraction ──────────────────────────────────────────────────────

def extract_workout_with_ai(grid_text: str, plan_title: str = '') -> dict:
    llm = build_extraction_llm()
    user_msg = (
        f"Titolo piano (suggerito dal coach): {plan_title or 'non specificato'}\n\n"
        f"Contenuto Excel:\n{grid_text}\n\n"
        f"Restituisci SOLO il JSON conforme allo schema."
    )
    try:
        resp = llm.invoke([
            SystemMessage(content=EXCEL_SYSTEM_PROMPT),
            HumanMessage(content=user_msg),
        ])
    except Exception as e:
        raise AIExtractionError(f"Chiamata LLM fallita: {e}") from e
    content = resp.content if isinstance(resp.content, str) else str(resp.content)
    try:
        raw = json.loads(content)
    except json.JSONDecodeError as e:
        raise AIExtractionError(f"JSON LLM invalido: {e}\nOutput: {content[:500]}") from e
    return raw


# ─── Normalize + match against Exercise DB ──────────────────────────────

_REST_SECONDS_RE = re.compile(
    r"^\s*(\d+)\s*(s|sec|secondi)?\s*$|^\s*(\d+)\s*'(\d+)?\s*$|^\s*(\d+)\s*(m|min|minuti)\s*$",
    flags=re.IGNORECASE,
)


def _parse_rest_seconds(rest: object) -> Optional[int]:
    """Parse 'rest_label' free-text → seconds. Returns None for free-form."""
    if rest is None:
        return None
    if isinstance(rest, (int, float)):
        return int(rest) if rest > 0 else None
    text = str(rest).strip().lower()
    if not text:
        return None
    if text in {'a piacere', 'libero', 'free', '-'}:
        return None
    m = _REST_SECONDS_RE.match(text)
    if not m:
        return None
    if m.group(1):
        v = int(m.group(1))
        unit = m.group(2) or 's'
        return v * 60 if unit.startswith('m') else v
    if m.group(3):
        mins = int(m.group(3))
        secs = int(m.group(4) or 0)
        return mins * 60 + secs
    if m.group(5):
        return int(m.group(5)) * 60
    return None


def normalize_and_match(raw_json: dict, coach=None) -> dict:
    """Validate via pydantic + best_match every exercise against Exercise DB."""
    try:
        validated = WorkoutExtraction.model_validate(raw_json)
    except ValidationError:
        raw_json.setdefault('sessions', [])
        validated = WorkoutExtraction.model_validate(raw_json)
    out = validated.model_dump()

    for s_idx, session in enumerate(out.get('sessions', []) or []):
        session.setdefault('order_index', s_idx)
        for block in session.get('blocks', []) or []:
            for ex in block.get('exercises', []) or []:
                _match_exercise_into(ex, coach=coach)
                # Backfill rest_seconds from rest_label when missing
                if ex.get('rest_seconds') in (None, 0) and ex.get('rest_label'):
                    parsed = _parse_rest_seconds(ex.get('rest_label'))
                    if parsed:
                        ex['rest_seconds'] = parsed

    return out


def _match_exercise_into(entry: dict, coach=None) -> None:
    name = (entry.get('raw_name') or '').strip()
    if not name:
        entry['matched_exercise_id'] = None
        entry['matched_exercise_name'] = None
        entry['match_confidence'] = 'none'
        entry['match_method'] = 'none'
        entry['uncertain'] = True
        entry['candidates'] = []
        return
    best, others, confidence, method = best_match(
        name, coach=coach, name_en=(entry.get('name_en') or '').strip() or None,
    )
    if best:
        entry['matched_exercise_id'] = best['id']
        entry['matched_exercise_name'] = best['name']
        entry['matched_primary_muscle'] = best.get('primary_muscle') or ''
        entry['matched_equipment'] = ', '.join(best.get('equipment') or [])
        entry['match_confidence'] = confidence
        entry['match_method'] = method
        entry['candidates'] = others
        entry['uncertain'] = entry.get('uncertain', False) or confidence in ('medium',)
    else:
        entry['matched_exercise_id'] = None
        entry['matched_exercise_name'] = None
        entry['matched_primary_muscle'] = None
        entry['matched_equipment'] = None
        entry['match_confidence'] = confidence
        entry['match_method'] = method
        entry['candidates'] = others
        entry['uncertain'] = True


# ─── Confidence ─────────────────────────────────────────────────────────

def compute_confidence(normalized: dict) -> ConfidenceSummary:
    total = 0
    uncertain = 0
    for session in normalized.get('sessions', []) or []:
        for block in session.get('blocks', []) or []:
            for ex in block.get('exercises', []) or []:
                total += 1
                if ex.get('uncertain') or not ex.get('matched_exercise_id'):
                    uncertain += 1
    ratio = (uncertain / total) if total else 0.0
    return ConfidenceSummary(
        fields_total=total,
        fields_uncertain=uncertain,
        ratio=round(ratio, 3),
    )


# ─── End-to-end ─────────────────────────────────────────────────────────

def run_import_pipeline(
    file_bytes: bytes,
    plan_title: str = '',
    coach=None,
) -> tuple[dict, ConfidenceSummary]:
    grid = excel_to_text(file_bytes)
    raw = extract_workout_with_ai(grid, plan_title)
    normalized = normalize_and_match(raw, coach=coach)
    confidence = compute_confidence(normalized)
    return normalized, confidence
