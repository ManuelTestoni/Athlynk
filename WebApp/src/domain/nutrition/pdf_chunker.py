"""Chunking delle sole pagine rilevanti per estrazione LLM chunk-by-chunk."""

from __future__ import annotations

from dataclasses import dataclass

from domain.nutrition.pdf_ingestion import PdfPage
from domain.nutrition.pdf_page_classifier import PageMeta


# Max char per chunk: bilanciamento tra contesto utile e token spesi
MAX_CHUNK_CHARS = 2500
MAX_CHUNKS_PER_DOC = 25


@dataclass
class Chunk:
    chunk_id: str
    page_number: int
    page_type: str
    relevance_score: float
    text: str


def _split_text(text: str, max_chars: int) -> list[str]:
    """Split semplice: prima per double-newline, poi accorpa fino a max_chars."""
    if len(text) <= max_chars:
        return [text]
    blocks = [b.strip() for b in text.split('\n\n') if b.strip()]
    if not blocks:
        # fallback: split a finestra fissa
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
                # blocco gigante: split a finestra
                for i in range(0, len(b), max_chars):
                    chunks.append(b[i:i + max_chars])
                cur = ''
    if cur:
        chunks.append(cur)
    return chunks


def chunk_pages(pages_with_meta: list[tuple[PdfPage, PageMeta]]) -> list[Chunk]:
    out: list[Chunk] = []
    for page, meta in pages_with_meta:
        text = page.combined_text
        if not text or not text.strip():
            continue
        parts = _split_text(text, MAX_CHUNK_CHARS)
        for i, part in enumerate(parts):
            chunk_id = f"p{page.page_number}-c{i + 1}"
            out.append(Chunk(
                chunk_id=chunk_id,
                page_number=page.page_number,
                page_type=meta.page_type,
                relevance_score=meta.relevance_score,
                text=part,
            ))
            if len(out) >= MAX_CHUNKS_PER_DOC:
                return out
    return out
