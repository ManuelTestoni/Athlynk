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
    Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment
)
from domain.chat.models import Notification

from .session_utils import (
    get_session_user, get_session_coach, get_session_client,
    get_active_relationship, can_manage_workouts,
)


# ---------------------------------------------------------------------------
# Normalization maps (target muscles + equipment)
# ---------------------------------------------------------------------------

MUSCLE_GROUPS = ['Petto', 'Schiena', 'Spalle', 'Bicipiti', 'Tricipiti',
                 'Quadricipiti', 'Femorali', 'Glutei', 'Core', 'Polpacci', 'Full Body']

MUSCLE_KEYWORDS = {
    'Petto': ['pettoral', 'petto'],
    'Schiena': ['dorsal', 'schiena', 'trapez', 'romboid', 'erettor', 'lat'],
    'Spalle': ['spalle', 'deltoide'],
    'Bicipiti': ['bicipit', 'brachiorad'],
    'Tricipiti': ['tricipit'],
    'Quadricipiti': ['quadricipit'],
    'Femorali': ['femoral', 'ischiocrural'],
    'Glutei': ['glute'],
    'Core': ['core', 'addominal', 'obliqu', 'flessori anca', 'retto', 'piriform', 'rotatori anca'],
    'Polpacci': ['polpacc', 'gastroc', 'soleo'],
    'Full Body': ['tutto il corpo', 'full body'],
}

EQUIP_GROUPS = ['Bilanciere', 'Manubri', 'Macchina', 'Cavi', 'Corpo Libero',
                'Kettlebell', 'Banda Elastica']

EQUIP_KEYWORDS = {
    'Bilanciere': ['bilanciere'],
    'Manubri': ['manubri', 'manubrio'],
    'Macchina': ['macchina', 'machine', 'leg press', 'leg curl', 'leg extension',
                 'lat machine', 'hack squat', 'remoergometro'],
    'Cavi': ['cavi'],
    'Corpo Libero': ['corpo libero', 'nessun attrezzo', 'sbarra', 'parallele',
                     'tappetino', 'materassino', 'ab wheel'],
    'Kettlebell': ['kettlebell'],
    'Banda Elastica': ['banda elastica', 'elastico'],
}


def normalize_muscles(raw_text):
    if not raw_text:
        return []
    parts = [p.strip().lower() for p in raw_text.split(',') if p.strip()]
    found = []
    for part in parts:
        for group, keywords in MUSCLE_KEYWORDS.items():
            if any(k in part for k in keywords):
                if group not in found:
                    found.append(group)
                break
    return found


def normalize_equipment(raw_text):
    if not raw_text:
        return []
    parts = [p.strip().lower() for p in raw_text.split(',') if p.strip()]
    found = []
    for part in parts:
        for group, keywords in EQUIP_KEYWORDS.items():
            if any(k in part for k in keywords):
                if group not in found:
                    found.append(group)
                break
    return found


def serialize_exercise_card(ex):
    return {
        'id': ex.id,
        'name': ex.name,
        'target_muscles_raw': ex.target_muscles or '',
        'secondary_muscles_raw': ex.secondary_muscles or '',
        'primary_muscles': normalize_muscles(ex.target_muscles),
        'secondary_muscles': normalize_muscles(ex.secondary_muscles),
        'equipment_raw': ex.equipment or '',
        'equipment_groups': normalize_equipment(ex.equipment),
        'video_url': ex.video_url or '',
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
            days_list = [{'id': d.id, 'order': d.day_order, 'name': d.day_name or f'Giorno {d.day_order}'} for d in a.workout_plan.days.all().order_by('day_order')]
            a.days_json = json.dumps(days_list)

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
                'primary_muscles': normalize_muscles(ex.exercise.target_muscles),
                'secondary_muscles': normalize_muscles(ex.exercise.secondary_muscles),
                'equipment_groups': normalize_equipment(ex.exercise.equipment),
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
        'status': plan.status,
        'last_step': plan.last_step or 1,
        'days': days,
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
            'status': 'DRAFT',
            'last_step': 1,
            'days': [],
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
    if 'last_step' in data:
        try:
            plan.last_step = max(1, min(3, int(data['last_step'])))
        except (TypeError, ValueError):
            pass
    plan.coach = coach
    plan.save()

    if 'days' not in data:
        return

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

        for ex_id, we in existing_ex.items():
            if ex_id not in seen_ex_ids:
                we.delete()

    for day_id, day in existing_days.items():
        if day_id not in seen_day_ids:
            day.delete()


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
        start_date = data.get('start_date')
        end_date = data.get('end_date') or None
        if not start_date:
            return JsonResponse({'error': 'Data inizio obbligatoria.'}, status=400)

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

    qs = Exercise.objects.all()
    if query:
        qs = qs.filter(name__icontains=query)
    if muscle and muscle in MUSCLE_KEYWORDS:
        kw_q = Q()
        for kw in MUSCLE_KEYWORDS[muscle]:
            kw_q |= Q(target_muscles__icontains=kw) | Q(secondary_muscles__icontains=kw)
        qs = qs.filter(kw_q)
    if equipment and equipment in EQUIP_KEYWORDS:
        kw_q = Q()
        for kw in EQUIP_KEYWORDS[equipment]:
            kw_q |= Q(equipment__icontains=kw)
        qs = qs.filter(kw_q)

    qs = qs.order_by('name')[:20]
    return JsonResponse([serialize_exercise_card(e) for e in qs], safe=False)


def api_exercise_filters(request):
    return JsonResponse({
        'muscles': MUSCLE_GROUPS,
        'equipment': EQUIP_GROUPS,
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
