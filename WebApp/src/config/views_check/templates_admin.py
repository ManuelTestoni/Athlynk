"""Gestione modelli (QuestionnaireTemplate): lista, builder, preset
di sistema e relative API."""

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
    circ_pad, skin_pad, WEIGHT_PAD,
)
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from ..services.images import to_webp, is_image

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment

from ..session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship



PRESET_ORDER = ['completo_coach', 'rapido_atleta', 'feedback_atleta', 'nutrizione', 'allenamento', 'calcolo_fabbisogni']


def _ensure_preset_clones(coach):
    """Lazy-clone any preset templates missing for this coach.

    Unmodified clones are also re-synced when the preset definition evolves
    (e.g. domande antropometriche migrate dal tipo `metrica` al tipo
    `antropometria`): senza questo, i cloni restano alla vecchia versione e
    «Ripristina» è disabilitato perché is_modified_preset=False.
    """
    existing = {
        t.preset_key: t for t in QuestionnaireTemplate.objects.filter(
            coach=coach, preset_key__in=list(PRESETS.keys())
        )
    }
    for key in PRESETS:
        tpl = existing.get(key)
        if tpl is None:
            QuestionnaireTemplate.objects.create(coach=coach, **build_template_payload(key))
            continue
        if tpl.is_modified_preset:
            continue
        payload = build_template_payload(key)
        if (tpl.questions_config != payload['questions_config']
                or tpl.steps_config != payload['steps_config']):
            tpl.title = payload['title']
            tpl.description = payload['description']
            tpl.steps_config = payload['steps_config']
            tpl.questions_config = payload['questions_config']
            tpl.save(update_fields=['title', 'description', 'steps_config',
                                    'questions_config', 'updated_at'])


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
