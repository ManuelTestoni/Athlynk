"""LLM extraction chunk-by-chunk for workout PDFs.

Returns parts (list of dicts conforming to chunk schema) + notes. Raises
AIExtractionError only if every chunk fails.
"""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor

from langchain_core.messages import SystemMessage, HumanMessage

from domain.shared.extraction import AIExtractionError  # noqa: F401  (re-export)
from domain.shared.llm_extraction import build_extraction_llm
from domain.shared.pdf.chunker import Chunk
from domain.workouts.imports.prompts import CHUNK_SYSTEM_PROMPT

# LLM calls are I/O-bound; the pipeline already runs in a background thread.
# ponytail: cap 3 workers to stay friendly with Ollama Cloud rate limits.
MAX_PARALLEL_CHUNKS = 3


def _annotate_provenance(raw: dict, chunk: Chunk) -> dict:
    for session in raw.get('sessions') or []:
        for block in session.get('blocks') or []:
            for ex in block.get('exercises') or []:
                ex.setdefault('source_page', chunk.page_number)
                ex.setdefault('source_chunk', chunk.chunk_id)
    return raw


def extract_chunk(chunk: Chunk, llm=None, suffix: str = '') -> dict:
    if llm is None:
        llm = build_extraction_llm(max_tokens=4000, timeout=45)
    user_msg = (
        f"Metadata chunk:\n"
        f"- page_number: {chunk.page_number}\n"
        f"- chunk_id: {chunk.chunk_id}\n"
        f"- page_type: {chunk.page_type}\n"
        f"- relevance_score: {chunk.relevance_score}\n\n"
        f"Testo del chunk:\n{chunk.text}\n\n"
        f"Restituisci SOLO JSON conforme allo schema."
    )
    try:
        resp = llm.invoke([
            SystemMessage(content=CHUNK_SYSTEM_PROMPT + suffix),
            HumanMessage(content=user_msg),
        ])
    except Exception as e:
        return {'sessions': [], 'extraction_notes': [f'chunk {chunk.chunk_id} LLM error: {e}']}
    content = resp.content if isinstance(resp.content, str) else str(resp.content)
    try:
        raw = json.loads(content)
    except json.JSONDecodeError:
        return {'sessions': [], 'extraction_notes': [f'chunk {chunk.chunk_id} JSON invalido']}
    return _annotate_provenance(raw, chunk)


RETRY_EMPTY_RELEVANCE_THRESHOLD = 0.5
RETRY_SUFFIX = (
    "\n\nRETRY ESAUSTIVO: la passata precedente non ha estratto sessioni da "
    "questo chunk nonostante sia rilevante. Sii MASSIMAMENTE esaustivo: scorri "
    "il testo riga per riga, estrai OGNI esercizio con sets/reps/load/recupero "
    "presente. Se il chunk contiene anche solo un'intestazione di giorno o "
    "blocco, emetti la struttura corrispondente."
)


def extract_all_chunks(
    chunks: list[Chunk],
    progress_cb=None,
    hints: str = '',
) -> tuple[list[dict], list[str]]:
    llm = build_extraction_llm(max_tokens=4000, timeout=45)
    notes: list[str] = []
    n = len(chunks) or 1

    done = 0

    def _tick(total: int):
        nonlocal done
        done += 1
        if progress_cb:
            try:
                progress_cb(done, total)
            except Exception:
                pass

    def _run(chunk: Chunk) -> dict:
        result = extract_chunk(chunk, llm=llm, suffix=hints)
        _tick(n)
        return result

    with ThreadPoolExecutor(max_workers=MAX_PARALLEL_CHUNKS) as pool:
        parts: list[dict] = list(pool.map(_run, chunks))

    failed = 0
    empty_high_relevance: list[tuple[int, Chunk]] = []
    for i, (chunk, result) in enumerate(zip(chunks, parts)):
        chunk_notes = result.get('extraction_notes') or []
        if isinstance(chunk_notes, str):
            chunk_notes = [chunk_notes]
        notes.extend(chunk_notes)
        if not result.get('sessions'):
            failed += 1
            if chunk.relevance_score >= RETRY_EMPTY_RELEVANCE_THRESHOLD:
                empty_high_relevance.append((i, chunk))

    if empty_high_relevance:
        retry_llm = build_extraction_llm(max_tokens=4000, timeout=60)
        total = n + len(empty_high_relevance)

        def _retry(item: tuple[int, Chunk]) -> tuple[int, dict]:
            _, chunk = item
            result = extract_chunk(chunk, llm=retry_llm, suffix=hints + RETRY_SUFFIX)
            _tick(total)
            return item[0], result

        with ThreadPoolExecutor(max_workers=MAX_PARALLEL_CHUNKS) as pool:
            retries = list(pool.map(_retry, empty_high_relevance))
        for _, retry in retries:
            if retry.get('sessions'):
                parts.append(retry)
                notes.append('retry: recuperato')
            elif retry.get('extraction_notes'):
                rn = retry['extraction_notes']
                notes.extend([rn] if isinstance(rn, str) else rn)

    if chunks and failed == len(chunks):
        if not any(p.get('sessions') for p in parts):
            raise AIExtractionError("Nessun chunk ha prodotto contenuto utile.")
    return parts, notes
