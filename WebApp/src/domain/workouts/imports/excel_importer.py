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

from domain.shared.doc_structure import DocStructure, detect_workout_structure
from domain.shared.excel_text import excel_to_text, ExcelParseError  # noqa: F401  (re-export)
from domain.shared.extraction import AIExtractionError  # noqa: F401  (re-export)
from domain.shared.llm_extraction import build_extraction_llm
from domain.workouts.imports.exercise_match import best_match
from domain.workouts.imports.prompts import (
    EXCEL_SYSTEM_PROMPT, SET_DETAILS_HINT, SUPERSET_HINT, weeks_hint,
)
from domain.workouts.imports.schemas import ConfidenceSummary, WorkoutExtraction


# ─── AI extraction ──────────────────────────────────────────────────────

def build_prompt_hints(structure: Optional[DocStructure]) -> str:
    """Composable suffixes appended to the base prompts per detected structure."""
    hints = SET_DETAILS_HINT + SUPERSET_HINT
    if structure and structure.week_count and structure.week_count >= 2:
        hints += weeks_hint(structure.week_count)
    return hints


def extract_workout_with_ai(
    grid_text: str,
    plan_title: str = '',
    structure: Optional[DocStructure] = None,
) -> dict:
    llm = build_extraction_llm()
    user_msg = (
        f"Titolo piano (suggerito dal coach): {plan_title or 'non specificato'}\n\n"
        f"Contenuto Excel:\n{grid_text}\n\n"
        f"Restituisci SOLO il JSON conforme allo schema."
    )
    try:
        resp = llm.invoke([
            SystemMessage(content=EXCEL_SYSTEM_PROMPT + build_prompt_hints(structure)),
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


# Shorthand superset notation: "ss Croci", "A1. Panca", "1a) Curl".
_SS_PREFIX_RE = re.compile(r'^\s*(?:ss|superset)[\s.:\-)]+', re.IGNORECASE)
_LETTER_NUM_RE = re.compile(r'^\s*([A-Da-d])([1-9])[\s.)\-]+')
_NUM_LETTER_RE = re.compile(r'^\s*([1-9])([a-dA-D])[\s.)\-]+')


def _shorthand_key(raw: str) -> tuple[Optional[str], bool]:
    """Returns (group_key, is_ss_marker) for a raw exercise name."""
    m = _LETTER_NUM_RE.match(raw)
    if m:
        return m.group(1).upper(), False
    m = _NUM_LETTER_RE.match(raw)
    if m:
        return m.group(1), False
    return None, bool(_SS_PREFIX_RE.match(raw))


def _strip_shorthand_prefix(ex: dict) -> None:
    for field in ('raw_name', 'name_en'):
        val = ex.get(field)
        if not val:
            continue
        stripped = _SS_PREFIX_RE.sub('', val)
        stripped = _LETTER_NUM_RE.sub('', stripped)
        stripped = _NUM_LETTER_RE.sub('', stripped)
        if stripped.strip():
            ex[field] = stripped.strip()


def _regroup_shorthand_supersets(session: dict) -> None:
    """Deterministic fallback: group consecutive shorthand-marked exercises
    into superset blocks and strip the prefix before DB matching.
    Prompt-first; this is the safety net when the LLM misses "ss"/"A1-A2"."""
    new_blocks: list[dict] = []
    for block in session.get('blocks') or []:
        exercises = block.get('exercises') or []
        if (block.get('block_type') or 'straight') != 'straight' or len(exercises) < 2:
            for ex in exercises:
                _strip_shorthand_prefix(ex)
            new_blocks.append(block)
            continue
        # groups: {'key': str|None, 'ss': bool, 'items': [ex]}
        groups: list[dict] = []
        for ex in exercises:
            raw = ex.get('raw_name') or ''
            key, is_ss = _shorthand_key(raw)
            _strip_shorthand_prefix(ex)
            if key is not None and groups and groups[-1]['key'] == key:
                groups[-1]['items'].append(ex)
            elif is_ss and groups:
                groups[-1]['ss'] = True
                groups[-1]['items'].append(ex)
            else:
                groups.append({'key': key, 'ss': False, 'items': [ex]})
        if all(len(g['items']) == 1 and not g['ss'] for g in groups):
            new_blocks.append(block)
            continue
        for g in groups:
            is_superset = len(g['items']) > 1 and (g['ss'] or g['key'] is not None)
            new_blocks.append({
                **{k: v for k, v in block.items() if k != 'exercises'},
                'block_type': 'superset' if is_superset else block.get('block_type'),
                'exercises': g['items'],
            })
    session['blocks'] = new_blocks


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
        _regroup_shorthand_supersets(session)
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
    structure = detect_workout_structure(grid)
    raw = extract_workout_with_ai(grid, plan_title, structure=structure)
    normalized = normalize_and_match(raw, coach=coach)
    confidence = compute_confidence(normalized)
    return normalized, confidence
