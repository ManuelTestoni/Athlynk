"""Fuzzy matching alimenti contro il DB Food.

Usato dall'importer Excel/AI: l'AI estrae nomi liberi ("petto di pollo",
"riso basmati"), qui li mappiamo a entry esistenti tramite ricerca per token.
"""

import re
from django.db.models import Q

from domain.nutrition.models import Food


STOPWORDS = {'di', 'da', 'a', 'al', 'il', 'lo', 'la', 'i', 'gli', 'le',
             'un', 'una', 'uno', 'con', 'e', 'o', 'in', 'del', 'della',
             'dello', 'dei', 'degli', 'delle', 'allo', 'alla', 'agli', 'alle',
             'per', 'su', 'fra', 'tra', 'sul', 'sulla'}

# Eccezioni plurali italiane irregolari (lookup esatto)
_PLURAL_EXCEPTIONS = {
    'uova': 'uovo',
    'uomini': 'uomo',
    'mani': 'mano',
    'dita': 'dito',
    'ginocchia': 'ginocchio',
    'lenzuola': 'lenzuolo',
    'paia': 'paio',
    'bue': 'bue', 'buoi': 'bue',
    'mille': 'mille',
}


def _singularize_it(token: str) -> str:
    """Riduce un token italiano alla forma singolare approssimata.

    Regole base:
    - parole < 4 char → invariate
    - eccezioni hardcoded → mappa
    - finale 'he' → 'ca' (banche → banca, oche → oca)
    - finale 'che' → 'ca' (idem)
    - finale 'ghe' → 'ga' (paghe → paga)
    - finale 'ci' → 'co' (medici → medico)
    - finale 'gi' → 'go' (laghi → lago)... ma anche fugi → fugo? compromesso
    - finale 'e' → 'a' (mele → mela, banane → banana)
    - finale 'i' → 'o' (panini → panino) — fallback generico
    """
    t = token.lower()
    if len(t) < 4:
        return t
    if t in _PLURAL_EXCEPTIONS:
        return _PLURAL_EXCEPTIONS[t]
    if t.endswith('ghi'):
        return t[:-3] + 'go'
    if t.endswith('chi'):
        return t[:-3] + 'co'
    if t.endswith('ghe'):
        return t[:-3] + 'ga'
    if t.endswith('che'):
        return t[:-3] + 'ca'
    if t.endswith('ci'):
        return t[:-2] + 'co'
    if t.endswith('gi'):
        return t[:-2] + 'go'
    if t.endswith('e'):
        return t[:-1] + 'a'
    if t.endswith('i'):
        return t[:-1] + 'o'
    return t


def _strip_brand(name: str) -> str:
    """Rimuove suffisso brand dopo trattino o pipe.

    "Proteine in polvere - ES Sport" → "Proteine in polvere"
    "Riso basmati | Brand" → "Riso basmati"
    """
    for sep in (' - ', ' – ', ' — ', ' | ', ' / '):
        idx = name.find(sep)
        if idx > 0:
            return name[:idx].strip()
    return name


def _tokenize(name: str) -> list[str]:
    """Tokenizza un nome alimento rimuovendo punteggiatura e stopwords italiane.
    Applica singolarizzazione approssimata e strip brand.
    """
    if not name:
        return []
    base = _strip_brand(name)
    cleaned = re.sub(r'[^\w\s]', ' ', base.lower())
    tokens = []
    for t in cleaned.split():
        if not t or t in STOPWORDS or len(t) <= 1:
            continue
        tokens.append(_singularize_it(t))
    return tokens


def fuzzy_match_food(name: str, limit: int = 5) -> list[dict]:
    """Cerca alimenti per token. Ritorna lista di {id,name,category,kcal,...,score}
    ordinata per score desc. Score 0..1: frazione di token matchati + boost prefix.
    """
    tokens = _tokenize(name)
    if not tokens:
        return []

    # OR su icontains per ogni token (tokens già singolarizzati: matchano sia
    # "banana" che "banane" dato che usiamo icontains su radice frequente)
    q = Q()
    for t in tokens:
        # rimuovi ultima lettera per match prefix-style su sing/plur
        root = t[:-1] if len(t) >= 5 else t
        q |= Q(nome_alimento__icontains=root)

    candidates = list(Food.objects.filter(q)[:60])
    scored = []
    name_lower = _strip_brand(name).lower().strip()
    name_tokens_set = set(tokens)

    for f in candidates:
        food_lower = f.nome_alimento.lower()
        food_tokens = set(_tokenize(f.nome_alimento))
        # match per token singolarizzato (set intersection)
        common = name_tokens_set & food_tokens
        matched: float = len(common)
        # fallback: anche substring match su radici
        for t in tokens:
            root = t[:-1] if len(t) >= 5 else t
            if root in food_lower and t not in {ft for ft in food_tokens if root in ft}:
                matched += 0.5
        score = matched / max(len(tokens), 1)
        # boost: prefix match
        if food_lower.startswith(name_lower) or name_lower.startswith(food_lower):
            score += 0.3
        # boost: tutti i token del query presenti
        if name_tokens_set and name_tokens_set.issubset(food_tokens):
            score += 0.4
        # boost: exact (anche con brand strippato)
        if food_lower == name_lower:
            score = 1.6
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
        # ritorna comunque candidati per UI revisione (utente conferma)
        return None, candidates, True
    return top, candidates[1:], False
