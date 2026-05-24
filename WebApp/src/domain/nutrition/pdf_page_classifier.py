"""Classificazione pagina-per-pagina del PDF dieta.

Logica deterministica keyword-based (zero chiamate LLM) per decidere quali
pagine inviare al modello AI. Riduce drasticamente il consumo di token.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from domain.nutrition.pdf_ingestion import PdfPage


# Keyword positive — segnali tipici di una pagina-dieta.
POSITIVE_KEYWORDS = {
    # pasti
    'colazione', 'pranzo', 'cena', 'spuntino', 'merenda',
    'breakfast', 'lunch', 'dinner', 'snack',
    # giorni
    'lunedì', 'lunedi', 'martedì', 'martedi', 'mercoledì', 'mercoledi',
    'giovedì', 'giovedi', 'venerdì', 'venerdi', 'sabato', 'domenica',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    # nutrienti / unità
    'kcal', 'calorie', 'proteine', 'carboidrati', 'grassi', 'lipidi',
    'grammi', 'porzione', 'quantità', 'quantita',
}

# Keyword negative — pagine quasi sicuramente irrilevanti.
NEGATIVE_KEYWORDS = {
    'privacy', 'consenso', 'termini', 'condizioni',
    'studio medico', 'contatti', 'pubblicità', 'pubblicita',
    'copertina', 'indice', 'sommario', 'partita iva', 'codice fiscale',
    'all rights reserved', 'cookie policy',
}


PAGE_TYPES = (
    'likely_diet_page',
    'likely_instruction_page',
    'decorative_or_irrelevant',
    'unknown',
)


@dataclass
class PageMeta:
    page_number: int
    page_type: str
    relevance_score: float       # 0..1
    positive_hits: int
    negative_hits: int
    text_density: float
    used_ocr: bool
    has_table: bool


_WORD_RE = re.compile(r"[a-zàèéìòùA-ZÀÈÉÌÒÙ]+")


def _count_keywords(text_lower: str, keywords: set[str]) -> int:
    """Conta occorrenze keyword (substring match per multi-word, word match singole)."""
    hits = 0
    for kw in keywords:
        if ' ' in kw:
            if kw in text_lower:
                hits += text_lower.count(kw)
        else:
            # word-boundary match approssimato
            hits += len(re.findall(rf'\b{re.escape(kw)}\b', text_lower))
    return hits


def classify_page(page: PdfPage) -> PageMeta:
    text = (page.combined_text or '').lower()
    pos = _count_keywords(text, POSITIVE_KEYWORDS)
    neg = _count_keywords(text, NEGATIVE_KEYWORDS)
    density = page.text_density

    # Page type
    if neg >= 3 and pos < 2:
        ptype = 'decorative_or_irrelevant'
    elif pos >= 4 or (pos >= 2 and page.likely_has_table):
        ptype = 'likely_diet_page'
    elif pos >= 1 and density > 50:
        ptype = 'likely_instruction_page'
    elif density < 20:
        ptype = 'decorative_or_irrelevant'
    else:
        ptype = 'unknown'

    # Score normalizzato
    raw = pos - 1.5 * neg
    if ptype == 'likely_diet_page':
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
                    min_score: float = 0.15) -> list[tuple[PdfPage, PageMeta]]:
    """Filtra pagine candidate per estrazione AI."""
    out: list[tuple[PdfPage, PageMeta]] = []
    for p, m in zip(pages, metas):
        if m.page_type == 'decorative_or_irrelevant':
            continue
        if m.relevance_score < min_score and m.page_type != 'likely_diet_page':
            continue
        out.append((p, m))
    return out
