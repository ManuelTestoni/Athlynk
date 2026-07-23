"""Pydantic: contratto del payload del recap atleta (boundary API).

Vive separato da chiron/schemas.py (contratto della chat LangGraph, ciclo di
vita diverso) ma segue lo stesso stile.
"""

from typing import Literal
from pydantic import BaseModel, Field

Confidence = Literal["low", "medium", "high"]
Domain = Literal["body_comp", "nutrition", "training", "cross"]
Direction = Literal["up", "stable", "down"]


class Evidence(BaseModel):
    """Dati grezzi puntuali che giustificano un insight — sempre allegati,
    mai un claim senza un modo di verificarlo."""
    metric: str
    window: str
    current_value: float | None = None
    previous_value: float | None = None
    n_current: int | None = None
    n_previous: int | None = None
    extra: dict = Field(default_factory=dict)


class RecapInsight(BaseModel):
    code: str
    domain: Domain
    observation: str
    interpretation: str
    recommendation: str | None = None
    confidence: Confidence
    evidence: Evidence


class RecapForecast(BaseModel):
    metric: str
    available: bool
    direction: Direction | None = None
    confidence: Confidence | None = None
    projected_2w: float | None = None
    projected_4w: float | None = None
    caveat: str


class WeightPoint(BaseModel):
    date: str
    value: float


class RecapScorecards(BaseModel):
    """Numeri grezzi (non insight) per la riga di scorecard — §2 del piano.
    Nessun calcolo nuovo: proiezione di ciò che aggregates_* ha già prodotto."""
    weight_current: float | None = None
    weight_delta: float | None = None
    weight_reliable: bool = False
    # Ultimo peso noto anche se fuori dagli ultimi 30gg (weight_current è None
    # in quel caso) — evita lo scorecard vuoto quando l'ultima pesata è, es.,
    # di 35gg fa: mostrare "nessun dato" mentre la Direzione usa la stessa
    # serie e produce comunque una proiezione è incoerente per il coach.
    weight_last_value: float | None = None
    weight_last_days_ago: int | None = None
    weight_series: list[WeightPoint] = Field(default_factory=list)
    # Vita: stesso trattamento del peso ma dominio "circonferenze" — V2.
    waist_current: float | None = None
    waist_delta: float | None = None
    waist_reliable: bool = False
    training_adherence_pct: float | None = None
    training_reliable: bool = False
    nutrition_adherence_pct: float | None = None
    nutrition_reliable: bool = False
    avg_rpe: float | None = None
    sessions_done_recent: int | None = None


class RecapComparison(BaseModel):
    """Rispetto al recap precedente (stesso coach+client) cosa è cambiato —
    V2: storico append-only invece di upsert singolo. available=False se
    questo è il primo recap mai generato per questa coppia coach/atleta."""
    available: bool = False
    previous_generated_at: str | None = None
    new_insight_codes: list[str] = Field(default_factory=list)
    resolved_insight_codes: list[str] = Field(default_factory=list)
    weight_delta_since_last_recap: float | None = None


class RecapPayload(BaseModel):
    client_id: int
    coach_id: int
    generated_at: str
    data_sufficiency: dict = Field(default_factory=dict)
    scorecards: RecapScorecards = Field(default_factory=RecapScorecards)
    insights: list[RecapInsight] = Field(default_factory=list)
    forecast: RecapForecast | None = None
    # Forecast secondari (V2) — mai sostituiscono l'headline "Direzione"
    # (sempre il peso): vita e aderenza nutrizionale settimanale, con soglie
    # più severe perché più sparsi/rumorosi. None se il coach non ha accesso
    # al dominio (gating) o il forecast non è disponibile.
    forecast_waist: RecapForecast | None = None
    forecast_nutrition: RecapForecast | None = None
    comparison: RecapComparison = Field(default_factory=RecapComparison)
    narrative_text: str = ''
    narrative_is_fallback: bool = False
    # {'training': bool, 'nutrition': bool} — sezioni che QUESTO coach può
    # vedere per questo atleta, secondo il suo relationship_type.
    sections_available: dict = Field(default_factory=dict)
