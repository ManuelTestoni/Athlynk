"""Tool LangChain disponibili a CHIRON.

Strategia ricerca web:
- Default: DuckDuckGo via `ddgs` (zero API key, free).
- Override opzionale: Tavily se `TAVILY_API_KEY` è presente (qualità migliore).
"""

import json
import logging
from functools import lru_cache

from decouple import config
from langchain_core.tools import tool

logger = logging.getLogger(__name__)


def _ddg_search(query: str, max_results: int = 5) -> list[dict]:
    """Esegue ricerca DuckDuckGo via libreria ddgs."""
    from ddgs import DDGS
    out: list[dict] = []
    try:
        with DDGS() as ddgs:
            for r in ddgs.text(query, max_results=max_results, region="it-it"):
                out.append({
                    "title": r.get("title") or "",
                    "url": r.get("href") or r.get("url") or "",
                    "content": r.get("body") or "",
                })
    except Exception as exc:
        logger.warning("CHIRON: DuckDuckGo search fallita: %s", exc)
    return out


@tool("web_search", parse_docstring=False)
def web_search(query: str) -> str:
    """Cerca su internet informazioni aggiornate. Usalo quando non conosci la risposta
    o serve un dato verificabile (studi, linee guida, prodotti, news). Input: query in
    italiano o inglese, breve e specifica."""
    results = _ddg_search(query, max_results=5)
    if not results:
        return json.dumps({"results": [], "error": "Nessun risultato dalla ricerca web."})
    return json.dumps({"results": results}, ensure_ascii=False)


@lru_cache(maxsize=1)
def get_web_search_tool():
    """Sceglie il provider: Tavily se la chiave esiste, altrimenti DuckDuckGo."""
    tavily_key = config("TAVILY_API_KEY", default="").strip()
    if tavily_key:
        try:
            from langchain_tavily import TavilySearch
            return TavilySearch(max_results=5, tavily_api_key=tavily_key)
        except Exception as exc:
            logger.warning("CHIRON: init Tavily fallito (%s), uso DuckDuckGo.", exc)
    return web_search


@lru_cache(maxsize=1)
def get_tools() -> list:
    return [get_web_search_tool()]
