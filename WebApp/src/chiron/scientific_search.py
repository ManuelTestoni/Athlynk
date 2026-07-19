"""Peer-reviewed literature search for CHIRON, via Europe PMC.

Why not a general web search: a coach asking "quante proteine per kg per
ipertrofia" needs the answer the field actually converged on, not the first blog
that ranks for it. Europe PMC covers PubMed/MEDLINE, is free and key-less, and
returns the metadata needed to judge authority — publication type, journal, year
and a real citation count.

Ranking is deliberate rather than "whatever the API returns first", because
neither of the API's own orderings is usable on its own:

- sorted by relevance, the top hits are whatever was published last week, with
  zero citations and no replication;
- sorted by citations, relevance collapses entirely — a query about resistance
  training returns the AHA cardiovascular statistics report, cited 6000 times
  and about nothing the coach asked.

So we query in tiers, strongest evidence first (meta-analyses and systematic
reviews, then RCTs, then anything), each tier already sorted by citations inside
its own relevance-filtered result set. Tiers are merged and scored, so a
well-cited meta-analysis outranks a fresh preprint without a hand-tuned cutoff.
"""

from __future__ import annotations

import logging
import math
from datetime import date

import requests

logger = logging.getLogger(__name__)

_ENDPOINT = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search'
_TIMEOUT = 12
_USER_AGENT = 'Athlynk-CHIRON/1.0 (coaching assistant; literature lookup)'

# Query tiers, strongest evidence first. `weight` is the head start a hit gets
# for the design of the study itself, before citations are considered.
_TIERS = (
    ('meta-analysis',
     '(PUB_TYPE:"Meta-Analysis" OR PUB_TYPE:"Systematic Review")', 1.00),
    ('rct',
     '(PUB_TYPE:"Randomized Controlled Trial")', 0.65),
    ('review',
     '(PUB_TYPE:"Review")', 0.40),
    ('any', '', 0.15),
)

# Journals whose scope is exactly this domain. A small nudge, not a gate: good
# work appears outside the list and the citation count already carries most of
# the signal.
_DOMAIN_JOURNALS = {
    'medicine and science in sports and exercise',
    'journal of the international society of sports nutrition',
    'sports medicine',
    'the american journal of clinical nutrition',
    'british journal of sports medicine',
    'the journal of strength and conditioning research',
    'journal of strength and conditioning research',
    'european journal of applied physiology',
    'the journal of physiology',
    'international journal of sport nutrition and exercise metabolism',
    'nutrients',
    'the british journal of nutrition',
    'scandinavian journal of medicine & science in sports',
    'journal of applied physiology',
    'frontiers in physiology',
    'frontiers in nutrition',
}

_MAX_ABSTRACT = 900

# Budget on outbound calls, so a hopeless query can't stall a chat turn.
_MAX_CALLS = 6

_QUERY_STOPWORDS = {
    'the', 'of', 'a', 'an', 'and', 'or', 'for', 'in', 'on', 'to', 'with',
    'per', 'vs', 'versus', 'is', 'are', 'does', 'do', 'how', 'what', 'much',
    'effect', 'effects', 'best', 'optimal',
}


def _terms(query: str) -> list[str]:
    """Content words, longest first — the longest are the most discriminating."""
    words = [
        ''.join(ch for ch in word if ch.isalnum() or ch == '-')
        for word in query.lower().split()
    ]
    keep = [
        w for w in words
        if len(w) > 2 and w not in _QUERY_STOPWORDS and not w.isdigit()
    ]
    return sorted(dict.fromkeys(keep), key=len, reverse=True)


def _term_clauses(query: str) -> list[str]:
    """Progressively looser relevance clauses.

    Europe PMC's free-text parser is effectively an OR, which combined with
    citation sorting drags in famous but unrelated papers — a caffeine question
    came back with a falls-prevention review cited 1400 times. Constraining each
    term to TITLE_ABS and ANDing them fixes relevance, but ANDing *every* term
    can over-constrain to zero hits, so we relax stepwise instead of picking one
    strictness up front.
    """
    terms = _terms(query)
    if not terms:
        return [query]
    variants = [terms]
    if len(terms) > 3:
        variants.append(terms[:3])
    if len(terms) > 2:
        variants.append(terms[:2])
    clauses = [' AND '.join(f'TITLE_ABS:"{t}"' for t in group) for group in variants]
    # Last resort: the raw phrase, still scoped to title/abstract.
    clauses.append(f'TITLE_ABS:"{query.strip()}"')
    return list(dict.fromkeys(clauses))


def _get(query: str, page_size: int) -> list[dict]:
    """One Europe PMC call. Network problems degrade to an empty tier."""
    try:
        resp = requests.get(
            _ENDPOINT,
            params={
                'query': query,
                'format': 'json',
                'pageSize': str(page_size),
                'resultType': 'core',
                # Citation order *within* an already relevance-filtered set.
                'sort': 'CITED desc',
            },
            timeout=_TIMEOUT,
            headers={'User-Agent': _USER_AGENT},
        )
        resp.raise_for_status()
        payload = resp.json()
    except (requests.RequestException, ValueError) as exc:
        logger.warning('CHIRON: Europe PMC query failed (%s): %s', query[:80], exc)
        return []
    return ((payload.get('resultList') or {}).get('result') or [])


def _int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _authors(record: dict) -> str:
    """"Schoenfeld BJ, Aragon AA, Krieger JW" → "Schoenfeld et al."."""
    raw = (record.get('authorString') or '').strip().rstrip('.')
    if not raw:
        return ''
    first = raw.split(',')[0].strip()
    surname = first.split(' ')[0] if first else ''
    if not surname:
        return ''
    return f'{surname} et al.' if ',' in raw else surname


def _journal(record: dict) -> str:
    info = record.get('journalInfo') or {}
    return ((info.get('journal') or {}).get('title') or '').strip()


def _url(record: dict) -> str:
    doi = (record.get('doi') or '').strip()
    if doi:
        return f'https://doi.org/{doi}'
    pmid = (record.get('pmid') or '').strip()
    if pmid:
        return f'https://pubmed.ncbi.nlm.nih.gov/{pmid}/'
    ext_id, source = record.get('id'), record.get('source')
    if ext_id and source:
        return f'https://europepmc.org/article/{source}/{ext_id}'
    return ''


def _title_overlap(record: dict, terms: list[str]) -> float:
    """Share of query terms appearing in the title.

    Constraining terms to TITLE_ABS keeps results on topic but not *about* the
    topic: "sleep AND muscle AND recovery" legitimately matches a knee-block
    analgesia trial that measured all three. Requiring the terms in the title
    instead returns nothing at all. So the title is scored rather than filtered
    on — papers actually about the question float up, the rest stay available.
    """
    if not terms:
        return 0.0
    title = (record.get('title') or '').lower()
    hits = sum(1 for t in terms if t in title)
    return hits / len(terms)


def _score(record: dict, tier_weight: float, this_year: int,
           terms: list[str]) -> float:
    """Evidence design + topical fit + citations per year + recency + journal."""
    year = _int(record.get('pubYear'))
    citations = _int(record.get('citedByCount'))

    # Citations per year, log-compressed. Normalising by age keeps a strong
    # recent paper competitive with an old one that has simply had longer to
    # accumulate; the log stops a single famous paper dominating every query.
    age = max(1, this_year - year + 1) if year else 12
    per_year = citations / age
    citation_score = min(math.log10(per_year + 1) / 2.0, 1.0)

    # Mild recency preference — guidance in this field does move.
    recency = 0.0
    if year:
        recency = max(0.0, min(1.0, (year - (this_year - 20)) / 20.0)) * 0.25

    journal_bonus = 0.15 if _journal(record).lower() in _DOMAIN_JOURNALS else 0.0

    # Weighted above citations: being on-topic matters more than being famous.
    topical = _title_overlap(record, terms) * 1.20

    return tier_weight + topical + citation_score + recency + journal_bonus


def _serialize(record: dict, study_type: str, this_year: int) -> dict:
    abstract = (record.get('abstractText') or '').strip()
    return {
        'title': (record.get('title') or '').strip().rstrip('.')[:300],
        'authors': _authors(record),
        'year': _int(record.get('pubYear')) or None,
        'journal': _journal(record),
        'doi': (record.get('doi') or '').strip(),
        'url': _url(record),
        'citations': _int(record.get('citedByCount')),
        'study_type': study_type,
        # Europe PMC does not carry an abstract for every indexed record; the
        # model is told to say so rather than fill the gap from memory.
        'content': abstract[:_MAX_ABSTRACT],
    }


_STUDY_TYPE_LABELS = {
    'meta-analysis': 'meta-analisi / revisione sistematica',
    'rct': 'studio randomizzato controllato',
    'review': 'revisione narrativa',
    'any': 'articolo peer-reviewed',
}


def search_literature(query: str, limit: int = 3) -> list[dict]:
    """Ranked peer-reviewed hits for `query` (English works best).

    Returns at most `limit` dicts. An empty list means nothing usable was found
    — callers must not paper over that.
    """
    query = (query or '').strip()
    if not query:
        return []

    this_year = date.today().year
    terms = _terms(query)
    clauses = _term_clauses(query)
    scored: list[tuple[float, dict]] = []
    seen: set[str] = set()
    calls = 0

    for tier_name, tier_filter, weight in _TIERS:
        for clause in clauses:
            if calls >= _MAX_CALLS:
                break
            full_query = f'({clause}) AND {tier_filter}' if tier_filter else clause
            calls += 1
            records = _get(full_query, page_size=6)
            if not records:
                continue                      # over-constrained: relax and retry
            for record in records:
                # Dedupe across tiers: an RCT is also a Journal Article.
                key = ((record.get('doi') or '').lower()
                       or f"{record.get('source')}:{record.get('id')}")
                if not key or key in seen:
                    continue
                seen.add(key)
                scored.append((
                    _score(record, weight, this_year, terms),
                    _serialize(record, _STUDY_TYPE_LABELS[tier_name], this_year),
                ))
            break                             # this tier answered; next tier
        # Enough strong evidence to rank meaningfully — don't spend the budget.
        if len(scored) >= limit * 3 or calls >= _MAX_CALLS:
            break

    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [item for _, item in scored[:limit]]
