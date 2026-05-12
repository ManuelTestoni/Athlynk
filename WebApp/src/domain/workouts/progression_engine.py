"""Progression engine.

Layers, applied in order, per (WorkoutExercise, week_number):
  1. Base values from WorkoutExercise.
  2. ProgressionRule list (ordered by order_index) — resolves each rule's
     contribution for that week and merges into the running cell.
  3. Week-type modifiers (DELOAD / TEST / TECHNIQUE / RECOVERY) from
     WeekDefinition + auto-deload contributed by DEL_AUTO rules.
  4. WeeklyOverride (forces specific cells).

Public entry points:
  compute_weekly_values(plan) — recompute + persist WeeklyValue rows for a plan.
  compute_for_exercise(ex, weeks, draft_rules=None) — pure, no persistence.
  preview_rules(ex, draft_rules, weeks) — pure preview for unsaved rules.
"""

from __future__ import annotations

from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from typing import Iterable, Optional

from django.db import transaction

from .models import (
    Exercise,
    ExerciseVariantTransition,
    ProgressionRule,
    WeekDefinition,
    WeeklyOverride,
    WeeklyValue,
    WorkoutExercise,
    WorkoutPlan,
)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CLAMP = {
    'load': (Decimal('0'), Decimal('9999')),
    'sets': (1, 20),
    'reps': (1, 100),
    'rpe': (Decimal('1'), Decimal('10')),
    'rir': (0, 20),
    'rest': (0, 3600),
    'velocity': (Decimal('0'), Decimal('5')),
}

DELOAD_DEFAULTS = {
    'load_factor': 0.6,
    'volume_factor': 0.5,
    'rpe_cap': 6,
}

WUP_PRESETS = {
    'HYPERTROPHY': {'rep_range': '8-12', 'rpe': 8},
    'STRENGTH': {'rep_range': '3-5', 'rpe': 8},
    'POWER': {'rep_range': '2-4', 'rpe': 7},
    'DELOAD': {'rep_range': '5', 'rpe': 6, 'load_factor': 0.6, 'volume_factor': 0.6},
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _to_decimal(value) -> Optional[Decimal]:
    if value is None or value == '':
        return None
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def _round_to(value: Decimal, step: Decimal) -> Decimal:
    if step is None or step == 0:
        return value
    return (value / step).quantize(Decimal('1'), rounding=ROUND_HALF_UP) * step


def _clamp(metric: str, value):
    bounds = CLAMP.get(metric)
    if bounds is None or value is None:
        return value
    lo, hi = bounds
    if isinstance(value, Decimal) and not isinstance(lo, Decimal):
        lo, hi = Decimal(str(lo)), Decimal(str(hi))
    if isinstance(value, (int, float)) and isinstance(lo, Decimal):
        value = Decimal(str(value))
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def _base_cell(ex: WorkoutExercise) -> dict:
    return {
        'load_value': _to_decimal(ex.load_value),
        'load_unit': ex.load_unit or '',
        'set_count': ex.set_count,
        'rep_range': ex.rep_range or (str(ex.rep_count) if ex.rep_count else ''),
        'rpe': _to_decimal(ex.rpe),
        'rir': ex.rir,
        'recovery_seconds': ex.recovery_seconds,
        'tempo': ex.tempo or '',
        'rom_stage': '',
        'variant_exercise_id': None,
        'velocity_target': None,
        'notes': '',
        'is_override': False,
        'is_deload': False,
    }


def _key_for_metric(metric: str) -> str:
    return {
        'load': 'load_value',
        'sets': 'set_count',
        'reps': 'rep_range',
        'rep_range': 'rep_range',
        'rpe': 'rpe',
        'rir': 'rir',
        'rest': 'recovery_seconds',
        'tempo': 'tempo',
        'rom': 'rom_stage',
        'duration': 'duration',
        'exercise_variant': 'variant_exercise_id',
        'frequency': 'frequency',
        'velocity': 'velocity_target',
        'notes': 'notes',
    }.get(metric, metric)


# ---------------------------------------------------------------------------
# Per-subtype resolvers
# ---------------------------------------------------------------------------

def _weeks_active_in(rule: ProgressionRule | dict, week: int, max_week: int) -> bool:
    start = _attr(rule, 'start_week', 1) or 1
    end = _attr(rule, 'end_week', None)
    if end is None:
        end = max_week
    return start <= week <= end


def _attr(rule, name, default=None):
    if isinstance(rule, dict):
        return rule.get(name, default)
    return getattr(rule, name, default)


def _params(rule) -> dict:
    p = _attr(rule, 'parameters', {}) or {}
    if isinstance(p, str):
        import json
        try:
            p = json.loads(p)
        except Exception:
            p = {}
    return p


def _step_index(week: int, start_week: int, every_n: int) -> int:
    every_n = max(1, int(every_n or 1))
    return max(0, (week - start_week) // every_n)


def _apply_rule(rule, cell: dict, week: int, base: dict, max_week: int, conflicts: list) -> None:
    subtype = _attr(rule, 'subtype')
    metric = _attr(rule, 'target_metric')
    params = _params(rule)
    start = _attr(rule, 'start_week', 1) or 1

    if not _weeks_active_in(rule, week, max_week):
        return

    handler = _HANDLERS.get(subtype)
    if handler is None:
        return
    handler(rule, cell, base, week, start, params, conflicts)


# --- LOAD ------------------------------------------------------------------

def _h_load_linear(rule, cell, base, week, start, params, conflicts):
    base_load = _to_decimal(base.get('load_value')) or Decimal('0')
    delta = _to_decimal(params.get('delta')) or Decimal('0')
    every = int(params.get('every_n_weeks') or 1)
    steps = _step_index(week, start, every)
    new_value = base_load + (delta * steps)
    new_value = _clamp('load', new_value)
    cell['load_value'] = new_value
    if params.get('unit'):
        cell['load_unit'] = params['unit']


def _h_load_percent(rule, cell, base, week, start, params, conflicts):
    base_load = _to_decimal(base.get('load_value')) or Decimal('0')
    pct = _to_decimal(params.get('delta_pct')) or Decimal('0')
    every = int(params.get('every_n_weeks') or 1)
    steps = _step_index(week, start, every)
    factor = (Decimal('1') + (pct / Decimal('100'))) ** steps if steps else Decimal('1')
    new_value = base_load * factor
    round_to = _to_decimal(params.get('round_to')) or Decimal('1.25')
    new_value = _round_to(new_value, round_to)
    new_value = _clamp('load', new_value)
    cell['load_value'] = new_value


def _h_load_micro(rule, cell, base, week, start, params, conflicts):
    _h_load_linear(rule, cell, base, week, start, params, conflicts)


def _h_load_manual(rule, cell, base, week, start, params, conflicts):
    by_week = (params.get('by_week') or {})
    value = by_week.get(str(week)) or by_week.get(week)
    if value is None:
        return
    cell['load_value'] = _clamp('load', _to_decimal(value))


def _h_load_top_backoff(rule, cell, base, week, start, params, conflicts):
    # Top set value drives cell.load_value; backoff applied via notes (V1 stub).
    base_load = _to_decimal(base.get('load_value')) or Decimal('0')
    delta = _to_decimal(params.get('delta')) or Decimal('0')
    steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
    top = base_load + (delta * steps)
    cell['load_value'] = _clamp('load', top)
    backoff_pct = _to_decimal(params.get('backoff_pct'))
    if backoff_pct:
        cell['notes'] = (cell.get('notes') or '') + f" Back-off {backoff_pct}% top set."


# --- VOLUME ----------------------------------------------------------------

def _h_vol_sets(rule, cell, base, week, start, params, conflicts):
    start_val = int(params.get('start') or base.get('set_count') or 3)
    end_val = int(params.get('end') or start_val)
    step = int(params.get('step') or 1)
    steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
    value = start_val + step * steps
    if end_val >= start_val:
        value = min(value, end_val)
    else:
        value = max(value, end_val)
    cell['set_count'] = _clamp('sets', value)


def _h_vol_reps(rule, cell, base, week, start, params, conflicts):
    lo = int(params.get('min') or 6)
    hi = int(params.get('max') or 12)
    step = int(params.get('step') or 1)
    steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
    value = lo + step * steps
    if value > hi:
        value = hi
    cell['rep_range'] = str(value)


def _h_vol_sets_reps(rule, cell, base, week, start, params, conflicts):
    _h_vol_sets(rule, cell, base, week, start, params.get('sets', {}), conflicts)
    _h_vol_reps(rule, cell, base, week, start, params.get('reps', {}), conflicts)


def _h_vol_double(rule, cell, base, week, start, params, conflicts):
    """Double progression: increase reps within range; when reaching top, bump load.

    Model: each `every_n_weeks` step adds +1 rep. When reps > rep_high, reset to
    rep_low and bump load by `load_step`. Stored as rep_range string + load_value.
    """
    rep_low = int(params.get('rep_low') or 8)
    rep_high = int(params.get('rep_high') or 12)
    load_step = _to_decimal(params.get('load_step')) or Decimal('2.5')
    every = int(params.get('every_n_weeks') or 1)
    steps = _step_index(week, start, every)

    cycle_len = rep_high - rep_low + 1
    full_cycles, remainder = divmod(steps, cycle_len)
    current_reps = rep_low + remainder
    base_load = _to_decimal(base.get('load_value')) or Decimal('0')
    new_load = base_load + (load_step * full_cycles)
    cell['rep_range'] = str(current_reps)
    cell['load_value'] = _clamp('load', new_load)
    if params.get('load_unit'):
        cell['load_unit'] = params['load_unit']


def _h_vol_triple(rule, cell, base, week, start, params, conflicts):
    # Reps → sets → load. V1: store as note + use double progression for reps/load.
    _h_vol_double(rule, cell, base, week, start, params, conflicts)
    extra_sets = int(params.get('extra_sets') or 0)
    if extra_sets:
        cell['set_count'] = _clamp('sets', (base.get('set_count') or 3) + extra_sets)


# --- INTENSITY -------------------------------------------------------------

def _h_int_rpe(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None and 'start' in params:
        steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
        val = _to_decimal(params['start']) + (_to_decimal(params.get('delta') or 0) * steps)
    if val is None:
        return
    cell['rpe'] = _clamp('rpe', _to_decimal(val))


def _h_int_rir(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None and 'start' in params:
        steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
        val = int(params['start']) + int(params.get('delta') or 0) * steps
    if val is None:
        return
    cell['rir'] = int(_clamp('rir', int(val)))


def _h_int_pct1rm(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None and 'start' in params:
        steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
        val = _to_decimal(params['start']) + (_to_decimal(params.get('delta') or 0) * steps)
    if val is None:
        return
    cell['load_value'] = _to_decimal(val)
    cell['load_unit'] = 'PERCENT_1RM'


# --- DENSITY ---------------------------------------------------------------

def _h_den_rest(rule, cell, base, week, start, params, conflicts):
    base_rest = base.get('recovery_seconds')
    if base_rest is None:
        base_rest = params.get('start_seconds')
    if base_rest is None:
        return
    delta = int(params.get('delta_seconds') or 0)
    min_s = int(params.get('min_seconds') or 0)
    steps = _step_index(week, start, int(params.get('every_n_weeks') or 1))
    new_val = int(base_rest) + delta * steps
    if new_val < min_s:
        new_val = min_s
    cell['recovery_seconds'] = _clamp('rest', new_val)


def _h_den_time(rule, cell, base, week, start, params, conflicts):
    # V1: surface as note.
    target_min = params.get('target_minutes')
    if target_min:
        cell['notes'] = (cell.get('notes') or '') + f" Densità: completare in {target_min}'."


# --- TEMPO -----------------------------------------------------------------

def _h_tempo_preset(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val:
        cell['tempo'] = str(val)


def _h_tempo_ecc(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None:
        return
    # Mutate first digit of tempo (eccentric).
    current = cell.get('tempo') or '0000'
    if len(current) >= 4:
        cell['tempo'] = str(val) + current[1:]


def _h_tempo_con(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None:
        return
    current = cell.get('tempo') or '0000'
    if len(current) >= 4:
        cell['tempo'] = current[:2] + str(val) + current[3:]


def _h_tempo_pause(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None:
        return
    current = cell.get('tempo') or '0000'
    if len(current) >= 4:
        cell['tempo'] = current[0] + str(val) + current[2:]


# --- ROM -------------------------------------------------------------------

def _h_rom_increase(rule, cell, base, week, start, params, conflicts):
    stages = params.get('stages') or ['partial', 'mid', 'full']
    weeks_per = int(params.get('weeks_per_stage') or 1)
    idx = min(len(stages) - 1, _step_index(week, start, weeks_per))
    cell['rom_stage'] = stages[idx]


def _h_rom_deficit(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val:
        cell['rom_stage'] = f"deficit:{val}"


def _h_rom_pause(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val:
        cell['notes'] = (cell.get('notes') or '') + f" Pausa allungamento {val}s."


# --- VARIANT ---------------------------------------------------------------

def _h_var_transition(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val:
        try:
            cell['variant_exercise_id'] = int(val)
        except (TypeError, ValueError):
            pass


# --- FREQUENCY -------------------------------------------------------------

def _h_freq_add(rule, cell, base, week, start, params, conflicts):
    add_at = params.get('add_at_week')
    if add_at and int(add_at) <= week:
        cell['notes'] = (cell.get('notes') or '') + f" Frequenza aumentata da S{add_at}."


# --- UNDULATION ------------------------------------------------------------

def _h_und_wup(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    focus = by_week.get(str(week)) or by_week.get(week)
    if not focus:
        return
    preset = (params.get('presets') or {}).get(focus) or WUP_PRESETS.get(focus, {})
    if 'rep_range' in preset:
        cell['rep_range'] = preset['rep_range']
    if 'rpe' in preset:
        cell['rpe'] = _to_decimal(preset['rpe'])
    if focus == 'DELOAD':
        cell['is_deload'] = True
        base_load = _to_decimal(base.get('load_value')) or Decimal('0')
        cell['load_value'] = _clamp('load', base_load * Decimal(str(preset.get('load_factor', 0.6))))
        if cell.get('set_count'):
            cell['set_count'] = _clamp('sets', max(1, int(cell['set_count'] * preset.get('volume_factor', 0.6))))


def _h_und_dup(rule, cell, base, week, start, params, conflicts):
    # Same shape as WUP for V1. DUP per-session UI is V3.
    _h_und_wup(rule, cell, base, week, start, params, conflicts)


def _h_und_block(rule, cell, base, week, start, params, conflicts):
    blocks = params.get('blocks') or []
    # blocks = [{name, weeks: [...], preset: {...}}]
    for block in blocks:
        weeks = block.get('weeks') or []
        if week in weeks or str(week) in [str(w) for w in weeks]:
            preset = block.get('preset') or {}
            if 'rep_range' in preset:
                cell['rep_range'] = preset['rep_range']
            if 'rpe' in preset:
                cell['rpe'] = _to_decimal(preset['rpe'])
            if 'load_factor' in preset:
                base_load = _to_decimal(base.get('load_value')) or Decimal('0')
                cell['load_value'] = _clamp('load', base_load * _to_decimal(preset['load_factor']))
            break


# --- DELOAD ----------------------------------------------------------------

def _h_del_auto(rule, cell, base, week, start, params, conflicts):
    on_weeks = [int(w) for w in (params.get('on_weeks') or [])]
    if week not in on_weeks:
        return
    _apply_deload(cell, base, params)


def _h_del_manual(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    if str(week) in by_week or week in by_week:
        overrides = by_week.get(str(week)) or by_week.get(week) or {}
        merged = {**DELOAD_DEFAULTS, **overrides}
        _apply_deload(cell, base, merged)


def _apply_deload(cell, base, params):
    base_load = _to_decimal(cell.get('load_value') or base.get('load_value')) or Decimal('0')
    load_factor = _to_decimal(params.get('load_factor', DELOAD_DEFAULTS['load_factor']))
    vol_factor = float(params.get('volume_factor', DELOAD_DEFAULTS['volume_factor']))
    rpe_cap = _to_decimal(params.get('rpe_cap', DELOAD_DEFAULTS['rpe_cap']))
    cell['load_value'] = _clamp('load', base_load * load_factor)
    if cell.get('set_count'):
        cell['set_count'] = _clamp('sets', max(1, int(cell['set_count'] * vol_factor)))
    if cell.get('rpe') is None or cell['rpe'] > rpe_cap:
        cell['rpe'] = rpe_cap
    cell['is_deload'] = True


# --- VELOCITY --------------------------------------------------------------

def _h_vel_target(rule, cell, base, week, start, params, conflicts):
    by_week = params.get('by_week') or {}
    val = by_week.get(str(week)) or by_week.get(week)
    if val is None:
        return
    cell['velocity_target'] = _to_decimal(val)


def _h_vel_range(rule, cell, base, week, start, params, conflicts):
    lo = params.get('min')
    hi = params.get('max')
    if lo and hi:
        cell['notes'] = (cell.get('notes') or '') + f" Velocità {lo}-{hi} m/s."


_HANDLERS = {
    'LOAD_LINEAR': _h_load_linear,
    'LOAD_PERCENT': _h_load_percent,
    'LOAD_MICRO': _h_load_micro,
    'LOAD_MANUAL': _h_load_manual,
    'LOAD_TOP_BACKOFF': _h_load_top_backoff,
    'VOL_SETS': _h_vol_sets,
    'VOL_REPS': _h_vol_reps,
    'VOL_SETS_REPS': _h_vol_sets_reps,
    'VOL_DOUBLE': _h_vol_double,
    'VOL_TRIPLE': _h_vol_triple,
    'INT_RPE': _h_int_rpe,
    'INT_RIR': _h_int_rir,
    'INT_PCT1RM': _h_int_pct1rm,
    'DEN_REST': _h_den_rest,
    'DEN_TIME': _h_den_time,
    'TEMPO_PRESET': _h_tempo_preset,
    'TEMPO_ECC': _h_tempo_ecc,
    'TEMPO_CON': _h_tempo_con,
    'TEMPO_PAUSE': _h_tempo_pause,
    'ROM_INCREASE': _h_rom_increase,
    'ROM_DEFICIT': _h_rom_deficit,
    'ROM_PAUSE': _h_rom_pause,
    'VAR_TRANSITION': _h_var_transition,
    'FREQ_ADD': _h_freq_add,
    'UND_WUP': _h_und_wup,
    'UND_DUP': _h_und_dup,
    'UND_BLOCK': _h_und_block,
    'DEL_AUTO': _h_del_auto,
    'DEL_MANUAL': _h_del_manual,
    'VEL_TARGET': _h_vel_target,
    'VEL_RANGE': _h_vel_range,
}


# ---------------------------------------------------------------------------
# Conflict detection
# ---------------------------------------------------------------------------

def _detect_conflicts(rules: list, max_week: int) -> list:
    """Find rules that target the same metric in overlapping weeks with
    conflict_strategy='ERROR'. Returns a list of {exercise_id, week, metric, rule_ids}.
    """
    out = []
    by_ex_metric = defaultdict(list)
    for r in rules:
        if _attr(r, 'conflict_strategy') != 'ERROR':
            continue
        key = (_attr(r, 'workout_exercise_id'), _attr(r, 'target_metric'))
        by_ex_metric[key].append(r)
    for (ex_id, metric), group in by_ex_metric.items():
        if len(group) < 2:
            continue
        for w in range(1, max_week + 1):
            active = [r for r in group if _weeks_active_in(r, w, max_week)]
            if len(active) >= 2:
                out.append({
                    'exercise_id': ex_id,
                    'week': w,
                    'metric': metric,
                    'rule_ids': [_attr(r, 'id') for r in active],
                })
    return out


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def compute_for_exercise(
    ex: WorkoutExercise,
    weeks: Iterable[int],
    rules: Optional[Iterable] = None,
    overrides: Optional[Iterable] = None,
    week_defs: Optional[dict] = None,
    max_week: Optional[int] = None,
) -> dict:
    """Pure: returns {week_number: cell_dict} for the exercise. Does not persist."""
    weeks = list(weeks)
    if not weeks:
        return {}
    max_week = max_week or max(weeks)
    rules = list(rules) if rules is not None else list(ex.progression_rules.all())
    overrides = list(overrides) if overrides is not None else list(ex.weekly_overrides.all())
    week_defs = week_defs or {}

    rules_sorted = sorted(rules, key=lambda r: (_attr(r, 'order_index') or 0, _attr(r, 'id') or 0))
    base = _base_cell(ex)
    conflicts: list = []

    auto_deload_weeks: set[int] = set()
    for r in rules_sorted:
        if _attr(r, 'subtype') == 'DEL_AUTO':
            for w in (_params(r).get('on_weeks') or []):
                try:
                    auto_deload_weeks.add(int(w))
                except (TypeError, ValueError):
                    pass

    out: dict = {}
    for week in weeks:
        cell = dict(base)
        for rule in rules_sorted:
            _apply_rule(rule, cell, week, base, max_week, conflicts)

        wd = week_defs.get(week)
        wtype = wd.week_type if wd else 'STANDARD'
        if week in auto_deload_weeks and wtype == 'STANDARD':
            wtype = 'DELOAD'

        if wtype == 'DELOAD' and not cell.get('is_deload'):
            params = {}
            if wd and wd.preset:
                params = WUP_PRESETS.get(wd.preset, {})
            _apply_deload(cell, base, params)
        elif wtype == 'TEST':
            cell['notes'] = (cell.get('notes') or '') + ' Test week — verifica massimali.'
            if cell.get('set_count'):
                cell['set_count'] = _clamp('sets', max(1, int(cell['set_count'] * 0.6)))
        elif wtype == 'TECHNIQUE':
            base_load = _to_decimal(base.get('load_value')) or Decimal('0')
            cell['load_value'] = _clamp('load', base_load * Decimal('0.5'))
            cell['notes'] = (cell.get('notes') or '') + ' Settimana tecnica.'
        elif wtype == 'RECOVERY':
            base_load = _to_decimal(base.get('load_value')) or Decimal('0')
            cell['load_value'] = _clamp('load', base_load * Decimal('0.4'))
            if cell.get('set_count'):
                cell['set_count'] = _clamp('sets', max(1, int(cell['set_count'] * 0.5)))

        for ov in overrides:
            if int(_attr(ov, 'week_number')) != week:
                continue
            metric = _attr(ov, 'metric')
            value_json = _attr(ov, 'value_json') or {}
            value = value_json.get('value') if isinstance(value_json, dict) else value_json
            key = _key_for_metric(metric)
            if key == 'load_value':
                cell['load_value'] = _to_decimal(value)
                unit = value_json.get('unit') if isinstance(value_json, dict) else None
                if unit:
                    cell['load_unit'] = unit
            elif key == 'set_count':
                cell['set_count'] = int(value) if value is not None else None
            elif key == 'rpe':
                cell['rpe'] = _to_decimal(value)
            elif key == 'rir':
                cell['rir'] = int(value) if value is not None else None
            elif key == 'recovery_seconds':
                cell['recovery_seconds'] = int(value) if value is not None else None
            elif key == 'velocity_target':
                cell['velocity_target'] = _to_decimal(value)
            else:
                cell[key] = value
            cell['is_override'] = True

        out[week] = cell
    return out


@transaction.atomic
def compute_weekly_values(plan: WorkoutPlan) -> dict:
    """Recompute and persist WeeklyValue rows for all exercises in the plan.

    Returns: {'computed': {ex_id: {week: cell}}, 'conflicts': [...]}
    """
    duration = plan.duration_weeks or 1
    if duration < 1:
        duration = 1
    weeks_range = list(range(1, duration + 1))

    week_defs = {wd.week_number: wd for wd in plan.weeks.all()}

    exercises = WorkoutExercise.objects.filter(workout_day__workout_plan=plan).select_related('exercise')
    rules_by_ex = defaultdict(list)
    for r in plan.progression_rules.all():
        rules_by_ex[r.workout_exercise_id].append(r)

    overrides_by_ex = defaultdict(list)
    for ov in WeeklyOverride.objects.filter(workout_exercise__workout_day__workout_plan=plan):
        overrides_by_ex[ov.workout_exercise_id].append(ov)

    all_rules = list(plan.progression_rules.all())
    conflicts = _detect_conflicts(all_rules, duration)

    computed = {}
    for ex in exercises:
        cells = compute_for_exercise(
            ex,
            weeks_range,
            rules=rules_by_ex.get(ex.id, []),
            overrides=overrides_by_ex.get(ex.id, []),
            week_defs=week_defs,
            max_week=duration,
        )
        computed[ex.id] = cells

        existing = {wv.week_number: wv for wv in ex.weekly_values.all()}
        keep_weeks = set(weeks_range)
        for week, cell in cells.items():
            wv = existing.get(week) or WeeklyValue(workout_exercise=ex, week_number=week)
            wv.load_value = cell.get('load_value')
            wv.load_unit = cell.get('load_unit') or ''
            wv.set_count = cell.get('set_count')
            wv.rep_range = cell.get('rep_range') or ''
            wv.rpe = cell.get('rpe')
            wv.rir = cell.get('rir')
            wv.recovery_seconds = cell.get('recovery_seconds')
            wv.tempo = cell.get('tempo') or ''
            wv.rom_stage = cell.get('rom_stage') or ''
            wv.variant_exercise_id = cell.get('variant_exercise_id')
            wv.velocity_target = cell.get('velocity_target')
            wv.notes = cell.get('notes') or ''
            wv.is_override = bool(cell.get('is_override'))
            wv.is_deload = bool(cell.get('is_deload'))
            wv.save()
        # Drop rows outside current duration range
        for week, wv in existing.items():
            if week not in keep_weeks:
                wv.delete()

    return {'computed': computed, 'conflicts': conflicts}


def sync_week_definitions(plan: WorkoutPlan) -> None:
    """Ensure one WeekDefinition row per week up to plan.duration_weeks. Removes extras."""
    duration = plan.duration_weeks or 1
    existing = {wd.week_number: wd for wd in plan.weeks.all()}
    for w in range(1, duration + 1):
        if w not in existing:
            WeekDefinition.objects.create(workout_plan=plan, week_number=w)
    for w, wd in existing.items():
        if w > duration:
            wd.delete()


def truncate_rules_to_duration(plan: WorkoutPlan) -> None:
    """When duration_weeks decreases, cap end_week / drop rules wholly out of range, and delete overrides past the new end."""
    duration = plan.duration_weeks or 1
    for r in plan.progression_rules.all():
        if r.start_week > duration:
            r.delete()
            continue
        if r.end_week and r.end_week > duration:
            r.end_week = duration
            r.save(update_fields=['end_week', 'updated_at'])
    WeeklyOverride.objects.filter(
        workout_exercise__workout_day__workout_plan=plan,
        week_number__gt=duration,
    ).delete()
