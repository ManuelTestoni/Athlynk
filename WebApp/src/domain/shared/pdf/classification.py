"""Shared page-classification type. Domain-neutral.

`PageMeta` is the per-page result produced by each domain's classifier and
consumed (duck-typed) by `chunker.chunk_pages`. Kept here as the single source
of truth so nutrition and workouts cannot drift. The classification *logic*
(keywords, regex heuristics) stays domain-specific in each app.
"""

from dataclasses import dataclass


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
