"""Real-time workout session + progress tracking views & APIs."""
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse, HttpResponseForbidden
from django.views.decorators.csrf import csrf_exempt
from django.utils import timezone
from django.db import transaction
from django.db.models import Avg, Count, Max, Sum, F
from datetime import timedelta, date
import json

from domain.accounts.models import ClientProfile, CoachProfile
from domain.workouts.models import (
    Exercise, WorkoutPlan, WorkoutDay, WorkoutExercise, WorkoutAssignment,
    WorkoutSession, WorkoutSetLog, SessionMedia, SessionCoachNote,
)
from domain.coaching.models import CoachingRelationship
from domain.chat.models import Notification

from .session_utils import (
    get_session_user, get_session_client, get_session_coach, can_manage_workouts,
)
from .views_workouts import normalize_muscles


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _can_coach_view_client(coach, client):
    if not coach or not client:
        return False
    return CoachingRelationship.objects.filter(
        coach=coach, client=client, status='ACTIVE'
    ).exists()


def _serialize_session_brief(s):
    return {
        'id': s.id,
        'started_at': s.started_at.isoformat() if s.started_at else None,
        'ended_at': s.ended_at.isoformat() if s.ended_at else None,
        'duration_minutes': s.duration_minutes,
        'avg_rpe': s.avg_rpe,
        'completed': s.completed,
        'interrupted': s.interrupted,
        'day_name': s.workout_day.day_name or f'Giorno {s.workout_day.day_order}',
        'day_id': s.workout_day.id,
        'notes': s.notes or '',
    }


def _serialize_session_full(s):
    out = _serialize_session_brief(s)
    sets = list(s.set_logs.select_related(
        'workout_exercise__exercise', 'workout_exercise__alternative_exercise'
    ).order_by('workout_exercise__order_index', 'set_number'))
    by_ex = {}
    exercise_notes_by_we = {}
    for sl in sets:
        we_id = sl.workout_exercise.id
        if sl.set_number == 0:
            exercise_notes_by_we[we_id] = sl.notes or ''
            continue
        if we_id not in by_ex:
            alt = sl.workout_exercise.alternative_exercise
            by_ex[we_id] = {
                'workout_exercise_id': we_id,
                'exercise_name': sl.workout_exercise.exercise.name,
                'prescribed_sets': sl.workout_exercise.set_count,
                'prescribed_reps': sl.workout_exercise.rep_range,
                'prescribed_load': float(sl.workout_exercise.load_value) if sl.workout_exercise.load_value else None,
                'prescribed_load_unit': sl.workout_exercise.load_unit or 'KG',
                'prescribed_recovery': sl.workout_exercise.recovery_seconds,
                'alternative_exercise': {'id': alt.id, 'name': alt.name} if alt else None,
                'exercise_note': '',
                'sets': [],
            }
        by_ex[we_id]['sets'].append({
            'set_number': sl.set_number,
            'reps_done': sl.reps_done,
            'load_used': float(sl.load_used) if sl.load_used else None,
            'load_unit': sl.load_unit,
            'rpe': sl.rpe,
            'notes': sl.notes or '',
            'completed': sl.completed,
            'is_extra_set': sl.is_extra_set,
            'exercise_substituted': sl.exercise_substituted,
            'actual_exercise': {
                'id': sl.actual_exercise.id, 'name': sl.actual_exercise.name,
            } if sl.actual_exercise else None,
        })
    for we_id, note in exercise_notes_by_we.items():
        if we_id in by_ex:
            by_ex[we_id]['exercise_note'] = note
    out['exercises'] = list(by_ex.values())
    out['exercise_notes'] = exercise_notes_by_we
    out['media'] = [{
        'id': m.id,
        'type': m.media_type,
        'url': m.file.url,
        'uploaded_at': m.uploaded_at.isoformat(),
        'coach_comment': m.coach_comment or '',
    } for m in s.media.all()]
    out['coach_notes'] = [{
        'id': n.id,
        'text': n.text,
        'coach_name': f"{n.coach.first_name} {n.coach.last_name}",
        'created_at': n.created_at.isoformat(),
    } for n in s.coach_notes.all()]
    return out


# ---------------------------------------------------------------------------
# Client: assignment detail
# ---------------------------------------------------------------------------

def client_assignment_detail_view(request, assignment_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    client = get_session_client(request)
    if not client:
        return redirect('dashboard')

    assignment = get_object_or_404(
        WorkoutAssignment.objects.select_related('workout_plan', 'coach')
                                 .prefetch_related('workout_plan__days__exercises__exercise'),
        id=assignment_id, client=client,
    )

    # Build days serialized for chart computation
    days_data = []
    for d in assignment.workout_plan.days.all().order_by('day_order'):
        ex_list = []
        for ex in d.exercises.all().order_by('order_index'):
            ex_list.append({
                'id': ex.id,
                'name': ex.exercise.name,
                'sets': ex.set_count or 3,
                'reps': ex.rep_range or '10',
                'load_value': float(ex.load_value) if ex.load_value else None,
                'load_unit': ex.load_unit or 'KG',
                'recovery_seconds': ex.recovery_seconds or 90,
                'notes': ex.technique_notes or '',
                'primary_muscles': normalize_muscles(ex.exercise.target_muscles),
                'secondary_muscles': normalize_muscles(ex.exercise.secondary_muscles),
            })
        days_data.append({
            'id': d.id,
            'order': d.day_order,
            'name': d.day_name or f'Giorno {d.day_order}',
            'exercises': ex_list,
        })

    PAGE_SIZE = 20
    sessions_qs = assignment.sessions.filter(client=client).order_by('-started_at')
    total_sessions = sessions_qs.count()
    sessions = list(sessions_qs[:PAGE_SIZE])

    return render(request, 'pages/allenamenti/client_detail.html', {
        'assignment': assignment,
        'plan': assignment.workout_plan,
        'days_json': json.dumps(days_data),
        'sessions': sessions,
        'total_sessions': total_sessions,
        'sessions_page_size': PAGE_SIZE,
        'has_more_sessions': total_sessions > PAGE_SIZE,
        'is_client': True,
        'client': client,
        'coach': assignment.coach,
    })


def client_assignment_volume_view(request, assignment_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    client = get_session_client(request)
    if not client:
        return redirect('dashboard')
    assignment = get_object_or_404(
        WorkoutAssignment.objects.select_related('workout_plan', 'coach')
                                 .prefetch_related('workout_plan__days__exercises__exercise'),
        id=assignment_id, client=client,
    )
    days_data = []
    for d in assignment.workout_plan.days.all().order_by('day_order'):
        ex_list = []
        for ex in d.exercises.all().order_by('order_index'):
            ex_list.append({
                'sets': ex.set_count or 3,
                'reps': ex.rep_range or '10',
                'recovery_seconds': ex.recovery_seconds or 90,
                'primary_muscles': normalize_muscles(ex.exercise.target_muscles),
                'secondary_muscles': normalize_muscles(ex.exercise.secondary_muscles),
            })
        days_data.append({'id': d.id, 'order': d.day_order, 'exercises': ex_list})
    return render(request, 'pages/allenamenti/client_volume.html', {
        'assignment': assignment,
        'plan': assignment.workout_plan,
        'days_json': json.dumps(days_data),
        'is_client': True,
        'client': client,
    })


@csrf_exempt
def api_assignment_sessions_list(request, assignment_id):
    if request.method != 'GET':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    assignment = get_object_or_404(WorkoutAssignment, id=assignment_id, client=client)
    try:
        offset = max(0, int(request.GET.get('offset', 0)))
        limit = min(50, max(1, int(request.GET.get('limit', 20))))
    except (TypeError, ValueError):
        offset, limit = 0, 20
    qs = assignment.sessions.filter(client=client).select_related('workout_day').order_by('-started_at')
    total = qs.count()
    items = []
    for s in qs[offset:offset + limit]:
        day_name = s.workout_day.day_name or f'Giorno {s.workout_day.day_order}'
        items.append({
            'id': s.id,
            'day_name': day_name,
            'started_at': s.started_at.isoformat() if s.started_at else None,
            'started_at_display': s.started_at.strftime('%d %b %Y %H:%M') if s.started_at else '',
            'duration_minutes': s.duration_minutes,
            'avg_rpe': s.avg_rpe,
            'completed': s.completed,
            'interrupted': s.interrupted,
        })
    return JsonResponse({
        'sessions': items,
        'total': total,
        'offset': offset,
        'limit': limit,
        'has_more': (offset + limit) < total,
    })


# ---------------------------------------------------------------------------
# Client: real-time session view
# ---------------------------------------------------------------------------

def client_session_active_view(request, assignment_id, day_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    client = get_session_client(request)
    if not client:
        return redirect('dashboard')

    assignment = get_object_or_404(
        WorkoutAssignment.objects.select_related('workout_plan'),
        id=assignment_id, client=client,
    )
    day = get_object_or_404(WorkoutDay, id=day_id, workout_plan=assignment.workout_plan)

    if assignment.status != 'ACTIVE':
        return redirect('client_assignment_detail', assignment_id=assignment.id)

    exercises_data = []
    for ex in day.exercises.select_related('exercise', 'alternative_exercise').order_by('order_index'):
        alt = ex.alternative_exercise
        exercises_data.append({
            'id': ex.id,
            'name': ex.exercise.name,
            'image_url': ex.exercise.image_url or '',
            'sets': ex.set_count or 3,
            'reps': ex.rep_range or '10',
            'load_value': float(ex.load_value) if ex.load_value else None,
            'load_unit': ex.load_unit or 'KG',
            'recovery_seconds': ex.recovery_seconds or 90,
            'notes': ex.technique_notes or '',
            'video_url': ex.exercise.video_url or '',
            'superset_group_id': ex.superset_group_id,
            'instructions': ex.exercise.instructions or '',
            'alternative_exercise': {
                'id': alt.id,
                'name': alt.name,
                'video_url': alt.video_url or '',
            } if alt else None,
        })

    # Settimana N · Giorno Y
    today = timezone.now().date()
    start = assignment.start_date or assignment.created_at.date()
    week_index = ((today - start).days // 7) + 1 if today >= start else 1

    return render(request, 'pages/allenamenti/session_active.html', {
        'assignment': assignment,
        'day': day,
        'exercises_json': json.dumps(exercises_data),
        'plan': assignment.workout_plan,
        'week_index': week_index,
        'is_client': True,
        'client': client,
    })


# ---------------------------------------------------------------------------
# Session APIs (start/log set/finish/media)
# ---------------------------------------------------------------------------

@csrf_exempt
def api_session_start(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)

    try:
        data = json.loads(request.body)
        assignment_id = data.get('assignment_id')
        day_id = data.get('day_id')
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    assignment = get_object_or_404(WorkoutAssignment, id=assignment_id, client=client)
    day = get_object_or_404(WorkoutDay, id=day_id, workout_plan=assignment.workout_plan)

    # Reuse an open session for the same (assignment, day, client) started in the last 6 hours
    existing = WorkoutSession.objects.filter(
        assignment=assignment, workout_day=day, client=client,
        ended_at__isnull=True,
        started_at__gte=timezone.now() - timedelta(hours=6),
    ).order_by('-started_at').first()
    session = existing or WorkoutSession.objects.create(
        assignment=assignment,
        workout_day=day,
        client=client,
        started_at=timezone.now(),
    )

    exercises = []
    for ex in day.exercises.select_related('exercise').order_by('order_index'):
        exercises.append({
            'workout_exercise_id': ex.id,
            'name': ex.exercise.name,
            'video_url': ex.exercise.video_url or '',
            'sets': ex.set_count or 3,
            'reps': ex.rep_range or '10',
            'load_value': float(ex.load_value) if ex.load_value else None,
            'load_unit': ex.load_unit or 'KG',
            'recovery_seconds': ex.recovery_seconds or 90,
            'notes': ex.technique_notes or '',
        })

    sets_logged = []
    exercise_notes_map = {}
    for sl in session.set_logs.all():
        if sl.set_number == 0:
            # Sentinel row used to persist exercise-level notes
            exercise_notes_map[sl.workout_exercise_id] = sl.notes or ''
            continue
        sets_logged.append({
            'workout_exercise_id': sl.workout_exercise_id,
            'set_number': sl.set_number,
            'reps_done': sl.reps_done,
            'load_used': float(sl.load_used) if sl.load_used is not None else None,
            'load_unit': sl.load_unit,
            'rpe': sl.rpe,
            'notes': sl.notes or '',
            'completed': sl.completed,
            'is_extra_set': sl.is_extra_set,
            'exercise_substituted': sl.exercise_substituted,
            'actual_exercise_id': sl.actual_exercise_id,
        })

    return JsonResponse({
        'session_id': session.id,
        'exercises': exercises,
        'sets_logged': sets_logged,
        'exercise_notes': exercise_notes_map,
        'started_at': session.started_at.isoformat(),
    })


@csrf_exempt
def api_session_log_set(request, session_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)

    session = get_object_or_404(WorkoutSession, id=session_id, client=client)

    try:
        data = json.loads(request.body)
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)

    we_id = data.get('workout_exercise_id')
    if not we_id:
        return JsonResponse({'error': 'workout_exercise_id required'}, status=400)
    we = get_object_or_404(WorkoutExercise, id=we_id, workout_day=session.workout_day)

    set_number = int(data.get('set_number') or 1)
    reps = data.get('reps_done')
    load = data.get('load_used')
    load_unit = data.get('load_unit') or 'KG'
    rpe = data.get('rpe')
    notes = data.get('notes') or ''
    completed = bool(data.get('completed', True))
    is_extra_set = bool(data.get('is_extra_set', False))
    exercise_substituted = bool(data.get('exercise_substituted', False))
    actual_exercise_id = data.get('actual_exercise_id')
    actual_exercise = None
    if actual_exercise_id:
        try:
            actual_exercise = Exercise.objects.get(id=actual_exercise_id)
        except Exercise.DoesNotExist:
            actual_exercise = None

    log, _ = WorkoutSetLog.objects.update_or_create(
        session=session, workout_exercise=we, set_number=set_number,
        defaults={
            'reps_done': int(reps) if reps not in (None, '') else None,
            'load_used': load if load not in (None, '') else None,
            'load_unit': load_unit,
            'rpe': int(rpe) if rpe not in (None, '') else None,
            'notes': notes,
            'completed': completed,
            'is_extra_set': is_extra_set,
            'exercise_substituted': exercise_substituted,
            'actual_exercise': actual_exercise,
        },
    )
    return JsonResponse({'set_id': log.id, 'success': True})


@csrf_exempt
def api_session_finish(request, session_id):
    if request.method not in ('POST', 'PATCH'):
        return JsonResponse({'error': 'method not allowed'}, status=405)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)

    session = get_object_or_404(WorkoutSession, id=session_id, client=client)

    try:
        data = json.loads(request.body) if request.body else {}
    except Exception:
        data = {}

    notes = data.get('notes') or ''
    interrupted = bool(data.get('interrupted', False))
    exercise_notes = data.get('exercise_notes') or []

    # Persist per-exercise notes as sentinel WorkoutSetLog rows (set_number=0)
    for entry in exercise_notes:
        try:
            we_id = int(entry.get('workout_exercise_id'))
        except (TypeError, ValueError):
            continue
        text = (entry.get('notes') or '').strip()
        if not text:
            continue
        if not WorkoutExercise.objects.filter(id=we_id, workout_day=session.workout_day).exists():
            continue
        WorkoutSetLog.objects.update_or_create(
            session=session, workout_exercise_id=we_id, set_number=0,
            defaults={
                'notes': text,
                'completed': False,
                'is_extra_set': False,
                'reps_done': None,
                'load_used': None,
                'rpe': None,
            },
        )

    session.notes = notes
    session.ended_at = timezone.now()
    session.completed = not interrupted
    session.interrupted = interrupted
    session.recompute_summary()
    session.save()

    return JsonResponse({
        'session_id': session.id,
        'duration': session.duration_minutes,
        'avg_rpe': session.avg_rpe,
    })


@csrf_exempt
def api_session_upload_media(request, session_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)

    session = get_object_or_404(WorkoutSession, id=session_id, client=client)

    f = request.FILES.get('file')
    if not f:
        return JsonResponse({'error': 'no file'}, status=400)

    mime = (f.content_type or '').lower()
    if mime.startswith('image/'):
        media_type = 'PHOTO'
        if f.size > 10 * 1024 * 1024:
            return JsonResponse({'error': 'Foto > 10MB non supportate'}, status=400)
    elif mime.startswith('video/'):
        media_type = 'VIDEO'
        if f.size > 50 * 1024 * 1024:
            return JsonResponse({'error': 'Video > 50MB non supportati'}, status=400)
    else:
        return JsonResponse({'error': 'tipo file non supportato'}, status=400)

    m = SessionMedia.objects.create(session=session, media_type=media_type, file=f)
    return JsonResponse({
        'media_id': m.id,
        'url': m.file.url,
        'type': media_type,
    })


# ---------------------------------------------------------------------------
# Coach: progressi page
# ---------------------------------------------------------------------------

def coach_client_progressi_view(request, client_id):
    coach = get_session_coach(request)
    if not coach or not can_manage_workouts(coach):
        return redirect('dashboard')

    client = get_object_or_404(ClientProfile, id=client_id)
    if not _can_coach_view_client(coach, client):
        return HttpResponseForbidden('Non autorizzato')

    active_assignment = WorkoutAssignment.objects.filter(
        client=client, coach=coach, status='ACTIVE'
    ).select_related('workout_plan').order_by('-start_date').first()

    last_session = WorkoutSession.objects.filter(client=client).order_by('-started_at').first()
    total_sessions = WorkoutSession.objects.filter(client=client, completed=True).count()

    # Build exercises list for filter dropdown
    exercises_in_program = []
    if active_assignment:
        for ex in WorkoutExercise.objects.filter(
            workout_day__workout_plan=active_assignment.workout_plan
        ).select_related('exercise').distinct().order_by('exercise__name'):
            if ex.exercise.id not in [e['exercise_id'] for e in exercises_in_program]:
                exercises_in_program.append({
                    'workout_exercise_id': ex.id,
                    'exercise_id': ex.exercise.id,
                    'name': ex.exercise.name,
                })

    return render(request, 'pages/clienti/progressi.html', {
        'client': client,
        'coach': coach,
        'active_assignment': active_assignment,
        'last_session': last_session,
        'total_sessions': total_sessions,
        'exercises_in_program_json': json.dumps(exercises_in_program),
    })


# ---------------------------------------------------------------------------
# Coach: progressi APIs
# ---------------------------------------------------------------------------

def _check_coach_access(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return None, JsonResponse({'error': 'forbidden'}, status=403)
    try:
        client = ClientProfile.objects.get(id=client_id)
    except ClientProfile.DoesNotExist:
        return None, JsonResponse({'error': 'not found'}, status=404)
    if not _can_coach_view_client(coach, client):
        return None, JsonResponse({'error': 'forbidden'}, status=403)
    return (coach, client), None


def api_progress_loads(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    we_id = request.GET.get('workout_exercise_id') or request.GET.get('exercise_id')
    range_param = request.GET.get('range', 'all')

    qs = WorkoutSetLog.objects.filter(session__client=client, completed=True)
    if we_id:
        qs = qs.filter(workout_exercise_id=we_id)

    today = timezone.now().date()
    if range_param == 'week':
        qs = qs.filter(session__started_at__date__gte=today - timedelta(days=7))
    elif range_param == 'month':
        qs = qs.filter(session__started_at__date__gte=today - timedelta(days=30))
    elif range_param == '3months':
        qs = qs.filter(session__started_at__date__gte=today - timedelta(days=90))

    by_date = {}
    for sl in qs.select_related('session'):
        d = sl.session.started_at.date()
        key = d.isoformat()
        if key not in by_date:
            by_date[key] = {'date': key, 'loads': [], 'reps': [], 'rpes': []}
        if sl.load_used is not None:
            by_date[key]['loads'].append(float(sl.load_used))
        if sl.reps_done is not None:
            by_date[key]['reps'].append(sl.reps_done)
        if sl.rpe is not None:
            by_date[key]['rpes'].append(sl.rpe)

    series = []
    for k in sorted(by_date.keys()):
        v = by_date[k]
        series.append({
            'date': k,
            'load_max': max(v['loads']) if v['loads'] else None,
            'reps_avg': round(sum(v['reps']) / len(v['reps']), 1) if v['reps'] else None,
            'rpe_avg': round(sum(v['rpes']) / len(v['rpes']), 1) if v['rpes'] else None,
        })

    progress_4w = None
    if series and we_id:
        cutoff = (today - timedelta(weeks=4)).isoformat()
        recent = [s['load_max'] for s in series if s['date'] >= cutoff and s['load_max'] is not None]
        before = [s['load_max'] for s in series if s['date'] < cutoff and s['load_max'] is not None]
        if recent and before:
            progress_4w = round(max(recent) - max(before), 1)

    return JsonResponse({
        'series': series,
        'progress_4w': progress_4w,
    })


def api_progress_volume(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    today = timezone.now().date()
    date_from = today - timedelta(weeks=12)
    sets = WorkoutSetLog.objects.filter(
        session__client=client, completed=True,
        session__started_at__date__gte=date_from,
    ).select_related('session', 'workout_exercise__exercise')

    weekly = {}
    for sl in sets:
        d = sl.session.started_at.date()
        # Monday of week
        monday = d - timedelta(days=d.weekday())
        wkey = monday.isoformat()
        muscles_p = normalize_muscles(sl.workout_exercise.exercise.target_muscles)
        muscles_s = normalize_muscles(sl.workout_exercise.exercise.secondary_muscles)
        reps = sl.reps_done or 0
        for m in muscles_p:
            weekly.setdefault(wkey, {}).setdefault(m, 0)
            weekly[wkey][m] += reps
        for m in muscles_s:
            weekly.setdefault(wkey, {}).setdefault(m, 0)
            weekly[wkey][m] += reps * 0.5

    weeks = sorted(weekly.keys())
    muscles_set = set()
    for w, mm in weekly.items():
        muscles_set.update(mm.keys())
    muscles_list = sorted(muscles_set)

    series = {m: [round(weekly.get(w, {}).get(m, 0), 1) for w in weeks] for m in muscles_list}

    return JsonResponse({
        'weeks': weeks,
        'muscles': muscles_list,
        'series': series,
    })


def api_progress_adherence(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    today = timezone.now().date()
    date_from = today - timedelta(weeks=12)

    sessions = WorkoutSession.objects.filter(
        client=client, completed=True,
        started_at__date__gte=date_from,
    ).select_related('assignment__workout_plan')

    # Group sessions by ISO week
    weekly_done = {}
    for s in sessions:
        d = s.started_at.date()
        monday = d - timedelta(days=d.weekday())
        wkey = monday.isoformat()
        weekly_done[wkey] = weekly_done.get(wkey, 0) + 1

    # Compute scheduled per week: from active assignments' frequency_per_week
    weekly_planned = {}
    for assn in WorkoutAssignment.objects.filter(client=client).select_related('workout_plan'):
        freq = assn.workout_plan.frequency_per_week or assn.workout_plan.days.count() or 0
        if not freq:
            continue
        start = assn.start_date or assn.created_at.date()
        end = assn.end_date or today
        d = start
        while d <= end and d <= today:
            monday = d - timedelta(days=d.weekday())
            wkey = monday.isoformat()
            if wkey not in weekly_planned:
                weekly_planned[wkey] = freq
            d += timedelta(days=7)

    weeks = sorted(set(list(weekly_done.keys()) + list(weekly_planned.keys())))
    weeks = [w for w in weeks if w >= date_from.isoformat()]

    series = []
    total_planned = 0
    total_done = 0
    for w in weeks:
        planned = weekly_planned.get(w, 0)
        done = weekly_done.get(w, 0)
        pct = round((done / planned) * 100, 1) if planned else (100.0 if done else 0.0)
        series.append({'week': w, 'planned': planned, 'done': done, 'pct': pct})
        total_planned += planned
        total_done += done

    overall_pct = round((total_done / total_planned) * 100, 1) if total_planned else None

    return JsonResponse({'series': series, 'overall_pct': overall_pct})


def api_progress_rpe(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    today = timezone.now().date()
    date_from = today - timedelta(weeks=12)
    sessions = WorkoutSession.objects.filter(
        client=client, completed=True,
        started_at__date__gte=date_from,
        avg_rpe__isnull=False,
    )
    weekly = {}
    for s in sessions:
        d = s.started_at.date()
        monday = d - timedelta(days=d.weekday())
        wkey = monday.isoformat()
        weekly.setdefault(wkey, []).append(s.avg_rpe)

    series = []
    for w in sorted(weekly.keys()):
        rpes = weekly[w]
        series.append({'week': w, 'avg_rpe': round(sum(rpes) / len(rpes), 1)})
    return JsonResponse({'series': series})


def api_progress_kpi(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    sessions = WorkoutSession.objects.filter(client=client, completed=True)
    total = sessions.count()
    avg_volume = (WorkoutSetLog.objects.filter(session__client=client, completed=True)
                  .aggregate(total=Count('id'))['total'] or 0)
    per_session = round(avg_volume / total, 1) if total else 0

    # Streak: consecutive days backwards from today
    streak = 0
    d = timezone.now().date()
    while sessions.filter(started_at__date=d).exists():
        streak += 1
        d -= timedelta(days=1)

    # Adherence overall
    adher = api_progress_adherence(request, client_id)
    adher_data = json.loads(adher.content) if hasattr(adher, 'content') else {}
    overall_pct = adher_data.get('overall_pct')

    return JsonResponse({
        'total_sessions': total,
        'avg_sets_per_session': per_session,
        'streak_days': streak,
        'overall_adherence_pct': overall_pct,
    })


def api_progress_sessions(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res

    sessions = WorkoutSession.objects.filter(client=client).select_related(
        'workout_day', 'assignment__workout_plan',
    ).order_by('-started_at')[:100]
    data = [{
        'id': s.id,
        'date': s.started_at.isoformat(),
        'plan_title': s.assignment.workout_plan.title,
        'day_name': s.workout_day.day_name or f'Giorno {s.workout_day.day_order}',
        'duration_minutes': s.duration_minutes,
        'avg_rpe': s.avg_rpe,
        'completed': s.completed,
        'interrupted': s.interrupted,
        'notes': (s.notes or '')[:120],
        'sets_completed': s.set_logs.filter(completed=True).count(),
        'sets_total': WorkoutExercise.objects.filter(workout_day=s.workout_day).aggregate(
            t=Sum('set_count'))['t'] or 0,
    } for s in sessions]
    return JsonResponse(data, safe=False)


def api_session_detail(request, session_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'forbidden'}, status=403)
    session = get_object_or_404(WorkoutSession, id=session_id)
    # Authorize: client owner OR coach of relationship
    if user.role == 'CLIENT':
        client = get_session_client(request)
        if session.client != client:
            return JsonResponse({'error': 'forbidden'}, status=403)
    elif user.role == 'COACH':
        coach = get_session_coach(request)
        if not _can_coach_view_client(coach, session.client):
            return JsonResponse({'error': 'forbidden'}, status=403)
    else:
        return JsonResponse({'error': 'forbidden'}, status=403)

    return JsonResponse(_serialize_session_full(session))


@csrf_exempt
def api_session_coach_note(request, session_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'forbidden'}, status=403)
    session = get_object_or_404(WorkoutSession, id=session_id)
    if not _can_coach_view_client(coach, session.client):
        return JsonResponse({'error': 'forbidden'}, status=403)

    try:
        data = json.loads(request.body)
        text = (data.get('text') or '').strip()
    except Exception:
        return JsonResponse({'error': 'invalid json'}, status=400)
    if not text:
        return JsonResponse({'error': 'testo vuoto'}, status=400)

    note = SessionCoachNote.objects.create(session=session, coach=coach, text=text)
    Notification.objects.create(
        target_user=session.client.user,
        notification_type='COACH_FEEDBACK',
        title='Nota dal tuo coach',
        body=text[:200],
        link_url=f'/allenamenti/assegnazione/{session.assignment.id}/dettagli/',
    )
    return JsonResponse({
        'id': note.id,
        'text': note.text,
        'created_at': note.created_at.isoformat(),
        'coach_name': f"{coach.first_name} {coach.last_name}",
    })


def api_progress_media_gallery(request, client_id):
    res, err = _check_coach_access(request, client_id)
    if err:
        return err
    coach, client = res
    media = SessionMedia.objects.filter(session__client=client).select_related(
        'session__workout_day'
    ).order_by('-uploaded_at')[:200]
    data = [{
        'id': m.id,
        'session_id': m.session.id,
        'url': m.file.url,
        'type': m.media_type,
        'uploaded_at': m.uploaded_at.isoformat(),
        'day_name': m.session.workout_day.day_name or f'Giorno {m.session.workout_day.day_order}',
        'coach_comment': m.coach_comment or '',
    } for m in media]
    return JsonResponse(data, safe=False)


@csrf_exempt
def api_media_comment(request, media_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'forbidden'}, status=403)
    m = get_object_or_404(SessionMedia, id=media_id)
    if not _can_coach_view_client(coach, m.session.client):
        return JsonResponse({'error': 'forbidden'}, status=403)
    try:
        data = json.loads(request.body)
        m.coach_comment = data.get('comment', '')
        m.save()
        return JsonResponse({'success': True, 'comment': m.coach_comment})
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=400)
