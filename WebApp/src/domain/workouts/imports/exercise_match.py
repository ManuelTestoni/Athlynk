"""Fuzzy matching of free-text exercise names against the Exercise DB.

Multi-stage:
  1. exact (case/diacritic-insensitive)
  2. normalized (synonyms expanded, qualifiers stripped)
  3. token Jaccard with prefix boost, arbitrated by equipment

Returns (best_or_None, top_candidates, confidence, method).

The catalogue is sourced from an English dataset, so `Exercise.name` is English
("barbell bench press") while coaches upload Italian documents ("panca piana con
bilanciere"). Two bridges cross that gap:

- the extractor emits `name_en` alongside the verbatim `raw_name` (see
  `imports/prompts.py`); we score both and keep the better hit;
- equipment words are matched through `Equipment.name_it`, which is already a
  curated Italian vocabulary ("Bilanciere", "Manubrio", "Cavo", "Corpo libero").

Equipment is an *arbiter*, not a bonus. Almost every movement exists in the
catalogue once per implement, so "panca piana con bilanciere" is one token away
from "band bench press"; without weighing the implement the matcher used to
return that at full confidence — a silently wrong match the coach never gets
asked to review, which is worse than no match at all.
"""

from __future__ import annotations

import re
import unicodedata
from functools import lru_cache
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
# The implement words among these are ALSO routed through _requested_equipment()
# below, which is what actually decides between same-movement variants.
_QUALIFIERS = {
    'bilanciere', 'manubri', 'manubrio', 'cavi', 'cavo', 'macchina', 'multipower',
    'smith', 'kettlebell', 'bar', 'barbell', 'dumbbell', 'cable', 'machine',
    'band', 'lever', 'leverage', 'assisted', 'sled', 'ez', 'elastico', 'elastici',
    'sbarra', 'corpo', 'libero', 'bodyweight',
    'presa', 'larga', 'stretta', 'neutra', 'supina', 'prona', 'inversa',
    'inclinata', 'declinata', 'piana', 'flat', 'incline', 'decline',
}

# Italian (and colloquial) implement words → the canonical `Equipment.name_it`
# already stored in the DB. Only forms that differ from the stored label need an
# entry here; exact matches on `name_it` are resolved dynamically.
_EQUIP_ALIASES = {
    'manubri': 'Manubrio', 'manubrio': 'Manubrio', 'dumbbell': 'Manubrio',
    'bilanciere': 'Bilanciere', 'barbell': 'Bilanciere', 'bilancere': 'Bilanciere',
    'ez': 'Bilanciere EZ',
    'cavi': 'Cavo', 'cavo': 'Cavo', 'cable': 'Cavo', 'pulley': 'Cavo',
    'elastico': 'Elastico', 'elastici': 'Elastico', 'band': 'Elastico',
    'kettlebell': 'Kettlebell',
    'macchina': 'Macchina a leva', 'machine': 'Macchina a leva',
    'lever': 'Macchina a leva', 'leverage': 'Macchina a leva',
    'assisted': 'Assistito', 'assistito': 'Assistito',
    'corpo libero': 'Corpo libero', 'bodyweight': 'Corpo libero',
    'smith': 'Smith machine', 'multipower': 'Smith machine',
    'trap bar': 'Trap bar', 'zavorrato': 'Zavorrato', 'weighted': 'Zavorrato',
}
# Deliberately absent: 'panca' (in "panca piana" it names the *movement*, bench
# press, not the bench) and 'sbarra'/'trazioni' — the catalogue files pull-ups
# under 'Corpo libero', so demanding a pull-up bar would reject every real hit.

# How many rows the SQL prefilter may hand to the Python scorer, per tier.
CANDIDATE_POOL = 200

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


@lru_cache(maxsize=1)
def _equipment_by_label() -> dict[str, int]:
    """`Equipment.name_it` (normalized) → id. Cached: the taxonomy is static."""
    from domain.workouts.models import Equipment
    out: dict[str, int] = {}
    for eq_id, name_it in Equipment.objects.values_list('id', 'name_it'):
        if name_it:
            out[_normalize(name_it)] = eq_id
    return out


def _requested_equipment(raw: str) -> set[int]:
    """Equipment ids named by the free text. Empty when the coach didn't say."""
    norm = _normalize(raw)
    by_label = _equipment_by_label()
    found: set[int] = set()

    # Multi-word labels first ("corpo libero" before "corpo"/"libero").
    for phrase, label in _EQUIP_ALIASES.items():
        if ' ' in phrase and phrase in norm:
            eq_id = by_label.get(_normalize(label))
            if eq_id:
                found.add(eq_id)
    for token in norm.split():
        label = _EQUIP_ALIASES.get(token)
        if label:
            eq_id = by_label.get(_normalize(label))
            if eq_id:
                found.add(eq_id)
        elif token in by_label:          # the stored label used verbatim
            found.add(by_label[token])
    return found


def _alias_list(ex: Exercise) -> list[str]:
    raw = ex.aliases
    if isinstance(raw, list):
        return [str(a) for a in raw if a]
    if isinstance(raw, str) and raw.strip():
        return [raw]
    return []


def fuzzy_match_exercise(
    name: str,
    coach=None,
    limit: int = 5,
    equipment_hint: set[int] | None = None,
) -> list[dict]:
    """Score Exercise rows against `name`. Returns ranked candidates.

    Restricts custom exercises to the requesting coach (or excludes all custom
    if no coach context). Score 0..1 with prefix/exact boosts.

    `equipment_hint` overrides the implement inferred from `name`. It exists so a
    translated query can be scored on its own clean text while still being
    arbitrated by the implement named in the Italian original.
    """
    if not name or not name.strip():
        return []
    core, quals = _tokenize(name)
    if not core:
        return []

    # SQL prefilter, narrow first. A pure OR over token roots matches hundreds of
    # rows in a 1200-exercise catalogue ("press" alone matches ~200), and the
    # truncation that follows would then drop the right row before scoring ever
    # sees it. So: rows containing EVERY token first, topped up with the OR set
    # only if that leaves room.
    def _token_q(root: str) -> Q:
        return Q(name__icontains=root) | Q(aliases__icontains=root)

    roots = [t[:max(4, len(t) - 1)] for t in core]

    def _scoped(qs):
        if coach is not None:
            qs = qs.filter(Q(is_custom=False) | Q(created_by=coach))
        else:
            qs = qs.filter(is_custom=False)
        return qs.prefetch_related('primary_muscles', 'equipment').distinct()

    q_and = Q()
    for root in roots:
        q_and &= _token_q(root)
    candidates = list(_scoped(Exercise.objects.filter(q_and))[:CANDIDATE_POOL])

    if len(candidates) < CANDIDATE_POOL:
        q_or = Q()
        for root in roots:
            q_or |= _token_q(root)
        seen = {ex.id for ex in candidates}
        for ex in _scoped(Exercise.objects.filter(q_or))[:CANDIDATE_POOL]:
            if ex.id not in seen:
                candidates.append(ex)
                seen.add(ex.id)
    name_norm = _normalize(name)
    name_expanded = _expand_synonyms(name_norm)
    core_set = set(core)
    quals_set = set(quals)
    req_equip = _requested_equipment(name) if equipment_hint is None else equipment_hint

    scored: list[tuple[float, Exercise]] = []
    for ex in candidates:
        cand_equip = {eq.id for eq in ex.equipment.all()}
        # Score the catalogue name and every stored alias; keep the best.
        best_variant = 0.0
        exact_hit = False
        for variant in [ex.name, *_alias_list(ex)]:
            v_norm = _normalize(variant)
            v_expanded = _expand_synonyms(v_norm)
            v_core, v_quals = _tokenize(variant)
            v_core_set = set(v_core)
            if not v_core_set:
                continue
            intersect = core_set & v_core_set
            union = core_set | v_core_set
            score = len(intersect) / max(len(union), 1)
            # all query core tokens present → strong signal
            if core_set and core_set.issubset(v_core_set):
                score += 0.35
            # qualifier overlap → small bonus
            if quals_set & set(v_quals):
                score += 0.05
            # prefix boost
            if v_expanded.startswith(name_expanded) or name_expanded.startswith(v_expanded):
                score += 0.20
            # A pile of bonuses is NOT an exact match. 1.0 is reserved for true
            # post-normalization equality and re-applied after the equipment
            # check below, so the 'exact' bucket stays trustworthy: everything
            # else tops out just under it and can still be reordered.
            best_variant = max(best_variant, min(score, 0.95))
            if v_norm == name_norm or v_expanded == name_expanded:
                exact_hit = True

        if not best_variant:
            continue

        # Equipment arbitrates between same-movement variants. Only applied when
        # the coach named an implement AND the candidate has one on file.
        equip_conflict = False
        if req_equip and cand_equip:
            if req_equip & cand_equip:
                best_variant += 0.25
            else:
                # Wrong implement: demote hard and forbid the exact/high bands,
                # so the row surfaces for review instead of silently saving.
                equip_conflict = True
                best_variant = min(best_variant, 0.80) - 0.35

        if exact_hit and not equip_conflict:
            final = 1.0
        else:
            final = max(0.0, min(best_variant, 0.95))
        scored.append((final, ex))

    scored.sort(key=lambda t: t[0], reverse=True)

    out: list[dict] = []
    for score, ex in scored[:limit]:
        primary_muscles = [m.name for m in ex.primary_muscles.all()]
        out.append({
            'id': ex.id,
            'name': ex.name,
            'is_custom': ex.is_custom,
            'equipment': [eq.name_it for eq in ex.equipment.all()],
            'primary_muscle': primary_muscles[0] if primary_muscles else '',
            'cover_image': ex.cover_image.url if ex.cover_image else '',
            'score': round(float(score), 3),
        })
    return out


def best_match(
    name: str,
    coach=None,
    threshold: float = 0.55,
    name_en: str | None = None,
) -> tuple[Optional[dict], list[dict], str, str]:
    """Return (best_or_None, others, confidence_bucket, method).

    confidence_bucket ∈ {'exact','high','medium','low','none'}.
    method ∈ {'exact','normalized','fuzzy','none'}.

    `name_en` is the extractor's English rendering of `name` (see
    `imports/prompts.py`). Both are scored and the stronger result wins, so an
    unhelpful translation can never make matching worse than the raw name alone.
    """
    cands = fuzzy_match_exercise(name, coach=coach, limit=5)
    # A confident raw-name hit is already 'high'/'exact' either way (see the
    # buckets below); scoring the translation too would only matter for the
    # exact-vs-high distinction, which downstream treats identically (neither
    # is flagged uncertain). Skip it — it's a DB round-trip per exercise that
    # buys nothing, and it's the main cost of the whole matching phase.
    if cands and cands[0]['score'] >= 0.85:
        name_en = None
    if name_en and _normalize(name_en) != _normalize(name):
        # Score the translation on its own clean text, but keep arbitrating with
        # the implement from the Italian original — coaches name it there
        # ("con bilanciere") and translations routinely drop it.
        hint = _requested_equipment(name) or _requested_equipment(name_en)
        en_cands = fuzzy_match_exercise(
            name_en, coach=coach, limit=5, equipment_hint=hint,
        )
        if en_cands and (not cands or en_cands[0]['score'] > cands[0]['score']):
            cands = en_cands
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
