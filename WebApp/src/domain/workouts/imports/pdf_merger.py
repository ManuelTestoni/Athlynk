"""Merge per-chunk extraction parts into a single WorkoutExtraction-shaped dict.

Strategy:
- group sessions by `day_label` (case/space-insensitive); fall back to `day_of_week`
- within a session, blocks are kept ordered by appearance; exercises deduped by
  raw_name within the same block (same name in different blocks remains distinct)
- preserve source_page/source_chunk of the first occurrence
"""

from __future__ import annotations

import re


def _norm(s: str) -> str:
    s = (s or '').strip().lower()
    return re.sub(r'\s+', ' ', s)


def _session_key(session: dict) -> str:
    """Identify same logical session across chunks."""
    label = _norm(session.get('day_label') or '')
    dow = (session.get('day_of_week') or '').strip().upper()
    return label or dow or 'unknown'


def _block_key(block: dict) -> str:
    name = _norm(block.get('block_name') or '')
    btype = (block.get('block_type') or 'straight').strip().lower()
    return f'{btype}::{name}'


def merge_chunks(parts: list[dict],
                 document_summary: dict | None = None,
                 extra_notes: list[str] | None = None,
                 plan_name: str | None = None) -> dict:
    """Return a dict shaped like WorkoutExtraction (pydantic-validatable)."""
    sessions_map: dict[str, dict] = {}
    session_order: list[str] = []

    plan_meta = {
        'plan_name': plan_name or None,
        'frequency_per_week': None,
        'goal': None,
        'notes': None,
    }

    for part in parts or []:
        # Capture top-level metadata if found
        if not plan_meta['plan_name'] and part.get('plan_name'):
            plan_meta['plan_name'] = str(part['plan_name']).strip() or None
        if plan_meta['frequency_per_week'] is None and part.get('frequency_per_week'):
            try:
                plan_meta['frequency_per_week'] = int(part['frequency_per_week'])
            except (TypeError, ValueError):
                pass
        if not plan_meta['goal'] and part.get('goal'):
            plan_meta['goal'] = str(part['goal']).strip() or None
        if not plan_meta['notes'] and part.get('notes'):
            plan_meta['notes'] = str(part['notes']).strip() or None

        for sess in (part.get('sessions') or []):
            skey = _session_key(sess)
            if skey not in sessions_map:
                session_order.append(skey)
                sessions_map[skey] = {
                    'day_label': sess.get('day_label') or skey.title(),
                    'day_of_week': sess.get('day_of_week'),
                    'session_type': sess.get('session_type'),
                    'order_index': len(session_order) - 1,
                    'notes': sess.get('notes'),
                    '_blocks_map': {},
                    '_block_order': [],
                    'blocks': [],
                }
            entry = sessions_map[skey]
            if not entry.get('day_of_week') and sess.get('day_of_week'):
                entry['day_of_week'] = sess['day_of_week']
            if not entry.get('session_type') and sess.get('session_type'):
                entry['session_type'] = sess['session_type']
            if not entry.get('notes') and sess.get('notes'):
                entry['notes'] = sess['notes']

            for block in (sess.get('blocks') or []):
                bkey = _block_key(block)
                if bkey not in entry['_blocks_map']:
                    entry['_block_order'].append(bkey)
                    entry['_blocks_map'][bkey] = {
                        'block_name': block.get('block_name'),
                        'block_type': (block.get('block_type') or 'straight') or 'straight',
                        '_seen_exercises': set(),
                        'exercises': [],
                    }
                bucket = entry['_blocks_map'][bkey]
                for ex in (block.get('exercises') or []):
                    raw = (ex.get('raw_name') or '').strip()
                    if not raw:
                        continue
                    ex_key = _norm(raw)
                    if ex_key in bucket['_seen_exercises']:
                        continue
                    bucket['_seen_exercises'].add(ex_key)
                    bucket['exercises'].append({
                        'raw_name': raw,
                        'sets': ex.get('sets'),
                        'reps': ex.get('reps'),
                        'reps_type': ex.get('reps_type'),
                        'load': ex.get('load'),
                        'load_unit': ex.get('load_unit'),
                        'load_type': ex.get('load_type'),
                        'rpe': ex.get('rpe'),
                        'rir': ex.get('rir'),
                        'tempo': ex.get('tempo'),
                        'rest_seconds': ex.get('rest_seconds'),
                        'rest_label': ex.get('rest_label'),
                        'distance': ex.get('distance'),
                        'distance_unit': ex.get('distance_unit'),
                        'duration_seconds': ex.get('duration_seconds'),
                        'notes': ex.get('notes'),
                        'uncertain': bool(ex.get('uncertain', False)),
                        'source_page': ex.get('source_page'),
                        'source_chunk': ex.get('source_chunk'),
                    })

    sessions_out = []
    for s_idx, skey in enumerate(session_order):
        entry = sessions_map[skey]
        blocks_out = []
        for bkey in entry['_block_order']:
            b = entry['_blocks_map'][bkey]
            b.pop('_seen_exercises', None)
            blocks_out.append(b)
        sessions_out.append({
            'day_label': entry['day_label'],
            'day_of_week': entry.get('day_of_week'),
            'session_type': entry.get('session_type'),
            'order_index': s_idx,
            'notes': entry.get('notes'),
            'blocks': blocks_out,
        })

    notes_collected: list[str] = []
    for part in parts or []:
        en = part.get('extraction_notes')
        if isinstance(en, str) and en.strip():
            notes_collected.append(en.strip())
        elif isinstance(en, list):
            notes_collected.extend([str(x).strip() for x in en if x])
    if extra_notes:
        notes_collected.extend([n for n in extra_notes if n])

    out = {
        **plan_meta,
        'sessions': sessions_out,
        'extraction_notes': notes_collected,
    }
    if document_summary:
        out['document_summary'] = document_summary
    return out
