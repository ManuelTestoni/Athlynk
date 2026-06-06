from django.shortcuts import render, redirect
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
    circ_label, skin_label, order_circ_keys, order_skin_keys, catalog_json,
)
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from .services.images import to_webp, is_image

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

from .session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship

RESERVED_FIELD_MAP = {
    'peso_corporeo':    ('weight_kg', None),
    'circ_spalle':      ('body_circumferences', 'shoulders'),
    'circ_petto':       ('body_circumferences', 'chest'),
    'circ_vita':        ('body_circumferences', 'waist'),
    'circ_fianchi':     ('body_circumferences', 'hips'),
    'circ_coscia':      ('body_circumferences', 'thigh_right'),
    'circ_braccio':     ('body_circumferences', 'arm_right'),
    'pl_petto':         ('skinfolds', 'chest'),
    'pl_addome':        ('skinfolds', 'abdomen'),
    'pl_coscia':        ('skinfolds', 'thigh'),
    'pl_tricipite':     ('skinfolds', 'tricep'),
    'note_messaggio':   ('notes', None),
    'note_infortuni':   ('injuries', None),
    'note_limitazioni': ('limitations', None),
}


def _get_q_value(q_id, resp):
    if not resp:
        return None
    if q_id in RESERVED_FIELD_MAP:
        field, key = RESERVED_FIELD_MAP[q_id]
        val = getattr(resp, field, None)
        if key:
            if not isinstance(val, dict):
                return None
            v = val.get(key)
            return v if v not in ('', None) else None
        return val if val not in ('', None) else None
    aj = resp.answers_json or {}
    v = aj.get(q_id)
    return v if v not in ('', None) else None


def _to_float(val):
    try:
        v = float(val or 0)
        return v or None
    except (ValueError, TypeError):
        return None


def build_measurements(raw_answers, questions_config, parse_fn):
    """Build (weight_kg, body_circumferences, skinfolds) from submitted answers.

    Template-driven: handles both legacy `metrica` antropometric questions (via
    RESERVED_FIELD_MAP) and the composite `antropometria` type. `parse_fn`
    normalizes a single metric value to its stored string form.
    """
    weight_kg = None
    circ, skin = {}, {}
    for q in (questions_config or []):
        qid = q.get('id')
        qtype = q.get('type')
        if qtype == 'antropometria':
            if q.get('weight'):
                w = _to_float(raw_answers.get('peso_corporeo'))
                if w:
                    weight_kg = w
            for key in q.get('circumferences') or []:
                circ[key] = parse_fn(raw_answers.get('circ::' + key))
            for key in q.get('skinfolds') or []:
                skin[key] = parse_fn(raw_answers.get('pl::' + key))
        elif qtype == 'metrica' and qid in RESERVED_FIELD_MAP:
            field, sub = RESERVED_FIELD_MAP[qid]
            val = raw_answers.get(qid)
            if field == 'weight_kg':
                w = _to_float(val)
                if w:
                    weight_kg = w
            elif field == 'body_circumferences':
                circ[sub] = parse_fn(val)
            elif field == 'skinfolds':
                skin[sub] = parse_fn(val)
    return weight_kg, circ, skin


def _measure_row(label, unit, val, prev):
    delta = None
    try:
        if prev not in (None, ''):
            delta = round(float(val) - float(prev), 1)
    except (ValueError, TypeError):
        delta = None
    return {'type': 'metrica', 'label': label, 'unit': unit,
            'value': val, 'previous': prev, 'delta': delta}


def _antropometria_rows(q, response, prev_response):
    """Expand a composite `antropometria` question into ordered metrica-style
    rows (weight → circonferenze → pliche) so detail.html renders them as usual."""
    rows = []
    if q.get('weight'):
        val = response.weight_kg
        if val not in (None, ''):
            prev = prev_response.weight_kg if prev_response else None
            rows.append({**_measure_row('Peso corporeo', 'kg', val, prev), 'id': 'peso_corporeo'})
    curr_c = response.body_circumferences or {}
    prev_c = (prev_response.body_circumferences or {}) if prev_response else {}
    for key in q.get('circumferences') or []:
        val = curr_c.get(key)
        if val in (None, ''):
            continue
        rows.append({**_measure_row(circ_label(key), 'cm', val, prev_c.get(key)), 'id': 'circ::' + key})
    curr_s = response.skinfolds or {}
    prev_s = (prev_response.skinfolds or {}) if prev_response else {}
    for key in q.get('skinfolds') or []:
        val = curr_s.get(key)
        if val in (None, ''):
            continue
        rows.append({**_measure_row(skin_label(key), 'mm', val, prev_s.get(key)), 'id': 'pl::' + key})
    return rows


def _collect_measurement_keys(responses):
    present_circ, present_skin = set(), set()
    for r in responses:
        for k, v in (r['body_circumferences'] or {}).items():
            if v not in (None, ''):
                present_circ.add(k)
        for k, v in (r['skinfolds'] or {}).items():
            if v not in (None, ''):
                present_skin.add(k)
    return order_circ_keys(present_circ), order_skin_keys(present_skin)


def _build_chart_data(target_client):
    """Time-series chart data, dynamic over the measurements actually stored
    for the athlete (ordered per ISAK catalog; legacy keys kept in tail)."""
    responses = list(
        QuestionnaireResponse.objects.filter(client=target_client)
        .order_by('submitted_at')
        .values('submitted_at', 'weight_kg', 'body_circumferences', 'skinfolds')
    )
    circ_keys, skin_keys = _collect_measurement_keys(responses)
    labels, weight = [], []
    chart_circ = {k: [] for k in circ_keys}
    chart_skin = {k: [] for k in skin_keys}
    for r in responses:
        labels.append(r['submitted_at'].strftime('%d/%m/%Y'))
        weight.append(float(r['weight_kg']) if r['weight_kg'] else None)
        circ = r['body_circumferences'] or {}
        for k in circ_keys:
            v = circ.get(k)
            chart_circ[k].append(float(v) if v else None)
        skin = r['skinfolds'] or {}
        for k in skin_keys:
            v = skin.get(k)
            chart_skin[k].append(float(v) if v else None)
    return {
        'labels': labels,
        'weight': weight,
        'circumferences': chart_circ,
        'skinfolds': chart_skin,
        'circ_keys': circ_keys,
        'skin_keys': skin_keys,
        'circ_labels': {k: circ_label(k) for k in circ_keys},
        'skin_labels': {k: skin_label(k) for k in skin_keys},
    }


def _build_check_sections(template, response, prev_response, attachments_by_q):
    if not template:
        return []
    questions = list(template.questions_config or [])
    steps = list(template.steps_config or [])
    if not steps:
        steps = [{'id': '__solo', 'label': 'Check', 'icon': 'ph-clipboard-text'}]

    fallback_sid = steps[0].get('id')
    sections = []
    for step in steps:
        sid = step.get('id')
        step_qs = [q for q in questions if (q.get('step_id') or fallback_sid) == sid]
        rendered = []
        for q in step_qs:
            q_id = q.get('id')
            q_type = q.get('type', 'aperta')

            if q_type == 'allegato':
                files = attachments_by_q.get(q_id, [])
                if not files:
                    continue
                rendered.append({
                    'id': q_id, 'type': 'allegato',
                    'label': q.get('label', 'Allegato'),
                    'files': files,
                })
                continue

            if q_type == 'antropometria':
                rendered.extend(_antropometria_rows(q, response, prev_response))
                continue

            val = _get_q_value(q_id, response)
            if val in (None, ''):
                continue

            prev_val = _get_q_value(q_id, prev_response)
            delta = None
            if q_type in ('metrica', 'range', 'media'):
                try:
                    if prev_val not in (None, ''):
                        delta = round(float(val) - float(prev_val), 1)
                except (ValueError, TypeError):
                    delta = None

            rendered.append({
                'id': q_id,
                'type': q_type,
                'label': q.get('label', q_id),
                'unit': q.get('unit'),
                'value': val,
                'previous': prev_val,
                'delta': delta,
                'options': q.get('options'),
                'min': q.get('min'),
                'max': q.get('max'),
                'min_label': q.get('minLabel'),
                'max_label': q.get('maxLabel'),
                'range_min': q.get('rangeMin'),
                'range_max': q.get('rangeMax'),
            })

        if rendered:
            sections.append({
                'id': sid,
                'label': step.get('label', 'Sezione'),
                'icon': step.get('icon') or 'ph-list',
                'questions': rendered,
            })
    return sections


def _has_allegato_questions(template):
    if not template:
        return False
    for q in (template.questions_config or []):
        if q.get('type') == 'allegato':
            return True
    return False


def _dict_deltas(curr, prev):
    curr = curr or {}
    prev = prev or {}
    out = {}
    for key in curr:
        try:
            if curr.get(key) and prev.get(key):
                out[key] = round(float(curr[key]) - float(prev[key]), 1)
            else:
                out[key] = None
        except (ValueError, TypeError):
            out[key] = None
    return out


def _compute_deltas(current_response, prev_response):
    weight_delta = None
    if prev_response and current_response.weight_kg and prev_response.weight_kg:
        weight_delta = float(current_response.weight_kg) - float(prev_response.weight_kg)

    prev_circ = prev_response.body_circumferences if prev_response else None
    prev_sf = prev_response.skinfolds if prev_response else None
    circ_deltas = _dict_deltas(current_response.body_circumferences, prev_circ)
    skinfold_deltas = _dict_deltas(current_response.skinfolds, prev_sf)
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
                'catalog_json': json.dumps(catalog_json()),
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

    template = response.questionnaire_template
    sections = _build_check_sections(template, response, prev_response, attachments_by_q)

    has_allegato_q = _has_allegato_questions(template)
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

    return render(request, 'pages/check/progress_charts.html', {
        'target_client': target_client,
        'is_coach_view': is_coach_view,
        'chart_data_json': json.dumps(chart_data),
        'total_checks': len(chart_data['labels']),
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

    responses_qs = (
        QuestionnaireResponse.objects.filter(coach=coach)
        .select_related('client')
        .only('id', 'submitted_at', 'weight_kg', 'status',
              'client__id', 'client__first_name', 'client__last_name', 'client__primary_goal')
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
        latest_weight_kg = rel.latest_weight_kg

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
            'primary_goal': client.primary_goal or '',
            'pending_count': pending_count,
            'status': status_val,
            'latest_check_at': latest_submitted_at.strftime('%-d %b %Y') if latest_submitted_at else None,
            'latest_weight': str(latest_weight_kg) if latest_weight_kg else None,
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
    assignments = list(
        AssignedCheck.objects.filter(client=client, is_active=True)
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

    # Validate required questions (antropometria is composite → skip simple check)
    errors = []
    for q in questions_config:
        if q.get('required') and q.get('type') != 'antropometria':
            val = raw_answers.get(q['id'])
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

    all_templates = (
        QuestionnaireTemplate.objects.filter(coach=coach, is_active=True)
        .defer('report_config')
    )

    presets_by_key = {t.preset_key: t for t in all_templates if t.preset_key}
    presets = [presets_by_key[k] for k in PRESET_ORDER if k in presets_by_key]
    customs = [t for t in all_templates.order_by('-updated_at') if not t.preset_key]

    customs_payload = [
        {
            'id': t.id,
            'title': t.title,
            'description': t.description or '',
            'questions_count': len(t.questions_config or []),
            'steps_count': len(t.steps_config or []),
            'folder_id': t.folder_id,
            'updated_at': t.updated_at.isoformat() if t.updated_at else '',
        }
        for t in customs
    ]

    folders = list(
        CheckFolder.objects.filter(coach=coach)
        .annotate(template_count=Count('templates', filter=Q(templates__is_active=True)))
        .order_by('order', 'title')
    )
    folders_payload = [
        {
            'id': f.id,
            'title': f.title,
            'label_text': f.label_text or '',
            'label_color': f.label_color or '',
            'order': f.order,
            'template_count': f.template_count,
        }
        for f in folders
    ]

    return render(request, 'pages/check/templates_list.html', {
        'presets': presets,
        'customs_payload': customs_payload,
        'folders_payload': folders_payload,
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
        'catalog_json': json.dumps(catalog_json()),
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
        'catalog_json': json.dumps(catalog_json()),
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
