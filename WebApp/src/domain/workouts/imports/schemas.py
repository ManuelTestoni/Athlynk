"""Pydantic schemas for workout import (Excel + PDF).

Validate the LLM extraction JSON and the confirm payload from the frontend.
Mirrors nutrition.schemas style.
"""

from typing import Literal, Optional, Union
from pydantic import BaseModel, Field, ConfigDict

from domain.shared.extraction import ConfidenceSummary  # noqa: F401  (re-export)


DayOfWeek = Literal[
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
]

BlockType = Literal['straight', 'superset', 'circuit', 'emom', 'amrap']

RepsType = Literal['fixed', 'range', 'amrap', 'time', 'distance']
LoadUnit = Literal['kg', 'lb', 'bw', 'band']
LoadType = Literal['absolute', 'percentage_1rm', 'rpe']
DistanceUnit = Literal['m', 'km', 'mi']
MatchConfidence = Literal['exact', 'high', 'medium', 'low', 'none']
MatchMethod = Literal['exact', 'normalized', 'fuzzy', 'semantic', 'manual']


class ExerciseEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    raw_name: str
    # English rendering produced by the extractor; the catalogue is English, the
    # documents are Italian. See `exercise_match.best_match`.
    name_en: Optional[str] = None
    matched_exercise_id: Optional[int] = None
    matched_exercise_name: Optional[str] = None
    matched_primary_muscle: Optional[str] = None
    matched_equipment: Optional[str] = None
    match_confidence: MatchConfidence = 'none'
    match_method: Optional[MatchMethod] = None
    uncertain: bool = False

    sets: Optional[int] = None
    reps: Optional[Union[int, str]] = None
    reps_type: Optional[RepsType] = None

    load: Optional[float] = None
    load_unit: Optional[LoadUnit] = None
    load_type: Optional[LoadType] = None
    rpe: Optional[float] = None
    rir: Optional[int] = None
    tempo: Optional[str] = None

    rest_seconds: Optional[int] = None
    rest_label: Optional[str] = None

    distance: Optional[float] = None
    distance_unit: Optional[DistanceUnit] = None
    duration_seconds: Optional[int] = None

    notes: Optional[str] = None
    source_page: Optional[int] = None
    source_chunk: Optional[str] = None

    candidates: list[dict] = Field(default_factory=list)


class BlockEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    block_name: Optional[str] = None
    block_type: Optional[BlockType] = None
    exercises: list[ExerciseEntry] = Field(default_factory=list)


class SessionEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    day_label: str = ''
    day_of_week: Optional[DayOfWeek] = None
    session_type: Optional[str] = None
    order_index: int = 0
    notes: Optional[str] = None
    blocks: list[BlockEntry] = Field(default_factory=list)


class DocumentSummary(BaseModel):
    model_config = ConfigDict(extra='ignore')

    total_pages: Optional[int] = None
    pages_processed: Optional[int] = None
    pages_skipped: Optional[int] = None
    relevant_pages: list[int] = Field(default_factory=list)
    ocr_pages: Optional[int] = None


class WorkoutExtraction(BaseModel):
    """Top-level normalized AI extraction + Exercise DB match."""
    model_config = ConfigDict(extra='ignore')

    plan_name: Optional[str] = None
    frequency_per_week: Optional[int] = None
    goal: Optional[str] = None
    notes: Optional[str] = None
    sessions: list[SessionEntry] = Field(default_factory=list)
    extraction_notes: list[str] = Field(default_factory=list)
    document_summary: Optional[DocumentSummary] = None


class ConfirmPayload(BaseModel):
    """POST body for /api/allenamenti/import/conferma/."""
    model_config = ConfigDict(extra='ignore')

    workout_json: WorkoutExtraction
    client_id: Optional[int] = None
    plan_title: str
    notes: Optional[str] = None
    assign_now: bool = False
