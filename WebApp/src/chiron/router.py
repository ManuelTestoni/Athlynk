"""Routing tra modelli LLM."""

from decouple import config


def pick_model(intent: str = "chat") -> str:
    """
    Sceglie il modello in base all'intento.
    Chat semplice va sul modello leggero (OLLAMA_MODEL_LIGHT) per costo; summary
    ed extraction (import PDF/Excel) restano sul modello pesante (OLLAMA_MODEL)
    perché qualità/affidabilità contano più del costo. Se OLLAMA_MODEL_LIGHT non
    è impostata, "chat" ricade sullo stesso modello pesante (no-op).
    """
    heavy = config("OLLAMA_MODEL", default="gpt-oss:120b")
    if intent == "chat":
        return config("OLLAMA_MODEL_LIGHT", default=heavy)
    return heavy
