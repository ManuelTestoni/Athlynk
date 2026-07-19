"""Assignment operations, as functions rather than HTTP handlers.

Assigning a plan is one thing the coach does, but the code for it lived inside
view bodies — once for the web app, again for the mobile API — and the copies
had already drifted (the mobile workout assign never set `end_date` or the
duration fields). CHIRON needs the same operation a third time, so it lives here
once instead.

Every function is transactional, re-resolves ownership itself, and returns the
created row. Notifications and e-mails are best-effort: a failed e-mail must not
roll back an assignment the athlete has already been notified about in-app.
"""

from __future__ import annotations

import logging
from datetime import date, timedelta

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)


class AssignmentError(Exception):
    """Refusal with a message meant for the coach."""


def _duration_end(start: date, value: int, unit: str) -> date:
    return start + timedelta(weeks=value) if unit == 'WEEKS' else start + timedelta(days=30 * value)


def _notify(client, notification_type: str, title: str, body: str, link_url: str) -> None:
    from domain.chat.models import Notification
    try:
        Notification.objects.create(
            target_user=client.user,
            notification_type=notification_type,
            title=title,
            body=body,
            link_url=link_url,
        )
    except Exception:
        logger.exception('assignment.notification_failed type=%s', notification_type)


# ---------------------------------------------------------------------------
# Workout plans
# ---------------------------------------------------------------------------

def assign_workout_plan(coach, plan, client, *, duration_value: int = 4,
                        duration_unit: str = 'WEEKS', overwrite: bool = True):
    """Give `client` an active assignment for `plan`.

    `overwrite` closes any other active plan, which is the behaviour every
    existing caller wanted: an athlete following two plans at once is a bug, not
    a feature.
    """
    from domain.workouts.models import WorkoutAssignment, WorkoutPlan

    if plan.coach_id != coach.id:
        raise AssignmentError('Questa scheda non è tua.')
    if not plan.days.filter(exercises__isnull=False).exists():
        raise AssignmentError('La scheda non contiene esercizi.')

    duration_unit = duration_unit if duration_unit in ('WEEKS', 'MONTHS') else 'WEEKS'
    duration_value = max(1, int(duration_value or 1))
    start = date.today()

    with transaction.atomic():
        if overwrite:
            WorkoutAssignment.objects.filter(
                client=client, coach=coach, status='ACTIVE',
            ).exclude(workout_plan=plan).update(status='COMPLETED', end_date=start)

        assignment = WorkoutAssignment.objects.create(
            workout_plan=plan, client=client, coach=coach, status='ACTIVE',
            start_date=start, end_date=_duration_end(start, duration_value, duration_unit),
            duration_value=duration_value, duration_unit=duration_unit,
        )
        plan.status = WorkoutPlan.STATUS_ACTIVE
        plan.save(update_fields=['status'])

    _notify(client, 'WORKOUT_ASSIGNED', 'Nuova scheda di allenamento',
            f'Ti è stata assegnata la scheda "{plan.title}".', '/allenamenti/')
    try:
        from django.conf import settings
        from config.services.email import send_workout_assigned
        send_workout_assigned(client, coach, plan, f'{settings.SITE_URL}/allenamenti/')
    except Exception:
        logger.exception('workout_assigned_email.failed plan_id=%s', plan.id)

    return assignment


# ---------------------------------------------------------------------------
# Nutrition plans
# ---------------------------------------------------------------------------

def assign_nutrition_plan(coach, plan, client, *, duration_value: int = 4,
                          duration_unit: str = 'WEEKS', notes: str | None = None):
    from domain.nutrition.models import NutritionAssignment

    if plan.coach_id != coach.id:
        raise AssignmentError('Questo piano non è tuo.')

    duration_unit = duration_unit if duration_unit in ('WEEKS', 'MONTHS') else 'WEEKS'
    duration_value = max(1, int(duration_value or 1))
    start = date.today()

    with transaction.atomic():
        NutritionAssignment.objects.filter(
            client=client, coach=coach, status='ACTIVE',
        ).update(status='CANCELLED')
        assignment = NutritionAssignment.objects.create(
            nutrition_plan=plan, client=client, coach=coach, status='ACTIVE',
            start_date=start, end_date=_duration_end(start, duration_value, duration_unit),
            duration_value=duration_value, duration_unit=duration_unit,
            notes=notes or None,
        )

    _notify(client, 'NUTRITION_ASSIGNED', 'Nuovo piano alimentare',
            f'Ti è stato assegnato il piano "{plan.title}".',
            f'/nutrizione/dettaglio/{assignment.id}/')
    try:
        from django.conf import settings
        from config.services.email import send_nutrition_assigned
        send_nutrition_assigned(
            client, coach, plan,
            f'{settings.SITE_URL}/nutrizione/dettaglio/{assignment.id}/')
    except Exception:
        logger.exception('nutrition_assigned_email.failed plan_id=%s', plan.id)

    return assignment


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def assign_check(coach, template, client, *, recurrence_type: str = 'once',
                 weekly_day: int | None = None, monthly_day: int | None = None,
                 duration_hours: int = 72, notes: str = ''):
    """Assign a questionnaire template, snapshotting its questions.

    The snapshot is what makes later template edits safe: a check already sent
    keeps the questions the athlete was actually asked.
    """
    from domain.checks.models import AssignedCheck

    if template.coach_id != coach.id:
        raise AssignmentError('Questo template di check non è tuo.')

    valid = dict(AssignedCheck.RECURRENCE_CHOICES)
    if recurrence_type not in valid:
        raise AssignmentError(
            f"Ricorrenza non valida. Ammesse: {', '.join(valid)}.")
    if recurrence_type == 'weekly' and weekly_day is None:
        raise AssignmentError('Per una ricorrenza settimanale serve il giorno della settimana.')
    if recurrence_type == 'monthly' and monthly_day is None:
        raise AssignmentError('Per una ricorrenza mensile serve il giorno del mese.')

    with transaction.atomic():
        assignment = AssignedCheck.objects.create(
            template=template,
            snapshot_config=template.questions_config,
            client=client,
            coach=coach,
            recurrence_type=recurrence_type,
            weekly_day=weekly_day if recurrence_type == 'weekly' else None,
            monthly_day=monthly_day if recurrence_type == 'monthly' else None,
            duration_hours=max(1, int(duration_hours or 72)),
            notes=notes or '',
        )
        if recurrence_type == 'once':
            _create_check_instance(assignment, timezone.localdate())

    _notify(client, 'CHECK_SUBMITTED', 'Nuovo check da compilare',
            f'{coach.first_name} ti ha assegnato un check.',
            '/check/i-miei-check/')
    return assignment


def _create_check_instance(assignment, due_date):
    from domain.checks.models import AssignedCheckInstance
    return AssignedCheckInstance.objects.create(
        assignment=assignment,
        due_date=due_date,
        expires_at=timezone.now() + timedelta(hours=assignment.duration_hours),
        status='pending',
        notified_at=timezone.now(),
    )


# ---------------------------------------------------------------------------
# Appointments
# ---------------------------------------------------------------------------

def create_appointment(coach, client, *, title: str, start_datetime,
                       appointment_type: str = 'consulenza',
                       duration_minutes: int = 60,
                       description: str = '', meeting_url: str = ''):
    from domain.calendar.models import Appointment

    title = (title or '').strip()
    if not title:
        raise AssignmentError("Serve un titolo per l'appuntamento.")
    if not start_datetime:
        raise AssignmentError("Serve data e ora dell'appuntamento.")
    if timezone.is_naive(start_datetime):
        start_datetime = timezone.make_aware(start_datetime)

    appointment = Appointment.objects.create(
        coach=coach,
        client=client,
        title=title[:200],
        appointment_type=appointment_type or 'consulenza',
        start_datetime=start_datetime,
        duration_minutes=max(1, int(duration_minutes or 60)),
        description=description or '',
        meeting_url=meeting_url if appointment_type == 'consulenza' else '',
        status='SCHEDULED',
    )

    when = timezone.localtime(start_datetime).strftime('%-d/%m alle %H:%M')
    _notify(client, 'APPOINTMENT_ACCEPTED', 'Nuovo appuntamento',
            f'{coach.first_name} ha fissato «{title}» per il {when}.', '/agenda/')
    return appointment
