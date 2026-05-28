"""Shared types for the LLM import pipelines (nutrition, workouts).

Single source of truth for the extraction error and the confidence summary so
the two domains cannot drift apart. Domain-specific schemas (ExerciseEntry,
FoodEntry, the per-domain ConfirmPayload, ...) stay in their own modules.
"""

from pydantic import BaseModel


class AIExtractionError(Exception):
    """LLM failed or returned invalid JSON (across all chunks where applicable)."""


class ConfidenceSummary(BaseModel):
    fields_total: int = 0
    fields_uncertain: int = 0
    ratio: float = 0.0
