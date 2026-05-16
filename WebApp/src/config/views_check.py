from django.shortcuts import render, redirect
from django.http import JsonResponse
from django.core.paginator import Paginator
from django.utils import timezone
from django.db.models import Q
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from django.utils.dateparse import parse_datetime
import os
import json

from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto
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

        context = {
            'page_obj': page_obj,
            'per_page': per_page,
            'upcoming_check': upcoming_check,
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

    context = {
        'to_review_count': to_review_count,
        'reviewed_count': reviewed_count,
        'upcoming_checks_count': upcoming_checks_count,
        'coach_clients_json': json.dumps(coach_clients),
    }
    return render(request, 'pages/check/dashboard.html', context)


def check_create_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    coach_filling_for_client = False

    if user.role == 'COACH':
        # Coach fills check on behalf of a client (in-studio visit)
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        client_id = request.GET.get('client_id') or request.POST.get('client_id')
        if not client_id:
            return redirect('check_dashboard')
        try:
            client = ClientProfile.objects.get(
                id=client_id,
                coaching_relationships_as_client__coach=coach,
                coaching_relationships_as_client__status='ACTIVE',
            )
        except ClientProfile.DoesNotExist:
            return redirect('check_dashboard')
        coach_filling_for_client = True
    elif user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')
        coach = relationship.coach
    else:
        return redirect('check_dashboard')

    if request.method == 'GET':
        return render(request, 'pages/check/create.html', {
            'client': client,
            'coach': coach,
            'coach_filling_for_client': coach_filling_for_client,
        })

    # ── POST ───────────────────────────────────────────────────────
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
            'coach_filling_for_client': coach_filling_for_client,
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

    if coach_filling_for_client:
        Notification.objects.create(
            target_user=client.user,
            notification_type='CHECK_SUBMITTED',
            title='Check compilato',
            body='Il tuo coach ha compilato un check per te.',
            link_url='/check/',
        )
        return redirect('clienti_detail', client_id=client.id)

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
