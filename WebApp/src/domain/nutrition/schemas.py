"""Pydantic schemas per l'import dieta da Excel.

Validano la risposta JSON dell'LLM e il payload di conferma del frontend.
"""

from typing import Literal, Optional
from pydantic import BaseModel, Field, ConfigDict

from domain.shared.extraction import ConfidenceSummary  # noqa: F401  (re-export)


DayOfWeek = Literal[
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
]

MealType = Literal[
    'BREAKFAST', 'MORNING_SNACK', 'LUNCH', 'AFTERNOON_SNACK', 'DINNER',
]

Unit = Literal['g', 'ml', 'portion', 'tbsp', 'tsp']

SubstitutionMode = Literal['ISOKCAL', 'ISOPROT', 'ISOCARB']


class SubstitutionEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    name: str
    quantity: Optional[float] = None
    unit: Unit = 'g'
    mode: SubstitutionMode = 'ISOKCAL'
    food_id: Optional[int] = None
    candidates: list[dict] = Field(default_factory=list)
    uncertain: bool = False
    notes: Optional[str] = None
    source_page: Optional[int] = None
    source_chunk: Optional[str] = None


class FoodEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    name: str
    quantity: Optional[float] = None
    unit: Unit = 'g'
    food_id: Optional[int] = None
    candidates: list[dict] = Field(default_factory=list)
    uncertain: bool = False
    notes: Optional[str] = None
    calories: Optional[float] = None
    protein_g: Optional[float] = None
    carbs_g: Optional[float] = None
    fat_g: Optional[float] = None
    source_page: Optional[int] = None
    source_chunk: Optional[str] = None
    substitutions: list[SubstitutionEntry] = Field(default_factory=list)


class MealEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    meal_type: MealType
    foods: list[FoodEntry] = Field(default_factory=list)


class DayEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    day_of_week: DayOfWeek
    meals: list[MealEntry] = Field(default_factory=list)


class SupplementEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    name: str
    dose: Optional[str] = None
    timing: Optional[str] = None
    notes: Optional[str] = None
    uncertain: bool = False
    supplement_id: Optional[int] = None
    candidates: list[dict] = Field(default_factory=list)
    source_page: Optional[int] = None


class DietExtraction(BaseModel):
    """Output normalizzato dell'estrazione AI + match Food."""
    model_config = ConfigDict(extra='ignore')

    diet_name: Optional[str] = None
    days: list[DayEntry] = Field(default_factory=list)
    supplements: list[SupplementEntry] = Field(default_factory=list)
    extraction_notes: Optional[str] = None
    total_calories_daily: Optional[float] = None
    notes: Optional[str] = None


class ConfirmPayload(BaseModel):
    """Body POST per /api/nutrizione/import/conferma/."""
    model_config = ConfigDict(extra='ignore')

    diet_json: DietExtraction
    client_id: int
    plan_title: str
    notes: Optional[str] = None
    assign_now: bool = True
