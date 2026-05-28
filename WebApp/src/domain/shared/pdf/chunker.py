"""Chunk relevant PDF pages for LLM extraction. Domain-neutral.

Accepts pages paired with a meta object exposing `page_type: str` and
`relevance_score: float` (duck-typed: nutrition.PageMeta and workouts.PageMeta
both qualify).
"""

from __future__ import annotations

from dataclasses import dataclass

from .ingestion import PdfPage


# Tuned down from 2500 to 1800: smaller chunks reduce LLM output truncation and
# "laziness" on long lists (the model tends to skip items when the output window
# is wide).
MAX_CHUNK_CHARS = 1800
# Overlap between consecutive chunks of the same page: avoids splitting a logical
# block (e.g. a header in chunk N and its body in chunk N+1).
CHUNK_OVERLAP_CHARS = 400
MAX_CHUNKS_PER_DOC = 30


@dataclass
class Chunk:
    chunk_id: str
    page_number: int
    page_type: str
    relevance_score: float
    text: str


def _split_text(text: str, max_chars: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]
    blocks = [b.strip() for b in text.split('\n\n') if b.strip()]
    if not blocks:
        return [text[i:i + max_chars] for i in range(0, len(text), max_chars)]
    chunks: list[str] = []
    cur = ''
    for b in blocks:
        if len(cur) + len(b) + 2 <= max_chars:
            cur = f"{cur}\n\n{b}" if cur else b
        else:
            if cur:
                chunks.append(cur)
            if len(b) <= max_chars:
                cur = b
            else:
                for i in range(0, len(b), max_chars):
                    chunks.append(b[i:i + max_chars])
                cur = ''
    if cur:
        chunks.append(cur)
    return chunks


def _apply_overlap(parts: list[str], overlap: int) -> list[str]:
    if overlap <= 0 or len(parts) <= 1:
        return parts
    out: list[str] = [parts[0]]
    for i in range(1, len(parts)):
        prev = parts[i - 1]
        tail = prev[-overlap:] if len(prev) > overlap else prev
        ws = tail.find(' ')
        if ws > 0:
            tail = tail[ws + 1:]
        out.append(tail + '\n\n' + parts[i])
    return out


def chunk_pages(pages_with_meta: list[tuple[PdfPage, object]]) -> list[Chunk]:
    """Chunk pages. Each meta must expose `.page_type` and `.relevance_score`."""
    out: list[Chunk] = []
    for page, meta in pages_with_meta:
        text = page.combined_text
        if not text or not text.strip():
            continue
        parts = _split_text(text, MAX_CHUNK_CHARS)
        parts = _apply_overlap(parts, CHUNK_OVERLAP_CHARS)
        for i, part in enumerate(parts):
            chunk_id = f"p{page.page_number}-c{i + 1}"
            out.append(Chunk(
                chunk_id=chunk_id,
                page_number=page.page_number,
                page_type=getattr(meta, 'page_type', 'unknown'),
                relevance_score=float(getattr(meta, 'relevance_score', 0.0) or 0.0),
                text=part,
            ))
            if len(out) >= MAX_CHUNKS_PER_DOC:
                return out
    return out
