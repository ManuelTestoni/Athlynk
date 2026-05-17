"""Routing tra modelli LLM. Stub per Fase 1."""

from decouple import config


def pick_model(intent: str = "chat") -> str:
    """
    Sceglie il modello in base all'intento.
    Fase 1: sempre il modello chat da OLLAMA_MODEL (default gpt-oss:120b).
    Fase 2: routing verso modelli più capaci per output strutturati (diete, allenamenti).
    """
    # TODO Fase 2: if intent in ("create_diet", "create_workout"): return config("OLLAMA_MODEL_STRUCTURED", default="gpt-oss:120b")
    return config("OLLAMA_MODEL", default="gpt-oss:120b")
