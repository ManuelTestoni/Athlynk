"""Query-independent "genericity" scoring for food names.

Higher score = more generic name = should rank higher in search. The expensive
part (scanning brand words / qualifiers) is precomputed once and stored in
Food.genericity_score, then used as a tiebreaker after query relevance.

Used by:
- the `compute_food_scores` management command (bulk recompute), and
- the Food pre_save signal (per-row, on insert/update).
"""
import re
import unicodedata
from collections import Counter

# ── Curated qualifier words that make a name less generic ───────────────────
MODIFIER_WORDS = {
    'sg', 'light', 'lite', 'bio', 'biologico', 'dop', 'igp', 'doc', 'docg',
    'isolato', 'idrolizzato', 'concentrato', 'deamarizzato', 'arricchito',
    'addizionato', 'aromatizzato', 'decaffeinato', 'dietetico', 'dieta',
    'proteico', 'iposodico', 'magro', 'scremato', 'parzialmente',
    'speciale', 'super', 'extra', 'premium', 'classico', 'tradizionale',
    'artigianale', 'gourmet', 'selezione', 'riserva',
}
MODIFIER_PHRASES = [
    'senza glutine', 'senza lattosio', 'senza zucchero', 'senza zuccheri',
    'a basso contenuto', 'ad alto contenuto', 'fonte di',
]

# Weights (tuned to the 1269-row table; all subtractive except boosts).
PENALTY_MODIFIER = 1.5      # per qualifier word/phrase
PENALTY_BRAND = 3.0         # has a (BRAND) parenthetical
PENALTY_ASTERISK = 2.0      # commercial-product marker *
PENALTY_PAREN = 1.0         # per parenthetical group (detail/qualifier)
PENALTY_COMMA = 0.4         # per comma (each adds a qualifier clause)
PENALTY_DIGIT_GROUP = 0.8   # per run of digits (quantities, %, codes)
PENALTY_PER_CHAR_OVER = 0.04  # per char beyond LENGTH_FREE
LENGTH_FREE = 16
BOOST_SINGLE_WORD = 2.0
BOOST_TWO_WORDS = 1.0

_WORD_RE = re.compile(r"[a-zàèéìòùáíóúäöüç]+", re.IGNORECASE)
_DIGIT_RE = re.compile(r"\d+")
_PAREN_RE = re.compile(r"\(([^)]*)\)")
# A parenthetical is a brand when its content is (mostly) uppercase letters —
# e.g. (FLAVIS), (SCHÄR), (CÉRÉAL) — vs descriptive like (cruda).
_BRANDISH = re.compile(r"^[A-ZÀ-Þ' .&-]{2,}$")


def _strip_accents(s: str) -> str:
    return ''.join(c for c in unicodedata.normalize('NFKD', s)
                   if not unicodedata.combining(c))


def discover_brands(names):
    """Scan all names, return Counter of detected brand tokens (uppercase
    parentheticals). Pure analysis, printed for transparency."""
    brands = Counter()
    for name in names:
        for inner in _PAREN_RE.findall(name):
            inner = inner.strip()
            if _BRANDISH.match(inner):
                brands[inner] += 1
    return brands


def score_name(name: str) -> float:
    """Query-independent genericity score for a single food name."""
    name = name or ''
    norm = _strip_accents(name).lower()
    score = 0.0

    # Brand parenthetical (uppercase content) → strong penalty.
    parens = _PAREN_RE.findall(name)
    for inner in parens:
        if _BRANDISH.match(inner.strip()):
            score -= PENALTY_BRAND
            break

    if '*' in name:
        score -= PENALTY_ASTERISK
    score -= PENALTY_PAREN * len(parens)
    score -= PENALTY_COMMA * name.count(',')
    score -= PENALTY_DIGIT_GROUP * len(_DIGIT_RE.findall(name))

    words = _WORD_RE.findall(norm)
    wordset = set(words)
    score -= PENALTY_MODIFIER * len(wordset & MODIFIER_WORDS)
    for phrase in MODIFIER_PHRASES:
        if phrase in norm:
            score -= PENALTY_MODIFIER

    over = max(0, len(name) - LENGTH_FREE)
    score -= PENALTY_PER_CHAR_OVER * over

    if len(words) == 1:
        score += BOOST_SINGLE_WORD
    elif len(words) == 2:
        score += BOOST_TWO_WORDS

    return round(score, 3)
