"""Deterministic document-structure detection (no LLM).

Runs on the full document text BEFORE extraction. The document *type*
(workout vs nutrition) is already known from the import entry point; the
detector only infers the layout profile, which the pipeline uses to pick
prompt hints, chunk split points and (nutrition) the MACRO fast path.

# ponytail: regex heuristics, not a parser — the coach can override the
# inferred shape in the review UI, so false positives are recoverable.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class DocStructure:
    # workout: 'single_week' | 'multi_week_columns' | 'unknown'
    # nutrition: 'food_weekly' | 'food_daily' | 'macro_daily' | 'macro_weekly' | 'unknown'
    layout: str = 'unknown'
    week_count: int | None = None
    day_tokens: list[str] = field(default_factory=list)
    has_superset_shorthand: bool = False
    session_header_spans: list[int] = field(default_factory=list)


_WEEK_RE = re.compile(
    r'(?:settimana|week|sett\.?|microciclo)\s*(\d{1,2})|\bW(\d{1,2})\b',
    re.IGNORECASE,
)

_DAY_RE = re.compile(
    r'\b(luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica'
    r'|lun|mar|mer|gio|ven|sab|dom'
    r'|monday|tuesday|wednesday|thursday|friday|saturday|sunday'
    r'|giorno\s*[1-7a-g])\b',
    re.IGNORECASE,
)

_SS_RE = re.compile(
    r'(?:^|\s)(?:ss\b|superset|super\s*set|[A-D][1-9][\s.)\-]|[1-9][a-dA-D][\s.)\-])',
    re.IGNORECASE | re.MULTILINE,
)

# Session/day headers used as preferred chunk split points (public: the
# PDF chunker uses it to keep a header and its table in the same chunk).
SESSION_HEADER_RE = re.compile(
    r'^[^\S\n]*(?:giorno\s*\w+|luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]'
    r'|venerd[iì]|sabato|domenica|day\s*\w+|sessione\s*\w*|workout\s*[A-Z\d]'
    r'|push|pull|legs|upper|lower|full\s*body)\b.{0,40}$',
    re.IGNORECASE | re.MULTILINE,
)

# Nutrition: macro keyword-number pairs vs food-quantity lines.
_MACRO_HIT_RE = re.compile(
    r'(?:kcal|calorie|prote\w*|carboidrati|carbo\b|cho\b|grassi|lipidi|fat)'
    r'\s*(?:tot\w*|giornalier\w*)?\s*[:=]?\s*\d',
    re.IGNORECASE,
)
_FOOD_QTY_RE = re.compile(
    r'\b\d{1,4}\s*(?:g|gr|grammi|ml)\b(?![^\n]*(?:prote|carbo|grassi|kcal))',
    re.IGNORECASE,
)


def _distinct_week_numbers(text: str) -> set[int]:
    weeks: set[int] = set()
    for m in _WEEK_RE.finditer(text):
        num = m.group(1) or m.group(2)
        try:
            n = int(num)
        except (TypeError, ValueError):
            continue
        if 1 <= n <= 52:
            weeks.add(n)
    return weeks


def _distinct_day_tokens(text: str) -> list[str]:
    seen: dict[str, None] = {}
    for m in _DAY_RE.finditer(text):
        seen.setdefault(m.group(0).lower(), None)
    return list(seen)


def _header_spans(text: str) -> list[int]:
    return [m.start() for m in SESSION_HEADER_RE.finditer(text)]


def detect_workout_structure(text: str) -> DocStructure:
    text = text or ''
    weeks = _distinct_week_numbers(text)
    week_count = max(weeks) if weeks else None
    layout = 'multi_week_columns' if len(weeks) >= 2 else 'single_week'
    return DocStructure(
        layout=layout,
        week_count=week_count,
        day_tokens=_distinct_day_tokens(text),
        has_superset_shorthand=bool(_SS_RE.search(text)),
        session_header_spans=_header_spans(text),
    )


def detect_diet_structure(text: str) -> DocStructure:
    text = text or ''
    day_tokens = _distinct_day_tokens(text)
    macro_hits = len(_MACRO_HIT_RE.findall(text))
    food_lines = len(_FOOD_QTY_RE.findall(text))
    # Macro-only plan: macro numbers dominate and almost no food quantities.
    is_macro = macro_hits >= 3 and food_lines <= max(2, macro_hits // 4)
    weekly = len(day_tokens) >= 2
    if is_macro:
        layout = 'macro_weekly' if weekly else 'macro_daily'
    else:
        layout = 'food_weekly' if weekly else 'food_daily'
    return DocStructure(
        layout=layout,
        week_count=None,
        day_tokens=day_tokens,
        has_superset_shorthand=False,
        session_header_spans=_header_spans(text),
    )
