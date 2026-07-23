"""Aggregazioni training per il recap: wrapper sottile sui KPI già calcolati
in config/views_session.py (adherence, RPE, volume — 12 settimane rolling,
finestra NON reinventata qui, vedi §3 del piano). L'unica logica nuova è la
compliance esercizi (saltati/sostituiti), letta da dati già espliciti
(session.overrides, WorkoutSetLog.exercise_substituted) — nessuna inferenza.
"""

MIN_RELIABLE_SESSIONS = 4


def compute_training(client):
    # Import lazy: config/views_session.py è layer HTTP, domain non dovrebbe
    # dipenderne a import-time (rischio di ordine di caricamento app Django).
    from config.views_session import _progress_adherence_data, _progress_rpe_data, _progress_volume_data

    adherence = _progress_adherence_data(client)
    total_sessions = sum(w['done'] for w in adherence['series'])
    adherence['reliable'] = adherence['overall_pct'] is not None and total_sessions >= MIN_RELIABLE_SESSIONS

    return {
        'adherence': adherence,
        'rpe': _progress_rpe_data(client),
        'volume': _progress_volume_data(client),
        'exercise_compliance': compute_exercise_compliance(client),
        'top_exercise_load': compute_top_exercise_load_trend(client),
        'sleep_signal': compute_recent_sleep_signal(client),
    }


def compute_recent_sleep_signal(client, lookback=3):
    """Ultimo self-report 'qualità del sonno' (1-5, check preset) + direzione
    sugli ultimi `lookback` check che lo contengono. SOLO qualificatore
    testuale per l'insight overreaching — mai un input numerico del forecast
    o della confidence (§3/§5 del piano: il self-report resta soggettivo)."""
    from domain.checks.models import QuestionnaireResponse

    responses = (
        QuestionnaireResponse.objects
        .filter(client=client, answers_json__has_key='benessere_sonno')
        .order_by('-submitted_at')[:lookback]
    )
    values = []
    for r in responses:
        try:
            v = float(r.answers_json.get('benessere_sonno'))
        except (TypeError, ValueError):
            continue
        values.append(v)
    if not values:
        return {'available': False, 'latest': None, 'trend': None}

    latest = values[0]
    trend = None
    if len(values) >= 2:
        # values è dal più recente al più vecchio: delta = recente - vecchio.
        delta = values[0] - values[-1]
        if delta <= -0.5:
            trend = 'declining'
        elif delta >= 0.5:
            trend = 'improving'
        else:
            trend = 'stable'
    return {'available': True, 'latest': latest, 'trend': trend}


def compute_top_exercise_load_trend(client, weeks=8, min_sessions=6):
    """Trend di carico (top_set per sessione) sull'esercizio più allenato
    nelle ultime `weeks` settimane — usato dalla regola plateau per un
    segnale più preciso del solo volume totale (§V2: "promuovere a metrica
    carico dedicata se il volume da solo risulta un proxy troppo grezzo",
    vedi ponytail in insights.py). Riusa build_exercise_trend_by_name, già
    esistente per la pagina progressi — nessuna query di trend duplicata."""
    from django.utils import timezone
    from datetime import timedelta
    from django.db.models import Count
    from django.db.models.functions import Coalesce
    from domain.workouts.models import WorkoutSetLog
    from config.views_session import build_exercise_trend_by_name

    since = timezone.now() - timedelta(weeks=weeks)
    top = (
        WorkoutSetLog.objects
        .annotate(done_name=Coalesce('actual_exercise__name', 'workout_exercise__exercise__name'))
        .filter(session__client=client, completed=True, session__started_at__gte=since,
                done_name__isnull=False)
        .exclude(set_number=0)
        .values('done_name')
        .annotate(n=Count('id'))
        .order_by('-n')
        .first()
    )
    if not top:
        return {'available': False, 'name': None, 'sessions': []}

    trend = build_exercise_trend_by_name(top['done_name'], client)
    sessions = [s for s in trend['sessions'] if s.get('top_set') is not None]
    if len(sessions) < min_sessions:
        return {'available': False, 'name': top['done_name'], 'sessions': sessions}

    return {'available': True, 'name': top['done_name'], 'sessions': sessions}


def compute_exercise_compliance(client, lookback_sessions=6, min_occurrences=3):
    """Esercizi rimossi/sostituiti di fatto rispetto al programma, sulle
    ultime `lookback_sessions` sessioni completate. Nessuna inferenza: legge
    solo session.overrides e i WorkoutSetLog effettivamente registrati."""
    from domain.workouts.models import WorkoutSession, WorkoutSetLog, WorkoutExercise

    sessions = list(
        WorkoutSession.objects.filter(client=client, completed=True)
        .order_by('-started_at')[:lookback_sessions]
    )
    if not sessions:
        return {'available': False, 'sessions_considered': 0, 'dropped': [], 'substituted': []}

    day_ids = {s.workout_day_id for s in sessions}
    plan_exercises = {
        we.id: we for we in
        WorkoutExercise.objects.filter(workout_day_id__in=day_ids).select_related('exercise')
    }

    missing_counts, substituted_counts = {}, {}
    for s in sessions:
        overrides = s.overrides or {}
        removed_ids = {int(x) for x in (overrides.get('removed') or [])}
        substituted_ids = {int(k) for k in (overrides.get('substituted') or {}).keys()}
        session_exercise_ids = {we_id for we_id, we in plan_exercises.items()
                                 if we.workout_day_id == s.workout_day_id}
        logged_we_ids = set(
            WorkoutSetLog.objects.filter(session=s, completed=True,
                                          workout_exercise_id__in=session_exercise_ids)
            .values_list('workout_exercise_id', flat=True)
        )
        for we_id in session_exercise_ids:
            if we_id in substituted_ids:
                substituted_counts[we_id] = substituted_counts.get(we_id, 0) + 1
            elif we_id in removed_ids or we_id not in logged_we_ids:
                missing_counts[we_id] = missing_counts.get(we_id, 0) + 1

    def _entries(counts):
        out = [
            {'exercise_name': plan_exercises[we_id].exercise.name, 'count': count}
            for we_id, count in counts.items()
            if count >= min_occurrences and we_id in plan_exercises
        ]
        return sorted(out, key=lambda e: -e['count'])

    return {
        'available': True,
        'sessions_considered': len(sessions),
        'dropped': _entries(missing_counts),
        'substituted': _entries(substituted_counts),
    }
