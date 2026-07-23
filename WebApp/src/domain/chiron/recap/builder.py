"""Orchestratore del recap atleta: aggrega, genera insight, forecast e
narrativa, applica il gating FULL/WORKOUT/NUTRITION e persiste in
AthleteRecap.

Gating nel builder, non solo nella view (difesa in profondità, §7 del
piano): una sezione fuori scope per questo coach non viene nemmeno
calcolata, quindi un bug nella view non può farla trapelare.
"""

import hashlib
import json
import logging
from datetime import date

from django.core.cache import cache

from config.services import cachekeys
from config.session_utils import get_active_relationships

from . import aggregates_body, aggregates_nutrition, aggregates_training
from . import insights as insights_engine
from . import forecast as forecast_engine
from . import narrative as narrative_engine
from .schemas import RecapPayload, RecapScorecards, RecapComparison, WeightPoint

logger = logging.getLogger(__name__)

CACHE_TTL_SECONDS = 20 * 60

_EMPTY_NUTRITION = {
    'available': False, 'reliable': False, 'n_log_days': 0,
    'weekday_pct': None, 'weekend_pct': None, 'overall_pct': None, 'window_days': 30,
    'weekly_pct_series': [],
}


def _coach_scope(coach, client):
    """Domini che QUESTO coach può vedere per questo atleta, secondo la sua
    relationship_type (FULL copre tutto; WORKOUT/NUTRITION solo il proprio)."""
    rels = get_active_relationships(client)
    training_ok = bool(rels['full'] and rels['full'].coach_id == coach.id) or \
                  bool(rels['workout'] and rels['workout'].coach_id == coach.id)
    nutrition_ok = bool(rels['full'] and rels['full'].coach_id == coach.id) or \
                   bool(rels['nutrition'] and rels['nutrition'].coach_id == coach.id)
    return {'training': training_ok, 'nutrition': nutrition_ok}


def _facts_hash(facts):
    raw = json.dumps(facts, sort_keys=True, default=str).encode('utf-8')
    return hashlib.sha256(raw).hexdigest()


def _compute_aggregates(client, scope):
    body = aggregates_body.compute_body_comp(client)
    training = aggregates_training.compute_training(client) if scope['training'] else {}
    nutrition = aggregates_nutrition.compute_nutrition(client) if scope['nutrition'] else _EMPTY_NUTRITION
    return {'body': body, 'training': training, 'nutrition': nutrition}


def _scorecards(body, training, nutrition):
    weight = body.get('weight', {})
    training = training or {}
    adherence = training.get('adherence') or {}
    rpe_series = (training.get('rpe') or {}).get('series') or []
    recent_rpe = [w['avg_rpe'] for w in rpe_series[-4:]]

    weight_series = weight.get('series') or []
    last_point = max(weight_series, key=lambda p: p[0]) if weight_series else None
    waist = (body.get('circumferences') or {}).get('waist', {})

    return RecapScorecards(
        weight_current=weight.get('current_avg'),
        weight_delta=weight.get('delta'),
        weight_reliable=bool(weight.get('reliable')),
        weight_last_value=last_point[1] if last_point else None,
        weight_last_days_ago=(date.today() - last_point[0]).days if last_point else None,
        weight_series=[WeightPoint(date=d.isoformat(), value=v) for d, v in weight_series],
        waist_current=waist.get('current_avg'),
        waist_delta=waist.get('delta'),
        waist_reliable=bool(waist.get('reliable')),
        training_adherence_pct=adherence.get('overall_pct'),
        training_reliable=bool(adherence.get('reliable')),
        nutrition_adherence_pct=nutrition.get('overall_pct'),
        nutrition_reliable=bool(nutrition.get('reliable')),
        avg_rpe=round(sum(recent_rpe) / len(recent_rpe), 1) if recent_rpe else None,
        sessions_done_recent=sum(w['done'] for w in adherence.get('series') or []) or None,
    )


def _build_comparison(previous, candidate_insights, weight_current):
    """Diff testuale rispetto al recap precedente (stesso coach+client) —
    V2: storico append-only, non serve una tabella di confronto separata."""
    if not previous:
        return RecapComparison(available=False)
    previous_codes = {i['code'] for i in (previous.facts_json.get('insights') or [])}
    current_codes = {i.code for i in candidate_insights}
    prev_weight = previous.facts_json.get('weight_current')
    weight_delta = (
        round(weight_current - prev_weight, 2)
        if (weight_current is not None and prev_weight is not None) else None
    )
    return RecapComparison(
        available=True,
        previous_generated_at=previous.generated_at.isoformat(),
        new_insight_codes=sorted(current_codes - previous_codes),
        resolved_insight_codes=sorted(previous_codes - current_codes),
        weight_delta_since_last_recap=weight_delta,
    )


def build_recap(coach, client, force_refresh=False):
    """Genera (o rigenera) il recap per questo atleta dal punto di vista di
    questo coach. force_refresh=True (bottone "aggiorna" coach-iniziato)
    bypassa la cache degli aggregati, rigenera la narrativa e forza una nuova
    riga di storico anche se i fatti non sono cambiati."""
    from domain.chiron.models import AthleteRecap, CoachRecapSettings

    scope = _coach_scope(coach, client)
    cache_key = cachekeys.athlete_recap(coach.id, client.id)

    aggregates = None if force_refresh else cache.get(cache_key)
    if aggregates is None:
        aggregates = _compute_aggregates(client, scope)
        cache.set(cache_key, aggregates, CACHE_TTL_SECONDS)

    body, training, nutrition = aggregates['body'], aggregates['training'], aggregates['nutrition']

    # V3 prep: soglie di anomalia per-coach, se mai impostate — altrimenti i
    # default di insights.DEFAULT_THRESHOLDS si applicano invariati.
    settings_row = CoachRecapSettings.objects.filter(coach=coach).first()
    thresholds = settings_row.thresholds if settings_row else {}

    candidate_insights = insights_engine.generate_insights(body, nutrition, training, thresholds=thresholds)
    weight_forecast = forecast_engine.forecast_weight(body.get('weight', {}).get('series') or [])

    waist_series = (body.get('circumferences') or {}).get('waist', {}).get('series') or []
    waist_forecast = forecast_engine.forecast_circumference(waist_series, 'waist')
    nutrition_forecast = forecast_engine.forecast_nutrition_adherence(nutrition.get('weekly_pct_series') or [])
    weight_current = (body.get('weight') or {}).get('current_avg')

    facts = {
        'insights': [i.model_dump() for i in candidate_insights],
        'forecast': weight_forecast.model_dump(),
        'forecast_waist': waist_forecast.model_dump(),
        'forecast_nutrition': nutrition_forecast.model_dump(),
        'weight_current': weight_current,
        'scope': scope,
    }
    content_hash = _facts_hash(facts)

    latest = AthleteRecap.objects.filter(coach=coach, client=client).first()  # Meta.ordering = -generated_at

    if not force_refresh and latest and latest.content_hash == content_hash:
        # Niente di nuovo: nessuna riga di storico in più, si ri-mostra l'ultima.
        recap = latest
        narrative_text, is_fallback = latest.narrative_text, latest.narrative_is_fallback
    else:
        athlete_name = f"{client.first_name} {client.last_name}".strip()
        narrative_text, is_fallback = narrative_engine.generate_narrative(candidate_insights, athlete_name)
        recap = AthleteRecap.objects.create(
            coach=coach, client=client, facts_json=facts,
            narrative_text=narrative_text, narrative_is_fallback=is_fallback,
            content_hash=content_hash,
        )

    previous = (
        AthleteRecap.objects.filter(coach=coach, client=client)
        .exclude(id=recap.id).first()
    )
    comparison = _build_comparison(previous, candidate_insights, weight_current)

    return RecapPayload(
        client_id=client.id,
        coach_id=coach.id,
        generated_at=recap.generated_at.isoformat(),
        data_sufficiency={
            'weight': bool(body.get('weight', {}).get('reliable')),
            'training': bool((training or {}).get('adherence', {}).get('reliable')),
            'nutrition': bool(nutrition.get('reliable')),
        },
        scorecards=_scorecards(body, training, nutrition),
        insights=candidate_insights,
        forecast=weight_forecast,
        forecast_waist=waist_forecast,
        forecast_nutrition=nutrition_forecast,
        comparison=comparison,
        narrative_text=narrative_text,
        narrative_is_fallback=is_fallback,
        sections_available=scope,
    )
