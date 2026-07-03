"""API endpoints for the workouts redesign foundation:

- Workout folders (per coach)
- Sport catalog (system + custom)
- Muscle groups (system)
- Custom exercises (per coach)
- Plan volume aggregator (per muscle group, per week)

All endpoints follow the existing session-based auth pattern and return JSON
suitable for both web (Alpine.js) and future mobile (Swift / Flutter) clients.
"""

from __future__ import annotations

from urllib.parse import urlsplit

from django.db import transaction
from django.db.models import Count, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.utils.text import slugify

from domain.workouts.models import (
    Exercise, MuscleGroup, Sport, WorkoutExercise,
    WorkoutFolder, WorkoutPlan,
)

from .http_utils import parse_json_body, require_coach, serialize_folder
from .session_utils import can_manage_workouts, get_session_user


# Allowed label color tokens (mapped in CSS — see pickers.css / charts.js)
ALLOWED_LABEL_COLORS = {
    'bronze', 'aegean', 'amber', 'emerald', 'rose',
    'violet', 'slate', 'sand', 'crimson', 'teal',
}

# Difficulty picklist — must match the <select> in wizard.html / _import_review.html
ALLOWED_DIFFICULTY = {'Principiante', 'Intermedio', 'Avanzato', 'Agonista'}


def _safe_http_url(raw, max_length=500):
    """Return a trimmed http(s) URL, or '' for anything else.

    Blocks javascript:/data:/file: and other schemes that HTML-escaping does
    not defang when the value lands in an href.
    """
    if not isinstance(raw, str):
        return ''
    url = raw.strip()[:max_length]
    if not url:
        return ''
    try:
        scheme = urlsplit(url).scheme.lower()
    except ValueError:
        return ''
    return url if scheme in ('http', 'https') else ''


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _require_coach(request):
    return require_coach(request, can_manage_workouts)


def _serialize_folder(folder, plan_count=None):
    count = plan_count if plan_count is not None else folder.plans.count()
    return serialize_folder(folder, 'plan_count', count)


def _serialize_sport(sport):
    return {
        'id': sport.id,
        'slug': sport.slug,
        'name': sport.name,
        'icon': sport.icon or '',
        'category': sport.category,
        'is_system': sport.is_system,
    }


def _serialize_muscle(m):
    return {
        'id': m.id,
        'slug': m.slug,
        'name': m.name,
        'region': m.region,
        'color_token': m.color_token,
    }


def _serialize_exercise_full(ex):
    return {
        'id': ex.id,
        'name': ex.name,
        'video_url': ex.video_url or '',
        'cover_image': ex.cover_image.url if ex.cover_image else '',
        'is_custom': ex.is_custom,
        'sports': [_serialize_sport(s) for s in ex.sports.all()],
        'primary_muscles': [_serialize_muscle(m) for m in ex.primary_muscles.all()],
        'secondary_muscles': [_serialize_muscle(m) for m in ex.secondary_muscles.all()],
        'equipment': ex.equipment or '',
        'difficulty_level': ex.difficulty_level or '',
        'coach_notes': ex.coach_notes or '',
        # legacy text (kept for backward compat)
        'target_muscle_group': ex.target_muscle_group or '',
        'primary_muscle': ex.primary_muscle or '',
        'secondary_muscle': ex.secondary_muscle or '',
    }


def _parse_body(request):
    return parse_json_body(request)


# ---------------------------------------------------------------------------
# Folders
# ---------------------------------------------------------------------------

def api_folders(request):
    coach, err = _require_coach(request)
    if err:
        return err

    if request.method == 'GET':
        folders = WorkoutFolder.objects.filter(coach=coach).annotate(_count=Count('plans'))
        return JsonResponse(
            [_serialize_folder(f, plan_count=f._count) for f in folders],
            safe=False,
        )

    if request.method == 'POST':
        data, perr = _parse_body(request)
        if perr:
            return perr
        title = (data.get('title') or '').strip()
        if not title:
            return JsonResponse({'error': 'Titolo richiesto.'}, status=400)
        if WorkoutFolder.objects.filter(coach=coach, title__iexact=title).exists():
            return JsonResponse({'error': 'Hai già una cartella con questo nome.'}, status=400)
        label_text = (data.get('label_text') or '').strip()[:40]
        label_color = (data.get('label_color') or '').strip().lower()
        if label_color and label_color not in ALLOWED_LABEL_COLORS:
            label_color = ''
        order = WorkoutFolder.objects.filter(coach=coach).count() + 1
        folder = WorkoutFolder.objects.create(
            coach=coach, title=title,
            label_text=label_text, label_color=label_color, order=order,
        )
        return JsonResponse(_serialize_folder(folder, plan_count=0), status=201)

    return JsonResponse({'error': 'method not allowed'}, status=405)


def api_folder_detail(request, folder_id):
    coach, err = _require_coach(request)
    if err:
        return err
    folder = get_object_or_404(WorkoutFolder, id=folder_id, coach=coach)

    if request.method == 'GET':
        return JsonResponse(_serialize_folder(folder))

    if request.method == 'PATCH':
        data, perr = _parse_body(request)
        if perr:
            return perr
        if 'title' in data:
            title = (data.get('title') or '').strip()
            if not title:
                return JsonResponse({'error': 'Titolo richiesto.'}, status=400)
            if WorkoutFolder.objects.filter(coach=coach, title__iexact=title).exclude(id=folder.id).exists():
                return JsonResponse({'error': 'Hai già una cartella con questo nome.'}, status=400)
            folder.title = title
        if 'label_text' in data:
            folder.label_text = (data.get('label_text') or '').strip()[:40]
        if 'label_color' in data:
            color = (data.get('label_color') or '').strip().lower()
            folder.label_color = color if color in ALLOWED_LABEL_COLORS or color == '' else folder.label_color
        if 'order' in data:
            try:
                folder.order = max(0, int(data.get('order')))
            except (TypeError, ValueError):
                pass
        folder.save()
        return JsonResponse(_serialize_folder(folder))

    if request.method == 'DELETE':
        action = request.GET.get('action', 'move_to_unfiled')
        target_id = request.GET.get('target_folder_id')

        if action == 'move_to_unfiled':
            folder.plans.update(folder=None)
        elif action == 'move_to':
            if not target_id:
                return JsonResponse({'error': 'target_folder_id richiesto.'}, status=400)
            try:
                target = WorkoutFolder.objects.get(id=int(target_id), coach=coach)
            except (WorkoutFolder.DoesNotExist, ValueError, TypeError):
                return JsonResponse({'error': 'Cartella di destinazione non trovata.'}, status=404)
            if target.id == folder.id:
                return JsonResponse({'error': 'Cartella di destinazione coincide.'}, status=400)
            folder.plans.update(folder=target)
        elif action == 'delete_plans':
            folder.plans.all().delete()
        else:
            return JsonResponse({'error': 'azione non valida.'}, status=400)

        folder.delete()
        return JsonResponse({'status': 'ok'})

    return JsonResponse({'error': 'method not allowed'}, status=405)


def api_folders_reorder(request):
    """POST {ids: [...]} → persiste l'ordine manuale delle cartelle del coach."""
    coach, err = _require_coach(request)
    if err:
        return err
    if request.method != 'POST':
        return JsonResponse({'error': 'method not allowed'}, status=405)
    data, perr = _parse_body(request)
    if perr:
        return perr
    ids = data.get('ids')
    if not isinstance(ids, list) or not ids:
        return JsonResponse({'error': 'ids richiesto.'}, status=400)
    folders = {f.id: f for f in WorkoutFolder.objects.filter(coach=coach, id__in=ids)}
    for idx, fid in enumerate(ids):
        folder = folders.get(fid)
        if folder and folder.order != idx + 1:
            folder.order = idx + 1
            folder.save(update_fields=['order', 'updated_at'])
    return JsonResponse({'status': 'ok'})


# ---------------------------------------------------------------------------
# Sports
# ---------------------------------------------------------------------------

def api_sports(request):
    coach, err = _require_coach(request)
    if err:
        return err

    if request.method == 'GET':
        sports = Sport.objects.filter(Q(is_system=True) | Q(created_by=coach)).order_by('order', 'name')
        return JsonResponse([_serialize_sport(s) for s in sports], safe=False)

    if request.method == 'POST':
        data, perr = _parse_body(request)
        if perr:
            return perr
        name = (data.get('name') or '').strip()
        if not name or len(name) < 2:
            return JsonResponse({'error': 'Nome sport richiesto (min 2 caratteri).'}, status=400)
        slug = slugify(name)[:80]
        if Sport.objects.filter(slug=slug).exists():
            return JsonResponse({'error': 'Esiste già uno sport con questo nome.'}, status=400)
        sport = Sport.objects.create(
            name=name, slug=slug,
            icon=(data.get('icon') or '').strip()[:60],
            category=(data.get('category') or 'OTHER'),
            is_system=False, created_by=coach,
            order=999,
        )
        return JsonResponse(_serialize_sport(sport), status=201)

    return JsonResponse({'error': 'method not allowed'}, status=405)


# ---------------------------------------------------------------------------
# Muscle groups
# ---------------------------------------------------------------------------

def api_muscle_groups(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)
    muscles = MuscleGroup.objects.all().order_by('region', 'order', 'name')
    return JsonResponse([_serialize_muscle(m) for m in muscles], safe=False)


# ---------------------------------------------------------------------------
# Custom exercises
# ---------------------------------------------------------------------------

def _exercise_payload_apply(ex, data, coach):
    name = (data.get('name') or '').strip()
    if name:
        ex.name = name[:200]
    if not ex.slug:
        # build a unique slug
        base = slugify(ex.name)[:200] or 'custom-exercise'
        candidate = f"{base}-c{coach.id}"
        suffix = 1
        while Exercise.objects.filter(slug=candidate).exclude(pk=ex.pk).exists():
            suffix += 1
            candidate = f"{base}-c{coach.id}-{suffix}"
        ex.slug = candidate[:220]

    # Free-text fields: trim + cap to the DB column length. Output is rendered
    # through Django auto-escaping, but length caps still prevent abuse.
    text_caps = {'equipment': 100, 'coach_notes': 5000}
    for fld, cap in text_caps.items():
        if fld in data:
            value = data.get(fld)
            value = value.strip()[:cap] if isinstance(value, str) else ''
            setattr(ex, fld, value)

    # difficulty_level is a fixed picklist on the UI — reject anything else.
    if 'difficulty_level' in data:
        diff = (data.get('difficulty_level') or '').strip()
        ex.difficulty_level = diff if diff in ALLOWED_DIFFICULTY else ''

    # video_url: only http(s). HTML-escaping does NOT neutralise a javascript:
    # href, so the scheme must be validated here before it reaches an <a href>.
    if 'video_url' in data:
        ex.video_url = _safe_http_url(data.get('video_url'))

    if 'cover_image' in data and not data.get('cover_image'):
        ex.cover_image = None
    ex.save()

    if 'sport_ids' in data:
        ids = [int(x) for x in (data.get('sport_ids') or []) if str(x).isdigit()]
        ex.sports.set(Sport.objects.filter(id__in=ids))
    if 'primary_muscle_ids' in data:
        ids = [int(x) for x in (data.get('primary_muscle_ids') or []) if str(x).isdigit()]
        ex.primary_muscles.set(MuscleGroup.objects.filter(id__in=ids))
    if 'secondary_muscle_ids' in data:
        ids = [int(x) for x in (data.get('secondary_muscle_ids') or []) if str(x).isdigit()]
        ex.secondary_muscles.set(MuscleGroup.objects.filter(id__in=ids))


def api_custom_exercises(request):
    coach, err = _require_coach(request)
    if err:
        return err

    if request.method == 'GET':
        qs = (
            Exercise.objects.filter(is_custom=True, created_by=coach)
            .prefetch_related('sports', 'primary_muscles', 'secondary_muscles')
            .order_by('name')
        )
        return JsonResponse([_serialize_exercise_full(e) for e in qs], safe=False)

    if request.method == 'POST':
        data, perr = _parse_body(request)
        if perr:
            return perr
        name = (data.get('name') or '').strip()
        if len(name) < 3:
            return JsonResponse({'error': 'Nome esercizio: minimo 3 caratteri.'}, status=400)
        primary_ids = data.get('primary_muscle_ids') or []
        if not primary_ids:
            return JsonResponse({'error': 'Seleziona almeno un muscolo primario.'}, status=400)
        sport_ids = data.get('sport_ids') or []
        if not sport_ids:
            return JsonResponse({'error': 'Seleziona almeno uno sport.'}, status=400)

        with transaction.atomic():
            ex = Exercise(is_custom=True, created_by=coach)
            ex.name = name
            ex.slug = ''  # filled in _exercise_payload_apply
            _exercise_payload_apply(ex, data, coach)
        return JsonResponse(_serialize_exercise_full(ex), status=201)

    return JsonResponse({'error': 'method not allowed'}, status=405)


def api_custom_exercise_detail(request, exercise_id):
    coach, err = _require_coach(request)
    if err:
        return err
    ex = get_object_or_404(Exercise, id=exercise_id, is_custom=True, created_by=coach)

    if request.method == 'GET':
        return JsonResponse(_serialize_exercise_full(ex))

    if request.method == 'PATCH':
        data, perr = _parse_body(request)
        if perr:
            return perr
        with transaction.atomic():
            _exercise_payload_apply(ex, data, coach)
        return JsonResponse(_serialize_exercise_full(ex))

    if request.method == 'DELETE':
        in_use = WorkoutExercise.objects.filter(exercise=ex).exists()
        if in_use:
            return JsonResponse(
                {'error': 'Esercizio in uso in una o più schede; non puoi eliminarlo.'},
                status=409,
            )
        ex.delete()
        return JsonResponse({'status': 'ok'})

    return JsonResponse({'error': 'method not allowed'}, status=405)


# ---------------------------------------------------------------------------
# Volume aggregator
# ---------------------------------------------------------------------------

def api_plan_volume(request, plan_id):
    """Return per-muscle-group, per-week volume for a plan.

    Volume metric: sum(set_count * reps), primary muscles count × 1.0,
    secondary muscles count × 0.5.

    Query params:
        weeks=1,2     comma-separated week numbers (default: all)
        groups=chest,back  comma-separated muscle slugs (default: all)
    """
    coach, err = _require_coach(request)
    if err:
        return err
    plan = get_object_or_404(WorkoutPlan, id=plan_id, coach=coach)

    duration = max(1, plan.duration_weeks or 1)
    weeks_param = request.GET.get('weeks', '').strip()
    if weeks_param:
        try:
            weeks = sorted({int(w) for w in weeks_param.split(',') if w.strip().isdigit()})
            weeks = [w for w in weeks if 1 <= w <= duration]
        except ValueError:
            weeks = list(range(1, duration + 1))
    else:
        weeks = list(range(1, duration + 1))
    if not weeks:
        weeks = [1]

    groups_param = request.GET.get('groups', '').strip()
    groups_filter = [g for g in groups_param.split(',') if g] if groups_param else None

    # Pull all exercises + their muscle relations in two queries
    exercises = (
        WorkoutExercise.objects
        .filter(workout_day__workout_plan=plan)
        .select_related('exercise')
        .prefetch_related(
            'exercise__primary_muscles',
            'exercise__secondary_muscles',
            'weekly_values',
        )
    )

    # init structure: { (slug, week) : {primary_sets, secondary_sets} }
    by_group: dict[tuple[str, int], dict[str, float]] = {}
    muscle_meta: dict[str, MuscleGroup] = {}

    for we in exercises:
        base_sets = we.set_count or 0

        # weekly_values overrides — by week_number
        weekly_overrides = {wv.week_number: wv for wv in we.weekly_values.all()}

        for w in weeks:
            ov = weekly_overrides.get(w)
            sets = ov.set_count if ov and ov.set_count is not None else base_sets
            if not sets:
                continue

            for m in we.exercise.primary_muscles.all():
                if groups_filter and m.slug not in groups_filter:
                    continue
                key = (m.slug, w)
                bucket = by_group.setdefault(key, {'primary_sets': 0.0, 'secondary_sets': 0.0})
                bucket['primary_sets'] += sets
                muscle_meta[m.slug] = m

            for m in we.exercise.secondary_muscles.all():
                if groups_filter and m.slug not in groups_filter:
                    continue
                key = (m.slug, w)
                bucket = by_group.setdefault(key, {'primary_sets': 0.0, 'secondary_sets': 0.0})
                bucket['secondary_sets'] += sets * 0.5
                muscle_meta.setdefault(m.slug, m)

    # Reshape into response
    muscle_payload = []
    for slug in sorted(muscle_meta.keys(), key=lambda s: (muscle_meta[s].region, muscle_meta[s].order)):
        m = muscle_meta[slug]
        per_week = [
            {
                'week': w,
                'primary_sets': by_group.get((slug, w), {}).get('primary_sets', 0),
                'secondary_sets': by_group.get((slug, w), {}).get('secondary_sets', 0),
            }
            for w in weeks
        ]
        muscle_payload.append({
            'slug': m.slug,
            'name': m.name,
            'region': m.region,
            'color_token': m.color_token,
            'per_week': per_week,
        })

    totals = []
    for w in weeks:
        s = 0
        for slug in muscle_meta:
            bucket = by_group.get((slug, w), {})
            s += bucket.get('primary_sets', 0) + bucket.get('secondary_sets', 0)
        totals.append({'week': w, 'sets': s})

    return JsonResponse({
        'plan_id': plan.id,
        'plan_kind': plan.plan_kind,
        'duration_weeks': duration,
        'weeks': weeks,
        'muscle_groups': muscle_payload,
        'total_per_week': totals,
    })
