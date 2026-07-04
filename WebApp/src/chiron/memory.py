"""Gestione memoria/contesto di CHIRON.

Problema: con conversazioni lunghe il contesto cresce → più token e più
allucinazioni. Soluzione: finestra scorrevole + riassunto rotante.

- Gli ultimi `KEEP_RECENT` messaggi restano integrali.
- Quando i messaggi non ancora riassunti superano `KEEP_RECENT + FOLD_BATCH`, i
  più vecchi vengono compressi in un unico riassunto (chiamata LLM) e segnati
  come "già riassunti" (`summary_up_to_id` avanza).
- Al modello arriva quindi: riassunto (piccolo) + ultimi messaggi. Bounded.

Tutto lato server (autorevole): il frontend non manda più la cronologia.
"""

import logging

from langchain_core.messages import HumanMessage, SystemMessage

from chiron.schemas import HistoryMessage

logger = logging.getLogger(__name__)

# Messaggi recenti tenuti SEMPRE integrali.
KEEP_RECENT = 8
# Soglia: si comprime solo quando i non-riassunti superano KEEP_RECENT + FOLD_BATCH.
FOLD_BATCH = 8
# Tetto di lunghezza del riassunto persistito.
SUMMARY_MAX_CHARS = 1500


def build_context(user) -> tuple[list[HistoryMessage], str]:
    """Ritorna (history_recente, summary) per il modello, comprimendo se serve.

    `history_recente` esclude il messaggio utente corrente (non ancora salvato):
    va chiamata PRIMA di persistere il nuovo messaggio.
    """
    from domain.chiron.models import ChironMessage, ChironSummary

    mem, _ = ChironSummary.objects.get_or_create(user=user)
    unsummed = list(
        ChironMessage.objects
        .filter(user=user, id__gt=mem.summary_up_to_id)
        .order_by('id')
    )

    if len(unsummed) > KEEP_RECENT + FOLD_BATCH:
        fold = unsummed[:-KEEP_RECENT]   # tutti tranne gli ultimi KEEP_RECENT
        keep = unsummed[-KEEP_RECENT:]
        new_summary = _summarize(mem.summary, fold)
        if new_summary:
            mem.summary = new_summary[:SUMMARY_MAX_CHARS]
            mem.summary_up_to_id = fold[-1].id
            mem.save(update_fields=['summary', 'summary_up_to_id', 'updated_at'])
            unsummed = keep
        # Se il riassunto fallisce non avanziamo: nessuna perdita di memoria,
        # al massimo questo turno usa qualche messaggio in più.

    history = [HistoryMessage(role=m.role, content=m.content) for m in unsummed]  # type: ignore[arg-type]
    return history, mem.summary


def reset(user) -> None:
    """Azzera la memoria (usato da clear history)."""
    from domain.chiron.models import ChironSummary
    ChironSummary.objects.filter(user=user).update(summary='', summary_up_to_id=0)


def _summarize(prev_summary: str, messages: list) -> str | None:
    """Comprime prev_summary + messaggi in un unico riassunto. None se fallisce."""
    from decouple import config
    from langchain_openai import ChatOpenAI
    from chiron.router import pick_model

    convo = "\n".join(f"{m.role}: {m.content}" for m in messages)
    sys = (
        "Riassumi la conversazione tra un coach e l'assistente CHIRON. Conserva "
        "fatti, decisioni, atleti citati, numeri e richieste in sospeso. Integra il "
        "riassunto precedente in un unico testo. Conciso, in italiano, max 180 parole."
    )
    usr = (
        f"Riassunto precedente:\n{prev_summary or '(nessuno)'}\n\n"
        f"Nuovi messaggi:\n{convo}\n\nRiassunto aggiornato unico:"
    )
    try:
        llm = ChatOpenAI(
            model=pick_model("summary"),
            temperature=0.2,
            api_key=config("OLLAMA_API_KEY"),
            base_url=config("OLLAMA_BASE_URL", default="https://ollama.com/v1"),
            max_completion_tokens=400,
            timeout=30,
        )
        resp = llm.invoke([SystemMessage(content=sys), HumanMessage(content=usr)])
        text = resp.content if isinstance(resp.content, str) else str(resp.content)
        return text.strip() or None
    except Exception:
        logger.exception("CHIRON: summarization fallita")
        return None
