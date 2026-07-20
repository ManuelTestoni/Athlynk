"""Shared factory for the extraction LLM client.

Centralizes the ChatOpenAI setup (Ollama Cloud, JSON-object response, low
temperature, fixed seed) so every import domain (nutrition, workouts) uses the
identical configuration.
"""

from decouple import config
from langchain_openai import ChatOpenAI

from chiron.router import pick_model


def build_extraction_llm(max_tokens: int = 4000, timeout: int = 30) -> ChatOpenAI:
    return ChatOpenAI(
        model=pick_model("extraction"),
        temperature=0.0,
        api_key=config("OLLAMA_API_KEY"),
        base_url=config("OLLAMA_BASE_URL", default="https://ollama.com/v1"),
        max_completion_tokens=max_tokens,
        timeout=timeout,
        # openai-python defaults to max_retries=2 (3 attempts, full timeout each) —
        # that triples worst-case latency per chunk when Ollama Cloud is slow.
        # The pipeline already has its own chunk-level retry pass, so disable this.
        max_retries=0,
        model_kwargs={
            "response_format": {"type": "json_object"},
            "top_p": 1.0,
            "seed": 42,
        },
    )
