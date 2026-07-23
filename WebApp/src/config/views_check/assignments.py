"""Assegnazione check agli atleti: API, generazione istanze ricorrenti,
notifiche e export ICS."""

from django.shortcuts import render, redirect
from django.http import JsonResponse, HttpResponse
from django.core.paginator import Paginator
from django.utils import timezone
from django.db.models import Q, Count, OuterRef, Subquery, JSONField
from django.core.files.storage import default_storage
from django.utils.dateparse import parse_datetime
from django.core.mail import send_mail
from django.conf import settings
import json
from datetime import timedelta

from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto, AssignedCheck, AssignedCheckInstance, QuestionAttachment, CheckFolder
from domain.checks.preset_templates import PRESETS, build_template_payload
from domain.checks.anthropometry import (
    circ_label, skin_label, order_circ_keys, order_skin_keys, catalog_json,
    circ_pad, skin_pad, WEIGHT_PAD,
)
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from ..services.images import to_webp, is_image
from ..services import cachekeys

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment  # type: ignore[no-redef]

from ..session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship
from ..http_utils import safe_int



def api_check_search(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    q = request.GET.get('q', '').strip()
    tab = request.GET.get('tab', 'da_revisionare')
    page = max(1, safe_int(request.GET, 'page', 1))
    per_page = safe_int(request.GET, 'per_page', 10)
    if per_page not in [10, 20]:
        per_page = 10

    responses_qs = (
        QuestionnaireResponse.objects.filter(coach=coach)
        .select_related('client')
        .only('id', 'submitted_at', 'weight_kg', 'status',
              'client__id', 'client__first_name', 'client__last_name')
        .order_by('-submitted_at')
    )

    if q:
        responses_qs = responses_qs.filter(
            Q(client__first_name__icontains=q) | Q(client__last_name__icontains=q)
        )

    if tab == 'da_revisionare':
        responses_qs = responses_qs.filter(status='COMPLETED')

    paginator = Paginator(responses_qs, per_page)
    page_obj = paginator.get_page(page)

    results = []
    for r in page_obj:
        results.append({
            'id': r.id,
            'client_id': r.client.id,
            'client_name': f"{r.client.first_name} {r.client.last_name}",
            'client_initials': f"{r.client.first_name[:1]}{r.client.last_name[:1]}".upper(),
            'submitted_at': r.submitted_at.strftime('%-d %b %Y, %H:%M') if r.submitted_at else '—',
            'weight_kg': str(r.weight_kg) if r.weight_kg else None,
            'status': r.status,
        })

    return JsonResponse({
        'results': results,
        'page': page_obj.number,
        'num_pages': paginator.num_pages,
        'total': paginator.count,
        'per_page': per_page,
    })


def _json_filled(v):
    """True when a JSONField subquery value holds real data (dict on Postgres,
    JSON string on sqlite)."""
    if not v:
        return False
    if isinstance(v, str):
        return v.strip() not in ('', '{}', 'null')
    return bool(v)


def _latest_check_name(rel):
    """Display name for a client's most recent check. Single measurements have no
    template title, so synthesize "Misurazione Singola - Pliche/Peso/Circonferenze"
    from whichever metric was recorded."""
    from .helpers import QUICK_MEASUREMENT_TYPE
    if rel.latest_qtype == QUICK_MEASUREMENT_TYPE:
        if _json_filled(rel.latest_skinfolds):
            sub = 'Pliche'
        elif _json_filled(rel.latest_circumferences):
            sub = 'Circonferenze'
        else:
            sub = 'Peso'
        return f'Misurazione Singola - {sub}'
    return rel.latest_title or 'Check'


def api_coach_clients_check_status(request):
    """Unique athletes for this coach with their latest check status."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    q = request.GET.get('q', '').strip()
    filter_status = request.GET.get('status', 'all')

    relationships = CoachingRelationship.objects.filter(
        coach=coach, status='ACTIVE'
    ).select_related('client').order_by('client__first_name', 'client__last_name')

    if q:
        relationships = relationships.filter(
            Q(client__first_name__icontains=q) | Q(client__last_name__icontains=q)
        )

    latest_sq = QuestionnaireResponse.objects.filter(
        client=OuterRef('client_id'), coach=coach
    ).order_by('-submitted_at')
    relationships = relationships.annotate(
        latest_submitted_at=Subquery(latest_sq.values('submitted_at')[:1]),
        latest_weight_kg=Subquery(latest_sq.values('weight_kg')[:1]),
        latest_title=Subquery(latest_sq.values('questionnaire_template__title')[:1]),
        latest_qtype=Subquery(latest_sq.values('questionnaire_template__questionnaire_type')[:1]),
        latest_skinfolds=Subquery(latest_sq.values('skinfolds')[:1], output_field=JSONField()),
        latest_circumferences=Subquery(latest_sq.values('body_circumferences')[:1], output_field=JSONField()),
        pending_count=Count(
            'client__questionnaire_responses',
            filter=Q(client__questionnaire_responses__coach=coach,
                     client__questionnaire_responses__status='COMPLETED'),
        ),
    )

    results = []
    for rel in relationships:
        client = rel.client
        pending_count = rel.pending_count or 0
        latest_submitted_at = rel.latest_submitted_at

        if pending_count > 0:
            status_val = 'da_revisionare'
        elif latest_submitted_at:
            status_val = 'aggiornato'
        else:
            status_val = 'nessun_check'

        if filter_status == 'da_revisionare' and status_val != 'da_revisionare':
            continue

        results.append({
            'client_id': client.id,
            'client_name': f"{client.first_name} {client.last_name}",
            'client_initials': f"{client.first_name[:1]}{client.last_name[:1]}".upper(),
            'pending_count': pending_count,
            'status': status_val,
            'latest_check_at': latest_submitted_at.strftime('%-d %b %Y') if latest_submitted_at else None,
            'latest_check_name': _latest_check_name(rel) if latest_submitted_at else None,
        })

    # da_revisionare first, then by latest check desc
    results.sort(key=lambda x: (
        0 if x['status'] == 'da_revisionare' else (1 if x['status'] == 'aggiornato' else 2),
        -(0 if x['latest_check_at'] is None else 1),
    ))

    return JsonResponse({'results': results, 'total': len(results)})


def api_check_schedule(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        data = json.loads(request.body)
        client_id = data.get('client_id')
        start_str = data.get('start_datetime')
        end_str = data.get('end_datetime')
        notes = data.get('notes', '')

        if not client_id or not start_str or not end_str:
            return JsonResponse({'error': 'Campi obbligatori mancanti'}, status=400)

        start_datetime = parse_datetime(start_str)
        end_datetime = parse_datetime(end_str)

        if not start_datetime or not end_datetime:
            return JsonResponse({'error': 'Formato data non valido'}, status=400)
        if end_datetime <= start_datetime:
            return JsonResponse({'error': 'La data di fine deve essere successiva alla data di inizio'}, status=400)

        client = ClientProfile.objects.get(
            id=client_id,
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE'
        )

        appointment = Appointment.objects.create(
            coach=coach,
            client=client,
            title=f"Check Progressi – {client.first_name} {client.last_name}",
            appointment_type='check',
            start_datetime=start_datetime,
            duration_minutes=max(1, int((end_datetime - start_datetime).total_seconds() // 60)),
            description=notes,
            status='SCHEDULED',
        )
        return JsonResponse({'success': True, 'appointment_id': appointment.id})

    except ClientProfile.DoesNotExist:
        return JsonResponse({'error': 'Atleta non trovato o non associato'}, status=404)
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)


def api_check_review(request, response_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        data = json.loads(request.body)
        response = QuestionnaireResponse.objects.select_related('client__user').get(id=response_id, coach=coach)
        response.status = 'REVIEWED'
        response.coach_feedback = data.get('coach_feedback', '')
        response.coach_private_notes = data.get('coach_private_notes', '')
        response.save(update_fields=['status', 'coach_feedback', 'coach_private_notes', 'updated_at'])
        cachekeys.invalidate_athlete_recap(response.client_id)
        Notification.objects.create(
            target_user=response.client.user,
            notification_type='CHECK_REVIEWED',
            title='Check revisionato',
            body='Il tuo coach ha revisionato il tuo check.',
            link_url=f'/check/{response.id}/',
        )
        return JsonResponse({'success': True})
    except QuestionnaireResponse.DoesNotExist:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)


WEEKDAY_ABBR = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']


def _create_instance(assignment, due_date):
    expires = timezone.now() + timedelta(hours=assignment.duration_hours)
    instance = AssignedCheckInstance.objects.create(
        assignment=assignment,
        due_date=due_date,
        expires_at=expires,
        status='pending',
        notified_at=timezone.now(),
    )
    _notify_client_new_instance(instance)
    return instance


def _generate_due_instances(client):
    today = timezone.localdate()
    assignments = list(
        AssignedCheck.objects.filter(client=client, is_active=True)
        .select_related('template', 'client__user', 'coach')
        .prefetch_related('instances')
    )
    if not assignments:
        return

    week_monday = today - timedelta(days=today.weekday())
    week_sunday = week_monday + timedelta(days=6)
    seven_days_ago = today - timedelta(days=7)
    seven_days_ahead = today + timedelta(days=7)

    needs_end_program_check = any(a.recurrence_type == 'end_program' for a in assignments)
    expiring = False
    if needs_end_program_check:
        try:
            from domain.workouts.models import WorkoutAssignment
            expiring = WorkoutAssignment.objects.filter(
                client=client, end_date__gte=today, end_date__lte=seven_days_ahead
            ).exists()
        except Exception:
            expiring = False
        if not expiring:
            try:
                from domain.nutrition.models import NutritionAssignment
                expiring = NutritionAssignment.objects.filter(
                    client=client, end_date__gte=today, end_date__lte=seven_days_ahead
                ).exists()
            except Exception:
                expiring = False

    for assignment in assignments:
        instances = list(assignment.instances.all())

        if assignment.recurrence_type == 'once':
            if not instances:
                _create_instance(assignment, today)

        elif assignment.recurrence_type == 'weekly' and assignment.weekly_day is not None:
            if today.weekday() == assignment.weekly_day:
                if not any(week_monday <= i.due_date <= week_sunday for i in instances):
                    _create_instance(assignment, today)

        elif assignment.recurrence_type == 'monthly' and assignment.monthly_day is not None:
            if today.day == assignment.monthly_day:
                if not any(i.due_date.year == today.year and i.due_date.month == today.month for i in instances):
                    _create_instance(assignment, today)

        elif assignment.recurrence_type == 'end_program':
            if expiring and not any(i.due_date >= seven_days_ago for i in instances):
                _create_instance(assignment, today)


def _notify_client_new_instance(instance):
    assignment = instance.assignment
    client = assignment.client
    coach = assignment.coach
    title = assignment.template.title if assignment.template else 'Check'
    send_mail(
        subject=f'Nuovo check da compilare: {title}',
        message=(
            f'Ciao {client.first_name},\n\n'
            f'Il tuo coach {coach.first_name} {coach.last_name} ti ha inviato un check da compilare: «{title}».\n\n'
            f'Hai tempo fino al {instance.expires_at.strftime("%d/%m/%Y alle %H:%M")} per compilarlo.\n\n'
            f'Accedi alla piattaforma: {settings.SITE_URL}/check/i-miei-check/\n\n'
            f'Saluti,\nAthlynk'
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[client.user.email],
        fail_silently=True,
    )


def _notify_coach_check_completed(instance):
    assignment = instance.assignment
    coach = assignment.coach
    client = assignment.client
    title = assignment.template.title if assignment.template else 'Check'
    send_mail(
        subject=f'{client.first_name} {client.last_name} ha compilato il check: {title}',
        message=(
            f'Ciao {coach.first_name},\n\n'
            f'{client.first_name} {client.last_name} ha compilato il check «{title}».\n\n'
            f'Accedi alla piattaforma per revisionarlo: {settings.SITE_URL}/check/\n\n'
            f'Saluti,\nAthlynk'
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[coach.user.email],
        fail_silently=True,
    )


def _build_ics(assignment):
    title = assignment.template.title if assignment.template else 'Check'
    uid = f'assigned-check-{assignment.id}@athlynk.it'
    now_str = timezone.now().strftime('%Y%m%dT%H%M%SZ')
    start_date = assignment.assigned_at.strftime('%Y%m%d')
    lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Athlynk//Athlynk//IT',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        f'UID:{uid}',
        f'DTSTAMP:{now_str}',
        f'DTSTART;VALUE=DATE:{start_date}',
        f'DTEND;VALUE=DATE:{start_date}',
        f'SUMMARY:Check – {title}',
        f'DESCRIPTION:{assignment.notes or "Check periodico Athlynk"}',
    ]
    if assignment.recurrence_type == 'weekly' and assignment.weekly_day is not None:
        byday = WEEKDAY_ABBR[assignment.weekly_day]
        lines.append(f'RRULE:FREQ=WEEKLY;BYDAY={byday}')
    elif assignment.recurrence_type == 'monthly' and assignment.monthly_day is not None:
        lines.append(f'RRULE:FREQ=MONTHLY;BYMONTHDAY={assignment.monthly_day}')
    lines += ['END:VEVENT', 'END:VCALENDAR']
    return '\r\n'.join(lines)


def api_check_assign(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        data = json.loads(request.body)
        client_ids    = data.get('client_ids')
        if client_ids is None and data.get('client_id'):
            client_ids = [data.get('client_id')]
        template_id   = data.get('template_id')
        recurrence    = data.get('recurrence_type', 'once')
        weekly_day    = data.get('weekly_day')
        monthly_day   = data.get('monthly_day')
        duration_hrs  = max(1, int(data.get('duration_hours', 72)))
        notes         = (data.get('notes') or '').strip()

        if not client_ids or not template_id:
            return JsonResponse({'error': 'Seleziona almeno un atleta e un check.'}, status=400)

        try:
            template = QuestionnaireTemplate.objects.get(id=template_id, coach=coach)
        except QuestionnaireTemplate.DoesNotExist:
            return JsonResponse({'error': 'Template non trovato.'}, status=404)

        clients = list(ClientProfile.objects.filter(
            id__in=client_ids,
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE',
        ).distinct())

        if not clients:
            return JsonResponse({'error': 'Nessun atleta valido selezionato.'}, status=400)

        assignment_ids = []
        for client in clients:
            assignment = AssignedCheck.objects.create(
                template=template,
                snapshot_config=template.questions_config,
                client=client,
                coach=coach,
                recurrence_type=recurrence,
                weekly_day=weekly_day if recurrence == 'weekly' else None,
                monthly_day=monthly_day if recurrence == 'monthly' else None,
                duration_hours=duration_hrs,
                notes=notes,
            )
            assignment_ids.append(assignment.id)

            if recurrence == 'once':
                _create_instance(assignment, timezone.localdate())
            else:
                send_mail(
                    subject=f'Check ricorrente assegnato: {template.title}',
                    message=(
                        f'Ciao {client.first_name},\n\n'
                        f'Il tuo coach {coach.first_name} {coach.last_name} ti ha assegnato un check periodico: «{template.title}».\n\n'
                        f'Troverai il check nella sezione "I miei check da compilare" quando sarà il momento.\n\n'
                        f'Saluti,\nAthlynk'
                    ),
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[client.user.email],
                    fail_silently=True,
                )

            Notification.objects.create(
                target_user=client.user,
                notification_type='CHECK_SUBMITTED',
                title='Nuovo check da compilare',
                body=f'Il tuo coach ti ha assegnato il check «{template.title}».',
                link_url='/check/i-miei-check/',
            )

        return JsonResponse({
            'success': True,
            'assigned_count': len(assignment_ids),
            'assignment_ids': assignment_ids,
            'assignment_id': assignment_ids[0] if assignment_ids else None,
        })

    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)


def api_check_assignment_ics(request, assignment_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    coach = get_session_coach(request)
    client = get_session_client(request) if user.role == 'CLIENT' else None

    try:
        if coach:
            assignment = AssignedCheck.objects.get(id=assignment_id, coach=coach)
        else:
            assignment = AssignedCheck.objects.get(id=assignment_id, client=client)
    except AssignedCheck.DoesNotExist:
        return JsonResponse({'error': 'Non trovato'}, status=404)

    ics = _build_ics(assignment)
    resp = HttpResponse(ics, content_type='text/calendar; charset=utf-8')
    resp['Content-Disposition'] = f'attachment; filename="check_{assignment_id}.ics"'
    return resp
