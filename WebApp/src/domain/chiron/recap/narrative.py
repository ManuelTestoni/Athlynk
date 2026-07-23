"""Riformulazione LLM del recap: SOLO testo, mai fatti.

Confine imposto architetturalmente, non solo da prompt: questo modulo riceve
in input la lista di RecapInsight già completamente popolata (template +
evidence) — non ha accesso a queryset o numeri grezzi non passati da una
regola, quindi non può strutturalmente inventare un fatto. Guardia anti-
allucinazione numerica post-hoc + fallback silenzioso ai template
deterministici se l'LLM fallisce, va in timeout o inventa un numero.
"""

import logging
import re

from decouple import config
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage

from chiron.router import pick_model

logger = logging.getLogger(__name__)

_NUMBER_RE = re.compile(r'-?\d+(?:[.,]\d+)?')


def _fmt(value):
    # Normalizza per il confronto: valore assoluto (la prosa spesso esprime un
    # delta negativo con una parola invece del segno, es. "vita calata di
    # 1.5cm" invece di "-1.5") e "12.0"/"12" contano come lo stesso numero.
    return f"{abs(float(value)):g}"


def _text_numbers(text):
    out = set()
    for raw in _NUMBER_RE.findall(text or ''):
        try:
            out.add(_fmt(raw.replace(',', '.')))
        except ValueError:
            continue
    return out


def _allowed_numbers(insights):
    """Ogni numero già presente nei fatti deterministici (observation +
    evidence) — non solo i campi scalari di evidence, anche i numeri già
    formattati dentro observation, che è esattamente ciò che passiamo
    all'LLM come "fatti"."""
    numbers = set()
    for insight in insights:
        numbers |= _text_numbers(insight.observation)
        for value in (insight.evidence.current_value, insight.evidence.previous_value,
                      insight.evidence.n_current, insight.evidence.n_previous):
            if value is not None:
                numbers.add(_fmt(value))
        for value in (insight.evidence.extra or {}).values():
            if isinstance(value, (int, float)):
                numbers.add(_fmt(value))
    return numbers


def _template_fallback(insights):
    if not insights:
        return "Nessun pattern rilevante emerso con i dati disponibili al momento."
    return "\n".join(f"• {i.interpretation}" for i in insights)


def build_narrative_llm(max_tokens=600, timeout=30):
    return ChatOpenAI(
        model=pick_model("summary"),  # sempre il modello pesante, mai il 20b flaky
        temperature=0.2,
        api_key=config("OLLAMA_API_KEY"),
        base_url=config("OLLAMA_BASE_URL", default="https://ollama.com/v1"),
        max_completion_tokens=max_tokens,
        timeout=timeout,
        max_retries=0,
    )


def generate_narrative(insights, athlete_name=""):
    """Ritorna (testo, is_fallback). Non solleva mai: un Ollama Cloud
    irraggiungibile non deve mai bloccare il rendering del recap."""
    fallback_text = _template_fallback(insights)
    if not insights:
        return fallback_text, False

    facts = "\n".join(
        f"- [{i.domain}] {i.observation} → {i.interpretation}"
        + (f" Consiglio: {i.recommendation}" if i.recommendation else '')
        for i in insights
    )
    sys = (
        "Riformula in prosa italiana chiara e concisa (max 150 parole) i seguenti fatti "
        "già calcolati su un atleta, per un coach. Non introdurre numeri o fatti che non "
        "siano già presenti nell'elenco. Non ripetere pedissequamente ogni riga: sintetizza."
    )
    usr = f"Atleta: {athlete_name or 'atleta'}\n\nFatti:\n{facts}\n\nTesto:"

    try:
        llm = build_narrative_llm()
        resp = llm.invoke([SystemMessage(content=sys), HumanMessage(content=usr)])
        text = resp.content if isinstance(resp.content, str) else str(resp.content)
        text = text.strip()
        if not text:
            return fallback_text, True
        if not _text_numbers(text).issubset(_allowed_numbers(insights)):
            logger.warning("CHIRON recap: guardia anti-allucinazione fallita, fallback a template")
            return fallback_text, True
        return text, False
    except Exception:
        logger.exception("CHIRON recap: riformulazione LLM fallita")
        return fallback_text, True
