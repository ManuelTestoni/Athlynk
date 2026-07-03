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
from ..http_utils import safe_int



PRESET_ORDER = ['prima_valutazione', 'completo_coach', 'rapido_atleta', 'feedback_atleta', 'nutrizione', 'allenamento']

# Preset rimossi dal modulo: i loro cloni (anche modificati) vanno disattivati
# alla prima apertura di «Gestisci Modelli». Le risposte storiche restano
# integre — referenziano il template via FK e conservano lo snapshot.
RETIRED_PRESET_KEYS = ['calcolo_fabbisogni']


def _ensure_preset_clones(coach):
    """Lazy-clone any preset templates missing for this coach.

    Unmodified clones are also re-synced when the preset definition evolves
    (e.g. domande antropometriche migrate dal tipo `metrica` al tipo
    `antropometria`): senza questo, i cloni restano alla vecchia versione e
    «Ripristina» è disabilitato perché is_modified_preset=False.
    """
    # Disattiva i cloni di preset ritirati (es. «Calcolo Fabbisogni», ora
    # disponibile come strumento dentro gli altri modelli).
    if RETIRED_PRESET_KEYS:
        QuestionnaireTemplate.objects.filter(
            coach=coach, preset_key__in=RETIRED_PRESET_KEYS, is_active=True
        ).update(is_active=False)

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


# ── Formule MB personalizzate (strumento «Calcolo Fabbisogni») ──────────────
import ast

# Nodi AST ammessi in un'espressione di formula MB: sola aritmetica pura sulle
# variabili note (niente chiamate, attributi o nomi arbitrari). Validazione via
# AST, mai eval.
_BMR_ALLOWED_NODES = (
    ast.Expression, ast.BinOp, ast.UnaryOp,
    ast.Add, ast.Sub, ast.Mult, ast.Div,
    ast.USub, ast.UAdd, ast.Load, ast.Name, ast.Constant,
)
_BMR_ALLOWED_VARS = {'P', 'H', 'A'}  # Peso(kg), Altezza(cm), Età(anni)


def _validate_bmr_expr(expr):
    """True se `expr` è un'espressione aritmetica sicura su P, H, A."""
    expr = (expr or '').strip()
    if not expr or len(expr) > 200:
        return False
    try:
        tree = ast.parse(expr, mode='eval')
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        if not isinstance(node, _BMR_ALLOWED_NODES):
            return False
        if isinstance(node, ast.Name) and node.id not in _BMR_ALLOWED_VARS:
            return False
        if isinstance(node, ast.Constant) and not isinstance(node.value, (int, float)):
            return False
    return True


def api_bmr_formula_create(request):
    """Salva una formula MB personalizzata sul profilo coach (sessione web).
    Body JSON {name, expr}; ritorna l'elenco aggiornato."""
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)
    try:
        data = json.loads(request.body or '{}')
    except json.JSONDecodeError:
        return JsonResponse({'error': 'Body non valido.'}, status=400)
    name = (data.get('name') or '').strip()
    expr = (data.get('expr') or '').strip()
    if not name or len(name) > 60:
        return JsonResponse({'error': 'Nome formula non valido.'}, status=400)
    if not _validate_bmr_expr(expr):
        return JsonResponse({'error': 'Formula non valida. Usa solo numeri, + − × ÷ ( ) e le variabili P, H, A.'}, status=400)
    formulas = list(coach.custom_bmr_formulas or [])
    if any((f.get('name') or '').strip().lower() == name.lower() for f in formulas):
        return JsonResponse({'error': 'Esiste già una formula con questo nome.'}, status=400)
    if len(formulas) >= 50:
        return JsonResponse({'error': 'Hai raggiunto il numero massimo di formule.'}, status=400)
    formulas.append({'name': name, 'expr': expr})
    coach.custom_bmr_formulas = formulas
    coach.save(update_fields=['custom_bmr_formulas', 'updated_at'])
    return JsonResponse({'success': True, 'formulas': formulas}, status=201)


def check_templates_api(request):
    """Paginated custom-only templates for the library. ?folder_id=&q=&offset=&limit="""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'forbidden'}, status=403)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'forbidden'}, status=403)

    LIMIT = 10
    offset = max(0, safe_int(request.GET, 'offset', 0))
    folder_id_raw = request.GET.get('folder_id', 'all')
    q = (request.GET.get('q') or '').strip().lower()

    qs = QuestionnaireTemplate.objects.filter(
        coach=coach, is_active=True,
    ).exclude(preset_key__isnull=False).exclude(preset_key='')

    if folder_id_raw == 'unfiled':
        qs = qs.filter(folder__isnull=True)
    elif folder_id_raw != 'all':
        try:
            qs = qs.filter(folder_id=int(folder_id_raw))
        except (ValueError, TypeError):
            pass

    if q:
        qs = qs.filter(Q(title__icontains=q) | Q(description__icontains=q))

    qs = qs.order_by('-updated_at')
    total = qs.count()
    page = qs[offset:offset + LIMIT]
    data = [
        {
            'id': t.id, 'title': t.title, 'description': t.description or '',
            'questions_count': len(t.questions_config or []),
            'steps_count': len(t.steps_config or []),
            'folder_id': t.folder_id,
            'updated_at': t.updated_at.isoformat() if t.updated_at else '',
        }
        for t in page
    ]
    return JsonResponse({'templates': data, 'has_more': total > offset + LIMIT, 'total': total})
