import json

from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.views.decorators.csrf import csrf_exempt
from django.db import transaction

from domain.workouts.models import (
    ProgressionRule, WeekDefinition, WeeklyOverride, WorkoutExercise, WorkoutPlan,
)
from domain.workouts import progression_engine

from .session_utils import get_session_coach, can_manage_workouts


def _coach_plan_or_403(request, plan_id):
    coach = get_session_coach(request)
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


@csrf_exempt
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


@csrf_exempt
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
