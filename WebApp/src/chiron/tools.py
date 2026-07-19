"""Tool LangChain disponibili a CHIRON.

Ricerca: solo letteratura peer-reviewed (Europe PMC), mai web generico.

CHIRON risponde a professionisti che prendono decisioni su persone reali: una
risposta corretta ma appoggiata a un blog non è accettabile, e una ricerca web
generica non offre modo di distinguere le due cose. Il tool restituisce quindi
solo articoli indicizzati, ordinati per tipo di studio e citazioni, con i
metadati necessari a citarli (vedi `chiron/scientific_search.py`).
"""

import json
import logging
from functools import lru_cache

from langchain_core.tools import tool

logger = logging.getLogger(__name__)


@tool("scientific_search", parse_docstring=False)
def scientific_search(query: str) -> str:
    """Cerca studi scientifici peer-reviewed (PubMed/Europe PMC) su allenamento,
    nutrizione, integrazione e fisiologia. Usalo SEMPRE prima di dare numeri,
    dosaggi, range o raccomandazioni: non inventare mai valori.

    IMPORTANTE: scrivi la query in INGLESE e con termini tecnici (la letteratura
    è in inglese). Esempi: "protein intake per kg hypertrophy", "creatine
    supplementation kidney function", "caffeine dose endurance performance".

    Restituisce fino a 3 studi con titolo, autori, anno, rivista, DOI, numero di
    citazioni e tipo di studio (meta-analisi, RCT, revisione). Devi SEMPRE citare
    le fonti che usi."""
    from chiron.scientific_search import search_literature

    try:
        results = search_literature(query, limit=3)
    except Exception:
        logger.exception('CHIRON: scientific_search fallita')
        return json.dumps({
            'results': [],
            'error': 'Ricerca bibliografica non disponibile in questo momento.',
        }, ensure_ascii=False)

    if not results:
        return json.dumps({
            'results': [],
            'note': ('Nessuno studio peer-reviewed trovato per questa query. '
                     'Riprova con termini inglesi più tecnici, oppure dillo '
                     "all'utente invece di rispondere a memoria."),
        }, ensure_ascii=False)

    return json.dumps({'results': results}, ensure_ascii=False)


@lru_cache(maxsize=1)
def get_web_search_tool():
    """Nome storico mantenuto per i chiamanti esistenti."""
    return scientific_search


@lru_cache(maxsize=1)
def get_tools() -> list:
    # Import lazy: i coach tool toccano i modelli Django.
    from chiron.coach_tools import get_coach_tools
    return [scientific_search, *get_coach_tools()]
