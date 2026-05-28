"""Page-by-page classifier for workout PDFs.

Deterministic keyword-based heuristics — same shape as nutrition classifier but
with workout-specific positive signals (sets/reps/load/RPE/exercise families).
"""

from __future__ import annotations

import re

from domain.shared.pdf.ingestion import PdfPage
from domain.shared.pdf import PageMeta  # noqa: F401  (PageMeta re-export)


POSITIVE_KEYWORDS = {
    # Block / set semantics
    'serie', 'series', 'set', 'sets', 'ripetizioni', 'reps', 'rep', 'ripe',
    'superset', 'circuit', 'circuito', 'amrap', 'emom', 'tabata',
    # Intensity
    'rpe', 'rir', 'recupero', 'rest', 'recovery', 'tempo',
    'carico', 'load', 'kg', '1rm', '%1rm', 'percentuale', 'bodyweight', 'bw',
    # Common exercises (canonical and abbreviations)
    'panca', 'squat', 'stacco', 'deadlift', 'rematore', 'lat machine', 'pulldown',
    'pulley', 'pressa', 'leg press', 'leg extension', 'leg curl', 'affondi',
    'curl', 'french press', 'pushdown', 'alzate', 'shoulder', 'overhead',
    'bench', 'bench press', 'row', 'hip thrust', 'glute', 'plank',
    # Day labels
    'lunedì', 'lunedi', 'martedì', 'martedi', 'mercoledì', 'mercoledi',
    'giovedì', 'giovedi', 'venerdì', 'venerdi', 'sabato', 'domenica',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    'push', 'pull', 'legs', 'upper', 'lower', 'full body',
    # Goal / programming
    'ipertrofia', 'forza', 'definizione', 'massa', 'hypertrophy', 'strength',
    'programmazione', 'mesociclo', 'macrociclo', 'deload',
}


NEGATIVE_KEYWORDS = {
    'privacy', 'consenso', 'termini', 'condizioni',
    'studio medico', 'contatti', 'pubblicità', 'pubblicita',
    'copertina', 'indice', 'sommario', 'partita iva', 'codice fiscale',
    'all rights reserved', 'cookie policy', 'liberatoria',
}


PAGE_TYPES = (
    'likely_workout_page',
    'likely_instruction_page',
    'decorative_or_irrelevant',
    'unknown',
)


def _count_keywords(text_lower: str, keywords: set[str]) -> int:
    hits = 0
    for kw in keywords:
        if ' ' in kw:
            if kw in text_lower:
                hits += text_lower.count(kw)
        else:
            hits += len(re.findall(rf'\b{re.escape(kw)}\b', text_lower))
    return hits


# Pattern "4x8", "3 x 10", "4×6": strong workout signal.
_SETS_REPS_RE = re.compile(r'\b\d{1,2}\s*[x×]\s*\d{1,3}\b', flags=re.IGNORECASE)


def classify_page(page: PdfPage) -> PageMeta:
    text = (page.combined_text or '').lower()
    pos = _count_keywords(text, POSITIVE_KEYWORDS)
    neg = _count_keywords(text, NEGATIVE_KEYWORDS)
    sets_reps = len(_SETS_REPS_RE.findall(text))
    pos += sets_reps * 2  # weight the structured pattern strongly
    density = page.text_density

    if neg >= 3 and pos < 2:
        ptype = 'decorative_or_irrelevant'
    elif pos >= 4 or (pos >= 2 and page.likely_has_table) or sets_reps >= 2:
        ptype = 'likely_workout_page'
    elif pos >= 1 and density > 50:
        ptype = 'likely_instruction_page'
    elif density < 20:
        ptype = 'decorative_or_irrelevant'
    else:
        ptype = 'unknown'

    raw = pos - 1.5 * neg
    if ptype == 'likely_workout_page':
        raw += 3
    elif ptype == 'likely_instruction_page':
        raw += 0.5
    score = max(0.0, min(1.0, raw / 10.0))

    return PageMeta(
        page_number=page.page_number,
        page_type=ptype,
        relevance_score=round(score, 3),
        positive_hits=pos,
        negative_hits=neg,
        text_density=density,
        used_ocr=page.used_ocr,
        has_table=page.likely_has_table,
    )


def classify_pages(pages: list[PdfPage]) -> list[PageMeta]:
    return [classify_page(p) for p in pages]


def select_relevant(pages: list[PdfPage], metas: list[PageMeta],
                    min_score: float = 0.08) -> list[tuple[PdfPage, PageMeta]]:
    out: list[tuple[PdfPage, PageMeta]] = []
    for p, m in zip(pages, metas):
        if m.page_type == 'decorative_or_irrelevant':
            continue
        if m.relevance_score < min_score and m.page_type not in (
            'likely_workout_page', 'likely_instruction_page'
        ):
            continue
        out.append((p, m))
    return out
