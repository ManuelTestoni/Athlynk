"""Chunking delle sole pagine rilevanti per estrazione LLM chunk-by-chunk."""

from __future__ import annotations

from dataclasses import dataclass

from domain.nutrition.pdf_ingestion import PdfPage
from domain.nutrition.pdf_page_classifier import PageMeta


# Max char per chunk: bilanciamento tra contesto utile e token spesi.
# Ridotto da 2500 a 1800: chunk più piccoli → meno truncation della risposta LLM
# e meno "laziness" su elenchi lunghi (l'LLM tende a saltare item se la
# finestra di output è ampia).
MAX_CHUNK_CHARS = 1800
# Overlap fra chunk consecutivi della stessa pagina: evita di tagliare un pasto
# a metà fra due chunk (es. header "Pranzo" finisce nel chunk N e foods nel N+1).
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


def _apply_overlap(parts: list[str], overlap: int) -> list[str]:
    """Prepende a ogni chunk N>0 la coda del chunk N-1 (max `overlap` char).
    Mantiene su un boundary di whitespace per non spezzare parole.
    """
    if overlap <= 0 or len(parts) <= 1:
        return parts
    out: list[str] = [parts[0]]
    for i in range(1, len(parts)):
        prev = parts[i - 1]
        tail = prev[-overlap:] if len(prev) > overlap else prev
        # taglia al primo whitespace per non spezzare token
        ws = tail.find(' ')
        if ws > 0:
            tail = tail[ws + 1:]
        out.append(tail + '\n\n' + parts[i])
    return out


def chunk_pages(pages_with_meta: list[tuple[PdfPage, PageMeta]]) -> list[Chunk]:
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
                page_type=meta.page_type,
                relevance_score=meta.relevance_score,
                text=part,
            ))
            if len(out) >= MAX_CHUNKS_PER_DOC:
                return out
    return out
