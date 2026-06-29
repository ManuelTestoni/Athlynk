"""Page view dei check: dashboard, compilazione, dettaglio, storico,
andamento e comparatore."""

from django.shortcuts import render, redirect
from django.urls import reverse
from django.http import JsonResponse, HttpResponse
from django.core.paginator import Paginator
from django.utils import timezone
from django.db.models import Q, Count, OuterRef, Subquery
from django.core.files.storage import default_storage
from django.utils.dateparse import parse_datetime
from django.core.mail import send_mail
from django.conf import settings
import json
from datetime import timedelta

from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto, AssignedCheck, AssignedCheckInstance, QuestionAttachment, CheckFolder
from domain.checks.preset_templates import PRESETS, build_template_payload
from domain.checks.anthropometry import (
    circ_label, skin_label, order_circ_keys, order_skin_keys, catalog_json, measurement_options,
    circ_pad, skin_pad, WEIGHT_PAD,
)
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from ..services.uploads import store_attachment

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

from ..session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship

from .helpers import (
    RESERVED_FIELD_MAP, build_measurements, _build_chart_data,
    _response_config, _build_check_sections, _has_allegato_questions,
    _compute_deltas, _build_prefill,
)
from .assignments import _generate_due_instances, _notify_coach_check_completed


def _template_has_fabbisogni(questions):
    """True se la config domande contiene lo strumento «Calcolo Fabbisogni»."""
    return any((q or {}).get('type') == 'strumento_fabbisogni' for q in (questions or []))


def _fabbisogni_prefill(client):
    """Precompila i dati di partenza dello strumento Fabbisogni dal profilo
    atleta: altezza, ultimo peso dai check, età dalla data di nascita, sesso.
    Tutti i valori restano modificabili a mano in fase di compilazione."""
    prefill = {}
    latest_w = (QuestionnaireResponse.objects
                .filter(client=client, weight_kg__isnull=False)
                .order_by('-submitted_at')
                .values_list('weight_kg', flat=True)
                .first())
    if latest_w:
        prefill['peso_kg'] = str(round(float(latest_w), 1))
    if client.birth_date:
        today = timezone.now().date()
        bd = client.birth_date
        age = today.year - bd.year - ((today.month, today.day) < (bd.month, bd.day))
        if 0 < age < 120:
            prefill['eta_anni'] = str(age)
    g = (client.gender or '').strip().lower()
    if g[:1] == 'm' or g in ('maschio', 'male', 'uomo'):
        prefill['sesso'] = 'Maschio'
    elif g[:1] == 'f' or g in ('femmina', 'female', 'donna'):
        prefill['sesso'] = 'Femmina'
    return prefill


def check_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    # ── CLIENT ─────────────────────────────────────────────────────
    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('client_blocked')

        # Lazy-generate any due assigned check instances
        _generate_due_instances(client)

        page = max(1, int(request.GET.get('page', 1)))
        per_page = int(request.GET.get('per_page', 10))
        if per_page not in [10, 20]:
            per_page = 10

        responses_qs = (
            QuestionnaireResponse.objects.filter(client=client)
            .defer('answers_json', 'body_circumferences', 'skinfolds',
                   'coach_feedback', 'coach_private_notes')
            .order_by('-submitted_at')
        )

        paginator = Paginator(responses_qs, per_page)
        page_obj = paginator.get_page(page)

        upcoming_check = Appointment.objects.filter(
            client=client,
            appointment_type__iexact='check',
            status='SCHEDULED',
            start_datetime__gte=timezone.now()
        ).order_by('start_datetime').first()

        pending_instances = AssignedCheckInstance.objects.filter(
            assignment__client=client, status='pending'
        ).select_related('assignment__template', 'assignment__coach').order_by('expires_at')

        # Mark expired instances
        now = timezone.now()
        expired_ids = [i.id for i in pending_instances if i.expires_at < now]
        if expired_ids:
            AssignedCheckInstance.objects.filter(id__in=expired_ids).update(status='expired')
            pending_instances = pending_instances.exclude(id__in=expired_ids)

        context = {
            'page_obj': page_obj,
            'per_page': per_page,
            'upcoming_check': upcoming_check,
            'pending_instances': list(pending_instances),
        }
        if request.META.get('HTTP_X_REQUESTED_WITH') == 'XMLHttpRequest':
            return render(request, 'pages/check/_check_table_fragment.html', context)
        return render(request, 'pages/check/dashboard_client.html', context)

    # ── COACH ──────────────────────────────────────────────────────
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    to_review_count = QuestionnaireResponse.objects.filter(coach=coach, status='COMPLETED').count()
    reviewed_count = QuestionnaireResponse.objects.filter(coach=coach, status='REVIEWED').count()
    upcoming_checks_count = Appointment.objects.filter(
        coach=coach,
        appointment_type__iexact='check',
        status='SCHEDULED',
        start_datetime__gte=timezone.now()
    ).count()

    coach_clients = list(
        CoachingRelationship.objects.filter(coach=coach, status='ACTIVE')
        .select_related('client')
        .values('client__id', 'client__first_name', 'client__last_name')
    )

    coach_templates = list(
        QuestionnaireTemplate.objects.filter(coach=coach, is_active=True)
        .exclude(questions_config=None)
        .values('id', 'title')
        .order_by('-updated_at')
    )

    pending_assignments_count = AssignedCheckInstance.objects.filter(
        assignment__coach=coach, status='pending'
    ).count()

    context = {
        'to_review_count': to_review_count,
        'reviewed_count': reviewed_count,
        'upcoming_checks_count': upcoming_checks_count,
        'pending_assignments_count': pending_assignments_count,
        'coach_clients_json': json.dumps(coach_clients),
        'coach_templates_json': json.dumps(coach_templates),
    }
    return render(request, 'pages/check/dashboard.html', context)


def check_create_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    coach_filling_for_client = False

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        client_id = request.GET.get('client_id') or request.POST.get('client_id')
        template_id = request.GET.get('template_id') or request.POST.get('template_id')
        if not client_id or not template_id:
            return redirect('check_dashboard')
        try:
            client = ClientProfile.objects.get(
                id=client_id,
                coaching_relationships_as_client__coach=coach,
                coaching_relationships_as_client__status='ACTIVE',
            )
        except ClientProfile.DoesNotExist:
            return redirect('check_dashboard')
        try:
            template = QuestionnaireTemplate.objects.get(id=template_id, coach=coach, is_active=True)
        except QuestionnaireTemplate.DoesNotExist:
            return redirect('check_dashboard')
        coach_filling_for_client = True
    elif user.role == 'CLIENT':
        # Il flusso self-service legacy è stato rimosso: gli atleti compilano
        # solo i check assegnati dal coach (chiavi misure ISAK uniformi).
        return redirect('client_assigned_checks')
    else:
        return redirect('check_dashboard')

    if request.method == 'GET':
        prefill = {}
        if _template_has_fabbisogni(template.questions_config):
            prefill.update(_fabbisogni_prefill(client))
        return render(request, 'pages/check/builder.html', {
            'client': client,
            'coach': coach,
            'template': template,
            'check_title': template.title,
            'questions_config_json': json.dumps(template.questions_config or []),
            'steps_config_json': json.dumps(template.steps_config or []),
            'catalog_json': json.dumps(catalog_json()),
            'prefill_json': json.dumps(prefill),
            'custom_bmr_formulas_json': json.dumps(coach.custom_bmr_formulas or []),
        })

    # ── POST ───────────────────────────────────────────────────────

    # New wizard flow (coach builder)
    if coach_filling_for_client and 'answers_json' in request.POST:
        try:
            raw_answers = json.loads(request.POST.get('answers_json', '{}'))
        except json.JSONDecodeError:
            return redirect('check_dashboard')

        questions_config = template.questions_config or []
        check_title = template.title

        def _parse_metric(val):
            try:
                v = float(val or 0)
                return str(round(v, 1)) if v > 0 else ''
            except (ValueError, TypeError):
                return ''

        weight_kg, body_circumferences, skinfolds = build_measurements(
            raw_answers, questions_config, _parse_metric)

        answers_json = {
            'mood': raw_answers.get('benessere_umore', ''),
            'diet_adherence': raw_answers.get('benessere_dieta', ''),
            'workout_adherence': raw_answers.get('benessere_workout', ''),
        }
        for k, v in raw_answers.items():
            if k == 'peso_corporeo' or k in RESERVED_FIELD_MAP \
                    or k.startswith('circ::') or k.startswith('pl::'):
                continue
            answers_json.setdefault(k, v)

        response = QuestionnaireResponse.objects.create(
            questionnaire_template=template,
            client=client,
            coach=coach,
            submitted_at=timezone.now(),
            status='REVIEWED',  # coach compiled → already reviewed
            weight_kg=weight_kg,
            body_circumferences=body_circumferences,
            skinfolds=skinfolds,
            answers_json=answers_json,
            questions_snapshot=questions_config,
            steps_snapshot=template.steps_config or [],
            injuries=raw_answers.get('note_infortuni', ''),
            limitations=raw_answers.get('note_limitazioni', ''),
            notes=raw_answers.get('note_messaggio', ''),
        )

        # Generic attachments (one input per `allegato` question, name=f'attachment_{q_id}', multiple)
        for q in questions_config:
            if q.get('type') != 'allegato':
                continue
            files = request.FILES.getlist(f'attachment_{q["id"]}')
            for f in files:
                prefix = f'check_attachments/{client.id}/{q["id"]}_{int(timezone.now().timestamp())}_'
                saved, kind = store_attachment(f, dir_prefix=prefix)
                if not saved:
                    continue  # rejected: not a real image or video
                QuestionAttachment.objects.create(
                    response=response,
                    question_id=q['id'],
                    file_url=default_storage.url(saved),
                    file_name=f.name,
                    mime_type=getattr(f, 'content_type', '') or '',
                )

        Notification.objects.create(
            target_user=client.user,
            notification_type='CHECK_SUBMITTED',
            title='Check compilato',
            body=f'Il tuo coach ha compilato un check "{check_title}" per te.',
            link_url='/check/',
        )
        return redirect('clienti_detail', client_id=client.id)

    return redirect('check_dashboard')


def check_detail_view(request, response_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        try:
            response = QuestionnaireResponse.objects.select_related(
                'client', 'coach', 'questionnaire_template'
            ).get(id=response_id, coach=coach)
        except QuestionnaireResponse.DoesNotExist:
            return redirect('check_dashboard')

    elif user.role == 'CLIENT':
        client = get_session_client(request)
        try:
            response = QuestionnaireResponse.objects.select_related(
                'client', 'coach', 'questionnaire_template'
            ).get(id=response_id, client=client)
        except QuestionnaireResponse.DoesNotExist:
            return redirect('check_dashboard')
    else:
        return redirect('login')

    prev_response = QuestionnaireResponse.objects.filter(
        client=response.client,
        submitted_at__lt=response.submitted_at
    ).order_by('-submitted_at').first()

    check_number = QuestionnaireResponse.objects.filter(
        client=response.client,
        submitted_at__lte=response.submitted_at
    ).count()

    weight_delta, circ_deltas, skinfold_deltas = _compute_deltas(response, prev_response)

    curr_circ = response.body_circumferences or {}
    prev_circ = (prev_response.body_circumferences or {}) if prev_response else {}
    circ_rows = [
        {'label': circ_label(key), 'current': curr_circ.get(key, ''),
         'previous': prev_circ.get(key, ''), 'delta': circ_deltas.get(key)}
        for key in order_circ_keys(k for k, v in curr_circ.items() if v not in (None, ''))
    ]

    curr_sf = response.skinfolds or {}
    prev_sf = (prev_response.skinfolds or {}) if prev_response else {}
    skinfold_rows = [
        {'label': skin_label(key), 'current': curr_sf.get(key, ''),
         'previous': prev_sf.get(key, ''), 'delta': skinfold_deltas.get(key)}
        for key in order_skin_keys(k for k, v in curr_sf.items() if v not in (None, ''))
    ]

    photos = list(response.photos.all())
    answers = response.answers_json or {}

    attachments = list(response.attachments.all())
    attachments_by_q = {}
    for a in attachments:
        attachments_by_q.setdefault(a.question_id, []).append(a)

    questions_cfg, steps_cfg = _response_config(response)
    sections = _build_check_sections(questions_cfg, steps_cfg, response, prev_response, attachments_by_q)

    has_allegato_q = _has_allegato_questions(questions_cfg)
    has_any_attachments = any(attachments_by_q.values())
    has_photos_tab = bool(photos) or has_any_attachments or has_allegato_q

    is_coach_view = (user.role == 'COACH')
    has_athlete_notes = bool(response.notes or response.injuries or response.limitations)
    has_coach_feedback = bool(response.coach_feedback)
    has_notes_tab = is_coach_view or has_athlete_notes or has_coach_feedback

    available_tabs = []
    for s in sections:
        available_tabs.append({'id': 'sec_' + str(s['id']), 'label': s['label'], 'icon': s['icon']})
    if has_photos_tab:
        photo_count = len(photos)
        for files in attachments_by_q.values():
            photo_count += len(files)
        available_tabs.append({'id': 'foto', 'label': 'Foto', 'icon': 'ph-camera', 'count': photo_count})
    if has_notes_tab:
        available_tabs.append({'id': 'note', 'label': 'Note & Feedback', 'icon': 'ph-notebook'})

    default_tab = available_tabs[0]['id'] if available_tabs else 'note'

    context = {
        'response': response,
        'prev_response': prev_response,
        'check_number': check_number,
        'weight_delta': weight_delta,
        'circ_rows': circ_rows,
        'skinfold_rows': skinfold_rows,
        'photos': photos,
        'answers': answers,
        'sections': sections,
        'attachments_by_q': attachments_by_q,
        'has_photos_tab': has_photos_tab,
        'has_notes_tab': has_notes_tab,
        'has_athlete_notes': has_athlete_notes,
        'has_coach_feedback': has_coach_feedback,
        'available_tabs': available_tabs,
        'default_tab': default_tab,
    }
    return render(request, 'pages/check/detail.html', context)


def check_edit_view(request, response_id):
    """Coach edits the athlete-filled data of an existing response.

    The check date (`submitted_at`) is intentionally never modified — it
    orients the time-series in the progress charts — only the compiled
    values are altered. Review status is left untouched."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')
    try:
        response = QuestionnaireResponse.objects.select_related(
            'client', 'coach', 'questionnaire_template'
        ).get(id=response_id, coach=coach)
    except QuestionnaireResponse.DoesNotExist:
        return redirect('check_dashboard')

    template = response.questionnaire_template
    if not template:
        return redirect('check_detail', response_id=response.id)

    # La modifica usa lo snapshot della compilazione (se presente): le domande
    # devono combaciare coi dati salvati, non con la config live del modello.
    questions_cfg, steps_cfg = _response_config(response)

    if request.method == 'GET':
        return render(request, 'pages/check/builder.html', {
            'client': response.client,
            'coach': coach,
            'template': template,
            'response': response,
            'is_edit': True,
            'check_title': template.title,
            'questions_config_json': json.dumps(questions_cfg),
            'steps_config_json': json.dumps(steps_cfg),
            'catalog_json': json.dumps(catalog_json()),
            'prefill_json': json.dumps(_build_prefill(response)),
            'custom_bmr_formulas_json': json.dumps(coach.custom_bmr_formulas or []),
        })

    # ── POST ───────────────────────────────────────────────────────
    try:
        raw_answers = json.loads(request.POST.get('answers_json', '{}'))
    except json.JSONDecodeError:
        return redirect('check_detail', response_id=response.id)

    questions_config = questions_cfg

    def _parse_metric(val):
        try:
            v = float(val or 0)
            return str(round(v, 1)) if v > 0 else ''
        except (ValueError, TypeError):
            return ''

    weight_kg, body_circumferences, skinfolds = build_measurements(
        raw_answers, questions_config, _parse_metric)

    answers_json = {
        'mood': raw_answers.get('benessere_umore', ''),
        'diet_adherence': raw_answers.get('benessere_dieta', ''),
        'workout_adherence': raw_answers.get('benessere_workout', ''),
    }
    for k, v in raw_answers.items():
        if k == 'peso_corporeo' or k in RESERVED_FIELD_MAP \
                or k.startswith('circ::') or k.startswith('pl::'):
            continue
        answers_json.setdefault(k, v)

    response.weight_kg = weight_kg
    response.body_circumferences = body_circumferences
    response.skinfolds = skinfolds
    response.answers_json = answers_json
    response.injuries = raw_answers.get('note_infortuni', '')
    response.limitations = raw_answers.get('note_limitazioni', '')
    response.notes = raw_answers.get('note_messaggio', '')
    # submitted_at intentionally NOT updated — it anchors the chart timeline.
    response.save(update_fields=[
        'weight_kg', 'body_circumferences', 'skinfolds', 'answers_json',
        'injuries', 'limitations', 'notes', 'updated_at',
    ])
    return redirect('check_detail', response_id=response.id)


def client_check_history_view(request, client_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    try:
        relationship = CoachingRelationship.objects.select_related('client').get(
            coach=coach, client__id=client_id
        )
        target_client = relationship.client
    except CoachingRelationship.DoesNotExist:
        return redirect('check_dashboard')

    page = max(1, int(request.GET.get('page', 1)))
    per_page = int(request.GET.get('per_page', 10))
    if per_page not in [10, 20]:
        per_page = 10

    responses_qs = (
        QuestionnaireResponse.objects.filter(coach=coach, client=target_client)
        .defer('answers_json', 'body_circumferences', 'skinfolds',
               'coach_feedback', 'coach_private_notes')
        .order_by('-submitted_at')
    )

    paginator = Paginator(responses_qs, per_page)
    page_obj = paginator.get_page(page)

    chart_data = _build_chart_data(target_client)

    context = {
        'target_client': target_client,
        'page_obj': page_obj,
        'per_page': per_page,
        'total_checks': paginator.count,
        'chart_data_json': json.dumps(chart_data),
    }
    return render(request, 'pages/check/client_history.html', context)


def check_progress_charts_view(request, client_id=None):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        target_client = get_session_client(request)
        is_coach_view = False
    elif user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        if not client_id:
            return redirect('check_dashboard')
        try:
            rel = CoachingRelationship.objects.select_related('client').get(coach=coach, client__id=client_id)
            target_client = rel.client
        except CoachingRelationship.DoesNotExist:
            return redirect('check_dashboard')
        is_coach_view = True
    else:
        return redirect('check_dashboard')

    chart_data = _build_chart_data(target_client)

    if is_coach_view:
        measurement_url = reverse('api_coach_measurement', args=[target_client.id])
    else:
        measurement_url = reverse('api_client_measurement')

    return render(request, 'pages/check/progress_charts.html', {
        'target_client': target_client,
        'is_coach_view': is_coach_view,
        'chart_data_json': json.dumps(chart_data),
        'total_checks': len(chart_data['labels']),
        'measurement_options_json': json.dumps(measurement_options()),
        'measurement_post_url': measurement_url,
    })


def check_comparator_view(request, client_id=None):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        target_client = get_session_client(request)
        is_coach_view = False
    elif user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        if not client_id:
            return redirect('check_dashboard')
        try:
            rel = CoachingRelationship.objects.select_related('client').get(coach=coach, client__id=client_id)
            target_client = rel.client
        except CoachingRelationship.DoesNotExist:
            return redirect('check_dashboard')
        is_coach_view = True
    else:
        return redirect('check_dashboard')

    photos_qs = ProgressPhoto.objects.filter(
        client=target_client
    ).order_by('-captured_at').values('id', 'file_url', 'photo_type', 'captured_at')

    photos_data = [
        {
            'id': p['id'],
            'url': p['file_url'],
            'photo_type': p['photo_type'],
            'date': p['captured_at'].strftime('%d/%m/%Y'),
        }
        for p in photos_qs
    ]

    return render(request, 'pages/check/comparatore.html', {
        'target_client': target_client,
        'is_coach_view': is_coach_view,
        'photos_json': json.dumps(photos_data),
        'total_photos': len(photos_data),
    })


def client_assigned_checks_view(request):
    return redirect('check_dashboard')


def fill_assigned_check_view(request, instance_id):
    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        return redirect('login')

    client = get_session_client(request)
    try:
        instance = AssignedCheckInstance.objects.select_related(
            'assignment__template', 'assignment__coach'
        ).get(id=instance_id, assignment__client=client)
    except AssignedCheckInstance.DoesNotExist:
        return redirect('client_assigned_checks')

    if instance.status == 'completed':
        return redirect('client_assigned_checks')
    if instance.status == 'pending' and timezone.now() > instance.expires_at:
        instance.status = 'expired'
        instance.save(update_fields=['status'])
        return redirect('client_assigned_checks')

    assignment = instance.assignment
    questions_config = assignment.snapshot_config or []
    steps_config = (assignment.template.steps_config or []) if assignment.template else []
    coach = assignment.coach

    if request.method == 'GET':
        return render(request, 'pages/check/fill_assigned.html', {
            'instance': instance,
            'assignment': assignment,
            'questions_config_json': json.dumps(questions_config),
            'steps_config_json': json.dumps(steps_config),
            'catalog_json': json.dumps(catalog_json()),
            'coach': coach,
            'errors': [],
        })

    # POST
    try:
        raw_answers = json.loads(request.POST.get('answers_json', '{}'))
    except json.JSONDecodeError:
        raw_answers = {}

    # Validate required questions (antropometria is composite → skip simple check;
    # allegato arriva in request.FILES, non in answers_json)
    errors = []
    for q in questions_config:
        if not q.get('required'):
            continue
        qtype = q.get('type')
        if qtype == 'antropometria':
            continue
        if qtype == 'allegato':
            if not request.FILES.getlist(f'attachment_{q["id"]}'):
                errors.append(f'«{q["label"]}» è obbligatoria.')
            continue
        val = raw_answers.get(q['id'])
        if qtype == 'checkbox':
            if not isinstance(val, list) or not val:
                errors.append(f'«{q["label"]}» è obbligatoria.')
            continue
        if val is None or str(val).strip() == '':
            errors.append(f'«{q["label"]}» è obbligatoria.')

    if errors:
        return render(request, 'pages/check/fill_assigned.html', {
            'instance': instance,
            'assignment': assignment,
            'questions_config_json': json.dumps(questions_config),
            'steps_config_json': json.dumps(steps_config),
            'catalog_json': json.dumps(catalog_json()),
            'coach': coach,
            'errors': errors,
            'prefill_json': json.dumps(raw_answers),
        })

    def _pm(val):
        try:
            v = float(val or 0)
            return str(round(v, 1)) if v > 0 else ''
        except (ValueError, TypeError):
            return ''

    weight_kg, body_circumferences, skinfolds = build_measurements(
        raw_answers, questions_config, _pm)

    STRUCTURED = {
        'peso_corporeo', 'note_infortuni', 'note_limitazioni', 'note_messaggio',
        'benessere_umore', 'benessere_dieta', 'benessere_workout',
    } | set(RESERVED_FIELD_MAP.keys())
    answers_json = {
        'mood': raw_answers.get('benessere_umore', ''),
        'diet_adherence': raw_answers.get('benessere_dieta', ''),
        'workout_adherence': raw_answers.get('benessere_workout', ''),
    }
    for k, v in raw_answers.items():
        if k in STRUCTURED or k.startswith('circ::') or k.startswith('pl::'):
            continue
        answers_json[k] = v

    template = assignment.template
    response_obj = QuestionnaireResponse.objects.create(
        questionnaire_template=template,
        client=client,
        coach=coach,
        submitted_at=timezone.now(),
        status='COMPLETED',
        weight_kg=weight_kg,
        body_circumferences=body_circumferences,
        skinfolds=skinfolds,
        answers_json=answers_json,
        questions_snapshot=questions_config,
        steps_snapshot=steps_config,
        injuries=raw_answers.get('note_infortuni', ''),
        limitations=raw_answers.get('note_limitazioni', ''),
        notes=raw_answers.get('note_messaggio', ''),
    )

    # Allegati: stesso protocollo del flusso coach (input name=f'attachment_{q_id}')
    for q in questions_config:
        if q.get('type') != 'allegato':
            continue
        files = request.FILES.getlist(f'attachment_{q["id"]}')
        for f in files:
            prefix = f'check_attachments/{client.id}/{q["id"]}_{int(timezone.now().timestamp())}_'
            saved, kind = store_attachment(f, dir_prefix=prefix)
            if not saved:
                continue  # rejected: not a real image or video
            QuestionAttachment.objects.create(
                response=response_obj,
                question_id=q['id'],
                file_url=default_storage.url(saved),
                file_name=f.name,
                mime_type=getattr(f, 'content_type', '') or '',
            )

    instance.status = 'completed'
    instance.response = response_obj
    instance.save(update_fields=['status', 'response'])

    _notify_coach_check_completed(instance)

    Notification.objects.create(
        target_user=coach.user,
        notification_type='CHECK_SUBMITTED',
        title=f'{client.first_name} ha compilato il check',
        body=f'{client.first_name} {client.last_name} ha compilato «{template.title if template else "Check"}».',
        link_url=f'/check/{response_obj.id}/',
    )

    return redirect('client_assigned_checks')
