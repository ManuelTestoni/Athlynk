"""Fuzzy matching alimenti contro il DB Food.

Usato dall'importer Excel/AI: l'AI estrae nomi liberi ("petto di pollo",
"riso basmati"), qui li mappiamo a entry esistenti tramite ricerca per token.
"""

import re
from django.db.models import Q

from domain.nutrition.models import Food


STOPWORDS = {'di', 'da', 'a', 'al', 'il', 'lo', 'la', 'i', 'gli', 'le',
             'un', 'una', 'uno', 'con', 'e', 'o', 'in', 'del', 'della'}


def _tokenize(name: str) -> list[str]:
    """Tokenizza un nome alimento rimuovendo punteggiatura e stopwords italiane."""
    if not name:
        return []
    cleaned = re.sub(r'[^\w\s]', ' ', name.lower())
    tokens = [t for t in cleaned.split() if t and t not in STOPWORDS and len(t) > 1]
    return tokens


def fuzzy_match_food(name: str, limit: int = 5) -> list[dict]:
    """Cerca alimenti per token. Ritorna lista di {id,name,category,kcal,...,score}
    ordinata per score desc. Score 0..1: frazione di token matchati + boost prefix.
    """
    tokens = _tokenize(name)
    if not tokens:
        return []

    # OR su icontains per ogni token
    q = Q()
    for t in tokens:
        q |= Q(nome_alimento__icontains=t)

    candidates = list(Food.objects.filter(q)[:40])
    scored = []
    name_lower = name.lower().strip()

    for f in candidates:
        food_lower = f.nome_alimento.lower()
        matched = sum(1 for t in tokens if t in food_lower)
        score = matched / max(len(tokens), 1)
        # boost: prefix match
        if food_lower.startswith(name_lower) or name_lower.startswith(food_lower):
            score += 0.3
        # boost: exact
        if food_lower == name_lower:
            score = 1.5
        scored.append((score, f))

    scored.sort(key=lambda x: x[0], reverse=True)
    out = []
    for score, f in scored[:limit]:
        out.append({
            'id': f.id,
            'name': f.nome_alimento,
            'category': f.categoria_alimento or '',
            'kcal': f.energia_kcal,
            'protein': f.proteine_g,
            'carb': f.carboidrati_g,
            'fat': f.lipidi_g,
            'fiber': f.fibra_g,
            'score': round(min(score, 1.0), 2),
        })
    return out


def best_match(name: str, threshold: float = 0.5) -> tuple[dict | None, list[dict], bool]:
    """Ritorna (best_food_or_None, top_candidates, is_uncertain).
    is_uncertain=True se score migliore < threshold.
    """
    candidates = fuzzy_match_food(name, limit=5)
    if not candidates:
        return None, [], True
    top = candidates[0]
    uncertain = top['score'] < threshold
    if uncertain:
        return None, candidates, True
    return top, candidates[1:], False
