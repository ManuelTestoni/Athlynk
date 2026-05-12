from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.db import transaction
from django.db.models import Q, Count
from django.utils import timezone
from datetime import date, timedelta
import json

from domain.accounts.models import ClientProfile
from domain.workouts.models import (
    Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment,
    ProgressionRule, WeekDefinition, WeeklyOverride, WeeklyValue,
)
from domain.workouts import progression_engine
from domain.chat.models import Notification

from .session_utils import (
    get_session_user, get_session_coach, get_session_client,
    get_active_relationship, can_manage_workouts,
)


# ---------------------------------------------------------------------------
# Exercise filter helpers (uses new schema fields)
# ---------------------------------------------------------------------------

def _distinct_values(field_name):
    return list(
        Exercise.objects.exclude(**{f'{field_name}__isnull': True})
        .exclude(**{field_name: ''})
        .values_list(field_name, flat=True)
        .distinct()
        .order_by(field_name)
    )


def serialize_exercise_card(ex):
    return {
        'id': ex.id,
        'name': ex.name,
        'video_url': ex.video_url or '',
        'difficulty_level': ex.difficulty_level or '',
        'target_muscle_group': ex.target_muscle_group or '',
        'primary_muscle': ex.primary_muscle or '',
        'secondary_muscle': ex.secondary_muscle or '',
        'equipment': ex.equipment or '',
        'movement_pattern_1': ex.movement_pattern_1 or '',
        'movement_pattern_2': ex.movement_pattern_2 or '',
        'body_region': ex.body_region or '',
        'exercise_classification': ex.exercise_classification or '',
    }


# ---------------------------------------------------------------------------
# List views
# ---------------------------------------------------------------------------

def allenamenti_list_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    query = request.GET.get('q', '')
    filter_status = request.GET.get('status', '')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')

        assignments = list(WorkoutAssignment.objects.filter(
            client=client,
        ).select_related('workout_plan', 'coach', 'client').prefetch_related(
            'workout_plan__days'
        ).order_by('-start_date', '-created_at'))

        today = date.today()
        for a in assignments:
            freq = a.workout_plan.frequency_per_week or a.workout_plan.days.count() or 0
            start = a.start_date or a.created_at.date()
            end = a.end_date or today
            weeks = max(1, ((min(end, today) - start).days // 7) + 1) if start <= today else 0
            a.expected_session_count = weeks * freq
            a.completed_session_count = a.sessions.filter(client=client, completed=True).count()
            a.progress_pct = min(100, round((a.completed_session_count / a.expected_session_count) * 100)) if a.expected_session_count else 0
            ordered_days = list(a.workout_plan.days.all().order_by('day_order'))
            days_with_ex = [d for d in ordered_days if d.exercises.exists()]
            days_list = [{'id': d.id, 'order': d.day_order, 'name': d.day_name or f'Giorno {d.day_order}'} for d in ordered_days if d.exercises.exists()]
            a.days_json = json.dumps(days_list)
            if not days_with_ex or a.completed_session_count == 0:
                a.next_day_id = None
            else:
                a.next_day_id = days_with_ex[a.completed_session_count % len(days_with_ex)].id

        if query:
            assignments = [a for a in assignments if query.lower() in a.workout_plan.title.lower()]
        if filter_status:
            assignments = [a for a in assignments if a.status == filter_status]

        return render(request, 'pages/allenamenti/client_list.html', {
            'assignments': assignments,
            'query': query,
            'filter_status': filter_status,
            'is_client': True,
            'client': client,
            'coach': relationship.coach,
            'has_coach': True,
            'today': today,
        })

    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')

    plans = (WorkoutPlan.objects
             .filter(coach=coach)
             .annotate(day_count=Count('days', distinct=True),
                       assignment_count=Count('assignments', distinct=True))
             .order_by('-updated_at'))
    if query:
        plans = plans.filter(title__icontains=query)
    if filter_status:
        plans = plans.filter(status=filter_status)

    return render(request, 'pages/allenamenti/list.html', {
        'plans': plans,
        'query': query,
        'filter_status': filter_status,
        'is_coach': True,
        'coach': coach,
    })


# ---------------------------------------------------------------------------
# Wizard view (single page, 3 steps)
# ---------------------------------------------------------------------------

def _decimal_to_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _serialize_progression(plan):
    weeks = [
        {
            'id': w.id,
            'week_number': w.week_number,
            'label': w.label,
            'week_type': w.week_type,
            'preset': w.preset,
            'notes': w.notes,
        }
        for w in plan.weeks.all().order_by('week_number')
    ]

    rules = [
        {
            'id': r.id,
            'workout_exercise_id': r.workout_exercise_id,
            'order_index': r.order_index,
            'family': r.family,
            'subtype': r.subtype,
            'target_metric': r.target_metric,
            'application_mode': r.application_mode,
            'start_week': r.start_week,
            'end_week': r.end_week,
            'parameters': r.parameters or {},
            'stackable': r.stackable,
            'conflict_strategy': r.conflict_strategy,
            'label': r.label,
        }
        for r in plan.progression_rules.all().order_by('workout_exercise_id', 'order_index', 'id')
    ]

    overrides = [
        {
            'id': ov.id,
            'workout_exercise_id': ov.workout_exercise_id,
            'week_number': ov.week_number,
            'metric': ov.metric,
            'value_json': ov.value_json,
        }
        for ov in WeeklyOverride.objects.filter(
            workout_exercise__workout_day__workout_plan=plan,
        ).order_by('workout_exercise_id', 'week_number', 'metric')
    ]

    computed = {}
    for wv in WeeklyValue.objects.filter(
        workout_exercise__workout_day__workout_plan=plan,
    ).order_by('workout_exercise_id', 'week_number'):
        ex_bucket = computed.setdefault(str(wv.workout_exercise_id), {})
        ex_bucket[str(wv.week_number)] = {
            'load_value': _decimal_to_float(wv.load_value),
            'load_unit': wv.load_unit or '',
            'set_count': wv.set_count,
            'rep_range': wv.rep_range or '',
            'rpe': _decimal_to_float(wv.rpe),
            'rir': wv.rir,
            'recovery_seconds': wv.recovery_seconds,
            'tempo': wv.tempo or '',
            'rom_stage': wv.rom_stage or '',
            'variant_exercise_id': wv.variant_exercise_id,
            'velocity_target': _decimal_to_float(wv.velocity_target),
            'notes': wv.notes or '',
            'is_override': wv.is_override,
            'is_deload': wv.is_deload,
        }

    return {
        'weeks': weeks,
        'rules': rules,
        'overrides': overrides,
        'computed': computed,
    }


def _serialize_plan_for_wizard(plan):
    days = []
    for d in plan.days.all().order_by('day_order'):
        exercises = []
        for ex in d.exercises.select_related('exercise').order_by('order_index'):
            exercises.append({
                'local_id': f'srv-ex-{ex.id}',
                'pk': ex.id,
                'exercise_id': ex.exercise.id,
                'exercise_name': ex.exercise.name,
                'target_muscle_group': ex.exercise.target_muscle_group or '',
                'primary_muscle': ex.exercise.primary_muscle or '',
                'secondary_muscle': ex.exercise.secondary_muscle or '',
                'equipment': ex.exercise.equipment or '',
                'sets': ex.set_count or 3,
                'reps': ex.rep_range or '10',
                'load_value': float(ex.load_value) if ex.load_value is not None else None,
                'load_unit': ex.load_unit or 'KG',
                'recovery_seconds': ex.recovery_seconds or 90,
                'notes': ex.technique_notes or '',
                'superset_group_id': ex.superset_group_id,
            })
        days.append({
            'local_id': f'srv-day-{d.id}',
            'pk': d.id,
            'order': d.day_order,
            'name': d.day_name or f'Giorno {d.day_order}',
            'exercises': exercises,
        })

    return {
        'id': plan.id,
        'title': plan.title,
        'description': plan.description or '',
        'goal': plan.goal or '',
        'level': plan.level or '',
        'frequency_per_week': plan.frequency_per_week or 3,
        'duration_weeks': plan.duration_weeks or 8,
        'status': plan.status,
        'last_step': plan.last_step or 1,
        'days': days,
        'progression': _serialize_progression(plan),
    }


def allenamenti_wizard_view(request, plan_id=None):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')

    if plan_id:
        plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)
        plan_data = _serialize_plan_for_wizard(plan)
    else:
        plan_data = {
            'id': None,
            'title': '',
            'description': '',
            'goal': '',
            'level': '',
            'frequency_per_week': None,
            'duration_weeks': 8,
            'status': 'DRAFT',
            'last_step': 1,
            'days': [],
            'progression': {'weeks': [], 'rules': [], 'overrides': [], 'computed': {}},
        }

    return render(request, 'pages/allenamenti/wizard.html', {
        'coach': coach,
        'plan_data_json': json.dumps(plan_data),
        'plan_data': plan_data,
    })


# ---------------------------------------------------------------------------
# Plan detail (for finalized plans)
# ---------------------------------------------------------------------------

def allenamenti_plan_detail_view(request, plan_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')

    plan = get_object_or_404(
        WorkoutPlan.objects.prefetch_related('days__exercises__exercise', 'assignments__client'),
        id=plan_id, coach=coach,
    )

    if plan.status == 'DRAFT':
        return redirect('allenamenti_wizard_resume', plan_id=plan.id)

    return render(request, 'pages/allenamenti/plan_detail.html', {
        'coach': coach,
        'plan': plan,
    })


# ---------------------------------------------------------------------------
# Save / autosave
# ---------------------------------------------------------------------------

def _apply_payload_to_plan(plan, data, coach):
    if 'title' in data:
        plan.title = (data.get('title') or '').strip() or plan.title or 'Bozza senza titolo'
    if 'description' in data:
        plan.description = data.get('description') or ''
    if 'goal' in data:
        plan.goal = data.get('goal') or None
    if 'level' in data:
        plan.level = data.get('level') or None
    if 'frequency_per_week' in data and data.get('frequency_per_week'):
        try:
            f = int(data['frequency_per_week'])
            if 1 <= f <= 6:
                plan.frequency_per_week = f
        except (TypeError, ValueError):
            pass
    if 'duration_weeks' in data and data.get('duration_weeks'):
        try:
            w = int(data['duration_weeks'])
            if 1 <= w <= 104:
                plan.duration_weeks = w
        except (TypeError, ValueError):
            pass
    if 'last_step' in data:
        try:
            plan.last_step = max(1, min(4, int(data['last_step'])))
        except (TypeError, ValueError):
            pass
    plan.coach = coach
    plan.save()

    if 'days' not in data and 'progression' not in data:
        return

    ex_local_to_pk = {}
    days_payload = data.get('days') or []

    existing_days = {d.id: d for d in plan.days.all()}
    seen_day_ids = set()

    for d_idx, day_data in enumerate(days_payload):
        day_pk = day_data.get('pk')
        if day_pk and day_pk in existing_days:
            day = existing_days[day_pk]
            day.day_order = d_idx + 1
            day.day_name = (day_data.get('name') or '').strip() or f'Giorno {d_idx+1}'
            day.save()
            seen_day_ids.add(day_pk)
        else:
            day = WorkoutDay.objects.create(
                workout_plan=plan,
                day_order=d_idx + 1,
                day_name=(day_data.get('name') or '').strip() or f'Giorno {d_idx+1}',
            )
            seen_day_ids.add(day.id)
            day_data['pk'] = day.id

        existing_ex = {e.id: e for e in day.exercises.all()}
        seen_ex_ids = set()

        for ex_idx, ex_data in enumerate(day_data.get('exercises') or []):
            exercise_id = ex_data.get('exercise_id')
            if not exercise_id:
                continue
            try:
                exercise_obj = Exercise.objects.get(id=exercise_id)
            except Exercise.DoesNotExist:
                continue

            ex_pk = ex_data.get('pk')
            sets = int(ex_data.get('sets') or 3)
            reps = str(ex_data.get('reps') or '10')
            recovery = int(ex_data.get('recovery_seconds') or 90)
            notes = ex_data.get('notes') or ''
            superset = ex_data.get('superset_group_id')
            try:
                superset_int = int(superset) if superset not in (None, '') else None
            except (TypeError, ValueError):
                superset_int = None
            load_value = ex_data.get('load_value')
            try:
                load_value_d = float(load_value) if load_value not in (None, '') else None
            except (TypeError, ValueError):
                load_value_d = None
            load_unit = ex_data.get('load_unit') or None
            if load_unit not in ('KG', 'PERCENT_1RM', 'BODYWEIGHT', None):
                load_unit = None

            if ex_pk and ex_pk in existing_ex:
                we = existing_ex[ex_pk]
                we.exercise = exercise_obj
                we.order_index = ex_idx + 1
                we.set_count = sets
                we.rep_range = reps
                we.recovery_seconds = recovery
                we.technique_notes = notes
                we.superset_group_id = superset_int
                we.load_value = load_value_d
                we.load_unit = load_unit
                we.save()
                seen_ex_ids.add(ex_pk)
            else:
                we = WorkoutExercise.objects.create(
                    workout_day=day,
                    exercise=exercise_obj,
                    order_index=ex_idx + 1,
                    set_count=sets,
                    rep_range=reps,
                    recovery_seconds=recovery,
                    technique_notes=notes,
                    superset_group_id=superset_int,
                    load_value=load_value_d,
                    load_unit=load_unit,
                )
                seen_ex_ids.add(we.id)
                ex_data['pk'] = we.id

            local_id = ex_data.get('local_id')
            if local_id:
                ex_local_to_pk[local_id] = we.id

        for ex_id, we in existing_ex.items():
            if ex_id not in seen_ex_ids:
                we.delete()

    for day_id, day in existing_days.items():
        if day_id not in seen_day_ids:
            day.delete()

    # Sync week definitions to plan.duration_weeks BEFORE applying rules.
    progression_engine.sync_week_definitions(plan)
    progression_engine.truncate_rules_to_duration(plan)

    if 'progression' in data:
        _apply_progression_payload(plan, data.get('progression') or {}, ex_local_to_pk)

    # Always recompute weekly values to keep cache fresh
    progression_engine.compute_weekly_values(plan)


def _resolve_exercise_id(payload_value, ex_local_to_pk):
    if payload_value in (None, ''):
        return None
    if isinstance(payload_value, int):
        return payload_value
    s = str(payload_value)
    if s.isdigit():
        return int(s)
    return ex_local_to_pk.get(s)


def _apply_progression_payload(plan, payload, ex_local_to_pk):
    duration = plan.duration_weeks or 1
    valid_exercise_ids = set(
        WorkoutExercise.objects.filter(workout_day__workout_plan=plan).values_list('id', flat=True)
    )

    # Week definitions (upsert)
    weeks_payload = payload.get('weeks') or []
    existing_weeks = {w.week_number: w for w in plan.weeks.all()}
    for w_data in weeks_payload:
        try:
            wn = int(w_data.get('week_number'))
        except (TypeError, ValueError):
            continue
        if wn < 1 or wn > duration:
            continue
        wd = existing_weeks.get(wn) or WeekDefinition(workout_plan=plan, week_number=wn)
        wd.label = (w_data.get('label') or '')[:40]
        wd.week_type = w_data.get('week_type') or 'STANDARD'
        wd.preset = (w_data.get('preset') or '')[:40]
        wd.notes = w_data.get('notes') or ''
        wd.save()

    # Rules (full diff: upsert + delete missing)
    rules_payload = payload.get('rules') or []
    existing_rules = {r.id: r for r in plan.progression_rules.all()}
    seen_rule_ids = set()
    for r_data in rules_payload:
        ex_id = _resolve_exercise_id(
            r_data.get('workout_exercise_id') or r_data.get('workout_exercise_local_id'),
            ex_local_to_pk,
        )
        if ex_id not in valid_exercise_ids:
            continue
        rule_pk = r_data.get('id')
        rule = existing_rules.get(rule_pk) if rule_pk else None
        if rule is None:
            rule = ProgressionRule(workout_plan=plan, workout_exercise_id=ex_id)
        else:
            rule.workout_exercise_id = ex_id
        rule.order_index = int(r_data.get('order_index') or 0)
        rule.family = r_data.get('family') or ''
        rule.subtype = r_data.get('subtype') or ''
        rule.target_metric = r_data.get('target_metric') or ''
        rule.application_mode = r_data.get('application_mode') or 'FIXED_INCREMENT'
        try:
            rule.start_week = max(1, int(r_data.get('start_week') or 1))
        except (TypeError, ValueError):
            rule.start_week = 1
        end_week = r_data.get('end_week')
        try:
            rule.end_week = int(end_week) if end_week not in (None, '') else None
        except (TypeError, ValueError):
            rule.end_week = None
        if rule.end_week and rule.end_week > duration:
            rule.end_week = duration
        params = r_data.get('parameters') or {}
        rule.parameters = params if isinstance(params, dict) else {}
        rule.stackable = bool(r_data.get('stackable', True))
        rule.conflict_strategy = r_data.get('conflict_strategy') or 'LAST_WINS'
        rule.label = (r_data.get('label') or '')[:80]
        rule.save()
        seen_rule_ids.add(rule.id)
        r_data['id'] = rule.id

    for rid, rule in existing_rules.items():
        if rid not in seen_rule_ids:
            rule.delete()

    # Overrides (full diff)
    overrides_payload = payload.get('overrides') or []
    existing_overrides = {
        (ov.workout_exercise_id, ov.week_number, ov.metric): ov
        for ov in WeeklyOverride.objects.filter(workout_exercise__workout_day__workout_plan=plan)
    }
    seen_override_keys = set()
    for o_data in overrides_payload:
        ex_id = _resolve_exercise_id(
            o_data.get('workout_exercise_id') or o_data.get('workout_exercise_local_id'),
            ex_local_to_pk,
        )
        if ex_id not in valid_exercise_ids:
            continue
        try:
            wn = int(o_data.get('week_number'))
        except (TypeError, ValueError):
            continue
        if wn < 1 or wn > duration:
            continue
        metric = o_data.get('metric')
        if not metric:
            continue
        value_json = o_data.get('value_json')
        if not isinstance(value_json, dict):
            value_json = {'value': value_json}
        key = (ex_id, wn, metric)
        ov = existing_overrides.get(key) or WeeklyOverride(
            workout_exercise_id=ex_id, week_number=wn, metric=metric,
        )
        ov.value_json = value_json
        ov.save()
        seen_override_keys.add(key)

    for key, ov in existing_overrides.items():
        if key not in seen_override_keys:
            ov.delete()


@csrf_exempt
def api_plan_save(request, plan_id=None):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'forbidden'}, status=403)

    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    try:
        body = request.body.decode('utf-8') if isinstance(request.body, bytes) else request.body
        data = json.loads(body) if body else {}
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    try:
        with transaction.atomic():
            if plan_id:
                plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)
            else:
                title = (data.get('title') or '').strip() or 'Bozza senza titolo'
                plan = WorkoutPlan.objects.create(
                    coach=coach,
                    title=title,
                    status='DRAFT',
                    last_step=int(data.get('last_step') or 1),
                )

            _apply_payload_to_plan(plan, data, coach)
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)

    return JsonResponse({
        'status': 'ok',
        'plan': _serialize_plan_for_wizard(plan),
    })


# ---------------------------------------------------------------------------
# Finalize: assign / save as template
# ---------------------------------------------------------------------------

@csrf_exempt
def api_plan_finalize(request, plan_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'forbidden'}, status=403)

    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)

    try:
        data = json.loads(request.body) if request.body else {}
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    has_exercises = WorkoutExercise.objects.filter(workout_day__workout_plan=plan).exists()
    if not has_exercises:
        return JsonResponse({'error': 'La scheda deve contenere almeno un esercizio.'}, status=400)

    action = data.get('action')

    if action == 'template':
        plan.status = 'TEMPLATE'
        plan.is_template = True
        plan.save()
        return JsonResponse({'status': 'ok', 'redirect_url': '/allenamenti/'})

    if action == 'assign':
        client_ids = data.get('client_ids') or []
        if not client_ids:
            return JsonResponse({'error': 'Seleziona almeno un cliente.'}, status=400)
        try:
            weeks = int(data.get('weeks') or 0)
        except (TypeError, ValueError):
            weeks = 0
        if weeks < 1:
            weeks = plan.duration_weeks or 0
        if weeks < 1:
            return JsonResponse({'error': 'Durata scheda non valida.'}, status=400)
        start_date = date.today()
        end_date = start_date + timedelta(weeks=weeks)

        clients = ClientProfile.objects.filter(
            id__in=client_ids,
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE',
        ).distinct()

        if not clients.exists():
            return JsonResponse({'error': 'Nessun cliente valido trovato.'}, status=400)

        with transaction.atomic():
            for client in clients:
                WorkoutAssignment.objects.create(
                    workout_plan=plan,
                    client=client,
                    coach=coach,
                    status='ACTIVE',
                    start_date=start_date,
                    end_date=end_date,
                )
                Notification.objects.create(
                    target_user=client.user,
                    notification_type='WORKOUT_ASSIGNED',
                    title='Nuova scheda di allenamento',
                    body=f'Ti è stata assegnata la scheda "{plan.title}".',
                    link_url='/allenamenti/',
                )
            plan.status = 'ACTIVE'
            plan.save()

        return JsonResponse({'status': 'ok', 'redirect_url': '/allenamenti/'})

    return JsonResponse({'error': 'azione non valida'}, status=400)


# ---------------------------------------------------------------------------
# Delete plan
# ---------------------------------------------------------------------------

@csrf_exempt
def api_plan_delete(request, plan_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'forbidden'}, status=403)
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)
    plan.delete()
    return JsonResponse({'status': 'ok'})


# ---------------------------------------------------------------------------
# Search APIs
# ---------------------------------------------------------------------------

def api_search_clients(request):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse([], safe=False)
    query = request.GET.get('q', '').strip()

    qs = ClientProfile.objects.filter(
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).distinct()

    if query:
        qs = qs.filter(Q(first_name__icontains=query) | Q(last_name__icontains=query))

    clients = qs.order_by('first_name', 'last_name')[:30]
    data = [{'id': c.id, 'name': f"{c.first_name} {c.last_name}".strip()} for c in clients]
    return JsonResponse(data, safe=False)


def api_search_exercises(request):
    query = request.GET.get('q', '').strip()
    muscle = request.GET.get('muscle', '').strip()
    equipment = request.GET.get('equipment', '').strip()
    sport = request.GET.get('sport', '').strip()

    qs = Exercise.objects.all()
    if query:
        qs = qs.filter(name__icontains=query)
    if muscle:
        qs = qs.filter(target_muscle_group__iexact=muscle)
    if equipment:
        qs = qs.filter(equipment__iexact=equipment)
    if sport:
        qs = qs.filter(exercise_classification__iexact=sport)

    qs = qs.order_by('name')[:20]
    return JsonResponse([serialize_exercise_card(e) for e in qs], safe=False)


def api_exercise_filters(request):
    return JsonResponse({
        'muscles': _distinct_values('target_muscle_group'),
        'equipment': _distinct_values('equipment'),
        'sports': _distinct_values('exercise_classification'),
    })


# ---------------------------------------------------------------------------
# Legacy redirects (preserve old URL names)
# ---------------------------------------------------------------------------

def allenamenti_create_view(request):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')
    return redirect('allenamenti_wizard')


def allenamenti_edit_view(request, assignment_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')
    try:
        a = WorkoutAssignment.objects.select_related('workout_plan').get(id=assignment_id, coach=coach)
    except WorkoutAssignment.DoesNotExist:
        return redirect('allenamenti_list')
    return redirect('allenamenti_wizard_resume', plan_id=a.workout_plan.id)
