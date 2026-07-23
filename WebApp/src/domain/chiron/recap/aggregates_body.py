"""Aggregazioni composizione corporea per il recap CHIRON.

Generalizza _compute_deltas()/_build_chart_data() (config/views_check/helpers.py)
da "delta check-vs-check precedente" a "media blocco attuale (0-30gg) vs
blocco precedente (31-60gg)", con contesto fino a 90gg per il forecast.
Totale per costruzione: mai un'eccezione, valori mancanti -> None.
"""

from datetime import date, timedelta

from domain.checks.models import QuestionnaireResponse
from domain.checks.anthropometry import (
    order_circ_keys, order_skin_keys, circ_label, skin_label,
    circ_range, skin_range, WEIGHT_RANGE,
)

MIN_RELIABLE_N = 3
CONTEXT_WINDOW_DAYS = 90
CURRENT_BLOCK_DAYS = 30


def _clean(value, value_range):
    """float(value) se dentro il range plausibile ISAK, altrimenti None —
    scarta outlier (errori di battitura) prima che sporchino un delta."""
    if value in (None, ''):
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    lo, hi = value_range
    return v if lo <= v <= hi else None


def _avg(values):
    return round(sum(values) / len(values), 2) if values else None


def _metric_block(current_map, previous_map, series_map, keys, label_fn):
    out = {}
    for key in keys:
        cur = current_map.get(key, [])
        prev = previous_map.get(key, [])
        cur_avg, prev_avg = _avg(cur), _avg(prev)
        delta = round(cur_avg - prev_avg, 2) if (cur_avg is not None and prev_avg is not None) else None
        out[key] = {
            'label': label_fn(key),
            'current_avg': cur_avg,
            'previous_avg': prev_avg,
            'delta': delta,
            'n_current': len(cur),
            'n_previous': len(prev),
            'reliable': (len(cur) + len(prev)) >= MIN_RELIABLE_N,
            # Serie completa (data, valore) sui 90gg — per il forecast esteso
            # a circonferenze/pliche (V2), non solo al peso.
            'series': sorted(series_map.get(key, [])),
        }
    return out


def compute_body_comp(client, today=None):
    """Peso (con serie completa per il forecast) + circonferenze/pliche
    per-chiave ISAK, ciascuna con la propria soglia di affidabilità
    indipendente (un atleta può avere molte pesate rapide e un solo check
    completo: peso affidabile, vita no)."""
    today = today or date.today()
    context_start = today - timedelta(days=CONTEXT_WINDOW_DAYS)
    current_start = today - timedelta(days=CURRENT_BLOCK_DAYS)

    responses = list(
        QuestionnaireResponse.objects
        .filter(client=client, submitted_at__date__gte=context_start, submitted_at__date__lte=today)
        .order_by('submitted_at')
        .values('submitted_at', 'weight_kg', 'body_circumferences', 'skinfolds')
    )

    weight_points = []  # [(date, value)] su tutta la finestra 90gg, per il forecast
    weight_current, weight_previous = [], []
    circ_keys, skin_keys = set(), set()
    circ_current, circ_previous, circ_series = {}, {}, {}
    skin_current, skin_previous, skin_series = {}, {}, {}

    for r in responses:
        d = r['submitted_at'].date()
        is_current = d >= current_start

        w = _clean(r['weight_kg'], WEIGHT_RANGE)
        if w is not None:
            weight_points.append((d, w))
            (weight_current if is_current else weight_previous).append(w)

        for key, raw in (r['body_circumferences'] or {}).items():
            value_range = circ_range(key)
            if value_range is None:
                continue
            v = _clean(raw, value_range)
            if v is None:
                continue
            circ_keys.add(key)
            (circ_current if is_current else circ_previous).setdefault(key, []).append(v)
            circ_series.setdefault(key, []).append((d, v))

        for key, raw in (r['skinfolds'] or {}).items():
            v = _clean(raw, skin_range(key))
            if v is None:
                continue
            skin_keys.add(key)
            (skin_current if is_current else skin_previous).setdefault(key, []).append(v)
            skin_series.setdefault(key, []).append((d, v))

    weight_current_avg, weight_previous_avg = _avg(weight_current), _avg(weight_previous)
    weight_delta = (
        round(weight_current_avg - weight_previous_avg, 2)
        if (weight_current_avg is not None and weight_previous_avg is not None) else None
    )

    return {
        'weight': {
            'current_avg': weight_current_avg,
            'previous_avg': weight_previous_avg,
            'delta': weight_delta,
            'n_current': len(weight_current),
            'n_previous': len(weight_previous),
            'reliable': (len(weight_current) + len(weight_previous)) >= MIN_RELIABLE_N,
            'series': weight_points,
        },
        'circumferences': _metric_block(circ_current, circ_previous, circ_series, order_circ_keys(circ_keys), circ_label),
        'skinfolds': _metric_block(skin_current, skin_previous, skin_series, order_skin_keys(skin_keys), skin_label),
    }
