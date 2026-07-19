"""Grafo LangGraph di CHIRON. Tutto lazy-load per evitare crash all'import."""

import json
import operator
from functools import lru_cache
from typing import Annotated, Any, TypedDict

from decouple import config
from langchain_core.messages import (
    AIMessage,
    BaseMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from langgraph.prebuilt import ToolNode, tools_condition

from chiron.prompts import get_system_prompt
from chiron.router import pick_model
from chiron.schemas import Action, ChatResponse, HistoryMessage, PendingAction, Source
from chiron.tools import get_tools


class ChironState(TypedDict):
    messages: Annotated[list[BaseMessage], operator.add]
    user_role: str
    memory_summary: str


@lru_cache(maxsize=2)
def _get_llm_with_tools(model: str):
    """
    Istanzia il LLM legato ai tool. Usa Ollama Cloud via endpoint OpenAI-compatibile.
    Richiede OLLAMA_API_KEY in env. Endpoint configurabile via OLLAMA_BASE_URL.
    Cache per nome modello (max 2: light + heavy) per il fallback in _chiron_node.
    """
    llm = ChatOpenAI(
        model=model,
        temperature=0.3,
        max_completion_tokens=1500,
        timeout=45,
        api_key=config("OLLAMA_API_KEY"),
        base_url=config("OLLAMA_BASE_URL", default="https://ollama.com/v1"),
    )
    return llm.bind_tools(get_tools())


def _chiron_node(state: ChironState) -> dict:
    """Nodo principale: applica system prompt per ruolo e invoca LLM.

    Se presente un riassunto di memoria (conversazione precedente compressa), lo
    inietta come SystemMessage subito dopo il prompt, così il modello mantiene il
    contesto senza tenere tutta la cronologia (meno token, meno allucinazioni).
    """
    system_prompt = get_system_prompt(state["user_role"])
    messages: list[BaseMessage] = [SystemMessage(content=system_prompt)]
    summary = state.get("memory_summary") or ""
    if summary:
        messages.append(SystemMessage(content=(
            "Riassunto della conversazione precedente (usalo come memoria, "
            "non ripeterlo all'utente):\n" + summary
        )))
    messages += state["messages"]
    model = pick_model("chat")
    response = _get_llm_with_tools(model).invoke(messages)
    heavy = config("OLLAMA_MODEL", default="gpt-oss:120b")
    if model != heavy and not response.content and not getattr(response, "tool_calls", None):
        # ponytail: gpt-oss:20b su Ollama Cloud a volte torna content vuoto, retry sul modello pesante
        response = _get_llm_with_tools(heavy).invoke(messages)
    return {"messages": [response]}


@lru_cache(maxsize=1)
def _get_graph():
    builder = StateGraph(ChironState)
    builder.add_node("chiron_agent", _chiron_node)
    # Un solo ToolNode esegue TUTTI i tool (web_search + coach tool): il nome
    # del nodo è solo un'etichetta, lo strumento giusto viene scelto dal modello.
    builder.add_node("tools", ToolNode(get_tools()))

    builder.add_edge(START, "chiron_agent")
    builder.add_conditional_edges("chiron_agent", tools_condition, {
        "tools": "tools",
        END: END,
    })
    builder.add_edge("tools", "chiron_agent")
    return builder.compile()


def _history_to_messages(history: list[HistoryMessage]) -> list[BaseMessage]:
    out: list[BaseMessage] = []
    for h in history:
        if h.role == "user":
            out.append(HumanMessage(content=h.content))
        else:
            out.append(AIMessage(content=h.content))
    return out


def _extract_sources(messages: list[BaseMessage]) -> list[Source]:
    """Estrae fonti dai ToolMessage prodotti da `scientific_search`."""
    sources: list[Source] = []
    seen_urls: set[str] = set()
    for m in messages:
        if not isinstance(m, ToolMessage):
            continue
        payload = m.content
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except (json.JSONDecodeError, ValueError):
                continue
        results: list[Any] = []
        if isinstance(payload, dict):
            results = payload.get("results", []) or []
        elif isinstance(payload, list):
            results = payload
        for r in results:
            if not isinstance(r, dict):
                continue
            url = r.get("url") or ""
            title = r.get("title") or url or "Fonte"
            if url and url not in seen_urls:
                seen_urls.add(url)
                sources.append(Source(
                    title=title[:200],
                    url=url,
                    authors=r.get("authors") or None,
                    year=r.get("year") or None,
                    journal=r.get("journal") or None,
                    doi=r.get("doi") or None,
                    citations=r.get("citations"),
                    study_type=r.get("study_type") or None,
                ))
    return sources


def _extract_actions(messages: list[BaseMessage]) -> list[Action]:
    """Raccoglie i link/azioni (campo "actions") prodotti dai coach tool."""
    actions: list[Action] = []
    seen_urls: set[str] = set()
    for m in messages:
        if not isinstance(m, ToolMessage):
            continue
        payload = m.content
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except (json.JSONDecodeError, ValueError):
                continue
        if not isinstance(payload, dict):
            continue
        for a in payload.get("actions", []) or []:
            if not isinstance(a, dict):
                continue
            url = a.get("url") or ""
            label = a.get("label") or url
            if url and url not in seen_urls:
                seen_urls.add(url)
                actions.append(Action(label=str(label)[:160], url=url))
    return actions


def _extract_pending_action(messages: list[BaseMessage]) -> PendingAction | None:
    """Raccoglie l'eventuale azione da confermare (campo "confirm") proposta dal
    modello via `propose_action`. Si tiene solo l'ULTIMA (una conferma per volta)."""
    found: PendingAction | None = None
    for m in messages:
        if not isinstance(m, ToolMessage):
            continue
        payload = m.content
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except (json.JSONDecodeError, ValueError):
                continue
        if not isinstance(payload, dict):
            continue
        confirm = payload.get("confirm")
        if isinstance(confirm, dict):
            try:
                found = PendingAction(**confirm)
            except Exception:
                continue
    return found


def _used_web_search(messages: list[BaseMessage]) -> bool:
    """True se è stato chiamato un tool di ricerca web (qualunque tool NON-coach).

    Così resta corretto sia con DuckDuckGo (`web_search`) sia con Tavily sia con
    futuri provider, senza dover conoscerne il nome.
    """
    from chiron.coach_tools import get_coach_tools
    coach_names = {t.name for t in get_coach_tools()}
    for m in messages:
        if isinstance(m, AIMessage):
            for tc in getattr(m, "tool_calls", None) or []:
                if tc.get("name") and tc["name"] not in coach_names:
                    return True
    return False


def run_chiron(
    message: str,
    user_role: str,
    history: list[HistoryMessage] | None = None,
    coach_id: int | None = None,
    memory_summary: str = "",
) -> ChatResponse:
    """Invoca il grafo CHIRON e ritorna una ChatResponse strutturata.

    `coach_id` viaggia nel RunnableConfig (non nello stato né come argomento del
    modello): i coach tool lo leggono per filtrare i dati al solo coach.
    `memory_summary` è il riassunto della conversazione più vecchia (vedi
    chiron.memory): tiene il contesto limitato e bounded.
    """
    history = history or []
    initial_messages: list[BaseMessage] = _history_to_messages(history)
    initial_messages.append(HumanMessage(content=message))

    config = {"configurable": {"coach_id": coach_id}} if coach_id else None
    final_state = _get_graph().invoke(
        {
            "messages": initial_messages,
            "user_role": user_role,
            "memory_summary": memory_summary or "",
        },
        config=config,
    )

    all_messages: list[BaseMessage] = final_state.get("messages", [])
    answer = ""
    for m in reversed(all_messages):
        if isinstance(m, AIMessage) and not getattr(m, "tool_calls", None):
            answer = m.content if isinstance(m.content, str) else str(m.content)
            break

    return ChatResponse(
        response=answer,
        sources=_extract_sources(all_messages),
        used_web_search=_used_web_search(all_messages),
        actions=_extract_actions(all_messages),
        pending_action=_extract_pending_action(all_messages),
    )


def run_chiron_stream(
    message: str,
    user_role: str,
    history: list[HistoryMessage] | None = None,
    coach_id: int | None = None,
    memory_summary: str = "",
):
    """Versione streaming di `run_chiron`: generatore che produce i token della
    risposta finale man mano che il modello li genera, poi un evento finale con
    la `ChatResponse` completa (fonti/azioni/conferma).

    Yields dict: `{"token": str}` per ogni pezzo di testo, e infine
    `{"done": ChatResponse}`. I round di tool-calling non emettono testo (i
    chunk hanno content vuoto) quindi vengono saltati naturalmente.
    """
    history = history or []
    initial_messages: list[BaseMessage] = _history_to_messages(history)
    initial_messages.append(HumanMessage(content=message))

    config = {"configurable": {"coach_id": coach_id}} if coach_id else None
    final_state: dict | None = None
    for mode, data in _get_graph().stream(
        {
            "messages": initial_messages,
            "user_role": user_role,
            "memory_summary": memory_summary or "",
        },
        config=config,
        stream_mode=["messages", "values"],
    ):
        if mode == "messages":
            chunk, meta = data
            # Only the answer node's text tokens — tool-deciding chunks carry no
            # content, so they're skipped without a tool_calls check.
            if (isinstance(chunk, AIMessage)
                    and meta.get("langgraph_node") == "chiron_agent"):
                text = chunk.content if isinstance(chunk.content, str) else ""
                if text:
                    yield {"token": text}
        elif mode == "values":
            final_state = data

    all_messages: list[BaseMessage] = (final_state or {}).get("messages", [])
    answer = ""
    for m in reversed(all_messages):
        if isinstance(m, AIMessage) and not getattr(m, "tool_calls", None):
            answer = m.content if isinstance(m.content, str) else str(m.content)
            break

    yield {"done": ChatResponse(
        response=answer,
        sources=_extract_sources(all_messages),
        used_web_search=_used_web_search(all_messages),
        actions=_extract_actions(all_messages),
        pending_action=_extract_pending_action(all_messages),
    )}
