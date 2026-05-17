"""Grafo LangGraph di CHIRON. Tutto lazy-load per evitare crash all'import."""

import json
import operator
from functools import lru_cache
from typing import Annotated, TypedDict

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
from chiron.schemas import ChatResponse, HistoryMessage, Source
from chiron.tools import get_tools


class ChironState(TypedDict):
    messages: Annotated[list[BaseMessage], operator.add]
    user_role: str


@lru_cache(maxsize=1)
def _get_llm_with_tools():
    """
    Istanzia il LLM legato ai tool. Usa Ollama Cloud via endpoint OpenAI-compatibile.
    Richiede OLLAMA_API_KEY in env. Endpoint configurabile via OLLAMA_BASE_URL.
    """
    llm = ChatOpenAI(
        model=pick_model("chat"),
        temperature=0.3,
        api_key=config("OLLAMA_API_KEY"),
        base_url=config("OLLAMA_BASE_URL", default="https://ollama.com/v1"),
    )
    return llm.bind_tools(get_tools())


def _chiron_node(state: ChironState) -> dict:
    """Nodo principale: applica system prompt per ruolo e invoca LLM."""
    system_prompt = get_system_prompt(state["user_role"])
    messages = [SystemMessage(content=system_prompt)] + state["messages"]
    response = _get_llm_with_tools().invoke(messages)
    return {"messages": [response]}


@lru_cache(maxsize=1)
def _get_graph():
    builder = StateGraph(ChironState)
    builder.add_node("chiron_agent", _chiron_node)
    builder.add_node("web_search", ToolNode(get_tools()))

    builder.add_edge(START, "chiron_agent")
    builder.add_conditional_edges("chiron_agent", tools_condition, {
        "tools": "web_search",
        END: END,
    })
    builder.add_edge("web_search", "chiron_agent")
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
    """Estrae fonti dai ToolMessage prodotti da TavilySearch."""
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
        results = []
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
                sources.append(Source(title=title[:200], url=url))
    return sources


def run_chiron(
    message: str,
    user_role: str,
    history: list[HistoryMessage] | None = None,
) -> ChatResponse:
    """Invoca il grafo CHIRON e ritorna una ChatResponse strutturata."""
    history = history or []
    initial_messages: list[BaseMessage] = _history_to_messages(history)
    initial_messages.append(HumanMessage(content=message))

    final_state = _get_graph().invoke({
        "messages": initial_messages,
        "user_role": user_role,
    })

    all_messages: list[BaseMessage] = final_state.get("messages", [])
    answer = ""
    for m in reversed(all_messages):
        if isinstance(m, AIMessage) and not getattr(m, "tool_calls", None):
            answer = m.content if isinstance(m.content, str) else str(m.content)
            break

    sources = _extract_sources(all_messages)
    used_web = any(isinstance(m, ToolMessage) for m in all_messages)

    return ChatResponse(
        response=answer,
        sources=sources,
        used_web_search=used_web,
    )
