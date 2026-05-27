from django.shortcuts import render, redirect
from django.http import JsonResponse, HttpResponse
from django.core.paginator import Paginator
from django.utils import timezone
from django.db.models import Q
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from django.utils.dateparse import parse_datetime
from django.core.mail import send_mail
from django.conf import settings
import os
import json
from datetime import timedelta

from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto, AssignedCheck, AssignedCheckInstance, QuestionAttachment
from domain.checks.preset_templates import PRESETS, build_template_payload
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from .services.images import to_webp, is_image

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

from .session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship

CIRC_LABELS = [
    ('shoulders', 'Spalle'),
    ('chest', 'Petto'),
    ('waist', 'Vita'),
    ('hips', 'Fianchi'),
    ('thigh_right', 'Coscia DX'),
    ('arm_right', 'Braccio DX'),
]

SKINFOLD_LABELS = [
    ('chest', 'Petto'),
    ('abdomen', 'Addome'),
    ('thigh', 'Coscia'),
    ('tricep', 'Tricipite'),
]


def _compute_deltas(current_response, prev_response):
    weight_delta = None
    if prev_response and current_response.weight_kg and prev_response.weight_kg:
        weight_delta = float(current_response.weight_kg) - float(prev_response.weight_kg)

    circ_deltas = {}
    curr_circ = current_response.body_circumferences or {}
    prev_circ = (prev_response.body_circumferences or {}) if prev_response else {}
    for key, _ in CIRC_LABELS:
        try:
            delta = float(curr_circ.get(key, '') or 0) - float(prev_circ.get(key, '') or 0)
            circ_deltas[key] = round(delta, 1) if curr_circ.get(key) and prev_circ.get(key) else None
        except (ValueError, TypeError):
            circ_deltas[key] = None

    skinfold_deltas = {}
    curr_sf = current_response.skinfolds or {}
    prev_sf = (prev_response.skinfolds or {}) if prev_response else {}
    for key, _ in SKINFOLD_LABELS:
        try:
            delta = float(curr_sf.get(key, '') or 0) - float(prev_sf.get(key, '') or 0)
            skinfold_deltas[key] = round(delta, 1) if curr_sf.get(key) and prev_sf.get(key) else None
        except (ValueError, TypeError):
            skinfold_deltas[key] = None

    return weight_delta, circ_deltas, skinfold_deltas


def check_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    # ── CLIENT ─────────────────────────────────────────────────────
    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')

        # Lazy-generate any due assigned check instances
        _generate_due_instances(client)

        page = max(1, int(request.GET.get('page', 1)))
        per_page = int(request.GET.get('per_page', 10))
        if per_page not in [10, 20]:
            per_page = 10

        responses_qs = QuestionnaireResponse.objects.filter(
            client=client
        ).order_by('-submitted_at')

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
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')
        coach = relationship.coach
        template = None
    else:
        return redirect('check_dashboard')

    if request.method == 'GET':
        if coach_filling_for_client:
            return render(request, 'pages/check/builder.html', {
                'client': client,
                'coach': coach,
                'template': template,
                'check_title': template.title,
                'questions_config_json': json.dumps(template.questions_config or []),
                'steps_config_json': json.dumps(template.steps_config or []),
            })
        return render(request, 'pages/check/create.html', {
            'client': client,
            'coach': coach,
            'coach_filling_for_client': False,
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

        try:
            weight_kg = float(raw_answers.get('peso_corporeo') or 0) or None
        except (ValueError, TypeError):
            weight_kg = None

        body_circumferences = {
            'shoulders': _parse_metric(raw_answers.get('circ_spalle')),
            'chest': _parse_metric(raw_answers.get('circ_petto')),
            'waist': _parse_metric(raw_answers.get('circ_vita')),
            'hips': _parse_metric(raw_answers.get('circ_fianchi')),
            'thigh_right': _parse_metric(raw_answers.get('circ_coscia')),
            'arm_right': _parse_metric(raw_answers.get('circ_braccio')),
        }
        skinfolds = {
            'chest': _parse_metric(raw_answers.get('pl_petto')),
            'abdomen': _parse_metric(raw_answers.get('pl_addome')),
            'thigh': _parse_metric(raw_answers.get('pl_coscia')),
            'tricep': _parse_metric(raw_answers.get('pl_tricipite')),
        }

        answers_json = {
            'mood': raw_answers.get('benessere_umore', ''),
            'diet_adherence': raw_answers.get('benessere_dieta', ''),
            'workout_adherence': raw_answers.get('benessere_workout', ''),
        }
        for k, v in raw_answers.items():
            answers_json.setdefault(k, v)

        response = QuestionnaireResponse.objects.create(
            questionnaire_template=template,
            client=client,
            coach=coach,
            submitted_at=timezone.now(),
            status='COMPLETED',
            weight_kg=weight_kg,
            body_circumferences=body_circumferences,
            skinfolds=skinfolds,
            answers_json=answers_json,
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
                save_path = f'check_attachments/{client.id}/{q["id"]}_{int(timezone.now().timestamp())}_{f.name}'
                if is_image(f):
                    saved = default_storage.save(save_path.rsplit('.', 1)[0] + '.webp', to_webp(f))
                else:
                    saved = default_storage.save(save_path, f)
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

    # Legacy client-facing flow (client fills own form)
    errors = {}

    def parse_float_field(val, field_name, label):
        val = (val or '').strip()
        if not val:
            return None, None
        try:
            v = float(val)
            if v < 0:
                return None, f'{label} non può essere negativo'
            return v, None
        except ValueError:
            return None, f'{label} deve essere un numero valido'

    weight_kg, err = parse_float_field(request.POST.get('weight_kg'), 'weight_kg', 'Peso')
    if err:
        errors['weight_kg'] = err

    def parse_measurement(val):
        val = (val or '').strip()
        if not val:
            return ''
        try:
            v = float(val)
            return '' if v < 0 else str(round(v, 1))
        except ValueError:
            return ''

    body_circumferences = {
        'shoulders': parse_measurement(request.POST.get('circ_spalle')),
        'chest': parse_measurement(request.POST.get('circ_petto')),
        'waist': parse_measurement(request.POST.get('circ_vita')),
        'hips': parse_measurement(request.POST.get('circ_fianchi')),
        'thigh_right': parse_measurement(request.POST.get('circ_coscia')),
        'arm_right': parse_measurement(request.POST.get('circ_braccio')),
    }

    skinfolds = {
        'chest': parse_measurement(request.POST.get('pl_petto')),
        'abdomen': parse_measurement(request.POST.get('pl_addome')),
        'thigh': parse_measurement(request.POST.get('pl_coscia')),
        'tricep': parse_measurement(request.POST.get('pl_tricipite')),
    }

    if errors:
        return render(request, 'pages/check/create.html', {
            'client': client,
            'coach': coach,
            'coach_filling_for_client': False,
            'errors': errors,
            'post_data': request.POST,
        })

    template, _ = QuestionnaireTemplate.objects.get_or_create(
        coach=coach,
        title='Check Settimanale Standard',
        defaults={
            'questionnaire_type': 'weekly_check',
            'phase': 'Generica',
            'is_active': True,
        }
    )

    answers_json = {
        'mood': request.POST.get('ans_mood', ''),
        'diet_adherence': request.POST.get('ans_diet', ''),
        'workout_adherence': request.POST.get('ans_workout', ''),
    }

    response = QuestionnaireResponse.objects.create(
        questionnaire_template=template,
        client=client,
        coach=coach,
        submitted_at=timezone.now(),
        status='COMPLETED',
        weight_kg=weight_kg,
        body_circumferences=body_circumferences,
        skinfolds=skinfolds,
        answers_json=answers_json,
        injuries=request.POST.get('injuries', ''),
        limitations=request.POST.get('limitations', ''),
        notes=request.POST.get('notes', ''),
    )

    for key, photo_type in [('photo_front', 'Front'), ('photo_side', 'Side'), ('photo_back', 'Back')]:
        file = request.FILES.get(key)
        if not file:
            continue
        if not is_image(file):
            continue
        webp_file = to_webp(file)
        save_path = f'progress_photos/{client.id}/{photo_type.lower()}_{int(timezone.now().timestamp())}.webp'
        saved_path = default_storage.save(save_path, webp_file)
        ProgressPhoto.objects.create(
            client=client,
            coach=coach,
            questionnaire_response=response,
            file_url=default_storage.url(saved_path),
            photo_type=photo_type,
            captured_at=timezone.now(),
        )

    Notification.objects.create(
        target_user=coach.user,
        notification_type='CHECK_SUBMITTED',
        title=f'Nuovo check da {client.first_name} {client.last_name}',
        body='Nuovo check da revisionare.',
        link_url='/check/',
    )
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
                'client', 'coach'
            ).get(id=response_id, coach=coach)
        except QuestionnaireResponse.DoesNotExist:
            return redirect('check_dashboard')

    elif user.role == 'CLIENT':
        client = get_session_client(request)
        try:
            response = QuestionnaireResponse.objects.select_related(
                'client', 'coach'
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

    circ_rows = []
    curr_circ = response.body_circumferences or {}
    prev_circ = (prev_response.body_circumferences or {}) if prev_response else {}
    for key, label in CIRC_LABELS:
        curr_val = curr_circ.get(key, '')
        prev_val = prev_circ.get(key, '')
        circ_rows.append({
            'label': label,
            'current': curr_val,
            'previous': prev_val,
            'delta': circ_deltas.get(key),
        })

    skinfold_rows = []
    curr_sf = response.skinfolds or {}
    prev_sf = (prev_response.skinfolds or {}) if prev_response else {}
    for key, label in SKINFOLD_LABELS:
        curr_val = curr_sf.get(key, '')
        prev_val = prev_sf.get(key, '')
        skinfold_rows.append({
            'label': label,
            'current': curr_val,
            'previous': prev_val,
            'delta': skinfold_deltas.get(key),
        })

    photos = list(response.photos.all())
    answers = response.answers_json or {}

    context = {
        'response': response,
        'prev_response': prev_response,
        'check_number': check_number,
        'weight_delta': weight_delta,
        'circ_rows': circ_rows,
        'skinfold_rows': skinfold_rows,
        'photos': photos,
        'answers': answers,
    }
    return render(request, 'pages/check/detail.html', context)


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

    responses_qs = QuestionnaireResponse.objects.filter(
        coach=coach, client=target_client
    ).order_by('-submitted_at')

    paginator = Paginator(responses_qs, per_page)
    page_obj = paginator.get_page(page)

    context = {
        'target_client': target_client,
        'page_obj': page_obj,
        'per_page': per_page,
        'total_checks': paginator.count,
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

    responses = list(
        QuestionnaireResponse.objects.filter(client=target_client)
        .order_by('submitted_at')
        .values('submitted_at', 'weight_kg', 'body_circumferences', 'skinfolds')
    )

    labels = []
    weight_data = []
    circ_keys = ['shoulders', 'chest', 'waist', 'hips', 'thigh_right', 'arm_right']
    skin_keys = ['chest', 'abdomen', 'thigh', 'tricep']
    circ_data = {k: [] for k in circ_keys}
    skin_data = {k: [] for k in skin_keys}

    for r in responses:
        labels.append(r['submitted_at'].strftime('%d/%m/%Y'))
        weight_data.append(float(r['weight_kg']) if r['weight_kg'] else None)
        circ = r['body_circumferences'] or {}
        for k in circ_keys:
            v = circ.get(k)
            circ_data[k].append(float(v) if v else None)
        skin = r['skinfolds'] or {}
        for k in skin_keys:
            v = skin.get(k)
            skin_data[k].append(float(v) if v else None)

    chart_data = {
        'labels': labels,
        'weight': weight_data,
        'circumferences': circ_data,
        'skinfolds': skin_data,
    }

    return render(request, 'pages/check/progress_charts.html', {
        'target_client': target_client,
        'is_coach_view': is_coach_view,
        'chart_data_json': json.dumps(chart_data),
        'total_checks': len(labels),
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


# ── API endpoints ─────────────────────────────────────────────────


def api_check_search(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    q = request.GET.get('q', '').strip()
    tab = request.GET.get('tab', 'da_revisionare')
    page = max(1, int(request.GET.get('page', 1)))
    per_page = int(request.GET.get('per_page', 10))
    if per_page not in [10, 20]:
        per_page = 10

    responses_qs = QuestionnaireResponse.objects.filter(coach=coach).select_related(
        'client'
    ).order_by('-submitted_at')

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
            'primary_goal': r.client.primary_goal or '',
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
            end_datetime=end_datetime,
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
        response = QuestionnaireResponse.objects.get(id=response_id, coach=coach)
        response.status = 'REVIEWED'
        response.coach_feedback = data.get('coach_feedback', '')
        response.coach_private_notes = data.get('coach_private_notes', '')
        response.save(update_fields=['status', 'coach_feedback', 'coach_private_notes', 'updated_at'])
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


# ── Assigned checks helpers ────────────────────────────────────────

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
    for assignment in AssignedCheck.objects.filter(client=client, is_active=True):
        if assignment.recurrence_type == 'once':
            if not assignment.instances.exists():
                _create_instance(assignment, today)

        elif assignment.recurrence_type == 'weekly' and assignment.weekly_day is not None:
            if today.weekday() == assignment.weekly_day:
                week_monday = today - timedelta(days=today.weekday())
                if not assignment.instances.filter(due_date__gte=week_monday, due_date__lte=week_monday + timedelta(days=6)).exists():
                    _create_instance(assignment, today)

        elif assignment.recurrence_type == 'monthly' and assignment.monthly_day is not None:
            if today.day == assignment.monthly_day:
                if not assignment.instances.filter(due_date__year=today.year, due_date__month=today.month).exists():
                    _create_instance(assignment, today)

        elif assignment.recurrence_type == 'end_program':
            # Check if any workout or nutrition plan ends within the next 7 days
            try:
                from domain.workouts.models import WorkoutAssignment
                expiring = WorkoutAssignment.objects.filter(
                    client=client,
                    end_date__gte=today,
                    end_date__lte=today + timedelta(days=7),
                ).exists()
            except Exception:
                expiring = False
            if not expiring:
                try:
                    from domain.nutrition.models import NutritionAssignment
                    expiring = NutritionAssignment.objects.filter(
                        client=client,
                        end_date__gte=today,
                        end_date__lte=today + timedelta(days=7),
                    ).exists()
                except Exception:
                    expiring = False
            if expiring and not assignment.instances.filter(due_date__gte=today - timedelta(days=7)).exists():
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
            f'Accedi alla piattaforma: https://athlynk.it/check/i-miei-check/\n\n'
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
            f'Accedi alla piattaforma per revisionarlo: https://athlynk.it/check/\n\n'
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


# ── Assigned check views ───────────────────────────────────────────

def client_assigned_checks_view(request):
    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        return redirect('login')

    client = get_session_client(request)
    _generate_due_instances(client)

    now = timezone.now()
    instances = AssignedCheckInstance.objects.filter(
        assignment__client=client
    ).select_related('assignment__template', 'assignment__coach').order_by('-due_date')

    # Auto-expire
    to_expire = [i.id for i in instances if i.status == 'pending' and i.expires_at < now]
    if to_expire:
        AssignedCheckInstance.objects.filter(id__in=to_expire).update(status='expired')

    pending   = [i for i in instances if i.status == 'pending' and i.expires_at >= now]
    completed = [i for i in instances if i.status == 'completed']
    expired   = [i for i in instances if i.status == 'expired' or (i.status == 'pending' and i.expires_at < now)]

    return render(request, 'pages/check/assigned_checks_client.html', {
        'pending': pending,
        'completed': completed,
        'expired': expired,
    })


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
    coach = assignment.coach

    if request.method == 'GET':
        return render(request, 'pages/check/fill_assigned.html', {
            'instance': instance,
            'assignment': assignment,
            'questions_config_json': json.dumps(questions_config),
            'coach': coach,
            'errors': [],
        })

    # POST
    try:
        raw_answers = json.loads(request.POST.get('answers_json', '{}'))
    except json.JSONDecodeError:
        raw_answers = {}

    # Validate required questions
    errors = []
    for q in questions_config:
        if q.get('required'):
            val = raw_answers.get(q['id'])
            if val is None or str(val).strip() == '':
                errors.append(f'«{q["label"]}» è obbligatoria.')

    if errors:
        return render(request, 'pages/check/fill_assigned.html', {
            'instance': instance,
            'assignment': assignment,
            'questions_config_json': json.dumps(questions_config),
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

    try:
        weight_kg = float(raw_answers.get('peso_corporeo') or 0) or None
    except (ValueError, TypeError):
        weight_kg = None

    body_circumferences = {
        'shoulders': _pm(raw_answers.get('circ_spalle')),
        'chest':     _pm(raw_answers.get('circ_petto')),
        'waist':     _pm(raw_answers.get('circ_vita')),
        'hips':      _pm(raw_answers.get('circ_fianchi')),
        'thigh_right': _pm(raw_answers.get('circ_coscia')),
        'arm_right': _pm(raw_answers.get('circ_braccio')),
    }
    skinfolds = {
        'chest':   _pm(raw_answers.get('pl_petto')),
        'abdomen': _pm(raw_answers.get('pl_addome')),
        'thigh':   _pm(raw_answers.get('pl_coscia')),
        'tricep':  _pm(raw_answers.get('pl_tricipite')),
    }
    STRUCTURED = {
        'peso_corporeo', 'circ_spalle', 'circ_petto', 'circ_vita', 'circ_fianchi',
        'circ_coscia', 'circ_braccio', 'pl_petto', 'pl_addome', 'pl_coscia',
        'pl_tricipite', 'note_infortuni', 'note_limitazioni', 'note_messaggio',
        'benessere_umore', 'benessere_dieta', 'benessere_workout',
    }
    answers_json = {
        'mood': raw_answers.get('benessere_umore', ''),
        'diet_adherence': raw_answers.get('benessere_dieta', ''),
        'workout_adherence': raw_answers.get('benessere_workout', ''),
    }
    for k, v in raw_answers.items():
        if k not in STRUCTURED:
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
        injuries=raw_answers.get('note_infortuni', ''),
        limitations=raw_answers.get('note_limitazioni', ''),
        notes=raw_answers.get('note_messaggio', ''),
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


# ── API: assign check ──────────────────────────────────────────────

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


# ── Template management (Gestisci Modelli) ─────────────────────────

PRESET_ORDER = ['completo_coach', 'rapido_atleta', 'feedback_atleta', 'nutrizione', 'allenamento']


def _ensure_preset_clones(coach):
    """Lazy-clone any preset templates missing for this coach."""
    existing_keys = set(QuestionnaireTemplate.objects.filter(
        coach=coach, preset_key__in=list(PRESETS.keys())
    ).values_list('preset_key', flat=True))
    for key in PRESETS:
        if key in existing_keys:
            continue
        QuestionnaireTemplate.objects.create(coach=coach, **build_template_payload(key))


def check_templates_list_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('check_dashboard')

    _ensure_preset_clones(coach)

    all_templates = QuestionnaireTemplate.objects.filter(coach=coach, is_active=True)

    presets_by_key = {t.preset_key: t for t in all_templates if t.preset_key}
    presets = [presets_by_key[k] for k in PRESET_ORDER if k in presets_by_key]
    customs = [t for t in all_templates.order_by('-updated_at') if not t.preset_key]

    return render(request, 'pages/check/templates_list.html', {
        'presets': presets,
        'customs': customs,
    })


def check_template_new_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('check_dashboard')

    if request.method == 'POST':
        try:
            title = (request.POST.get('title') or '').strip() or 'Nuovo modello'
            steps_config = json.loads(request.POST.get('steps_config_json', '[]'))
            questions_config = json.loads(request.POST.get('questions_config_json', '[]'))
        except json.JSONDecodeError:
            return redirect('check_templates_list')
        tpl = QuestionnaireTemplate.objects.create(
            coach=coach,
            title=title,
            questionnaire_type='custom_check',
            is_active=True,
            steps_config=steps_config,
            questions_config=questions_config,
        )
        return redirect('check_template_edit', template_id=tpl.id)

    default_steps = [{'id': 's_1', 'label': 'Step 1', 'icon': 'ph-list'}]
    return render(request, 'pages/check/template_builder.html', {
        'template': None,
        'mode': 'new',
        'title': '',
        'steps_config_json': json.dumps(default_steps),
        'questions_config_json': json.dumps([]),
        'preset_key': '',
        'is_modified_preset': False,
    })


def check_template_edit_view(request, template_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('check_dashboard')
    try:
        tpl = QuestionnaireTemplate.objects.get(id=template_id, coach=coach, is_active=True)
    except QuestionnaireTemplate.DoesNotExist:
        return redirect('check_templates_list')

    if request.method == 'POST':
        try:
            title = (request.POST.get('title') or '').strip() or tpl.title
            steps_config = json.loads(request.POST.get('steps_config_json', '[]'))
            questions_config = json.loads(request.POST.get('questions_config_json', '[]'))
        except json.JSONDecodeError:
            return redirect('check_template_edit', template_id=tpl.id)
        tpl.title = title
        tpl.steps_config = steps_config
        tpl.questions_config = questions_config
        if tpl.preset_key:
            tpl.is_modified_preset = True
        tpl.save()
        return redirect('check_template_edit', template_id=tpl.id)

    return render(request, 'pages/check/template_builder.html', {
        'template': tpl,
        'mode': 'edit',
        'title': tpl.title,
        'steps_config_json': json.dumps(tpl.steps_config or []),
        'questions_config_json': json.dumps(tpl.questions_config or []),
        'preset_key': tpl.preset_key or '',
        'is_modified_preset': bool(tpl.is_modified_preset),
    })


def api_check_template_restore(request, template_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)
    try:
        tpl = QuestionnaireTemplate.objects.get(id=template_id, coach=coach, is_active=True)
    except QuestionnaireTemplate.DoesNotExist:
        return JsonResponse({'error': 'Template non trovato.'}, status=404)
    if not tpl.preset_key or tpl.preset_key not in PRESETS:
        return JsonResponse({'error': 'Solo i preset di sistema possono essere ripristinati.'}, status=400)
    payload = build_template_payload(tpl.preset_key)
    tpl.title = payload['title']
    tpl.description = payload['description']
    tpl.steps_config = payload['steps_config']
    tpl.questions_config = payload['questions_config']
    tpl.is_modified_preset = False
    tpl.save()
    return JsonResponse({'success': True})


def api_check_template_duplicate(request, template_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)
    try:
        tpl = QuestionnaireTemplate.objects.get(id=template_id, coach=coach, is_active=True)
    except QuestionnaireTemplate.DoesNotExist:
        return JsonResponse({'error': 'Template non trovato.'}, status=404)
    copy = QuestionnaireTemplate.objects.create(
        coach=coach,
        title=f'Copia di {tpl.title}',
        description=tpl.description,
        questionnaire_type='custom_check',
        is_active=True,
        steps_config=tpl.steps_config,
        questions_config=tpl.questions_config,
    )
    return JsonResponse({'success': True, 'template_id': copy.id})


def api_check_template_delete(request, template_id):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)
    try:
        tpl = QuestionnaireTemplate.objects.get(id=template_id, coach=coach, is_active=True)
    except QuestionnaireTemplate.DoesNotExist:
        return JsonResponse({'error': 'Template non trovato.'}, status=404)
    tpl.is_active = False
    tpl.save(update_fields=['is_active', 'updated_at'])
    return JsonResponse({'success': True})
