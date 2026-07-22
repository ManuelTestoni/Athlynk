"""Pydantic schemas per l'import dieta da Excel.

Validano la risposta JSON dell'LLM e il payload di conferma del frontend.
"""

from typing import Annotated, Literal, Optional
from pydantic import BaseModel, Field, ConfigDict, BeforeValidator

from domain.shared.extraction import ConfidenceSummary  # noqa: F401  (re-export)


DayOfWeek = Literal[
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
]

MealType = Literal[
    'BREAKFAST', 'MORNING_SNACK', 'LUNCH', 'AFTERNOON_SNACK', 'DINNER',
]

SubstitutionMode = Literal['ISOKCAL', 'ISOPROT', 'ISOCARB']

# The LLM often omits `unit` or emits null / a synonym ("grammi", "cucchiaio",
# "porzione"). A bare `unit: <Literal> = 'g'` default only fills an ABSENT key — an
# explicit null still fails the Literal, which used to blow up the WHOLE extraction
# (one weekly grid produced 77 validation errors → import failed → wizard stalled).
# A BeforeValidator on the type coerces anything unrecognized to grams, so a missing
# or odd unit can never fail validation — applied everywhere `unit: Unit` is used.
_UNIT_ALIASES = {
    'g': 'g', 'gr': 'g', 'grammo': 'g', 'grammi': 'g', 'gram': 'g', 'grams': 'g',
    'ml': 'ml', 'millilitro': 'ml', 'millilitri': 'ml', 'milliliter': 'ml',
    'milliliters': 'ml', 'cc': 'ml',
    'portion': 'portion', 'porzione': 'portion', 'porzioni': 'portion',
    'pz': 'portion', 'pezzo': 'portion', 'pezzi': 'portion', 'unita': 'portion',
    'unità': 'portion', 'unit': 'portion',
    'tbsp': 'tbsp', 'cucchiaio': 'tbsp', 'cucchiai': 'tbsp', 'tablespoon': 'tbsp',
    'tsp': 'tsp', 'cucchiaino': 'tsp', 'cucchiaini': 'tsp', 'teaspoon': 'tsp',
}


def _coerce_unit(value):
    if value is None:
        return 'g'
    return _UNIT_ALIASES.get(str(value).strip().lower(), 'g')


Unit = Annotated[
    Literal['g', 'ml', 'portion', 'tbsp', 'tsp'],
    BeforeValidator(_coerce_unit),
]


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
    target_kcal: Optional[int] = None
    target_protein_g: Optional[int] = None
    target_carb_g: Optional[int] = None
    target_fat_g: Optional[int] = None


class SupplementEntry(BaseModel):
    model_config = ConfigDict(extra='ignore')

    name: str
    dose: Optional[str] = None
    timing: Optional[str] = None
    notes: Optional[str] = None
    uncertain: bool = False
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

    # Structure hints (detector/LLM) — the coach can override in review.
    plan_mode: Optional[Literal['FOOD', 'MACRO']] = None
    plan_kind: Optional[Literal['DAILY', 'WEEKLY']] = None
    daily_kcal: Optional[int] = None
    protein_target_g: Optional[int] = None
    carb_target_g: Optional[int] = None
    fat_target_g: Optional[int] = None


class ConfirmPayload(BaseModel):
    """Body POST per /api/nutrizione/import/conferma/."""
    model_config = ConfigDict(extra='ignore')

    diet_json: DietExtraction
    plan_title: str
    notes: Optional[str] = None
