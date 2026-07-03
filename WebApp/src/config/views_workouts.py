import logging

from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.db import transaction
from django.db.models import Q, Count
from django.core.cache import cache
from datetime import date, timedelta
import json

from domain.accounts.models import ClientProfile
from domain.workouts.models import (
    Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment,
    ProgressionRule, WeekDefinition, WeeklyOverride, WeeklyValue,
    WorkoutFolder, Sport,
)
from domain.workouts import progression_engine
from domain.coaching.models import CoachingRelationship
from domain.chat.models import Notification

from .services.email import send_workout_assigned
from .services import import_quota

logger = logging.getLogger(__name__)
from .session_utils import (
    get_session_user, get_session_coach, get_session_client,
    get_workout_coach, can_manage_workouts,
)
from .http_utils import safe_int


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


WORKOUT_HISTORY_PAGE_SIZE = 5


def _enrich_client_assignment(a, client, today):
    """Hero assignment: compute days_json, expected/completed/progress, next_day_id."""
    plan = a.workout_plan
    ordered_days = sorted(plan.days.all(), key=lambda d: d.day_order)
    freq = plan.frequency_per_week or len(ordered_days) or 0
    start = a.start_date or a.created_at.date()
    end = a.end_date or today
    if start <= today:
        weeks = max(1, ((min(end, today) - start).days // 7) + 1)
    else:
        weeks = 0
    a.expected_session_count = weeks * freq
    a.completed_session_count = getattr(a, '_completed', 0)
    a.progress_pct = min(100, round((a.completed_session_count / a.expected_session_count) * 100)) if a.expected_session_count else 0
    days_with_ex = [d for d in ordered_days if list(d.exercises.all())]
    a.days_json = json.dumps([{'id': d.id, 'order': d.day_order, 'name': d.day_name or f'Giorno {d.day_order}'} for d in days_with_ex])
    if not days_with_ex or a.completed_session_count == 0:
        a.next_day_id = None
    else:
        a.next_day_id = days_with_ex[a.completed_session_count % len(days_with_ex)].id


def _enrich_client_history_row(a, today):
    """History row: lightweight expected/completed/progress (no days prefetch)."""
    plan = a.workout_plan
    freq = plan.frequency_per_week or 0
    start = a.start_date or a.created_at.date()
    end = a.end_date or today
    if start <= today and freq:
        weeks = max(1, ((min(end, today) - start).days // 7) + 1)
        a.expected_session_count = weeks * freq
    else:
        a.expected_session_count = 0
    a.completed_session_count = getattr(a, '_completed', 0)
    a.progress_pct = min(100, round((a.completed_session_count / a.expected_session_count) * 100)) if a.expected_session_count else 0


def _serialize_history_row(a):
    plan = a.workout_plan
    return {
        'id': a.id,
        'plan_id': plan.id,
        'plan_title': plan.title,
        'plan_kind': plan.plan_kind,
        'goal': plan.goal or '',
        'level': plan.level or '',
        'sport_name': plan.sport.name if plan.sport_id else '',
        'frequency_per_week': plan.frequency_per_week or 0,
        'duration_weeks': plan.duration_weeks or 0,
        'status': a.status,
        'start_date': a.start_date.strftime('%d %b %Y') if a.start_date else '',
        'end_date':   a.end_date.strftime('%d %b %Y')   if a.end_date else '',
        'expected_session_count': a.expected_session_count,
        'completed_session_count': a.completed_session_count,
        'progress_pct': a.progress_pct,
    }


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
        # Resolve the training professional (FULL coach or Allenatore). A client
        # with only a nutritionist still has access — just no workout section — so
        # send them to the dashboard instead of the suspended-access page.
        workout_coach = get_workout_coach(client)
        if not workout_coach:
            return redirect('dashboard')

        today = date.today()

        # Hero: latest ACTIVE assignment (single object, full prefetch).
        current_assignment = (
            WorkoutAssignment.objects
            .filter(client=client, status='ACTIVE')
            .select_related('workout_plan', 'workout_plan__sport', 'workout_plan__folder', 'coach', 'client')
            .prefetch_related('workout_plan__days__exercises')
            .annotate(_completed=Count('sessions', filter=Q(sessions__client=client, sessions__completed=True), distinct=True))
            .order_by('-start_date', '-created_at')
            .first()
        )
        if current_assignment is not None:
            _enrich_client_assignment(current_assignment, client, today)

        # History: paginated table (first WORKOUT_HISTORY_PAGE_SIZE rows).
        past_qs = (
            WorkoutAssignment.objects
            .filter(client=client)
            .select_related('workout_plan', 'workout_plan__sport')
            .annotate(_completed=Count('sessions', filter=Q(sessions__client=client, sessions__completed=True), distinct=True))
            .order_by('-start_date', '-created_at')
        )
        if current_assignment is not None:
            past_qs = past_qs.exclude(id=current_assignment.id)

        past_total = past_qs.count()
        past_first = list(past_qs[:WORKOUT_HISTORY_PAGE_SIZE])
        for a in past_first:
            _enrich_client_history_row(a, today)
        past_data = [_serialize_history_row(a) for a in past_first]

        return render(request, 'pages/allenamenti/client_list.html', {
            'current_assignment': current_assignment,
            'past_data_json': json.dumps(past_data),
            'past_total': past_total,
            'past_initial_count': len(past_first),
            'past_has_more': past_total > len(past_first),
            'history_page_size': WORKOUT_HISTORY_PAGE_SIZE,
            'is_client': True,
            'client': client,
            'coach': workout_coach,
            'has_coach': True,
            'today': today,
        })

    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')

    _wkey = f'workout_plans:{coach.id}'
    _cached = cache.get(_wkey)
    if _cached:
        plans_data, folders_data, clients_data = _cached
    else:
        plans_qs = list(WorkoutPlan.objects
                        .filter(coach=coach)
                        .select_related('folder', 'sport')
                        .annotate(day_count=Count('days', distinct=True),
                                  assignment_count=Count('assignments', distinct=True))
                        .order_by('-updated_at'))

        folders = list(
            WorkoutFolder.objects.filter(coach=coach)
            .annotate(plan_count=Count('plans'))
            .order_by('order', 'title')
        )

        # Progression families per plan, inferred from per-week overrides vs base
        # (counted one hit per exercise per family). Programmazioni only in the UI.
        prog_summary = progression_engine.classify_progressions_for_plans(
            [p.id for p in plans_qs]
        )

        plans_data = [
            {
                'id': p.id,
                'title': p.title,
                'description': p.description or '',
                'status': p.status,
                'plan_kind': p.plan_kind,
                'goal': p.goal or '',
                'level': p.level or '',
                'frequency_per_week': p.frequency_per_week or 0,
                'duration_weeks': p.duration_weeks or 0,
                'day_count': p.day_count,
                'assignment_count': p.assignment_count,
                'folder_id': p.folder_id,
                'sport_id': p.sport_id,
                'sport_name': p.sport.name if p.sport_id else '',
                'sport_icon': (p.sport.icon if p.sport_id else '') or '',
                'updated_at': p.updated_at.isoformat() if p.updated_at else '',
                'progression_summary': prog_summary.get(p.id, []),
            }
            for p in plans_qs
        ]

        folders_data = [
            {
                'id': f.id,
                'title': f.title,
                'label_text': f.label_text or '',
                'label_color': f.label_color or '',
                'order': f.order,
                'plan_count': f.plan_count,
            }
            for f in folders
        ]

        clients = (ClientProfile.objects
                   .filter(coaching_relationships_as_client__coach=coach,
                           coaching_relationships_as_client__status='ACTIVE')
                   .select_related('user')
                   .distinct())
        clients_data = [
            {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
            for c in clients
        ]
        cache.set(_wkey, (plans_data, folders_data, clients_data), 300)

    response = render(request, 'pages/allenamenti/library.html', {
        'plans_json': json.dumps(plans_data),
        'folders_json': json.dumps(folders_data),
        'clients_json': json.dumps(clients_data),
        'query': query,
        'filter_status': filter_status,
        'is_coach': True,
        'coach': coach,
    })
    # Prevent the browser bfcache from restoring a stale list after a delete.
    response['Cache-Control'] = 'no-store'
    return response


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
        for ex in d.exercises.select_related('exercise').prefetch_related(
            'exercise__primary_muscles', 'exercise__secondary_muscles',
        ).order_by('order_index'):
            exercises.append({
                'local_id': f'srv-ex-{ex.id}',
                'pk': ex.id,
                'exercise_id': ex.exercise.id,
                'exercise_name': ex.exercise.name,
                'target_muscle_group': ex.exercise.target_muscle_group or '',
                'primary_muscle': ex.exercise.primary_muscle or '',
                'secondary_muscle': ex.exercise.secondary_muscle or '',
                'primary_muscles': [
                    {'slug': m.slug, 'name': m.name, 'color_token': m.color_token}
                    for m in ex.exercise.primary_muscles.all()
                ],
                'secondary_muscles': [
                    {'slug': m.slug, 'name': m.name, 'color_token': m.color_token}
                    for m in ex.exercise.secondary_muscles.all()
                ],
                'equipment': ex.exercise.equipment or '',
                'sets': ex.set_count or 3,
                'reps': ex.rep_range or '10',
                'load_value': float(ex.load_value) if ex.load_value is not None else None,
                'load_unit': ex.load_unit or 'KG',
                'recovery_seconds': ex.recovery_seconds or 90,
                'notes': ex.technique_notes or '',
                'coach_notes': ex.technique_notes or '',
                'execution_type': ex.execution_type or 'REPETITION',
                'rpe': ex.rpe,
                'rir': ex.rir,
                'tempo': ex.tempo or '',
                'superset_group_id': ex.superset_group_id,
                'set_details': ex.set_details or [],
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
        'frequency_per_week': plan.frequency_per_week or 4,
        'duration_weeks': plan.duration_weeks or 8,
        'status': plan.status,
        'last_step': plan.last_step or 1,
        'folder_id': plan.folder_id,
        'sport_id': plan.sport_id,
        'sport_name': plan.sport.name if plan.sport_id else '',
        'plan_kind': plan.plan_kind,
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
        WorkoutPlan.objects
            .select_related('folder', 'sport')
            .prefetch_related('days__exercises__exercise'),
        id=plan_id, coach=coach,
    )

    if plan.status == 'DRAFT':
        return redirect('allenamenti_wizard_resume', plan_id=plan.id)

    qs = plan.assignments.select_related('client').order_by('-created_at')
    assignments_count = qs.count()
    _first = list(qs[:5])
    assignments_first = [
        {
            'id': a.id, 'client_id': a.client.id,
            'first_name': a.client.first_name, 'last_name': a.client.last_name,
            'status': a.status,
            'start_date': a.start_date.isoformat() if a.start_date else None,
            'end_date': a.end_date.isoformat() if a.end_date else None,
        }
        for a in _first
    ]
    assignments_first_count = len(_first)

    return render(request, 'pages/allenamenti/plan_detail.html', {
        'coach': coach,
        'plan': plan,
        'assignments_count': assignments_count,
        'assignments_first': assignments_first,
        'assignments_first_count': assignments_first_count,
    })


def api_plan_assignments_list(request, plan_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'forbidden'}, status=403)
    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)
    LIMIT = 10
    offset = max(0, safe_int(request.GET, 'offset', 0))
    qs = plan.assignments.select_related('client').order_by('-created_at')
    total = qs.count()
    data = [
        {
            'id': a.id, 'client_id': a.client.id,
            'first_name': a.client.first_name, 'last_name': a.client.last_name,
            'status': a.status,
            'start_date': a.start_date.isoformat() if a.start_date else None,
            'end_date': a.end_date.isoformat() if a.end_date else None,
        }
        for a in qs[offset:offset + LIMIT]
    ]
    return JsonResponse({'assignments': data, 'has_more': total > offset + LIMIT})


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
            if 1 <= f <= 14:
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

    # Folder (optional, nullable)
    if 'folder_id' in data:
        folder_id = data.get('folder_id')
        if folder_id in (None, '', 0):
            plan.folder = None
        else:
            try:
                plan.folder = WorkoutFolder.objects.get(id=int(folder_id), coach=coach)
            except (WorkoutFolder.DoesNotExist, TypeError, ValueError):
                pass

    # Sport (optional, nullable)
    if 'sport_id' in data:
        sport_id = data.get('sport_id')
        if sport_id in (None, '', 0):
            plan.sport = None
        else:
            try:
                plan.sport = Sport.objects.get(id=int(sport_id))
            except (Sport.DoesNotExist, TypeError, ValueError):
                pass

    # Plan kind (WEEKLY | PROGRAM)
    if 'plan_kind' in data:
        kind = (data.get('plan_kind') or '').upper()
        if kind in (WorkoutPlan.KIND_WEEKLY, WorkoutPlan.KIND_PROGRAM):
            plan.plan_kind = kind

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
            # `coach_notes` is the new canonical key; `notes` kept for back-compat
            notes = ex_data.get('coach_notes') or ex_data.get('notes') or ''
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

            # New optional fields
            execution_type = (ex_data.get('execution_type') or '').strip().upper() or None
            if execution_type and execution_type not in ('REPETITION', 'RAMPING', 'TEST'):
                execution_type = None

            def _opt_int(value, lo, hi):
                if value in (None, ''):
                    return None
                try:
                    v = int(value)
                except (TypeError, ValueError):
                    return None
                return v if lo <= v <= hi else None

            rpe_v = _opt_int(ex_data.get('rpe'), 1, 10)
            rir_v = _opt_int(ex_data.get('rir'), 0, 10)
            tempo_v = (ex_data.get('tempo') or '').strip()[:50] or None
            set_details = _coerce_set_details(ex_data.get('set_details'), sets)

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
                we.execution_type = execution_type
                we.rpe = rpe_v
                we.rir = rir_v
                we.tempo = tempo_v
                we.set_details = set_details
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
                    execution_type=execution_type,
                    rpe=rpe_v,
                    rir=rir_v,
                    tempo=tempo_v,
                    set_details=set_details,
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

    # Overrides — upsert only (the progression grid owns deletions, see note below)
    overrides_payload = payload.get('overrides') or []
    existing_overrides = {
        (ov.workout_exercise_id, ov.week_number, ov.metric): ov
        for ov in WeeklyOverride.objects.filter(workout_exercise__workout_day__workout_plan=plan)
    }
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

    # NOTE: do not delete overrides absent from the payload. The per-week
    # progression grid (api_progression_cell) is the authority for WeeklyOverride
    # and owns its own clear/delete path; the builder save only knows the legacy
    # `overrides` array, so a blanket diff-delete here wiped every grid edit on the
    # next autosave. Out-of-range overrides are pruned by truncate_rules_to_duration.


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

    cache.delete(f'workout_plans:{coach.id}')
    return JsonResponse({
        'status': 'ok',
        'plan': _serialize_plan_for_wizard(plan),
    })


# ---------------------------------------------------------------------------
# Finalize: assign / save as template
# ---------------------------------------------------------------------------

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
            return JsonResponse({'error': 'Seleziona almeno un atleta.'}, status=400)
        try:
            weeks = int(data.get('weeks') or 0)
        except (TypeError, ValueError):
            weeks = 0
        if weeks < 1:
            weeks = plan.duration_weeks or 0
        if weeks < 1:
            return JsonResponse({'error': 'Durata scheda non valida.'}, status=400)
        overwrite = bool(data.get('overwrite'))
        start_date = date.today()
        end_date = start_date + timedelta(weeks=weeks)

        clients = ClientProfile.objects.filter(
            id__in=client_ids,
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE',
        ).distinct()

        if not clients.exists():
            return JsonResponse({'error': 'Nessun atleta valido trovato.'}, status=400)

        with transaction.atomic():
            if overwrite:
                WorkoutAssignment.objects.filter(
                    client__in=clients,
                    coach=coach,
                    status='ACTIVE',
                ).exclude(workout_plan=plan).update(
                    status='COMPLETED',
                    end_date=start_date,
                )
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
                # Fire-and-forget email notification (silenced if user opted out).
                try:
                    from django.conf import settings as _settings
                    plan_url = f"{_settings.SITE_URL}/allenamenti/"
                    send_workout_assigned(client, coach, plan, plan_url)
                except Exception:
                    logger.exception('workout_assigned_email.failed plan_id=%s', plan.id)
            plan.status = 'ACTIVE'
            plan.save()

        return JsonResponse({'status': 'ok', 'redirect_url': '/allenamenti/'})

    if action == 'draft':
        plan.status = 'DRAFT'
        plan.is_template = False
        plan.save()
        return JsonResponse({'status': 'ok', 'redirect_url': f'/allenamenti/{plan.id}/'})

    return JsonResponse({'error': 'azione non valida'}, status=400)


# ---------------------------------------------------------------------------
# Delete plan
# ---------------------------------------------------------------------------

def api_plan_delete(request, plan_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'forbidden'}, status=403)
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)

    # Atleti con la scheda assegnata: avvisali in chat dopo l'eliminazione.
    from domain.accounts.models import ClientProfile
    from domain.chat.services import send_plan_deleted_message
    client_ids = list(plan.assignments.values_list('client_id', flat=True).distinct())
    clients = list(ClientProfile.objects.filter(id__in=client_ids))

    with transaction.atomic():
        plan.delete()
        transaction.on_commit(lambda: [send_plan_deleted_message(coach, c) for c in clients])

    cache.delete(f'workout_plans:{coach.id}')
    return JsonResponse({'status': 'ok'})


# ---------------------------------------------------------------------------
# Duplicate plan
# ---------------------------------------------------------------------------

def api_plan_duplicate(request, plan_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'forbidden'}, status=403)
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)

    source = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)

    with transaction.atomic():
        new_plan = WorkoutPlan.objects.create(
            coach=coach,
            title=f"{source.title} (copia)",
            description=source.description,
            level=source.level,
            goal=source.goal,
            is_template=False,
            status='DRAFT',
            frequency_per_week=source.frequency_per_week,
            duration_weeks=source.duration_weeks,
            last_step=source.last_step,
            folder=source.folder,
            sport=source.sport,
            plan_kind=source.plan_kind,
        )

        # Days + exercises
        for src_day in source.days.all().prefetch_related('exercises'):
            new_day = WorkoutDay.objects.create(
                workout_plan=new_plan,
                day_order=src_day.day_order,
                day_name=src_day.day_name,
                title=src_day.title,
                focus_area=src_day.focus_area,
                day_type=src_day.day_type,
                notes=src_day.notes,
            )
            for src_ex in src_day.exercises.all():
                WorkoutExercise.objects.create(
                    workout_day=new_day,
                    exercise=src_ex.exercise,
                    order_index=src_ex.order_index,
                    set_count=src_ex.set_count,
                    rep_count=src_ex.rep_count,
                    rep_range=src_ex.rep_range,
                    rir=src_ex.rir,
                    rpe=src_ex.rpe,
                    rm_reference=src_ex.rm_reference,
                    load_percentage=src_ex.load_percentage,
                    recovery_seconds=src_ex.recovery_seconds,
                    tempo=src_ex.tempo,
                    execution_type=src_ex.execution_type,
                    technique_notes=src_ex.technique_notes,
                    superset_group_id=src_ex.superset_group_id,
                    alternative_exercise=src_ex.alternative_exercise,
                    load_value=src_ex.load_value,
                    load_unit=src_ex.load_unit,
                    starts_at_week=src_ex.starts_at_week,
                    ends_at_week=src_ex.ends_at_week,
                    inactive_weeks=list(src_ex.inactive_weeks or []),
                    set_details=list(src_ex.set_details or []),
                )

        # Progression metadata (week definitions + per-cell overrides).
        for wdef in WeekDefinition.objects.filter(workout_plan=source):
            WeekDefinition.objects.create(
                workout_plan=new_plan,
                week_number=wdef.week_number,
                label=wdef.label,
                week_type=wdef.week_type,
                preset=wdef.preset,
                notes=wdef.notes,
            )

        # Map old exercise pk → new exercise pk (same ordering by day/order).
        src_ex_pks = list(
            WorkoutExercise.objects.filter(workout_day__workout_plan=source)
            .order_by('workout_day__day_order', 'order_index', 'id')
            .values_list('id', flat=True)
        )
        new_ex_pks = list(
            WorkoutExercise.objects.filter(workout_day__workout_plan=new_plan)
            .order_by('workout_day__day_order', 'order_index', 'id')
            .values_list('id', flat=True)
        )
        ex_map = dict(zip(src_ex_pks, new_ex_pks)) if len(src_ex_pks) == len(new_ex_pks) else {}

        if ex_map:
            for ov in WeeklyOverride.objects.filter(workout_exercise__workout_day__workout_plan=source):
                new_ex_id = ex_map.get(ov.workout_exercise_id)
                if not new_ex_id:
                    continue
                WeeklyOverride.objects.create(
                    workout_exercise_id=new_ex_id,
                    week_number=ov.week_number,
                    metric=ov.metric,
                    value_json=ov.value_json,
                )
            for wv in WeeklyValue.objects.filter(workout_exercise__workout_day__workout_plan=source):
                new_ex_id = ex_map.get(wv.workout_exercise_id)
                if not new_ex_id:
                    continue
                WeeklyValue.objects.create(
                    workout_exercise_id=new_ex_id,
                    week_number=wv.week_number,
                    load_value=wv.load_value,
                    load_unit=wv.load_unit,
                    set_count=wv.set_count,
                    rep_range=wv.rep_range,
                    rpe=wv.rpe,
                    rir=wv.rir,
                    recovery_seconds=wv.recovery_seconds,
                    tempo=wv.tempo,
                    rom_stage=wv.rom_stage,
                    variant_exercise=wv.variant_exercise,
                    velocity_target=wv.velocity_target,
                    notes=wv.notes,
                    is_override=wv.is_override,
                    is_deload=wv.is_deload,
                )

    cache.delete(f'workout_plans:{coach.id}')
    return JsonResponse({
        'status': 'ok',
        'plan_id': new_plan.id,
        'redirect_url': f'/allenamenti/wizard/{new_plan.id}/',
    })


# ---------------------------------------------------------------------------
# Search APIs
# ---------------------------------------------------------------------------

def api_search_clients(request):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse([], safe=False)
    query = request.GET.get('q', '').strip()
    exclude_plan_id = request.GET.get('exclude_plan_id', '').strip()

    qs = ClientProfile.objects.filter(
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).distinct()

    if query:
        qs = qs.filter(Q(first_name__icontains=query) | Q(last_name__icontains=query))

    if exclude_plan_id:
        try:
            assigned_ids = WorkoutAssignment.objects.filter(
                workout_plan_id=int(exclude_plan_id),
                coach=coach,
                status='ACTIVE',
            ).values_list('client_id', flat=True)
            qs = qs.exclude(id__in=list(assigned_ids))
        except (ValueError, TypeError):
            pass

    clients = list(qs.order_by('first_name', 'last_name')[:30])

    # Look up each client's currently active assignment (different plan than the
    # one being assigned) so the wizard can warn about overwrites.
    active_map = {}
    if clients:
        client_ids = [c.id for c in clients]
        active_qs = WorkoutAssignment.objects.filter(
            client_id__in=client_ids,
            coach=coach,
            status='ACTIVE',
        ).select_related('workout_plan').order_by('-start_date')
        if exclude_plan_id:
            try:
                active_qs = active_qs.exclude(workout_plan_id=int(exclude_plan_id))
            except (ValueError, TypeError):
                pass
        today = date.today()
        for a in active_qs:
            if a.client_id in active_map:
                continue
            weeks_remaining = 0
            if a.end_date:
                delta_days = (a.end_date - today).days
                weeks_remaining = max(0, int(round(delta_days / 7)))
            active_map[a.client_id] = {
                'assignment_id': a.id,
                'plan_id': a.workout_plan_id,
                'plan_title': a.workout_plan.title,
                'end_date': a.end_date.isoformat() if a.end_date else None,
                'weeks_remaining': weeks_remaining,
            }

    data = [
        {
            'id': c.id,
            'name': f"{c.first_name} {c.last_name}".strip(),
            'active_assignment': active_map.get(c.id),
        }
        for c in clients
    ]
    return JsonResponse(data, safe=False)


def api_search_exercises(request):
    query = request.GET.get('q', '').strip()
    muscle = request.GET.get('muscle', '').strip()
    muscle_slug = request.GET.get('muscle_slug', '').strip()
    equipment = request.GET.get('equipment', '').strip()
    sport = request.GET.get('sport', '').strip()
    sport_slug = request.GET.get('sport_slug', '').strip()
    custom_only = request.GET.get('custom', '').strip().lower() in ('1', 'true', 'yes')

    coach = get_session_coach(request)

    qs = Exercise.objects.all()

    # Hide other coaches' custom exercises
    if coach:
        qs = qs.filter(Q(is_custom=False) | Q(created_by=coach))
    else:
        qs = qs.filter(is_custom=False)

    if query:
        qs = qs.filter(name__icontains=query)
    if muscle_slug:
        qs = qs.filter(
            Q(primary_muscles__slug=muscle_slug) | Q(secondary_muscles__slug=muscle_slug)
        )
    elif muscle:
        qs = qs.filter(target_muscle_group__iexact=muscle)
    if equipment:
        qs = qs.filter(equipment__iexact=equipment)
    if sport_slug:
        qs = qs.filter(sports__slug=sport_slug)
    elif sport:
        qs = qs.filter(exercise_classification__iexact=sport)
    if custom_only:
        qs = qs.filter(is_custom=True)

    qs = qs.distinct().order_by('name')[:30]

    def _card(ex):
        card = serialize_exercise_card(ex)
        card.update({
            'is_custom': ex.is_custom,
            'primary_muscles': list(ex.primary_muscles.values('slug', 'name', 'color_token')),
            'secondary_muscles': list(ex.secondary_muscles.values('slug', 'name', 'color_token')),
            'sports': list(ex.sports.values('slug', 'name', 'icon')),
            'cover_image': ex.cover_image.url if ex.cover_image else '',
        })
        return card

    return JsonResponse([_card(e) for e in qs], safe=False)


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


def api_client_workout_history(request):
    """Paginated past workout assignments for the logged-in client."""
    if request.method != 'GET':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'forbidden'}, status=403)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    try:
        offset = max(0, int(request.GET.get('offset', 0)))
        limit = min(20, max(1, int(request.GET.get('limit', WORKOUT_HISTORY_PAGE_SIZE))))
    except (TypeError, ValueError):
        offset, limit = 0, WORKOUT_HISTORY_PAGE_SIZE

    current = (
        WorkoutAssignment.objects
        .filter(client=client, status='ACTIVE')
        .order_by('-start_date', '-created_at')
        .values_list('id', flat=True)
        .first()
    )
    qs = (
        WorkoutAssignment.objects
        .filter(client=client)
        .select_related('workout_plan', 'workout_plan__sport')
        .annotate(_completed=Count('sessions', filter=Q(sessions__client=client, sessions__completed=True), distinct=True))
        .order_by('-start_date', '-created_at')
    )
    if current is not None:
        qs = qs.exclude(id=current)
    total = qs.count()
    today = date.today()
    page = list(qs[offset:offset + limit])
    for a in page:
        _enrich_client_history_row(a, today)
    items = [_serialize_history_row(a) for a in page]
    return JsonResponse({
        'items': items,
        'total': total,
        'offset': offset,
        'limit': limit,
        'has_more': (offset + limit) < total,
    })


def coach_client_workout_history_view(request, client_id):
    """Coach-facing storico of the workout plans (schede) an athlete followed.
    Page render on GET; JSON page when ?partial=1 (Carica altri)."""
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')
    relationship = get_object_or_404(
        CoachingRelationship.objects.select_related('client'),
        coach=coach, client_id=client_id,
    )
    client = relationship.client

    try:
        offset = max(0, int(request.GET.get('offset', 0)))
    except (TypeError, ValueError):
        offset = 0
    limit = WORKOUT_HISTORY_PAGE_SIZE

    current = (
        WorkoutAssignment.objects
        .filter(client=client, status='ACTIVE')
        .order_by('-start_date', '-created_at')
        .values_list('id', flat=True)
        .first()
    )
    qs = (
        WorkoutAssignment.objects
        .filter(client=client, coach=coach)
        .select_related('workout_plan', 'workout_plan__sport')
        .annotate(_completed=Count('sessions', filter=Q(sessions__client=client, sessions__completed=True), distinct=True))
        .order_by('-start_date', '-created_at')
    )
    if current is not None:
        qs = qs.exclude(id=current)
    total = qs.count()
    today = date.today()
    page = list(qs[offset:offset + limit])
    for a in page:
        _enrich_client_history_row(a, today)
    items = [_serialize_history_row(a) for a in page]
    has_more = (offset + limit) < total

    if request.GET.get('partial'):
        return JsonResponse({'items': items, 'has_more': has_more})

    return render(request, 'pages/clienti/storico_allenamenti.html', {
        'coach': coach,
        'client': client,
        'items': items,
        'total': total,
        'has_more': has_more,
        'page_size': limit,
    })


# ---------------------------------------------------------------------------
# AI import — Excel (sync) + PDF (async, polling)
# ---------------------------------------------------------------------------

from django.views.decorators.http import require_http_methods

from domain.shared.import_jobs import JobStore, serialize_status

_MAX_WORKOUT_EXCEL_SIZE = 10 * 1024 * 1024   # 10 MB
_MAX_WORKOUT_PDF_SIZE = 20 * 1024 * 1024     # 20 MB

_WORKOUT_IMPORT_JOBS = JobStore(prefix='workout_import:', ttl=600)


def allenamenti_import_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')
    return render(request, 'pages/allenamenti/import_workout.html', {})


def allenamenti_import_pdf_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')
    return render(request, 'pages/allenamenti/import_workout_pdf.html', {})


@require_http_methods(['POST'])
def api_workout_import_excel(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    uploaded = request.FILES.get('file')
    if not uploaded:
        return JsonResponse({'error': 'File mancante'}, status=422)
    if uploaded.size > _MAX_WORKOUT_EXCEL_SIZE:
        return JsonResponse({'error': 'excel_invalid', 'detail': 'File troppo grande (max 10MB)'}, status=422)
    name_lower = (uploaded.name or '').lower()
    if not (name_lower.endswith('.xlsx') or name_lower.endswith('.xls')):
        return JsonResponse({'error': 'excel_invalid', 'detail': 'Formato file non supportato (solo .xlsx/.xls)'}, status=422)

    plan_title = (request.POST.get('plan_title') or '').strip()[:200]
    client_id = request.POST.get('client_id') or ''
    client_data = _resolve_import_client(coach, client_id)
    if isinstance(client_data, JsonResponse):
        return client_data

    allowed, _ = import_quota.consume(coach, import_quota.WORKOUT)
    if not allowed:
        return import_quota.limit_response(import_quota.WORKOUT)

    from domain.workouts.imports.excel_importer import (
        run_import_pipeline, ExcelParseError, AIExtractionError,
    )

    try:
        file_bytes = uploaded.read()
        extracted, confidence = run_import_pipeline(file_bytes, plan_title, coach=coach)
    except ExcelParseError as e:
        return JsonResponse({'error': 'excel_invalid', 'detail': str(e)}, status=422)
    except AIExtractionError as e:
        return JsonResponse({'error': 'ai_failed', 'detail': str(e)}, status=500)
    except Exception as e:
        return JsonResponse({'error': 'unknown', 'detail': str(e)}, status=500)

    payload = {
        'extracted': extracted,
        'confidence': confidence.model_dump(),
        'client': client_data,
        'plan_title': plan_title or extracted.get('plan_name') or '',
    }
    status = 206 if confidence.ratio >= 0.5 else 200
    if status == 206:
        payload['warning'] = 'high_uncertainty'
    return JsonResponse(payload, status=status)


def _resolve_import_client(coach, client_id):
    """Validate client belongs to coach. Returns dict or JsonResponse on error."""
    if not client_id:
        return None
    try:
        client = ClientProfile.objects.get(
            id=int(client_id),
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE',
        )
    except (ValueError, ClientProfile.DoesNotExist):
        return JsonResponse({'error': 'Atleta non valido o non associato'}, status=403)
    return {'id': client.id, 'name': f"{client.first_name} {client.last_name}".strip()}


def _run_workout_pdf_job(job_id: str, file_bytes: bytes, plan_title: str,
                         client_data, coach_id: int) -> None:
    from domain.workouts.imports.pdf_importer import run_pdf_pipeline
    from domain.shared.pdf.ingestion import PdfParseError
    from domain.workouts.imports.pdf_extractor import AIExtractionError

    from domain.accounts.models import CoachProfile
    try:
        coach_obj = CoachProfile.objects.get(id=coach_id)
    except CoachProfile.DoesNotExist:
        coach_obj = None

    progress = _WORKOUT_IMPORT_JOBS.progress_cb(job_id)

    try:
        extracted, confidence = run_pdf_pipeline(
            file_bytes, plan_title, progress_cb=progress, coach=coach_obj,
        )
    except PdfParseError as e:
        msg = str(e)
        code = 'pdf_no_content' if 'non sembra contenere' in msg.lower() else 'pdf_invalid'
        _WORKOUT_IMPORT_JOBS.set(job_id, {'status': 'error', 'error_code': code, 'detail': msg})
        return
    except AIExtractionError as e:
        _WORKOUT_IMPORT_JOBS.set(job_id, {'status': 'error', 'error_code': 'ai_failed', 'detail': str(e)})
        return
    except Exception as e:
        _WORKOUT_IMPORT_JOBS.set(job_id, {'status': 'error', 'error_code': 'unknown', 'detail': str(e)})
        return

    result = {
        'extracted': extracted,
        'confidence': confidence.model_dump(),
        'document_summary': extracted.get('document_summary'),
        'client': client_data,
        'plan_title': plan_title or extracted.get('plan_name') or '',
        'warning': 'high_uncertainty' if confidence.ratio >= 0.5 else None,
    }
    _WORKOUT_IMPORT_JOBS.set(job_id, {
        'status': 'done', 'phase': 'finalize', 'percent': 100, 'result': result,
    })


@require_http_methods(['POST'])
def api_workout_import_pdf(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    uploaded = request.FILES.get('file')
    if not uploaded:
        return JsonResponse({'error': 'File mancante'}, status=422)
    if uploaded.size > _MAX_WORKOUT_PDF_SIZE:
        return JsonResponse({'error': 'pdf_invalid', 'detail': 'File troppo grande (max 20MB)'}, status=422)
    name_lower = (uploaded.name or '').lower()
    if not name_lower.endswith('.pdf'):
        return JsonResponse({'error': 'pdf_invalid', 'detail': 'Formato file non supportato (solo .pdf)'}, status=422)

    plan_title = (request.POST.get('plan_title') or '').strip()[:200]
    client_id = request.POST.get('client_id') or ''
    client_data = _resolve_import_client(coach, client_id)
    if isinstance(client_data, JsonResponse):
        return client_data

    allowed, _ = import_quota.consume(coach, import_quota.WORKOUT)
    if not allowed:
        return import_quota.limit_response(import_quota.WORKOUT)

    file_bytes = uploaded.read()
    job_id = _WORKOUT_IMPORT_JOBS.spawn(
        target=_run_workout_pdf_job,
        args=(file_bytes, plan_title, client_data, coach.id),
        initial_phase='analyze',
    )
    return JsonResponse({'job_id': job_id, 'status': 'queued'}, status=202)


@require_http_methods(['GET'])
def api_workout_import_pdf_status(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    job_id = request.GET.get('job_id') or ''
    if not job_id:
        return JsonResponse({'error': 'job_not_found', 'detail': 'job_id mancante'}, status=400)
    job = _WORKOUT_IMPORT_JOBS.get(job_id)
    if not job:
        return JsonResponse({'error': 'job_not_found', 'detail': 'Job scaduto o inesistente'}, status=404)
    return JsonResponse(serialize_status(job_id, job))


# Maps from AI extraction JSON to DB columns.
_VALID_LOAD_UNIT_MAP = {
    'kg': WorkoutExercise.LOAD_UNIT_KG,
    'lb': WorkoutExercise.LOAD_UNIT_KG,           # converted below
    'bw': WorkoutExercise.LOAD_UNIT_BODYWEIGHT,
    'band': WorkoutExercise.LOAD_UNIT_BODYWEIGHT, # closest existing choice
}

_BLOCK_TYPE_NATIVE = {'straight', 'superset'}     # supported via superset_group_id alone


def _coerce_load(ex_payload: dict) -> tuple[float | None, str | None]:
    load = ex_payload.get('load')
    unit = (ex_payload.get('load_unit') or '').lower() or None
    load_type = (ex_payload.get('load_type') or '').lower() or None

    if load_type == 'percentage_1rm':
        try:
            return float(load), WorkoutExercise.LOAD_UNIT_PERCENT
        except (TypeError, ValueError):
            return None, WorkoutExercise.LOAD_UNIT_PERCENT
    if unit == 'lb' and load is not None:
        try:
            return round(float(load) * 0.4536, 2), WorkoutExercise.LOAD_UNIT_KG
        except (TypeError, ValueError):
            return None, WorkoutExercise.LOAD_UNIT_KG
    if unit in ('bw', 'band'):
        return None, WorkoutExercise.LOAD_UNIT_BODYWEIGHT
    if load is None:
        return None, None
    try:
        return float(load), WorkoutExercise.LOAD_UNIT_KG
    except (TypeError, ValueError):
        return None, None


def _coerce_set_details(raw, set_count: int) -> list:
    """Sanitize the builder's per-set override list.

    Returns a clean list (length capped to set_count, max 30) where each entry
    keeps only the known keys. Empty/invalid input -> [] (uniform prescription).
    """
    if not isinstance(raw, list) or not raw:
        return []

    def _num(v):
        try:
            f = float(v)
            return int(f) if f.is_integer() else f
        except (TypeError, ValueError):
            return None

    out = []
    for entry in raw[:min(set_count or len(raw), 30)]:
        if not isinstance(entry, dict):
            out.append({})
            continue
        clean = {}
        for k in ('reps', 'rep_range', 'tempo'):
            val = entry.get(k)
            if val not in (None, ''):
                clean[k] = str(val)[:50]
        for k in ('rir', 'rpe', 'recovery_seconds'):
            n = _num(entry.get(k))
            if n is not None:
                clean[k] = int(n)
        lv = _num(entry.get('load_value'))
        if lv is not None:
            clean['load_value'] = lv
        lu = entry.get('load_unit')
        if lu in ('KG', 'PERCENT_1RM', 'BODYWEIGHT'):
            clean['load_unit'] = lu
        out.append(clean)
    # If every entry is empty, treat as uniform.
    return out if any(out) else []


def _coerce_reps(ex_payload: dict) -> tuple[int | None, str | None]:
    """Return (rep_count_int, rep_range_str). One of them is set; never both."""
    reps = ex_payload.get('reps')
    reps_type = (ex_payload.get('reps_type') or '').lower()
    if reps is None:
        return None, None
    if isinstance(reps, int):
        if reps_type == 'range':
            return None, str(reps)
        return reps, None
    s = str(reps).strip()
    if not s:
        return None, None
    if reps_type == 'fixed':
        try:
            return int(s), None
        except ValueError:
            return None, s[:50]
    return None, s[:50]


@require_http_methods(['POST'])
def api_workout_import_confirm(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    try:
        data = json.loads(request.body)
    except (ValueError, json.JSONDecodeError):
        return JsonResponse({'error': 'Body JSON non valido'}, status=400)

    workout_json = data.get('workout_json') or {}
    plan_title = (data.get('plan_title') or workout_json.get('plan_name') or '').strip()[:200]
    notes = (data.get('notes') or '') or None
    assign_now = bool(data.get('assign_now', False))
    client_id = data.get('client_id')

    # Plan kind selector (WEEKLY single week vs PROGRAM multi-week).
    plan_kind = (data.get('plan_kind') or 'WEEKLY').upper()
    if plan_kind not in (WorkoutPlan.KIND_WEEKLY, WorkoutPlan.KIND_PROGRAM):
        plan_kind = WorkoutPlan.KIND_WEEKLY
    try:
        duration_weeks = int(data.get('duration_weeks') or 1)
    except (TypeError, ValueError):
        duration_weeks = 1
    duration_weeks = max(1, min(52, duration_weeks))
    if plan_kind == WorkoutPlan.KIND_WEEKLY:
        duration_weeks = 1

    if not plan_title:
        return JsonResponse({'error': 'Titolo scheda obbligatorio'}, status=400)

    client = None
    if client_id:
        try:
            client = ClientProfile.objects.get(
                id=int(client_id),
                coaching_relationships_as_client__coach=coach,
                coaching_relationships_as_client__status='ACTIVE',
            )
        except (ValueError, ClientProfile.DoesNotExist):
            return JsonResponse({'error': 'Atleta non associato'}, status=403)

    sessions = workout_json.get('sessions') or []
    if not sessions:
        return JsonResponse({'error': 'Nessuna sessione nella scheda'}, status=400)

    # Verify every exercise has a matched Exercise (uncertain rows must be resolved).
    missing = []
    for s_idx, sess in enumerate(sessions):
        for b_idx, block in enumerate(sess.get('blocks') or []):
            for e_idx, ex in enumerate(block.get('exercises') or []):
                if not ex.get('matched_exercise_id'):
                    missing.append({
                        'session': s_idx, 'block': b_idx, 'exercise': e_idx,
                        'raw_name': ex.get('raw_name') or '',
                    })
    if missing:
        return JsonResponse({
            'error': 'unmatched_exercises',
            'detail': 'Risolvi tutti gli esercizi prima di salvare.',
            'missing': missing,
        }, status=400)

    try:
        with transaction.atomic():
            goal_val = (workout_json.get('goal') or '').strip()[:200] or None
            freq = workout_json.get('frequency_per_week')
            try:
                freq_int = int(freq) if freq else None
            except (TypeError, ValueError):
                freq_int = None

            plan = WorkoutPlan.objects.create(
                coach=coach,
                title=plan_title,
                description=(workout_json.get('notes') or '').strip() or None,
                goal=goal_val,
                frequency_per_week=freq_int,
                duration_weeks=duration_weeks,
                status=WorkoutPlan.STATUS_DRAFT,
                plan_kind=plan_kind,
                is_template=False,
            )

            superset_counter = 1
            for s_idx, sess in enumerate(sessions):
                day_name = (sess.get('day_label') or '').strip()[:100] or f'Giorno {s_idx+1}'
                day_obj = WorkoutDay.objects.create(
                    workout_plan=plan,
                    day_order=s_idx + 1,
                    day_name=day_name,
                    day_type=(sess.get('session_type') or '').strip()[:100] or None,
                    notes=(sess.get('notes') or '').strip() or None,
                )
                ex_order = 0
                for block in sess.get('blocks') or []:
                    btype = (block.get('block_type') or 'straight').lower()
                    block_name = (block.get('block_name') or '').strip()
                    is_grouped = btype in ('superset', 'circuit')
                    group_id = superset_counter if is_grouped else None
                    if is_grouped:
                        superset_counter += 1
                    block_tag = None
                    if btype not in _BLOCK_TYPE_NATIVE:
                        block_tag = f'[{btype.upper()}{":" + block_name if block_name else ""}] '

                    for ex_payload in block.get('exercises') or []:
                        try:
                            exercise_obj = Exercise.objects.get(id=int(ex_payload['matched_exercise_id']))
                        except (Exercise.DoesNotExist, ValueError, TypeError, KeyError):
                            continue

                        ex_order += 1
                        rep_count, rep_range = _coerce_reps(ex_payload)
                        load_val, load_unit = _coerce_load(ex_payload)
                        rest = ex_payload.get('rest_seconds')
                        try:
                            rest_int = int(rest) if rest not in (None, '') else None
                        except (TypeError, ValueError):
                            rest_int = None
                        rpe_raw = ex_payload.get('rpe')
                        rir_raw = ex_payload.get('rir')
                        try:
                            rpe_int = int(round(float(rpe_raw))) if rpe_raw not in (None, '') else None
                        except (TypeError, ValueError):
                            rpe_int = None
                        try:
                            rir_int = int(rir_raw) if rir_raw not in (None, '') else None
                        except (TypeError, ValueError):
                            rir_int = None

                        sets_raw = ex_payload.get('sets')
                        try:
                            sets_int = int(sets_raw) if sets_raw not in (None, '') else None
                        except (TypeError, ValueError):
                            sets_int = None

                        tn_bits = []
                        if block_tag:
                            tn_bits.append(block_tag.strip())
                        if ex_payload.get('notes'):
                            tn_bits.append(str(ex_payload['notes']).strip())
                        if ex_payload.get('rest_label') and rest_int is None:
                            tn_bits.append(f"Recupero: {ex_payload['rest_label']}")
                        if ex_payload.get('duration_seconds'):
                            tn_bits.append(f"Durata: {ex_payload['duration_seconds']}s")
                        if ex_payload.get('distance') and ex_payload.get('distance_unit'):
                            tn_bits.append(f"Distanza: {ex_payload['distance']}{ex_payload['distance_unit']}")
                        technique_notes = '\n'.join(tn_bits) or None

                        WorkoutExercise.objects.create(
                            workout_day=day_obj,
                            exercise=exercise_obj,
                            order_index=ex_order,
                            set_count=sets_int,
                            rep_count=rep_count,
                            rep_range=rep_range,
                            rir=rir_int,
                            rpe=rpe_int,
                            recovery_seconds=rest_int,
                            tempo=(ex_payload.get('tempo') or '').strip()[:50] or None,
                            load_value=load_val,
                            load_unit=load_unit,
                            technique_notes=technique_notes,
                            superset_group_id=group_id,
                        )

            # Sync progression scaffolding (single-week WEEKLY plan).
            progression_engine.sync_week_definitions(plan)
            progression_engine.compute_weekly_values(plan)

            assignment_id = None
            if assign_now and client:
                start_date = date.today()
                weeks = plan.duration_weeks or 1
                end_date = start_date + timedelta(weeks=weeks)
                WorkoutAssignment.objects.filter(
                    client=client, coach=coach, status='ACTIVE',
                ).update(status='COMPLETED', end_date=start_date)
                assignment = WorkoutAssignment.objects.create(
                    workout_plan=plan,
                    client=client,
                    coach=coach,
                    status='ACTIVE',
                    start_date=start_date,
                    end_date=end_date,
                )
                assignment_id = assignment.id
                Notification.objects.create(
                    target_user=client.user,
                    notification_type='WORKOUT_ASSIGNED',
                    title='Nuova scheda di allenamento',
                    body=f'Ti è stata assegnata la scheda "{plan.title}".',
                    link_url='/allenamenti/',
                )
                try:
                    from django.conf import settings as _settings
                    plan_url = f"{_settings.SITE_URL}/allenamenti/"
                    send_workout_assigned(client, coach, plan, plan_url)
                except Exception:
                    logger.exception('workout_assigned_email.failed plan_id=%s', plan.id)
                plan.status = WorkoutPlan.STATUS_ACTIVE
                plan.save(update_fields=['status'])
    except Exception as e:
        return JsonResponse({'error': 'save_failed', 'detail': str(e)}, status=500)

    return JsonResponse({
        'ok': True,
        'plan_id': plan.id,
        'assignment_id': assignment_id,
        'redirect_url': f'/allenamenti/{plan.id}/',
    })
