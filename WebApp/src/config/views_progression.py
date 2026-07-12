import json
from decimal import Decimal

from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.db import transaction

from domain.workouts.models import (
    Exercise, WeekDefinition, WeeklyOverride, WorkoutDay,
    WorkoutExercise, WorkoutPlan,
)
from domain.workouts import progression_engine

from .session_utils import get_session_coach, can_manage_workouts


_CELL_METRICS = {
    'set_count', 'rep_range', 'load_value', 'load_unit',
    'rpe', 'rir', 'recovery_seconds', 'tempo', 'set_details',
}


def _coach_plan_or_403(request, plan_id):
    # _request_coach resolves the acting coach from either the web session OR a
    # mobile Bearer token, so the iOS coach app can drive the same grid endpoints.
    from .api import _request_coach
    coach = _request_coach(request)
    if not coach or not can_manage_workouts(coach):
        return None, JsonResponse({'error': 'forbidden'}, status=403)
    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)
    return plan, None


def _decimal_to_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _cell_to_json(cell):
    return {
        'load_value': _decimal_to_float(cell.get('load_value')),
        'load_unit': cell.get('load_unit') or '',
        'set_count': cell.get('set_count'),
        'rep_range': cell.get('rep_range') or '',
        'rpe': _decimal_to_float(cell.get('rpe')),
        'rir': cell.get('rir'),
        'recovery_seconds': cell.get('recovery_seconds'),
        'tempo': cell.get('tempo') or '',
        'rom_stage': cell.get('rom_stage') or '',
        'variant_exercise_id': cell.get('variant_exercise_id'),
        'velocity_target': _decimal_to_float(cell.get('velocity_target')),
        'notes': cell.get('notes') or '',
        'is_override': bool(cell.get('is_override')),
        'is_deload': bool(cell.get('is_deload')),
    }


def api_progression_preview(request, plan_id):
    """Pure preview: compute weekly values for a single exercise from draft rules.

    Body: { workout_exercise_id, rules: [...draft], overrides?: [...] }
    Returns: { computed: {week_n: cell}, conflicts: [...] }
    """
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    try:
        body = json.loads(request.body or '{}')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    ex_id = body.get('workout_exercise_id')
    try:
        ex = WorkoutExercise.objects.get(id=ex_id, workout_day__workout_plan=plan)
    except WorkoutExercise.DoesNotExist:
        return JsonResponse({'error': 'exercise not found'}, status=404)

    duration = plan.duration_weeks or 1
    weeks = list(range(1, duration + 1))

    draft_rules = body.get('rules') or []
    # Normalise: ensure dicts have the keys used by engine helpers.
    rules_input = []
    for r in draft_rules:
        rules_input.append({
            'id': r.get('id'),
            'workout_exercise_id': ex.id,
            'order_index': r.get('order_index') or 0,
            'family': r.get('family'),
            'subtype': r.get('subtype'),
            'target_metric': r.get('target_metric'),
            'application_mode': r.get('application_mode') or 'FIXED_INCREMENT',
            'start_week': r.get('start_week') or 1,
            'end_week': r.get('end_week'),
            'parameters': r.get('parameters') or {},
            'stackable': r.get('stackable', True),
            'conflict_strategy': r.get('conflict_strategy') or 'LAST_WINS',
        })

    overrides_input = body.get('overrides') or []
    week_defs = {wd.week_number: wd for wd in plan.weeks.all()}

    cells = progression_engine.compute_for_exercise(
        ex, weeks, rules=rules_input, overrides=overrides_input,
        week_defs=week_defs, max_week=duration,
    )

    conflicts = progression_engine._detect_conflicts(rules_input, duration)

    return JsonResponse({
        'computed': {str(w): _cell_to_json(c) for w, c in cells.items()},
        'conflicts': conflicts,
    })


def api_progression_special_week(request, plan_id, week_number):
    """Update WeekDefinition.week_type/preset for a single week, then recompute."""
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    try:
        body = json.loads(request.body or '{}')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    duration = plan.duration_weeks or 1
    try:
        wn = int(week_number)
    except (TypeError, ValueError):
        return JsonResponse({'error': 'invalid week'}, status=400)
    if wn < 1 or wn > duration:
        return JsonResponse({'error': 'week out of range'}, status=400)

    valid_types = {c[0] for c in WeekDefinition.WEEK_TYPE_CHOICES}
    week_type = body.get('week_type') or 'STANDARD'
    if week_type not in valid_types:
        return JsonResponse({'error': 'invalid week_type'}, status=400)

    with transaction.atomic():
        wd, _ = WeekDefinition.objects.get_or_create(workout_plan=plan, week_number=wn)
        wd.week_type = week_type
        wd.preset = (body.get('preset') or '')[:40]
        wd.notes = body.get('notes') or ''
        wd.label = (body.get('label') or '')[:40]
        wd.save()
        result = progression_engine.compute_weekly_values(plan)

    return JsonResponse({
        'status': 'ok',
        'week': {
            'week_number': wd.week_number,
            'week_type': wd.week_type,
            'preset': wd.preset,
            'notes': wd.notes,
            'label': wd.label,
        },
        'conflicts': result['conflicts'],
    })


def api_progression_day_grid(request, plan_id, day_id):
    """Per-day grid for the new Step 3 UI: every exercise's effective values
    across all weeks, with forward-fill from WeeklyOverride records."""
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'GET':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    if not plan.days.filter(id=day_id).exists():
        return JsonResponse({'error': 'day not found'}, status=404)
    grid = progression_engine.compute_day_grid(plan, day_id)
    # JSON-safe Decimal handling already done in helper for load_value (float).
    return JsonResponse({'status': 'ok', 'grid': grid})


def api_progression_cell(request, plan_id):
    """Upsert/clear a single (exercise, week, metric) override. Forward-propagation
    is handled by compute_day_grid: subsequent weeks inherit until a later
    override appears."""
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    try:
        body = json.loads(request.body or '{}')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    try:
        ex_id = int(body.get('workout_exercise_id'))
        week = int(body.get('week_number'))
    except (TypeError, ValueError):
        return JsonResponse({'error': 'invalid ids'}, status=400)
    metric = body.get('metric')
    if metric not in _CELL_METRICS:
        return JsonResponse({'error': 'invalid metric'}, status=400)

    try:
        ex = WorkoutExercise.objects.get(id=ex_id, workout_day__workout_plan=plan)
    except WorkoutExercise.DoesNotExist:
        return JsonResponse({'error': 'exercise not found'}, status=404)

    duration = plan.duration_weeks or 1
    if week < (ex.starts_at_week or 1) or week > duration:
        return JsonResponse({'error': 'week out of range'}, status=400)

    value = body.get('value', None)
    clear = bool(body.get('clear')) or value is None or value == ''

    with transaction.atomic():
        if week == 1:
            # Week 1 mirrors the builder's phase-level base values (bidirectional
            # sync): write straight to WorkoutExercise instead of a WeeklyOverride —
            # compute_day_grid's walk-back range never reads an override at week 1,
            # so one would be dead weight, and this is what makes the builder's
            # own Step-2 fields pick up the edit too.
            if metric == 'load_value':
                coerced = None if clear else Decimal(str(value))
            elif metric == 'set_details':
                coerced = value if (not clear and isinstance(value, list)) else []
            else:
                coerced = None if clear else value
            setattr(ex, metric, coerced)
            ex.save(update_fields=[metric, 'updated_at'])
            # Defensive: a stray week-1 override should never exist, but clear it if present.
            WeeklyOverride.objects.filter(workout_exercise=ex, week_number=1, metric=metric).delete()
        elif clear:
            WeeklyOverride.objects.filter(
                workout_exercise=ex, week_number=week, metric=metric,
            ).delete()
        else:
            WeeklyOverride.objects.update_or_create(
                workout_exercise=ex, week_number=week, metric=metric,
                defaults={'value_json': value},
            )
        # Recompute so the builder charts reflect the edit without a full save.
        result = progression_engine.compute_weekly_values(plan)

    computed = {
        str(ex_id): {str(w): _cell_to_json(cell) for w, cell in cells.items()}
        for ex_id, cells in result['computed'].items()
    }
    return JsonResponse({'status': 'ok', 'computed': computed})


def api_progression_delete_cell(request, plan_id, exercise_id):
    """Remove a workout exercise from a specific week onward, or just at that
    single week. Body: { mode: 'single' | 'forward', week_number }.

    - 'single'  → add week to inactive_weeks (gap; later weeks remain active)
    - 'forward' → set ends_at_week = week-1 (this week and all following hidden)

    If the result leaves no active week, the WorkoutExercise row is deleted
    entirely so it disappears from the plan."""
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    try:
        body = json.loads(request.body or '{}')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    mode = body.get('mode') or 'forward'
    if mode not in ('single', 'forward'):
        return JsonResponse({'error': 'invalid mode'}, status=400)
    try:
        week = int(body.get('week_number'))
    except (TypeError, ValueError):
        return JsonResponse({'error': 'invalid week'}, status=400)

    try:
        ex = WorkoutExercise.objects.get(id=exercise_id, workout_day__workout_plan=plan)
    except WorkoutExercise.DoesNotExist:
        return JsonResponse({'error': 'exercise not found'}, status=404)

    duration = plan.duration_weeks or 1
    if week < 1 or week > duration:
        return JsonResponse({'error': 'week out of range'}, status=400)

    with transaction.atomic():
        if mode == 'forward':
            new_end = week - 1
            if new_end < (ex.starts_at_week or 1):
                # Nothing left active → delete the row entirely.
                ex.delete()
                return JsonResponse({'status': 'ok', 'deleted': True})
            ex.ends_at_week = new_end
            # Drop any per-cell overrides past the new boundary.
            WeeklyOverride.objects.filter(workout_exercise=ex, week_number__gt=new_end).delete()
            ex.save(update_fields=['ends_at_week', 'updated_at'])
        else:  # 'single'
            inactive = list({int(x) for x in (ex.inactive_weeks or []) if str(x).isdigit()})
            if week not in inactive:
                inactive.append(week)
            inactive.sort()
            ex.inactive_weeks = inactive
            WeeklyOverride.objects.filter(workout_exercise=ex, week_number=week).delete()
            # Compute effective active set; if empty, drop row.
            active = [w for w in range(ex.starts_at_week or 1, (ex.ends_at_week or duration) + 1) if w not in inactive]
            if not active:
                ex.delete()
                return JsonResponse({'status': 'ok', 'deleted': True})
            ex.save(update_fields=['inactive_weeks', 'updated_at'])

    return JsonResponse({'status': 'ok', 'deleted': False})


def api_progression_add_exercise(request, plan_id):
    """Create a new WorkoutExercise on a day, active from `starts_at_week`
    onward. Used by the "+ Aggiungi" button under each week column."""
    plan, err = _coach_plan_or_403(request, plan_id)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    try:
        body = json.loads(request.body or '{}')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    try:
        day_id = int(body.get('workout_day_id'))
        exercise_id = int(body.get('exercise_id'))
        starts_at_week = int(body.get('starts_at_week') or 1)
    except (TypeError, ValueError):
        return JsonResponse({'error': 'invalid ids'}, status=400)

    duration = plan.duration_weeks or 1
    if starts_at_week < 1 or starts_at_week > duration:
        return JsonResponse({'error': 'starts_at_week out of range'}, status=400)

    try:
        day = WorkoutDay.objects.get(id=day_id, workout_plan=plan)
    except WorkoutDay.DoesNotExist:
        return JsonResponse({'error': 'day not found'}, status=404)
    try:
        ex_def = Exercise.objects.get(id=exercise_id)
    except Exercise.DoesNotExist:
        return JsonResponse({'error': 'exercise not found'}, status=404)

    last_order = day.exercises.order_by('-order_index').values_list('order_index', flat=True).first() or 0

    with transaction.atomic():
        we = WorkoutExercise.objects.create(
            workout_day=day,
            exercise=ex_def,
            order_index=last_order + 1,
            set_count=body.get('set_count') or 3,
            rep_range=body.get('rep_range') or '10',
            load_value=body.get('load_value'),
            load_unit=body.get('load_unit') or 'KG',
            recovery_seconds=body.get('recovery_seconds') or 90,
            rpe=body.get('rpe'),
            rir=body.get('rir'),
            tempo=body.get('tempo') or '',
            starts_at_week=starts_at_week,
        )

    return JsonResponse({
        'status': 'ok',
        'workout_exercise': {
            'id': we.id,
            'exercise_id': we.exercise_id,
            'name': ex_def.name,
            'order_index': we.order_index,
            'starts_at_week': we.starts_at_week,
        },
    })
