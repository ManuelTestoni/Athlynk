"""Fuzzy matching of free-text exercise names against the Exercise DB.

Multi-stage:
  1. exact (case/diacritic-insensitive)
  2. normalized (synonyms expanded, qualifiers stripped)
  3. token Jaccard with prefix boost

Returns (best_or_None, top_candidates, confidence, method).
"""

from __future__ import annotations

import re
import unicodedata
from typing import Optional

from django.db.models import Q

from domain.workouts.models import Exercise


# Italian/English exercise synonyms collapse to a canonical token.
# Keys are normalized (lowercase, no diacritics, no punctuation) input tokens.
_SYNONYMS = {
    # Bench press family
    'panca': 'bench', 'panca piana': 'bench press', 'distensioni': 'press',
    'bench': 'bench', 'bp': 'bench press',
    # Squat
    'squat': 'squat', 'back squat': 'back squat', 'front squat': 'front squat',
    'accosciata': 'squat',
    # Deadlift
    'stacco': 'deadlift', 'stacchi': 'deadlift', 'sdl': 'deadlift',
    'rdl': 'romanian deadlift', 'deadlift': 'deadlift',
    # Row
    'rematore': 'row', 'rowing': 'row', 'pulley': 'row',
    'lat machine': 'pulldown', 'pulldown': 'pulldown', 'lat pulldown': 'pulldown',
    # Shoulders
    'military press': 'overhead press', 'ohp': 'overhead press',
    'lento avanti': 'overhead press', 'spinte sopra la testa': 'overhead press',
    'alzate laterali': 'lateral raise', 'laterali': 'lateral raise',
    # Arms
    'curl bilanciere': 'barbell curl', 'curl manubri': 'dumbbell curl',
    'french press': 'skull crusher', 'estensioni tricipiti': 'tricep extension',
    'push down': 'pushdown', 'pushdown': 'pushdown',
    # Legs
    'leg press': 'leg press', 'pressa': 'leg press',
    'leg extension': 'leg extension', 'leg curl': 'leg curl',
    'affondi': 'lunge', 'lunge': 'lunge',
    'hip thrust': 'hip thrust',
    # Cardio
    'corsa': 'running', 'tapis roulant': 'treadmill', 'cyclette': 'bike',
}

# Qualifiers that don't change the movement family — kept as secondary signal.
_QUALIFIERS = {
    'bilanciere', 'manubri', 'manubrio', 'cavi', 'macchina', 'multipower',
    'smith', 'kettlebell', 'bar', 'barbell', 'dumbbell', 'cable', 'machine',
    'presa', 'larga', 'stretta', 'neutra', 'supina', 'prona', 'inversa',
    'inclinata', 'declinata', 'piana', 'flat', 'incline', 'decline',
}

_STOPWORDS = {
    'di', 'da', 'a', 'al', 'il', 'lo', 'la', 'i', 'gli', 'le',
    'un', 'una', 'uno', 'con', 'e', 'o', 'in', 'del', 'della', 'sui',
    'dello', 'dei', 'degli', 'delle', 'allo', 'alla', 'su', 'tra', 'fra',
    'the', 'of', 'on', 'for', 'with', 'and',
}


def _strip_accents(s: str) -> str:
    nfkd = unicodedata.normalize('NFKD', s)
    return ''.join(c for c in nfkd if not unicodedata.combining(c))


def _normalize(name: str) -> str:
    s = _strip_accents((name or '').lower())
    s = re.sub(r'[^\w\s]', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def _expand_synonyms(text: str) -> str:
    # Multi-word synonyms first (longest key first to avoid partial overshadow).
    for k in sorted(_SYNONYMS.keys(), key=len, reverse=True):
        if ' ' in k and k in text:
            text = text.replace(k, _SYNONYMS[k])
    # Single-token replacement
    tokens = [_SYNONYMS.get(t, t) for t in text.split()]
    return ' '.join(tokens)


def _tokenize(name: str) -> tuple[list[str], list[str]]:
    """Return (core_tokens, qualifier_tokens). Stopwords dropped."""
    norm = _expand_synonyms(_normalize(name))
    core: list[str] = []
    quals: list[str] = []
    for t in norm.split():
        if not t or t in _STOPWORDS or len(t) <= 1:
            continue
        if t in _QUALIFIERS:
            quals.append(t)
        else:
            core.append(t)
    return core, quals


def fuzzy_match_exercise(
    name: str,
    coach=None,
    limit: int = 5,
) -> list[dict]:
    """Score Exercise rows against `name`. Returns ranked candidates.

    Restricts custom exercises to the requesting coach (or excludes all custom
    if no coach context). Score 0..1 with prefix/exact boosts.
    """
    if not name or not name.strip():
        return []
    core, quals = _tokenize(name)
    if not core:
        return []

    # SQL prefilter: any token matches name (icontains on first 5 chars to cover
    # singular/plural and minor typos).
    q = Q()
    for t in core:
        root = t[:max(4, len(t) - 1)]
        q |= Q(name__icontains=root)
    qs = Exercise.objects.filter(q)
    if coach is not None:
        qs = qs.filter(Q(is_custom=False) | Q(created_by=coach))
    else:
        qs = qs.filter(is_custom=False)
    qs = qs.distinct()[:80]

    candidates = list(qs)
    name_norm = _normalize(name)
    name_expanded = _expand_synonyms(name_norm)
    core_set = set(core)
    quals_set = set(quals)

    scored: list[tuple[float, Exercise]] = []
    for ex in candidates:
        ex_norm = _normalize(ex.name)
        ex_expanded = _expand_synonyms(ex_norm)
        ex_core, ex_quals = _tokenize(ex.name)
        ex_core_set = set(ex_core)
        if not ex_core_set:
            continue
        intersect = core_set & ex_core_set
        union = core_set | ex_core_set
        jaccard = len(intersect) / max(len(union), 1)
        # base
        score = jaccard
        # all query core tokens present → strong signal
        if core_set and core_set.issubset(ex_core_set):
            score += 0.35
        # qualifier match → small bonus
        if quals_set & set(ex_quals):
            score += 0.05
        # prefix boost
        if ex_expanded.startswith(name_expanded) or name_expanded.startswith(ex_expanded):
            score += 0.20
        # exact (post-normalization)
        if ex_norm == name_norm or ex_expanded == name_expanded:
            score = 1.0
        scored.append((min(score, 1.0), ex))

    scored.sort(key=lambda t: t[0], reverse=True)

    out: list[dict] = []
    for score, ex in scored[:limit]:
        out.append({
            'id': ex.id,
            'name': ex.name,
            'is_custom': ex.is_custom,
            'equipment': ex.equipment or '',
            'primary_muscle': ex.primary_muscle or '',
            'target_muscle_group': ex.target_muscle_group or '',
            'cover_image': ex.cover_image.url if ex.cover_image else '',
            'score': round(float(score), 3),
        })
    return out


def best_match(
    name: str,
    coach=None,
    threshold: float = 0.55,
) -> tuple[Optional[dict], list[dict], str, str]:
    """Return (best_or_None, others, confidence_bucket, method).

    confidence_bucket ∈ {'exact','high','medium','low','none'}.
    method ∈ {'exact','normalized','fuzzy','none'}.
    """
    cands = fuzzy_match_exercise(name, coach=coach, limit=5)
    if not cands:
        return None, [], 'none', 'none'
    top = cands[0]
    score = top['score']
    if score >= 0.999:
        return top, cands[1:], 'exact', 'exact'
    if score >= 0.85:
        return top, cands[1:], 'high', 'normalized'
    if score >= threshold:
        return top, cands[1:], 'medium', 'fuzzy'
    if score >= 0.30:
        return None, cands, 'low', 'fuzzy'
    return None, cands, 'none', 'none'
