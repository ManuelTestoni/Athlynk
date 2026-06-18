import json
import threading
import uuid
import calendar as cal_lib
from datetime import date, timedelta
from collections import defaultdict
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.db import transaction
from django.core.cache import cache

from config.session_utils import (
    get_session_user, get_session_coach, get_session_client, can_manage_nutrition,
    get_nutrition_coach,
)
from config.services import import_quota
from domain.coaching.models import CoachingRelationship, ClientAnamnesis
from domain.chat.models import Notification
from django.db.models import Count, Sum, F, FloatField, ExpressionWrapper, Case, When, Value, IntegerField
from domain.nutrition.models import (
    Food, NutritionPlan, NutritionFolder, Meal, MealItem, MealItemSubstitution,
    NutritionAssignment, DietDay, ClientMacroLogEntry,
    Supplement, SupplementSheet, SupplementSheetItem, SupplementAssignment,
)


NUTRITION_HISTORY_PAGE_SIZE = 5


def _bulk_plan_macros(plan_ids):
    """Single DB query → {plan_id: {kcal, prot, carb, fat}}.

    Sums all meal items across the plan (matches existing list-view semantics
    for both DAILY and WEEKLY; substitution averaging belongs to detail view).
    """
    if not plan_ids:
        return {}
    rows = (
        MealItem.objects
        .filter(meal__plan_id__in=list(plan_ids), food__isnull=False)
        .values('meal__plan_id')
        .annotate(
            kcal=Sum(ExpressionWrapper(F('food__energia_kcal') * F('quantity_g') / 100.0, output_field=FloatField())),
            prot=Sum(ExpressionWrapper(F('food__proteine_g')   * F('quantity_g') / 100.0, output_field=FloatField())),
            carb=Sum(ExpressionWrapper(F('food__carboidrati_g')* F('quantity_g') / 100.0, output_field=FloatField())),
            fat=Sum(ExpressionWrapper(F('food__lipidi_g')      * F('quantity_g') / 100.0, output_field=FloatField())),
        )
    )
    out = {}
    for r in rows:
        out[r['meal__plan_id']] = {
            'kcal': round(r['kcal'] or 0),
            'prot': round(r['prot'] or 0),
            'carb': round(r['carb'] or 0),
            'fat':  round(r['fat']  or 0),
        }
    return out


def _serialize_history_assignment(a, macros):
    plan = a.nutrition_plan
    m = macros.get(plan.id, {'kcal': 0, 'prot': 0, 'carb': 0, 'fat': 0})
    return {
        'id': a.id,
        'plan_title': plan.title,
        'plan_type': plan.plan_type or '',
        'plan_kind': plan.plan_kind,
        'plan_mode': plan.plan_mode,
        'status': a.status,
        'assigned_at': a.assigned_at.strftime('%d %b %Y') if a.assigned_at else '',
        'start_date': a.start_date.strftime('%d %b %Y') if a.start_date else '',
        'end_date':   a.end_date.strftime('%d %b %Y')   if a.end_date else '',
        'kcal': m['kcal'], 'prot': m['prot'], 'carb': m['carb'], 'fat': m['fat'],
    }
from domain.accounts.models import ClientProfile
from config.services.email import send_nutrition_assigned


WEEKDAY_MAP = {
    'LUN': 'MONDAY', 'MAR': 'TUESDAY', 'MER': 'WEDNESDAY',
    'GIO': 'THURSDAY', 'VEN': 'FRIDAY', 'SAB': 'SATURDAY', 'DOM': 'SUNDAY',
    'MONDAY': 'MONDAY', 'TUESDAY': 'TUESDAY', 'WEDNESDAY': 'WEDNESDAY',
    'THURSDAY': 'THURSDAY', 'FRIDAY': 'FRIDAY', 'SATURDAY': 'SATURDAY', 'SUNDAY': 'SUNDAY',
}
WEEKDAY_ORDER = {'MONDAY': 0, 'TUESDAY': 1, 'WEDNESDAY': 2, 'THURSDAY': 3, 'FRIDAY': 4, 'SATURDAY': 5, 'SUNDAY': 6}
# Long weekday code → short UI code used by the wizard/client front-end.
WEEKDAY_REVERSE = {'MONDAY': 'LUN', 'TUESDAY': 'MAR', 'WEDNESDAY': 'MER',
                   'THURSDAY': 'GIO', 'FRIDAY': 'VEN', 'SATURDAY': 'SAB', 'SUNDAY': 'DOM'}


def _normalize_weekday(code):
    if not code:
        return None
    return WEEKDAY_MAP.get(str(code).upper())


def _coerce_non_negative_int(raw):
    """Returns (value_or_None, error_bool). Empty/zero → None; negatives → error."""
    if raw in (None, '', 0, '0'):
        return None, False
    try:
        val = int(raw)
    except (TypeError, ValueError):
        return None, True
    if val < 0:
        return None, True
    return val, False


def _plan_macro_targets(plan):
    """Macro targets for a MACRO plan.

    DAILY → plan-level targets. WEEKLY → per-day targets plus the average of
    the filled days (so list/summary views stay meaningful).
    """
    if plan.plan_kind == 'WEEKLY':
        days = []
        sums = {'kcal': 0, 'prot': 0, 'carb': 0, 'fat': 0}
        filled = 0
        for d in plan.days.all():
            has_target = any([d.target_kcal, d.target_protein_g, d.target_carb_g, d.target_fat_g])
            days.append({
                'code': WEEKDAY_REVERSE.get(d.day_of_week, d.day_of_week),
                'day_of_week': d.day_of_week,
                'label': d.get_day_of_week_display(),
                'kcal': d.target_kcal, 'protein': d.target_protein_g,
                'carb': d.target_carb_g, 'fat': d.target_fat_g,
            })
            if has_target:
                filled += 1
                sums['kcal'] += d.target_kcal or 0
                sums['prot'] += d.target_protein_g or 0
                sums['carb'] += d.target_carb_g or 0
                sums['fat'] += d.target_fat_g or 0
        avg = {k: round(v / filled) if filled else 0 for k, v in sums.items()}
        avg['pct'] = _macro_kcal_pct(avg['prot'], avg['carb'], avg['fat'])
        return {'days': days, 'avg': avg, 'filled': filled}
    avg = {
        'kcal': plan.daily_kcal or 0,
        'prot': plan.protein_target_g or 0,
        'carb': plan.carb_target_g or 0,
        'fat': plan.fat_target_g or 0,
    }
    avg['pct'] = _macro_kcal_pct(avg['prot'], avg['carb'], avg['fat'])
    return {
        'avg': avg,
        'days': [],
        'filled': 1 if (plan.daily_kcal or plan.protein_target_g or plan.carb_target_g or plan.fat_target_g) else 0,
    }


def _macro_kcal_pct(prot, carb, fat):
    """Macro split as % of kcal (prot×4, carb×4, fat×9). Used for proportion bars."""
    pk, ck, fk = (prot or 0) * 4, (carb or 0) * 4, (fat or 0) * 9
    total = pk + ck + fk
    if not total:
        return {'prot': 0, 'carb': 0, 'fat': 0}
    return {
        'prot': round(pk / total * 100),
        'carb': round(ck / total * 100),
        'fat': round(fk / total * 100),
    }


# ─── Coach views ────────────────────────────────────────────────────────────────

def nutrizione_piani_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')
        nutrition_coach = get_nutrition_coach(client)
        if not nutrition_coach:
            return redirect('client_blocked')
        if not ClientAnamnesis.objects.filter(client=client).exists():
            return render(request, 'pages/nutrizione/no_prima_visita.html', {})

        active_assignment = (
            NutritionAssignment.objects
            .select_related('nutrition_plan', 'coach')
            .filter(client=client, coach=nutrition_coach, status='ACTIVE')
            .order_by('-created_at')
            .first()
        )

        past_qs = (
            NutritionAssignment.objects
            .select_related('nutrition_plan')
            .filter(client=client, coach=nutrition_coach)
            .exclude(status='ACTIVE')
            .order_by('-created_at')
        )
        past_total = past_qs.count()
        past_first = list(past_qs[:NUTRITION_HISTORY_PAGE_SIZE])

        plan_ids = set()
        if active_assignment:
            plan_ids.add(active_assignment.nutrition_plan_id)
        plan_ids.update(a.nutrition_plan_id for a in past_first)
        macros = _bulk_plan_macros(plan_ids)
        # MACRO plans have no meal items — surface the coach's targets instead.
        for a in ([active_assignment] + past_first):
            if a and a.nutrition_plan.plan_mode == 'MACRO':
                t = _plan_macro_targets(a.nutrition_plan)['avg']
                macros[a.nutrition_plan_id] = {
                    'kcal': t['kcal'], 'prot': t['prot'], 'carb': t['carb'], 'fat': t['fat'],
                }

        active_data = None
        if active_assignment:
            m = macros.get(active_assignment.nutrition_plan_id, {'kcal': 0, 'prot': 0, 'carb': 0, 'fat': 0})
            active_data = {
                'assignment': active_assignment,
                'plan': active_assignment.nutrition_plan,
                'kcal': m['kcal'], 'prot': m['prot'], 'carb': m['carb'], 'fat': m['fat'],
            }

        past_data = [_serialize_history_assignment(a, macros) for a in past_first]

        supp_assignment = (
            SupplementAssignment.objects
            .filter(client=client, coach=nutrition_coach, status='ACTIVE')
            .select_related('sheet')
            .prefetch_related('sheet__items__supplement')
            .order_by('-assigned_at')
            .first()
        )

        return render(request, 'pages/nutrizione/client_piani.html', {
            'active_data': active_data,
            'past_data_json': json.dumps(past_data),
            'past_total': past_total,
            'past_initial_count': len(past_data),
            'past_has_more': past_total > len(past_data),
            'history_page_size': NUTRITION_HISTORY_PAGE_SIZE,
            'coach': nutrition_coach,
            'supp_assignment': supp_assignment,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plans = (
        coach.nutrition_plans
        .select_related('folder')
        .prefetch_related('meals__items__food', 'days')
        .annotate(assigned_count=Count('assignments'))
        .order_by('-updated_at')
    )

    active_assignments = (
        NutritionAssignment.objects
        .filter(coach=coach, status='ACTIVE')
        .values_list('nutrition_plan_id', 'client_id')
    )
    assigned_map: dict[int, list[int]] = {}
    for plan_id, client_id in active_assignments:
        assigned_map.setdefault(plan_id, []).append(client_id)

    plans_payload = []
    for plan in plans:
        if plan.plan_mode == 'MACRO':
            avg = _plan_macro_targets(plan)['avg']
            total_kcal, total_prot, total_carb, total_fat = (
                avg['kcal'], avg['prot'], avg['carb'], avg['fat'],
            )
        else:
            total_kcal = total_prot = total_carb = total_fat = 0
            for meal in plan.meals.all():
                for item in meal.items.all():
                    total_kcal += item.kcal
                    total_prot += item.protein
                    total_carb += item.carbs
                    total_fat += item.fat
        plans_payload.append({
            'id': plan.id,
            'title': plan.title,
            'description': plan.description or '',
            'plan_type': plan.plan_type or '',
            'plan_kind': plan.plan_kind,
            'plan_mode': plan.plan_mode,
            'status': plan.status or '',
            'is_template': plan.is_template,
            'folder_id': plan.folder_id,
            'kcal': round(total_kcal),
            'prot': round(total_prot),
            'carb': round(total_carb),
            'fat': round(total_fat),
            'assigned_count': plan.assigned_count,
            'assigned_client_ids': assigned_map.get(plan.id, []),
            'updated_at': plan.updated_at.isoformat() if plan.updated_at else '',
        })

    folders = list(
        NutritionFolder.objects.filter(coach=coach)
        .annotate(plan_count=Count('plans'))
        .order_by('order', 'title')
    )
    folders_payload = [
        {
            'id': f.id,
            'title': f.title,
            'label_text': f.label_text or '',
            'label_color': f.label_color or '',
            'order': f.order,
            'plan_count': f.plan_count,
        }
        for f in folders
    ]

    clients = (
        ClientProfile.objects.filter(
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
        for c in clients
    ])

    return render(request, 'pages/nutrizione/piani_list.html', {
        'plans_json': json.dumps(plans_payload),
        'folders_json': json.dumps(folders_payload),
        'clients_json': clients_json,
    })


def nutrizione_piano_create_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    if request.method == 'POST':
        return _handle_plan_save(request, coach, plan=None)

    clients = (
        ClientProfile.objects.filter(
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
        for c in clients
    ])

    initial_folder_id = request.GET.get('folder_id')
    try:
        initial_folder_id = int(initial_folder_id) if initial_folder_id else None
    except (TypeError, ValueError):
        initial_folder_id = None
    if initial_folder_id and not NutritionFolder.objects.filter(id=initial_folder_id, coach=coach).exists():
        initial_folder_id = None

    kind = (request.GET.get('kind') or 'DAILY').upper()
    if kind not in ('DAILY', 'WEEKLY'):
        kind = 'DAILY'

    mode = (request.GET.get('mode') or 'FOOD').upper()
    if mode not in ('FOOD', 'MACRO'):
        mode = 'FOOD'

    folders = NutritionFolder.objects.filter(coach=coach).order_by('order', 'id').values('id', 'title')
    folders_json = json.dumps(list(folders))

    return render(request, 'pages/nutrizione/piano_create.html', {
        'clients_json': clients_json,
        'plan': None,
        'meals_json': '[]',
        'initial_folder_id': initial_folder_id,
        'plan_kind': kind,
        'plan_mode': mode,
        'day_targets_json': '[]',
        'folders_json': folders_json,
        'supplements_json': '{"items": [], "notes": ""}',
    })


def nutrizione_piano_edit_view(request, plan_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)

    if request.method == 'POST':
        return _handle_plan_save(request, coach, plan=plan)

    clients = (
        ClientProfile.objects.filter(
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
        for c in clients
    ])

    REVERSE_WEEKDAY = {'MONDAY': 'LUN', 'TUESDAY': 'MAR', 'WEDNESDAY': 'MER',
                       'THURSDAY': 'GIO', 'FRIDAY': 'VEN', 'SATURDAY': 'SAB', 'SUNDAY': 'DOM'}

    meals_data = []
    meals_qs = (
        plan.meals
        .select_related('day')
        .prefetch_related('items__food', 'items__substitutions__food')
        .all()
    )
    for meal in meals_qs:
        items_data = []
        for item in meal.items.all():
            if not item.food:
                continue
            subs_data = []
            for sub in item.substitutions.all():
                subs_data.append({
                    'food_id': sub.food_id,
                    'food_name': sub.food.nome_alimento,
                    'mode': sub.mode,
                    'quantity_g': sub.quantity_g,
                    'kcal_per_100g': sub.food.energia_kcal,
                    'protein_per_100g': sub.food.proteine_g,
                    'carb_per_100g': sub.food.carboidrati_g,
                    'fat_per_100g': sub.food.lipidi_g,
                })
            items_data.append({
                'food_id': item.food_id,
                'food_name': item.food.nome_alimento,
                'quantity_g': item.quantity_g,
                'kcal_per_100g': item.food.energia_kcal,
                'protein_per_100g': item.food.proteine_g,
                'carb_per_100g': item.food.carboidrati_g,
                'fat_per_100g': item.food.lipidi_g,
                'fiber_per_100g': item.food.fibra_g,
                'sat_fat_per_100g': item.food.lipidi_saturi_g,
                'cholesterol_per_100g': item.food.colesterolo_mg,
                'sugars_per_100g': item.food.carboidrati_solubili_g,
                'iron_per_100g': item.food.fe_mg,
                'calcium_per_100g': item.food.ca_mg,
                'sodium_per_100g': item.food.na_mg,
                'potassium_per_100g': item.food.k_mg,
                'phosphorus_per_100g': item.food.p_mg,
                'zinc_per_100g': item.food.zn_mg,
                'magnesium_per_100g': item.food.mg_mg,
                'copper_per_100g': item.food.cu_mg,
                'selenium_per_100g': item.food.se_ug,
                'iodine_per_100g': item.food.i_ug,
                'manganese_per_100g': item.food.mn_mg,
                'vit_b1_per_100g': item.food.vit_b1_mg,
                'vit_b2_per_100g': item.food.vit_b2_mg,
                'vit_c_per_100g': item.food.vit_c_mg,
                'niacin_per_100g': item.food.niacina_mg,
                'vit_b6_per_100g': item.food.vit_b6_mg,
                'folate_per_100g': item.food.folati_ug,
                'vit_b12_per_100g': item.food.vit_b12_ug,
                'isoleucine_per_100g': item.food.isoleucina_mg,
                'leucine_per_100g': item.food.leucina_mg,
                'valine_per_100g': item.food.valina_mg,
                'lactose_per_100g': item.food.lattosio_g,
                'notes': item.notes or '',
                'substitutions': subs_data,
            })
        day_code = REVERSE_WEEKDAY.get(meal.day.day_of_week) if meal.day else None
        meals_data.append({
            'name': meal.name,
            'time_of_day': meal.time_of_day or '',
            'notes': meal.notes or '',
            'day_of_week': day_code,
            'items': items_data,
        })

    folders = NutritionFolder.objects.filter(coach=coach).order_by('order', 'id').values('id', 'title')
    folders_json = json.dumps(list(folders))

    plan_kind = getattr(plan, 'plan_kind', None) or 'DAILY'
    plan_mode = getattr(plan, 'plan_mode', None) or 'FOOD'

    day_targets_data = []
    if plan_mode == 'MACRO' and plan_kind == 'WEEKLY':
        for d in plan.days.all():
            day_targets_data.append({
                'day_of_week': WEEKDAY_REVERSE.get(d.day_of_week, d.day_of_week),
                'kcal': d.target_kcal,
                'protein': d.target_protein_g,
                'carb': d.target_carb_g,
                'fat': d.target_fat_g,
            })

    supplements_data = {'items': [], 'notes': ''}
    sheet = plan.supplement_sheet
    if sheet:
        supplements_data['notes'] = sheet.notes or ''
        for it in sheet.items.select_related('supplement').order_by('order'):
            supplements_data['items'].append({
                'supplement_id': it.supplement_id,
                'supplement_name': it.supplement.name,
                'dose': it.dose,
                'timing': it.timing or '',
                'notes': it.notes or '',
            })

    return render(request, 'pages/nutrizione/piano_create.html', {
        'clients_json': clients_json,
        'plan': plan,
        'meals_json': json.dumps(meals_data),
        'plan_kind': plan_kind,
        'plan_mode': plan_mode,
        'day_targets_json': json.dumps(day_targets_data),
        'folders_json': folders_json,
        'supplements_json': json.dumps(supplements_data),
    })


def nutrizione_piano_detail_view(request, plan_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    meals = plan.meals.prefetch_related('items__food', 'items__substitutions__food').all()

    include_subs = bool(plan.include_substitutions_in_avg)
    total_kcal = total_prot = total_carb = total_fat = total_fiber = 0
    meals_detail = []
    for meal in meals:
        m_kcal = m_prot = m_carb = m_fat = 0
        items = []
        for item in meal.items.all():
            subs = list(item.substitutions.all())
            n = 1 + len(subs)
            if include_subs and subs:
                i_kcal = (item.kcal + sum(s.kcal for s in subs)) / n
                i_prot = (item.protein + sum(s.protein for s in subs)) / n
                i_carb = (item.carbs + sum(s.carbs for s in subs)) / n
                i_fat = (item.fat + sum(s.fat for s in subs)) / n
            else:
                i_kcal, i_prot, i_carb, i_fat = item.kcal, item.protein, item.carbs, item.fat
            m_kcal += i_kcal
            m_prot += i_prot
            m_carb += i_carb
            m_fat += i_fat
            items.append(item)
        total_kcal += m_kcal
        total_prot += m_prot
        total_carb += m_carb
        total_fat += m_fat
        total_fiber += sum(item.fiber for item in items)
        meals_detail.append({
            'meal': meal,
            'items': items,
            'kcal': round(m_kcal),
            'prot': round(m_prot),
            'carb': round(m_carb),
            'fat': round(m_fat),
        })

    assignments = (
        NutritionAssignment.objects
        .filter(nutrition_plan=plan)
        .select_related('client__user')
        .order_by('-assigned_at')
    )

    already_assigned_ids = set(
        NutritionAssignment.objects
        .filter(nutrition_plan=plan, status='ACTIVE')
        .values_list('client_id', flat=True)
    )

    clients = (
        ClientProfile.objects.filter(
            coaching_relationships_as_client__coach=coach,
            coaching_relationships_as_client__status='ACTIVE'
        ).select_related('user')
    )
    assignable_clients = [c for c in clients if c.id not in already_assigned_ids]
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
        for c in assignable_clients
    ])

    macro_targets = _plan_macro_targets(plan) if plan.plan_mode == 'MACRO' else None

    return render(request, 'pages/nutrizione/piano_detail.html', {
        'plan': plan,
        'meals_detail': meals_detail,
        'total_kcal': round(total_kcal),
        'total_prot': round(total_prot),
        'total_carb': round(total_carb),
        'total_fat': round(total_fat),
        'total_fiber': round(total_fiber),
        'assignments': assignments,
        'clients_json': clients_json,
        'assignments_count': assignments.count(),
        'macro_targets': macro_targets,
    })


@require_http_methods(["POST"])
def nutrizione_piano_delete_view(request, plan_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)

    # Atleti con il piano assegnato: avvisali in chat dopo l'eliminazione.
    from domain.chat.services import send_plan_deleted_message
    client_ids = list(plan.assignments.values_list('client_id', flat=True).distinct())
    clients = list(ClientProfile.objects.filter(id__in=client_ids))

    with transaction.atomic():
        plan.delete()
        transaction.on_commit(lambda: [send_plan_deleted_message(coach, c) for c in clients])

    return JsonResponse({'ok': True})


def nutrizione_piano_duplicate_view(request, plan_id):
    """Deep-copy a nutrition plan (days → meals → items → substitutions) into a
    new DRAFT owned by the same coach. Supplement sheet link is OneToOne, so the
    copy starts without one. Returns the new plan id for client-side redirect."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    if request.method != 'POST':
        return JsonResponse({'error': 'Metodo non consentito'}, status=405)

    source = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)

    with transaction.atomic():
        new_plan = NutritionPlan.objects.create(
            coach=coach,
            title=f"{source.title} (copia)",
            description=source.description,
            plan_type=source.plan_type,
            plan_kind=source.plan_kind,
            plan_mode=source.plan_mode,
            nutrition_goal=source.nutrition_goal,
            daily_kcal=source.daily_kcal,
            protein_target_g=source.protein_target_g,
            carb_target_g=source.carb_target_g,
            fat_target_g=source.fat_target_g,
            meals_per_day=source.meals_per_day,
            status='DRAFT',
            is_template=False,
            include_substitutions_in_avg=source.include_substitutions_in_avg,
            folder=source.folder,
        )

        # Days first, so meals can be re-pointed to the copied day.
        day_map = {}
        for src_day in source.days.all():
            new_day = DietDay.objects.create(
                plan=new_plan,
                day_of_week=src_day.day_of_week,
                order=src_day.order,
                notes=src_day.notes,
                target_kcal=src_day.target_kcal,
                target_protein_g=src_day.target_protein_g,
                target_carb_g=src_day.target_carb_g,
                target_fat_g=src_day.target_fat_g,
            )
            day_map[src_day.id] = new_day

        for src_meal in source.meals.all().prefetch_related('items__substitutions'):
            new_meal = Meal.objects.create(
                plan=new_plan,
                day=day_map.get(src_meal.day_id) if src_meal.day_id else None,
                name=src_meal.name,
                order=src_meal.order,
                time_of_day=src_meal.time_of_day,
                notes=src_meal.notes,
            )
            for src_item in src_meal.items.all():
                new_item = MealItem.objects.create(
                    meal=new_meal,
                    food=src_item.food,
                    quantity_g=src_item.quantity_g,
                    notes=src_item.notes,
                    uncertain=src_item.uncertain,
                    raw_name=src_item.raw_name,
                )
                for src_sub in src_item.substitutions.all():
                    MealItemSubstitution.objects.create(
                        item=new_item,
                        food=src_sub.food,
                        mode=src_sub.mode,
                        quantity_g=src_sub.quantity_g,
                        order=src_sub.order,
                    )

    return JsonResponse({'ok': True, 'id': new_plan.id})


# ─── API: Wizard CRUD (Sezione 9.3) ──────────────────────────────────────────────

def _require_coach_json(request):
    user = get_session_user(request)
    if not user:
        return None, JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return None, JsonResponse({'error': 'Non autorizzato'}, status=403)
    return coach, None


def _meal_json(meal):
    return {
        'id': meal.id,
        'name': meal.name,
        'order': meal.order,
        'time_of_day': meal.time_of_day or '',
        'notes': meal.notes or '',
        'day_of_week': meal.day.day_of_week if meal.day_id else None,
    }


def _item_json(item):
    food = item.food
    return {
        'id': item.id,
        'meal_id': item.meal_id,
        'food_id': item.food_id,
        'food_name': food.nome_alimento if food else (item.raw_name or ''),
        'quantity_g': item.quantity_g,
        'kcal_per_100g': food.energia_kcal if food else 0,
        'protein_per_100g': food.proteine_g if food else 0,
        'carb_per_100g': food.carboidrati_g if food else 0,
        'fat_per_100g': food.lipidi_g if food else 0,
        'fiber_per_100g': food.fibra_g if food else 0,
        'sat_fat_per_100g': food.lipidi_saturi_g if food else 0,
        'cholesterol_per_100g': food.colesterolo_mg if food else 0,
        'sugars_per_100g': food.carboidrati_solubili_g if food else 0,
        'iron_per_100g': food.fe_mg if food else 0,
        'calcium_per_100g': food.ca_mg if food else 0,
        'sodium_per_100g': food.na_mg if food else 0,
        'potassium_per_100g': food.k_mg if food else 0,
        'phosphorus_per_100g': food.p_mg if food else 0,
        'zinc_per_100g': food.zn_mg if food else 0,
        'magnesium_per_100g': food.mg_mg if food else 0,
        'copper_per_100g': food.cu_mg if food else 0,
        'selenium_per_100g': food.se_ug if food else 0,
        'iodine_per_100g': food.i_ug if food else 0,
        'manganese_per_100g': food.mn_mg if food else 0,
        'vit_b1_per_100g': food.vit_b1_mg if food else 0,
        'vit_b2_per_100g': food.vit_b2_mg if food else 0,
        'vit_c_per_100g': food.vit_c_mg if food else 0,
        'niacin_per_100g': food.niacina_mg if food else 0,
        'vit_b6_per_100g': food.vit_b6_mg if food else 0,
        'folate_per_100g': food.folati_ug if food else 0,
        'vit_b12_per_100g': food.vit_b12_ug if food else 0,
        'isoleucine_per_100g': food.isoleucina_mg if food else 0,
        'leucine_per_100g': food.leucina_mg if food else 0,
        'valine_per_100g': food.valina_mg if food else 0,
        'lactose_per_100g': food.lattosio_g if food else 0,
        'notes': item.notes or '',
    }


@require_http_methods(["PATCH"])
def api_plan_patch(request, plan_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    if 'plan_kind' in data:
        incoming = (data.get('plan_kind') or '').upper()
        if incoming and incoming != plan.plan_kind:
            return JsonResponse({'error': 'plan_kind non modificabile'}, status=400)

    editable = {
        'title': str, 'description': str, 'plan_type': str, 'nutrition_goal': str,
        'status': str, 'daily_kcal': int, 'protein_target_g': int,
        'carb_target_g': int, 'fat_target_g': int, 'is_template': bool,
    }
    for field, cast in editable.items():
        if field not in data:
            continue
        value = data[field]
        if value in ('', None) and cast in (int,):
            setattr(plan, field, None)
        else:
            try:
                setattr(plan, field, cast(value) if cast is not bool else bool(value))
            except (TypeError, ValueError):
                return JsonResponse({'error': f'{field} non valido'}, status=400)

    if 'folder_id' in data:
        fid = data.get('folder_id')
        if fid in (None, '', 0):
            plan.folder = None
        else:
            try:
                plan.folder = NutritionFolder.objects.get(id=int(fid), coach=coach)
            except (NutritionFolder.DoesNotExist, ValueError, TypeError):
                plan.folder = None

    plan.save()
    return JsonResponse({
        'ok': True, 'id': plan.id, 'plan_kind': plan.plan_kind,
        'status': plan.status, 'is_template': plan.is_template,
    })


@require_http_methods(["POST"])
def api_plan_meal_create(request, plan_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    name = (data.get('name') or '').strip() or 'Pasto'
    time_of_day = (data.get('time_of_day') or '').strip() or None
    notes = (data.get('notes') or '').strip() or None

    day_obj = None
    if plan.plan_kind == 'WEEKLY':
        day_code = _normalize_weekday(data.get('day_of_week'))
        if not day_code:
            return JsonResponse({'error': 'day_of_week obbligatorio per piani settimanali'}, status=400)
        day_obj, _ = DietDay.objects.get_or_create(
            plan=plan, day_of_week=day_code,
            defaults={'order': WEEKDAY_ORDER.get(day_code, 0)},
        )

    next_order = (plan.meals.filter(day=day_obj).count()
                  if plan.plan_kind == 'WEEKLY'
                  else plan.meals.count())

    meal = Meal.objects.create(
        plan=plan, day=day_obj, name=name, order=next_order,
        time_of_day=time_of_day, notes=notes,
    )
    return JsonResponse(_meal_json(meal), status=201)


@require_http_methods(["PATCH", "DELETE"])
def api_meal_detail(request, meal_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    meal = get_object_or_404(Meal, id=meal_id, plan__coach=coach)

    if request.method == 'DELETE':
        meal.delete()
        return JsonResponse({'ok': True})

    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    if 'name' in data:
        meal.name = (data.get('name') or '').strip() or meal.name
    if 'time_of_day' in data:
        meal.time_of_day = (data.get('time_of_day') or '').strip() or None
    if 'notes' in data:
        meal.notes = (data.get('notes') or '').strip() or None
    if 'order' in data:
        try:
            meal.order = int(data.get('order'))
        except (TypeError, ValueError):
            return JsonResponse({'error': 'order non valido'}, status=400)

    meal.save()
    return JsonResponse(_meal_json(meal))


@require_http_methods(["POST"])
def api_meal_item_create(request, meal_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    meal = get_object_or_404(Meal, id=meal_id, plan__coach=coach)
    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    food_id = data.get('food_id')
    qty = data.get('quantity_g')
    if not food_id or not qty:
        return JsonResponse({'error': 'food_id e quantity_g obbligatori'}, status=400)
    try:
        food = Food.objects.get(id=int(food_id))
    except (Food.DoesNotExist, ValueError, TypeError):
        return JsonResponse({'error': 'Alimento non trovato'}, status=404)

    item = MealItem.objects.create(
        meal=meal, food=food,
        quantity_g=float(qty),
        notes=(data.get('notes') or '').strip() or None,
    )
    return JsonResponse(_item_json(item), status=201)


@require_http_methods(["PATCH", "DELETE"])
def api_meal_item_detail(request, item_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    item = get_object_or_404(MealItem, id=item_id, meal__plan__coach=coach)

    if request.method == 'DELETE':
        item.delete()
        return JsonResponse({'ok': True})

    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    if 'quantity_g' in data:
        try:
            item.quantity_g = float(data.get('quantity_g'))
        except (TypeError, ValueError):
            return JsonResponse({'error': 'quantity_g non valido'}, status=400)
    if 'notes' in data:
        item.notes = (data.get('notes') or '').strip() or None

    item.save()
    return JsonResponse(_item_json(item))


@require_http_methods(["POST"])
def api_plan_copy_day(request, plan_id, dest_day, src_day):
    coach, err = _require_coach_json(request)
    if err:
        return err
    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    if plan.plan_kind != 'WEEKLY':
        return JsonResponse({'error': 'Solo piani settimanali'}, status=400)

    src_code = _normalize_weekday(src_day)
    dest_code = _normalize_weekday(dest_day)
    if not src_code or not dest_code or src_code == dest_code:
        return JsonResponse({'error': 'Giorni non validi'}, status=400)

    try:
        body = json.loads(request.body or '{}')
    except ValueError:
        body = {}
    mode = (body.get('mode') or 'append').lower()
    if mode not in ('append', 'replace'):
        return JsonResponse({'error': 'mode deve essere append o replace'}, status=400)

    try:
        src_day_obj = plan.days.get(day_of_week=src_code)
    except DietDay.DoesNotExist:
        return JsonResponse({'error': 'Giorno sorgente vuoto'}, status=404)

    dest_day_obj, _ = DietDay.objects.get_or_create(
        plan=plan, day_of_week=dest_code,
        defaults={'order': WEEKDAY_ORDER.get(dest_code, 0)},
    )

    with transaction.atomic():
        if mode == 'replace':
            Meal.objects.filter(plan=plan, day=dest_day_obj).delete()
            offset = 0
        else:
            offset = Meal.objects.filter(plan=plan, day=dest_day_obj).count()

        created_meals = []
        src_meals = src_day_obj.meals.prefetch_related('items').order_by('order')
        for i, src_meal in enumerate(src_meals):
            new_meal = Meal.objects.create(
                plan=plan, day=dest_day_obj,
                name=src_meal.name,
                order=offset + i,
                time_of_day=src_meal.time_of_day,
                notes=src_meal.notes,
            )
            for src_item in src_meal.items.all():
                MealItem.objects.create(
                    meal=new_meal,
                    food=src_item.food,
                    quantity_g=src_item.quantity_g,
                    notes=src_item.notes,
                )
            created_meals.append(_meal_json(new_meal))

    return JsonResponse({'ok': True, 'meals': created_meals}, status=201)


@require_http_methods(["PUT"])
def api_plan_supplements(request, plan_id):
    coach, err = _require_coach_json(request)
    if err:
        return err
    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    try:
        data = json.loads(request.body or '{}')
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    items_raw = data.get('items') or []
    notes = data.get('notes') or ''

    with transaction.atomic():
        if not items_raw:
            sheet = plan.supplement_sheet
            if sheet and not sheet.assignments.exists():
                plan.supplement_sheet = None
                plan.save(update_fields=['supplement_sheet'])
                sheet.delete()
            elif sheet:
                plan.supplement_sheet = None
                plan.save(update_fields=['supplement_sheet'])
            return JsonResponse({'ok': True, 'sheet': None})

        sheet = plan.supplement_sheet
        if sheet is None:
            sheet = SupplementSheet.objects.create(
                coach=coach,
                title=f'Integrazione · {plan.title}'[:200],
                notes=notes,
            )
            plan.supplement_sheet = sheet
            plan.save(update_fields=['supplement_sheet'])
        else:
            sheet.notes = notes
            sheet.save(update_fields=['notes', 'updated_at'])
            sheet.items.all().delete()

        for order, raw in enumerate(items_raw):
            sup_id = raw.get('supplement_id')
            if not sup_id:
                continue
            try:
                supplement = Supplement.objects.get(id=int(sup_id))
            except (Supplement.DoesNotExist, ValueError, TypeError):
                continue
            SupplementSheetItem.objects.create(
                sheet=sheet,
                supplement=supplement,
                dose=(raw.get('dose') or '').strip(),
                timing=(raw.get('timing') or '').strip() or None,
                notes=(raw.get('notes') or '').strip() or None,
                order=order,
            )

    return JsonResponse({
        'ok': True,
        'sheet': {
            'id': sheet.id, 'title': sheet.title, 'notes': sheet.notes or '',
            'items': [
                {
                    'id': it.id, 'supplement_id': it.supplement_id,
                    'supplement_name': it.supplement.name,
                    'dose': it.dose, 'timing': it.timing or '',
                    'notes': it.notes or '', 'order': it.order,
                }
                for it in sheet.items.select_related('supplement').order_by('order')
            ],
        },
    })


# ─── API ────────────────────────────────────────────────────────────────────────

def api_food_search(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    q = request.GET.get('q', '').strip()
    category = request.GET.get('cat', '').strip()

    food_search_mode = (user.email_prefs or {}).get('food_search_mode', 'alimento')
    foods = Food.objects.all()
    if food_search_mode == 'media':
        foods = foods.filter(nome_alimento__icontains='media')
    else:
        foods = foods.exclude(nome_alimento__icontains='media')
    if q:
        foods = foods.filter(nome_alimento__icontains=q)
        # Query-dependent relevance: exact > starts-with > word-boundary > contains.
        # Tiebroken by the precomputed query-independent genericity_score (desc).
        foods = foods.annotate(relevance=Case(
            When(nome_alimento__iexact=q, then=Value(4)),
            When(nome_alimento__istartswith=q, then=Value(3)),
            When(nome_alimento__icontains=f' {q}', then=Value(2)),
            default=Value(1),
            output_field=IntegerField(),
        )).order_by('-relevance', '-genericity_score', 'nome_alimento')
    if category:
        foods = foods.filter(categoria_alimento=category)
    foods = foods[:30]

    return JsonResponse({
        'results': [
            {
                'id': f.id,
                'name': f.nome_alimento,
                'category': f.categoria_alimento or '',
                'kcal': f.energia_kcal,
                'protein': f.proteine_g,
                'carb': f.carboidrati_g,
                'fat': f.lipidi_g,
                'fiber': f.fibra_g,
                'sat_fat': f.lipidi_saturi_g,
                'cholesterol': f.colesterolo_mg,
                'sugars': f.carboidrati_solubili_g,
                'iron': f.fe_mg,
                'calcium': f.ca_mg,
                'sodium': f.na_mg,
                'potassium': f.k_mg,
                'phosphorus': f.p_mg,
                'zinc': f.zn_mg,
                'magnesium': f.mg_mg,
                'copper': f.cu_mg,
                'selenium': f.se_ug,
                'iodine': f.i_ug,
                'manganese': f.mn_mg,
                'vit_b1': f.vit_b1_mg,
                'vit_b2': f.vit_b2_mg,
                'vit_c': f.vit_c_mg,
                'niacin': f.niacina_mg,
                'vit_b6': f.vit_b6_mg,
                'folate': f.folati_ug,
                'vit_b12': f.vit_b12_ug,
                'isoleucine': f.isoleucina_mg,
                'leucine': f.leucina_mg,
                'valine': f.valina_mg,
                'lactose': f.lattosio_g,
            }
            for f in foods
        ]
    })


@require_http_methods(["POST"])
def api_piano_assign(request, plan_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    try:
        data = json.loads(request.body)
        client_id = int(data.get('client_id', 0))
        start_date = data.get('start_date') or None
        end_date = data.get('end_date') or None
        notes = data.get('notes', '')
    except (ValueError, KeyError):
        return JsonResponse({'error': 'Dati non validi'}, status=400)

    client = get_object_or_404(ClientProfile, id=client_id)
    rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
    if not rel:
        return JsonResponse({'error': 'Atleta non associato'}, status=403)

    NutritionAssignment.objects.filter(client=client, coach=coach, status='ACTIVE').update(status='CANCELLED')
    assignment = NutritionAssignment.objects.create(
        nutrition_plan=plan,
        client=client,
        coach=coach,
        start_date=start_date,
        end_date=end_date,
        status='ACTIVE',
        notes=notes,
    )
    Notification.objects.create(
        target_user=client.user,
        notification_type='NUTRITION_ASSIGNED',
        title='Nuovo piano alimentare',
        body=f'Ti è stato assegnato il piano "{plan.title}".',
        link_url=f'/nutrizione/dettaglio/{assignment.id}/',
    )
    try:
        from django.conf import settings as _settings
        plan_url = f"{_settings.SITE_URL}/nutrizione/dettaglio/{assignment.id}/"
        send_nutrition_assigned(client, coach, plan, plan_url)
    except Exception:
        pass
    return JsonResponse({'ok': True, 'assignment_id': assignment.id})


# ─── Client views ────────────────────────────────────────────────────────────────

def nutrizione_client_detail_view(request, assignment_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    client = get_session_client(request)
    if not client:
        return redirect('login')

    assignment = get_object_or_404(NutritionAssignment, id=assignment_id, client=client)
    plan = assignment.nutrition_plan

    if plan.plan_mode == 'MACRO':
        return _render_client_macro_detail(request, assignment, plan)

    meals = plan.meals.prefetch_related('items__food', 'items__substitutions__food').all()

    include_subs = bool(plan.include_substitutions_in_avg)
    total_kcal = total_prot = total_carb = total_fat = 0
    meals_detail = []
    for meal in meals:
        m_kcal = m_prot = m_carb = m_fat = 0
        items = list(meal.items.all())
        for item in items:
            subs = list(item.substitutions.all())
            n = 1 + len(subs)
            if include_subs and subs:
                m_kcal += (item.kcal + sum(s.kcal for s in subs)) / n
                m_prot += (item.protein + sum(s.protein for s in subs)) / n
                m_carb += (item.carbs + sum(s.carbs for s in subs)) / n
                m_fat += (item.fat + sum(s.fat for s in subs)) / n
            else:
                m_kcal += item.kcal
                m_prot += item.protein
                m_carb += item.carbs
                m_fat += item.fat
        total_kcal += m_kcal
        total_prot += m_prot
        total_carb += m_carb
        total_fat += m_fat
        meals_detail.append({
            'meal': meal,
            'items': items,
            'kcal': round(m_kcal),
            'prot': round(m_prot),
            'carb': round(m_carb),
            'fat': round(m_fat),
        })

    return render(request, 'pages/nutrizione/client_piano_detail.html', {
        'assignment': assignment,
        'plan': plan,
        'meals_detail': meals_detail,
        'total_kcal': round(total_kcal),
        'total_prot': round(total_prot),
        'total_carb': round(total_carb),
        'total_fat': round(total_fat),
        'include_subs': include_subs,
    })


def _macro_log_json(entry):
    food = entry.food
    return {
        'id': entry.id,
        'day_of_week': WEEKDAY_REVERSE.get(entry.day_of_week) if entry.day_of_week else None,
        'log_date': entry.log_date.isoformat() if entry.log_date else None,
        'meal_name': entry.meal_name or '',
        'food_id': entry.food_id,
        'food_name': food.nome_alimento if food else (entry.raw_name or ''),
        'category': (food.categoria_alimento or '') if food else '',
        'quantity_g': entry.quantity_g,
        'kcal_per_100g': food.energia_kcal if food else 0,
        'protein_per_100g': food.proteine_g if food else 0,
        'carb_per_100g': food.carboidrati_g if food else 0,
        'fat_per_100g': food.lipidi_g if food else 0,
    }


def _render_client_macro_detail(request, assignment, plan):
    """Client-facing view for a MACRO plan: coach targets + the client's own
    food log with live macro totals (computed front-end)."""
    today = date.today()
    targets = _plan_macro_targets(plan)
    entries = (
        assignment.macro_log
        .filter(log_date=today)
        .select_related('food')
        .all()
    )
    log_json = json.dumps([_macro_log_json(e) for e in entries])

    week_days = [
        {'code': WEEKDAY_REVERSE[c], 'day_of_week': c,
         'label': dict(DietDay.DAY_CHOICES)[c]}
        for c in WEEKDAY_ORDER
    ]

    return render(request, 'pages/nutrizione/client_piano_macro.html', {
        'assignment': assignment,
        'plan': plan,
        'targets_json': json.dumps(targets),
        'log_json': log_json,
        'week_days_json': json.dumps(week_days),
        'is_weekly': plan.plan_kind == 'WEEKLY',
        'today_str': today.isoformat(),
    })


# ─── API: Client macro food-log CRUD ──────────────────────────────────────────────

def _require_client_json(request):
    user = get_session_user(request)
    if not user:
        return None, JsonResponse({'error': 'Non autenticato'}, status=401)
    client = get_session_client(request)
    if not client:
        return None, JsonResponse({'error': 'Non autorizzato'}, status=403)
    return client, None


@require_http_methods(["POST"])
def api_macro_log_create(request, assignment_id):
    client, err = _require_client_json(request)
    if err:
        return err
    assignment = get_object_or_404(
        NutritionAssignment, id=assignment_id, client=client,
    )
    if assignment.nutrition_plan.plan_mode != 'MACRO':
        return JsonResponse({'error': 'Piano non compatibile'}, status=400)
    try:
        data = json.loads(request.body)
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    food_id = data.get('food_id')
    try:
        food = Food.objects.get(id=food_id)
    except (Food.DoesNotExist, ValueError, TypeError):
        return JsonResponse({'error': 'Alimento non trovato'}, status=400)

    try:
        qty = float(data.get('quantity_g'))
    except (TypeError, ValueError):
        return JsonResponse({'error': 'Quantità non valida'}, status=400)
    if qty <= 0:
        return JsonResponse({'error': 'La quantità deve essere positiva'}, status=400)

    day_code = None
    if assignment.nutrition_plan.plan_kind == 'WEEKLY':
        day_code = _normalize_weekday(data.get('day_of_week'))
        if not day_code:
            return JsonResponse({'error': 'Giorno non valido'}, status=400)

    meal_name = (data.get('meal_name') or '').strip()[:100] or None

    entry = ClientMacroLogEntry.objects.create(
        assignment=assignment,
        day_of_week=day_code,
        log_date=date.today(),
        food=food,
        quantity_g=qty,
        meal_name=meal_name,
    )
    return JsonResponse({'ok': True, 'entry': _macro_log_json(entry)})


@require_http_methods(["PATCH", "DELETE"])
def api_macro_log_detail(request, entry_id):
    client, err = _require_client_json(request)
    if err:
        return err
    entry = get_object_or_404(
        ClientMacroLogEntry, id=entry_id, assignment__client=client,
    )

    if entry.log_date and entry.log_date < date.today():
        return JsonResponse({'error': 'Non puoi modificare un giorno passato'}, status=403)

    if request.method == "DELETE":
        entry.delete()
        return JsonResponse({'ok': True})

    try:
        data = json.loads(request.body)
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)
    update_fields = []
    if 'quantity_g' in data:
        try:
            qty = float(data.get('quantity_g'))
        except (TypeError, ValueError):
            return JsonResponse({'error': 'Quantità non valida'}, status=400)
        if qty <= 0:
            return JsonResponse({'error': 'La quantità deve essere positiva'}, status=400)
        entry.quantity_g = qty
        update_fields.append('quantity_g')
    if 'meal_name' in data:
        entry.meal_name = (data.get('meal_name') or '').strip()[:100] or None
        update_fields.append('meal_name')
    if update_fields:
        entry.save(update_fields=update_fields + ['updated_at'])
    return JsonResponse({'ok': True, 'entry': _macro_log_json(entry)})


@require_http_methods(['GET'])
def api_macro_log_history(request, assignment_id):
    """Last 7 closed days grouped by log_date, including per-day targets."""
    client, err = _require_client_json(request)
    if err:
        return err
    assignment = get_object_or_404(
        NutritionAssignment, id=assignment_id, client=client,
    )
    if assignment.nutrition_plan.plan_mode != 'MACRO':
        return JsonResponse({'error': 'Piano non compatibile'}, status=400)

    today = date.today()
    cutoff = today - timedelta(days=7)
    entries = (
        assignment.macro_log
        .filter(log_date__isnull=False, log_date__lt=today, log_date__gte=cutoff)
        .select_related('food')
        .order_by('-log_date', 'created_at')
    )

    plan = assignment.nutrition_plan
    targets_raw = _plan_macro_targets(plan)
    day_targets_map = {}
    if plan.plan_kind == 'WEEKLY':
        for d in targets_raw.get('days', []):
            day_targets_map[d['day_of_week']] = {
                'kcal': d['kcal'] or 0,
                'prot': d['protein'] or 0,
                'carb': d['carb'] or 0,
                'fat': d['fat'] or 0,
            }

    by_date = defaultdict(list)
    for e in entries:
        by_date[e.log_date.isoformat()].append(_macro_log_json(e))

    _MONTHS_IT_SHORT = ['', 'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
                        'lug', 'ago', 'set', 'ott', 'nov', 'dic']
    _DAYS_IT_SHORT = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom']

    history = []
    for d_str, items in sorted(by_date.items(), reverse=True):
        d_obj = date.fromisoformat(d_str)
        if plan.plan_kind == 'DAILY':
            target = {
                'kcal': plan.daily_kcal or 0,
                'prot': plan.protein_target_g or 0,
                'carb': plan.carb_target_g or 0,
                'fat': plan.fat_target_g or 0,
            }
        else:
            dow = cal_lib.day_name[d_obj.weekday()].upper()
            target = day_targets_map.get(dow, {'kcal': 0, 'prot': 0, 'carb': 0, 'fat': 0})
        history.append({
            'date': d_str,
            'dow_short': _DAYS_IT_SHORT[d_obj.weekday()].upper(),
            'date_short': f"{d_obj.day} {_MONTHS_IT_SHORT[d_obj.month].upper()}",
            'entries': items,
            'target': target,
        })
    return JsonResponse({'history': history})


def macro_log_day_view(request, assignment_id, date_str):
    """Full-page detail for one closed day's macro log."""
    from django.http import Http404
    user = get_session_user(request)
    if not user:
        return redirect('login')
    client = get_session_client(request)
    if not client:
        return redirect('dashboard')

    try:
        log_date = date.fromisoformat(date_str)
    except ValueError:
        raise Http404

    if log_date >= date.today():
        raise Http404

    assignment = get_object_or_404(NutritionAssignment, id=assignment_id, client=client)
    plan = assignment.nutrition_plan
    if plan.plan_mode != 'MACRO':
        raise Http404

    entries = list(
        assignment.macro_log
        .filter(log_date=log_date)
        .select_related('food')
        .order_by('created_at')
    )
    log_json = json.dumps([_macro_log_json(e) for e in entries])

    if plan.plan_kind == 'DAILY':
        day_target = {
            'kcal': plan.daily_kcal or 0,
            'prot': plan.protein_target_g or 0,
            'carb': plan.carb_target_g or 0,
            'fat': plan.fat_target_g or 0,
        }
    else:
        dow = cal_lib.day_name[log_date.weekday()].upper()
        day_obj = plan.days.filter(day_of_week=dow).first()
        day_target = {
            'kcal': (day_obj.target_kcal or 0) if day_obj else 0,
            'prot': (day_obj.target_protein_g or 0) if day_obj else 0,
            'carb': (day_obj.target_carb_g or 0) if day_obj else 0,
            'fat': (day_obj.target_fat_g or 0) if day_obj else 0,
        }

    _MONTHS_IT = ['', 'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
                  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre']
    _DAYS_IT = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica']

    return render(request, 'pages/nutrizione/client_piano_macro_day.html', {
        'assignment': assignment,
        'plan': plan,
        'log_date': log_date,
        'date_display_day': _DAYS_IT[log_date.weekday()],
        'date_display_full': f"{log_date.day} {_MONTHS_IT[log_date.month]} {log_date.year}",
        'log_json': log_json,
        'day_target_json': json.dumps(day_target),
    })


# ─── Internal helpers ────────────────────────────────────────────────────────────

def _handle_plan_save(request, coach, plan):
    try:
        data = json.loads(request.body)
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    title = data.get('title', '').strip()
    if not title:
        return JsonResponse({'error': 'Titolo obbligatorio'}, status=400)

    meals_raw = data.get('meals', [])

    folder_obj = None
    if 'folder_id' in data:
        fid = data.get('folder_id')
        if fid not in (None, '', 0):
            try:
                folder_obj = NutritionFolder.objects.get(id=int(fid), coach=coach)
            except (NutritionFolder.DoesNotExist, ValueError, TypeError):
                folder_obj = None

    incoming_kind = (data.get('plan_kind') or '').upper()
    if incoming_kind and incoming_kind not in ('DAILY', 'WEEKLY'):
        return JsonResponse({'error': 'plan_kind non valido'}, status=400)

    incoming_mode = (data.get('plan_mode') or '').upper()
    if incoming_mode and incoming_mode not in ('FOOD', 'MACRO'):
        return JsonResponse({'error': 'plan_mode non valido'}, status=400)

    macro_labels = {
        'daily_kcal': 'Kcal',
        'protein_target_g': 'Proteine',
        'carb_target_g': 'Carboidrati',
        'fat_target_g': 'Grassi',
    }
    for field, label in macro_labels.items():
        raw = data.get(field)
        if raw in (None, '', 0):
            continue
        try:
            val = int(raw)
        except (TypeError, ValueError):
            return JsonResponse({'error': f'{label}: valore non valido'}, status=400)
        if val < 0:
            return JsonResponse({'error': f'{label}: il valore non può essere negativo'}, status=400)
        data[field] = val

    if plan is not None and incoming_kind and incoming_kind != plan.plan_kind:
        return JsonResponse(
            {'error': 'plan_kind non modificabile dopo la creazione'},
            status=400,
        )
    if plan is not None and incoming_mode and incoming_mode != plan.plan_mode:
        return JsonResponse(
            {'error': 'plan_mode non modificabile dopo la creazione'},
            status=400,
        )

    plan_mode = (plan.plan_mode if plan is not None else (incoming_mode or 'FOOD'))

    # Parse + validate per-day macro targets (WEEKLY MACRO plans only).
    parsed_day_targets = []
    if plan_mode == 'MACRO' and (incoming_kind or (plan.plan_kind if plan else 'DAILY')) == 'WEEKLY':
        for dt in (data.get('day_targets') or []):
            day_code = _normalize_weekday(dt.get('day_of_week'))
            if not day_code:
                continue
            parsed = {'day_of_week': day_code}
            for src, dst, label in (
                ('kcal', 'target_kcal', 'Kcal'),
                ('protein', 'target_protein_g', 'Proteine'),
                ('carb', 'target_carb_g', 'Carboidrati'),
                ('fat', 'target_fat_g', 'Grassi'),
            ):
                val, err = _coerce_non_negative_int(dt.get(src))
                if err:
                    return JsonResponse(
                        {'error': f'{label} ({day_code}): valore non valido o negativo'},
                        status=400,
                    )
                parsed[dst] = val
            # Skip wholly-empty days.
            if any(parsed[k] is not None for k in ('target_kcal', 'target_protein_g', 'target_carb_g', 'target_fat_g')):
                parsed_day_targets.append(parsed)

    with transaction.atomic():
        if plan is None:
            plan_kind = incoming_kind or 'DAILY'
            plan = NutritionPlan.objects.create(
                coach=coach,
                title=title,
                description=data.get('description', ''),
                plan_type=data.get('plan_type', ''),
                plan_kind=plan_kind,
                plan_mode=plan_mode,
                nutrition_goal=data.get('nutrition_goal', ''),
                daily_kcal=data.get('daily_kcal') or None,
                protein_target_g=data.get('protein_target_g') or None,
                carb_target_g=data.get('carb_target_g') or None,
                fat_target_g=data.get('fat_target_g') or None,
                meals_per_day=len(meals_raw) or None,
                status='PUBLISHED',
                is_template=data.get('is_template', False),
                include_substitutions_in_avg=bool(data.get('include_substitutions_in_avg', False)),
                folder=folder_obj,
            )
        else:
            plan.title = title
            plan.description = data.get('description', '')
            plan.plan_type = data.get('plan_type', '')
            plan.nutrition_goal = data.get('nutrition_goal', '')
            plan.daily_kcal = data.get('daily_kcal') or None
            plan.protein_target_g = data.get('protein_target_g') or None
            plan.carb_target_g = data.get('carb_target_g') or None
            plan.fat_target_g = data.get('fat_target_g') or None
            plan.meals_per_day = len(meals_raw) or None
            plan.is_template = data.get('is_template', False)
            if 'include_substitutions_in_avg' in data:
                plan.include_substitutions_in_avg = bool(data.get('include_substitutions_in_avg'))
            if 'folder_id' in data:
                plan.folder = folder_obj
            plan.save()
            plan.meals.all().delete()

        is_weekly = plan.plan_kind == 'WEEKLY'

        # ── MACRO mode: no meals, only targets ──────────────────────────────
        if plan_mode == 'MACRO':
            plan.meals.all().delete()
            if is_weekly:
                keep_codes = {p['day_of_week'] for p in parsed_day_targets}
                plan.days.exclude(day_of_week__in=keep_codes).delete()
                existing = {d.day_of_week: d for d in plan.days.all()}
                for p in parsed_day_targets:
                    day = existing.get(p['day_of_week'])
                    if day is None:
                        day = DietDay(plan=plan, day_of_week=p['day_of_week'])
                    day.order = WEEKDAY_ORDER.get(p['day_of_week'], 0)
                    day.target_kcal = p['target_kcal']
                    day.target_protein_g = p['target_protein_g']
                    day.target_carb_g = p['target_carb_g']
                    day.target_fat_g = p['target_fat_g']
                    day.save()
            else:
                plan.days.all().delete()
            return JsonResponse({
                'ok': True, 'plan_id': plan.id,
                'plan_kind': plan.plan_kind, 'plan_mode': plan.plan_mode,
            })

        # ── FOOD mode: build meals ──────────────────────────────────────────
        day_cache = {}
        if is_weekly:
            day_cache = {d.day_of_week: d for d in plan.days.all()}

        saved_meals = 0
        for meal_data in meals_raw:
            # Resolve valid food items first. A meal with no foods is never
            # persisted — we don't fill the DB with empty meals/days.
            valid_items = []
            for item_data in meal_data.get('items', []):
                food_id = item_data.get('food_id')
                qty = item_data.get('quantity_g', 0)
                if not food_id or not qty:
                    continue
                try:
                    food = Food.objects.get(id=food_id)
                except Food.DoesNotExist:
                    continue
                valid_items.append((food, float(qty), item_data))
            if not valid_items:
                continue

            day_obj = None
            if is_weekly:
                day_code = _normalize_weekday(meal_data.get('day_of_week'))
                if day_code:
                    day_obj = day_cache.get(day_code)
                    if day_obj is None:
                        day_obj = DietDay.objects.create(
                            plan=plan,
                            day_of_week=day_code,
                            order=WEEKDAY_ORDER.get(day_code, 0),
                        )
                        day_cache[day_code] = day_obj

            meal = Meal.objects.create(
                plan=plan,
                day=day_obj,
                name=meal_data.get('name', f'Pasto {saved_meals + 1}'),
                order=saved_meals,
                time_of_day=meal_data.get('time_of_day', '') or None,
                notes=meal_data.get('notes', '') or None,
            )
            saved_meals += 1
            for food, qty, item_data in valid_items:
                item = MealItem.objects.create(
                    meal=meal,
                    food=food,
                    quantity_g=qty,
                    notes=item_data.get('notes', '') or None,
                )
                for s_order, sub_data in enumerate(item_data.get('substitutions') or []):
                    s_food_id = sub_data.get('food_id')
                    s_qty = sub_data.get('quantity_g', 0)
                    s_mode = (sub_data.get('mode') or '').upper()
                    if not s_food_id or not s_qty or s_mode not in ('ISOKCAL', 'ISOPROT', 'ISOCARB'):
                        continue
                    try:
                        s_food = Food.objects.get(id=s_food_id)
                    except Food.DoesNotExist:
                        continue
                    MealItemSubstitution.objects.create(
                        item=item,
                        food=s_food,
                        mode=s_mode,
                        quantity_g=float(s_qty),
                        order=s_order,
                    )

        # Keep meals_per_day in sync with what we actually stored (empties skipped).
        if plan.meals_per_day != (saved_meals or None):
            plan.meals_per_day = saved_meals or None
            plan.save(update_fields=['meals_per_day'])

        if is_weekly:
            used_days = {m.day_id for m in plan.meals.all() if m.day_id}
            plan.days.exclude(id__in=used_days).delete()
        else:
            plan.days.all().delete()

    return JsonResponse({'ok': True, 'plan_id': plan.id, 'plan_kind': plan.plan_kind})


# ─── Supplement views ────────────────────────────────────────────────────────────

def _clients_json(coach):
    clients = ClientProfile.objects.filter(
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE'
    ).select_related('user')
    return json.dumps([
        {'id': c.id, 'name': f'{c.first_name} {c.last_name}'.strip() or c.user.email}
        for c in clients
    ])


def integratori_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    sheets = (
        coach.supplement_sheets
        .prefetch_related('items__supplement', 'assignments')
        .order_by('-created_at')
    )
    sheets_data = []
    sheets_json_data = []
    for s in sheets:
        item_count = s.items.count()
        assigned_count = s.assignments.filter(status='ACTIVE').count()
        sheets_data.append({
            'sheet': s,
            'item_count': item_count,
            'assigned_count': assigned_count,
        })
        sheets_json_data.append({
            'id': s.id,
            'title': s.title,
            'notes': s.notes or '',
            'item_count': item_count,
            'assigned_count': assigned_count,
            'updated_at': s.updated_at.strftime('%d %b') if s.updated_at else '',
            'detail_url': f'/nutrizione/integratori/{s.id}/',
            'edit_url': f'/nutrizione/integratori/{s.id}/modifica/',
        })

    return render(request, 'pages/nutrizione/integratori_list.html', {
        'sheets_data': sheets_data,
        'sheets_json': json.dumps(sheets_json_data),
        'clients_json': _clients_json(coach),
    })


def integratori_create_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    if request.method == 'POST':
        return _handle_sheet_save(request, coach, sheet=None)

    return render(request, 'pages/nutrizione/integratori_create.html', {
        'sheet': None,
        'items_json': '[]',
        'clients_json': _clients_json(coach),
    })


def integratori_edit_view(request, sheet_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    sheet = get_object_or_404(SupplementSheet, id=sheet_id, coach=coach)

    if request.method == 'POST':
        return _handle_sheet_save(request, coach, sheet=sheet)

    items_data = []
    for item in sheet.items.select_related('supplement').all():
        items_data.append({
            'supplement_id': item.supplement_id,
            'supplement_name': item.supplement.name,
            'supplement_unit': item.supplement.unit,
            'dose': item.dose,
            'timing': item.timing or '',
            'notes': item.notes or '',
        })

    return render(request, 'pages/nutrizione/integratori_create.html', {
        'sheet': sheet,
        'items_json': json.dumps(items_data),
        'clients_json': _clients_json(coach),
    })


def integratori_detail_view(request, sheet_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    sheet = get_object_or_404(SupplementSheet, id=sheet_id, coach=coach)
    items = sheet.items.select_related('supplement').all()
    assignments = sheet.assignments.filter(status='ACTIVE').select_related('client')

    return render(request, 'pages/nutrizione/integratori_detail.html', {
        'sheet': sheet,
        'items': items,
        'assignments': assignments,
        'clients_json': _clients_json(coach),
    })


def api_supplement_search(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    q = request.GET.get('q', '').strip()
    category = request.GET.get('cat', '').strip()

    supps = Supplement.objects.all()
    if q:
        supps = supps.filter(name__icontains=q)
    if category:
        supps = supps.filter(category=category)
    supps = supps[:30]

    return JsonResponse({'results': [
        {
            'id': s.id,
            'name': s.name,
            'category': s.category or '',
            'unit': s.unit,
            'description': s.description or '',
        }
        for s in supps
    ]})


@require_http_methods(["POST"])
def api_sheet_assign(request, sheet_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    sheet = get_object_or_404(SupplementSheet, id=sheet_id, coach=coach)
    try:
        data = json.loads(request.body)
        client_id = int(data.get('client_id', 0))
    except (ValueError, KeyError):
        return JsonResponse({'error': 'Dati non validi'}, status=400)

    client = get_object_or_404(ClientProfile, id=client_id)
    rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
    if not rel:
        return JsonResponse({'error': 'Atleta non associato'}, status=403)

    SupplementAssignment.objects.filter(client=client, coach=coach, status='ACTIVE').update(status='CANCELLED')
    assignment = SupplementAssignment.objects.create(
        sheet=sheet, client=client, coach=coach, status='ACTIVE',
        notes=data.get('notes', '') or None,
    )
    Notification.objects.create(
        target_user=client.user,
        notification_type='SUPPLEMENT_ASSIGNED',
        title='Nuova scheda integratori',
        body=f'Ti è stata assegnata la scheda "{sheet.name}".',
        link_url='/nutrizione/integratori/',
    )
    return JsonResponse({'ok': True, 'assignment_id': assignment.id})


@require_http_methods(["POST"])
def api_sheet_delete(request, sheet_id):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    sheet = get_object_or_404(SupplementSheet, id=sheet_id, coach=coach)
    sheet.delete()
    return JsonResponse({'ok': True})


def _handle_sheet_save(request, coach, sheet):
    try:
        data = json.loads(request.body)
    except ValueError:
        return JsonResponse({'error': 'JSON non valido'}, status=400)

    title = data.get('title', '').strip()
    if not title:
        return JsonResponse({'error': 'Titolo obbligatorio'}, status=400)

    items_raw = data.get('items', [])

    with transaction.atomic():
        if sheet is None:
            sheet = SupplementSheet.objects.create(
                coach=coach,
                title=title,
                notes=data.get('notes', '') or None,
            )
        else:
            sheet.title = title
            sheet.notes = data.get('notes', '') or None
            sheet.save()
            sheet.items.all().delete()

        for order, item_data in enumerate(items_raw):
            supp_id = item_data.get('supplement_id')
            dose = item_data.get('dose', '').strip()
            if not supp_id or not dose:
                continue
            try:
                supp = Supplement.objects.get(id=supp_id)
            except Supplement.DoesNotExist:
                continue
            SupplementSheetItem.objects.create(
                sheet=sheet,
                supplement=supp,
                dose=dose,
                timing=item_data.get('timing', '') or None,
                notes=item_data.get('notes', '') or None,
                order=order,
            )

    return JsonResponse({'ok': True, 'sheet_id': sheet.id})


# ─── Import Dieta da Excel (AI) ─────────────────────────────────────────────────

# Meal type → label IT per Meal.name salvato in DB
_MEAL_TYPE_LABELS = {
    'BREAKFAST': 'Colazione',
    'MORNING_SNACK': 'Spuntino mattutino',
    'LUNCH': 'Pranzo',
    'AFTERNOON_SNACK': 'Spuntino pomeridiano',
    'DINNER': 'Cena',
}

_VALID_DAYS = {'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'}
_VALID_MEAL_TYPES = set(_MEAL_TYPE_LABELS.keys())
_MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10 MB


def nutrizione_import_view(request):
    """Pagina SPA Alpine per l'import dieta da Excel (3 step)."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return redirect('dashboard')
    return render(request, 'pages/nutrizione/import_diet.html', {})


@require_http_methods(['POST'])
def api_diet_import_excel(request):
    """Riceve multipart {file, plan_title, client_id} → estrazione AI → JSON."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    uploaded = request.FILES.get('file')
    if not uploaded:
        return JsonResponse({'error': 'File mancante'}, status=422)
    if uploaded.size > _MAX_UPLOAD_SIZE:
        return JsonResponse({'error': 'File troppo grande (max 10MB)'}, status=422)
    name_lower = (uploaded.name or '').lower()
    if not (name_lower.endswith('.xlsx') or name_lower.endswith('.xls')):
        return JsonResponse({'error': 'Formato file non supportato (solo .xlsx/.xls)'}, status=422)

    plan_title = (request.POST.get('plan_title') or '').strip()[:200]
    client_id = request.POST.get('client_id') or ''

    # Verifica relazione coach-client (se fornito)
    client_data = None
    if client_id:
        try:
            client = ClientProfile.objects.get(id=int(client_id))
            rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
            if not rel:
                return JsonResponse({'error': 'Atleta non associato'}, status=403)
            client_data = {'id': client.id, 'name': f"{client.first_name} {client.last_name}".strip()}
        except (ValueError, ClientProfile.DoesNotExist):
            return JsonResponse({'error': 'Atleta non valido'}, status=422)

    allowed, _ = import_quota.consume(coach, import_quota.DIET)
    if not allowed:
        return import_quota.limit_response(import_quota.DIET)

    # Import locale per evitare overhead se la view non è chiamata
    from domain.nutrition.excel_importer import (
        run_import_pipeline, ExcelParseError, AIExtractionError,
    )

    try:
        file_bytes = uploaded.read()
        extracted, confidence = run_import_pipeline(file_bytes, plan_title)
    except ExcelParseError as e:
        return JsonResponse({'error': 'excel_invalid', 'detail': str(e)}, status=422)
    except AIExtractionError as e:
        return JsonResponse({'error': 'ai_failed', 'detail': str(e)}, status=500)
    except Exception as e:
        return JsonResponse({'error': 'unknown', 'detail': str(e)}, status=500)

    payload = {
        'extracted': extracted,
        'confidence': confidence.model_dump(),
        'client': client_data,
        'plan_title': plan_title or extracted.get('diet_name') or '',
    }
    status = 206 if confidence.ratio >= 0.5 else 200
    if status == 206:
        payload['warning'] = 'high_uncertainty'
    return JsonResponse(payload, status=status)


@require_http_methods(['POST'])
def api_diet_import_confirm(request):
    """Salva nel DB il JSON revisionato dal nutrizionista."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    try:
        data = json.loads(request.body)
    except (ValueError, json.JSONDecodeError):
        return JsonResponse({'error': 'Body JSON non valido'}, status=400)

    diet_json = data.get('diet_json') or {}
    plan_title = (data.get('plan_title') or diet_json.get('diet_name') or '').strip()[:200]
    notes = (data.get('notes') or '') or None
    assign_now = bool(data.get('assign_now', True))
    client_id = data.get('client_id')

    if not plan_title:
        return JsonResponse({'error': 'Titolo piano obbligatorio'}, status=400)

    client = None
    if client_id:
        try:
            client = ClientProfile.objects.get(id=int(client_id))
            rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
            if not rel:
                return JsonResponse({'error': 'Atleta non associato'}, status=403)
        except (ValueError, ClientProfile.DoesNotExist):
            return JsonResponse({'error': 'Atleta non valido'}, status=400)

    days_data = diet_json.get('days') or []
    if not days_data:
        return JsonResponse({'error': 'Nessun giorno nella dieta'}, status=400)

    valid_days = [d for d in days_data if d.get('day_of_week') in _VALID_DAYS]
    inferred_kind = 'WEEKLY' if len(valid_days) > 1 else 'DAILY'

    # Persistenza atomica
    try:
        with transaction.atomic():
            plan = NutritionPlan.objects.create(
                coach=coach,
                title=plan_title,
                description=diet_json.get('extraction_notes') or None,
                plan_kind=inferred_kind,
                status='DRAFT',
                is_template=False,
            )

            for day_idx, day in enumerate(days_data):
                dow = day.get('day_of_week')
                if dow not in _VALID_DAYS:
                    continue
                diet_day = DietDay.objects.create(
                    plan=plan,
                    day_of_week=dow,
                    order=day_idx,
                    notes=day.get('notes') or None,
                )
                for meal_idx, meal in enumerate(day.get('meals') or []):
                    mt = meal.get('meal_type')
                    if mt not in _VALID_MEAL_TYPES:
                        continue
                    meal_obj = Meal.objects.create(
                        plan=plan,
                        day=diet_day,
                        name=_MEAL_TYPE_LABELS[mt],
                        order=meal_idx,
                        notes=meal.get('notes') or None,
                    )
                    for food in (meal.get('foods') or []):
                        raw_name = (food.get('name') or '').strip()
                        if not raw_name:
                            continue
                        food_id = food.get('food_id')
                        food_obj = None
                        if food_id:
                            try:
                                food_obj = Food.objects.get(id=int(food_id))
                            except (ValueError, Food.DoesNotExist):
                                food_obj = None
                        # Quantità in grammi (conversione minimale per unit g/ml; portion/tbsp/tsp salvate as-is)
                        qty = food.get('quantity')
                        try:
                            qty_g = float(qty) if qty is not None else 0.0
                        except (TypeError, ValueError):
                            qty_g = 0.0
                        meal_item = MealItem.objects.create(
                            meal=meal_obj,
                            food=food_obj,
                            quantity_g=qty_g,
                            notes=food.get('notes') or None,
                            uncertain=bool(food.get('uncertain')) or food_obj is None,
                            raw_name=raw_name if not food_obj else None,
                        )
                        # Persisti sostituzioni: solo quelle con food_id matchato
                        for sub_idx, sub in enumerate(food.get('substitutions') or []):
                            sub_food_id = sub.get('food_id')
                            if not sub_food_id:
                                continue
                            try:
                                sub_food = Food.objects.get(id=int(sub_food_id))
                            except (ValueError, Food.DoesNotExist):
                                continue
                            try:
                                sub_qty = float(sub.get('quantity') or 0.0)
                            except (TypeError, ValueError):
                                sub_qty = 0.0
                            if sub_qty <= 0:
                                # fallback: stessa grammatura dell'item principale
                                sub_qty = qty_g
                            mode = sub.get('mode') or 'ISOKCAL'
                            if mode not in ('ISOKCAL', 'ISOPROT', 'ISOCARB'):
                                mode = 'ISOKCAL'
                            MealItemSubstitution.objects.create(
                                item=meal_item,
                                food=sub_food,
                                mode=mode,
                                quantity_g=sub_qty,
                                order=sub_idx,
                            )

            # Persisti integratori in una SupplementSheet collegata
            supplements_in = diet_json.get('supplements') or []
            valid_supps = [s for s in supplements_in if s.get('supplement_id')]
            if valid_supps:
                sheet = SupplementSheet.objects.create(
                    coach=coach,
                    title=f'Integrazione · {plan.title}'[:200],
                    notes=None,
                )
                plan.supplement_sheet = sheet
                plan.save(update_fields=['supplement_sheet'])
                for s_idx, s_in in enumerate(valid_supps):
                    try:
                        sup_obj = Supplement.objects.get(id=int(s_in.get('supplement_id')))
                    except (Supplement.DoesNotExist, ValueError, TypeError):
                        continue
                    SupplementSheetItem.objects.create(
                        sheet=sheet,
                        supplement=sup_obj,
                        dose=(s_in.get('dose') or '').strip()[:100],
                        timing=(s_in.get('timing') or '').strip() or None,
                        notes=(s_in.get('notes') or '').strip() or None,
                        order=s_idx,
                    )

            assignment_id = None
            if assign_now and client:
                # Cancella precedente assignment attivo (coerente con api_piano_assign)
                NutritionAssignment.objects.filter(
                    client=client, coach=coach, status='ACTIVE',
                ).update(status='CANCELLED')
                assignment = NutritionAssignment.objects.create(
                    nutrition_plan=plan,
                    client=client,
                    coach=coach,
                    status='ACTIVE',
                    notes=notes,
                )
                assignment_id = assignment.id
                Notification.objects.create(
                    target_user=client.user,
                    notification_type='NUTRITION_ASSIGNED',
                    title='Nuovo piano alimentare',
                    body=f'Ti è stato assegnato il piano "{plan.title}".',
                    link_url=f'/nutrizione/dettaglio/{assignment.id}/',
                )
                try:
                    from django.conf import settings as _settings
                    plan_url = f"{_settings.SITE_URL}/nutrizione/dettaglio/{assignment.id}/"
                    send_nutrition_assigned(client, coach, plan, plan_url)
                except Exception:
                    pass
    except Exception as e:
        return JsonResponse({'error': 'save_failed', 'detail': str(e)}, status=500)

    return JsonResponse({
        'ok': True,
        'plan_id': plan.id,
        'assignment_id': assignment_id,
    })


# ─── Import Dieta da PDF (AI, async con polling) ────────────────────────────────

_MAX_PDF_UPLOAD_SIZE = 20 * 1024 * 1024  # 20 MB
_PDF_JOB_TTL = 600                        # 10 min
_PDF_JOB_PREFIX = 'pdf_import:'


def _pdf_job_key(job_id: str) -> str:
    return f'{_PDF_JOB_PREFIX}{job_id}'


def _set_job(job_id: str, payload: dict) -> None:
    cache.set(_pdf_job_key(job_id), payload, _PDF_JOB_TTL)


def _get_job(job_id: str) -> dict | None:
    return cache.get(_pdf_job_key(job_id))


def nutrizione_import_pdf_view(request):
    """Pagina SPA Alpine per l'import dieta da PDF."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return redirect('dashboard')
    return render(request, 'pages/nutrizione/import_diet_pdf.html', {})


def _run_pdf_job(job_id: str, file_bytes: bytes, plan_title: str,
                 client_data: dict | None) -> None:
    """Worker eseguito in background thread. Aggiorna lo stato via cache."""
    from domain.nutrition.pdf_importer import run_pdf_pipeline
    from domain.shared.pdf import PdfParseError
    from domain.nutrition.pdf_extractor import AIExtractionError

    def progress(phase: str, percent: int) -> None:
        existing = _get_job(job_id) or {}
        existing.update({
            'status': 'running',
            'phase': phase,
            'percent': percent,
        })
        _set_job(job_id, existing)

    try:
        extracted, confidence = run_pdf_pipeline(file_bytes, plan_title, progress_cb=progress)
    except PdfParseError as e:
        msg = str(e)
        code = 'pdf_no_content' if 'non sembra contenere' in msg.lower() else 'pdf_invalid'
        _set_job(job_id, {'status': 'error', 'error_code': code, 'detail': msg})
        return
    except AIExtractionError as e:
        _set_job(job_id, {'status': 'error', 'error_code': 'ai_failed', 'detail': str(e)})
        return
    except Exception as e:
        _set_job(job_id, {'status': 'error', 'error_code': 'unknown', 'detail': str(e)})
        return

    result = {
        'extracted': extracted,
        'confidence': confidence.model_dump(),
        'document_summary': extracted.get('document_summary'),
        'client': client_data,
        'plan_title': plan_title or extracted.get('diet_name') or '',
        'warning': 'high_uncertainty' if confidence.ratio >= 0.5 else None,
    }
    _set_job(job_id, {
        'status': 'done',
        'phase': 'finalize',
        'percent': 100,
        'result': result,
    })


@require_http_methods(['POST'])
def api_diet_import_pdf(request):
    """Avvia il job di import PDF e ritorna job_id (async)."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    uploaded = request.FILES.get('file')
    if not uploaded:
        return JsonResponse({'error': 'File mancante'}, status=422)
    if uploaded.size > _MAX_PDF_UPLOAD_SIZE:
        return JsonResponse({'error': 'pdf_invalid', 'detail': 'File troppo grande (max 20MB)'}, status=422)
    name_lower = (uploaded.name or '').lower()
    if not name_lower.endswith('.pdf'):
        return JsonResponse({'error': 'pdf_invalid', 'detail': 'Formato file non supportato (solo .pdf)'}, status=422)

    plan_title = (request.POST.get('plan_title') or '').strip()[:200]
    client_id = request.POST.get('client_id') or ''

    client_data = None
    if client_id:
        try:
            client = ClientProfile.objects.get(id=int(client_id))
            rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
            if not rel:
                return JsonResponse({'error': 'Atleta non associato'}, status=403)
            client_data = {'id': client.id, 'name': f"{client.first_name} {client.last_name}".strip()}
        except (ValueError, ClientProfile.DoesNotExist):
            return JsonResponse({'error': 'Atleta non valido'}, status=422)

    allowed, _ = import_quota.consume(coach, import_quota.DIET)
    if not allowed:
        return import_quota.limit_response(import_quota.DIET)

    file_bytes = uploaded.read()
    job_id = uuid.uuid4().hex
    _set_job(job_id, {'status': 'queued', 'phase': 'analyze', 'percent': 0})

    # TODO Fase 2: sostituire threading con Celery per multi-worker.
    thread = threading.Thread(
        target=_run_pdf_job,
        args=(job_id, file_bytes, plan_title, client_data),
        daemon=True,
    )
    thread.start()

    return JsonResponse({'job_id': job_id, 'status': 'queued'}, status=202)


@require_http_methods(['GET'])
def api_diet_import_pdf_status(request):
    """Polling endpoint: ritorna stato + (se done) risultato dell'estrazione."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    coach = get_session_coach(request)
    if not coach or not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)

    job_id = request.GET.get('job_id') or ''
    if not job_id:
        return JsonResponse({'error': 'job_not_found', 'detail': 'job_id mancante'}, status=400)
    job = _get_job(job_id)
    if not job:
        return JsonResponse({'error': 'job_not_found', 'detail': 'Job scaduto o inesistente'}, status=404)

    # Esposizione campi flat per il frontend
    payload = {
        'job_id': job_id,
        'status': job.get('status'),
        'phase': job.get('phase'),
        'percent': job.get('percent', 0),
    }
    if job.get('status') == 'done':
        payload['result'] = job.get('result')
    elif job.get('status') == 'error':
        payload['error_code'] = job.get('error_code')
        payload['detail'] = job.get('detail')
    return JsonResponse(payload)



@require_http_methods(['GET'])
def api_client_nutrition_history(request):
    """Paginated past nutrition assignments for the logged-in client."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'forbidden'}, status=403)
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    nutrition_coach = get_nutrition_coach(client)
    if not nutrition_coach:
        return JsonResponse({'error': 'no_coach'}, status=404)
    try:
        offset = max(0, int(request.GET.get('offset', 0)))
        limit = min(20, max(1, int(request.GET.get('limit', NUTRITION_HISTORY_PAGE_SIZE))))
    except (TypeError, ValueError):
        offset, limit = 0, NUTRITION_HISTORY_PAGE_SIZE

    qs = (
        NutritionAssignment.objects
        .select_related('nutrition_plan')
        .filter(client=client, coach=nutrition_coach)
        .exclude(status='ACTIVE')
        .order_by('-created_at')
    )
    total = qs.count()
    page = list(qs[offset:offset + limit])
    macros = _bulk_plan_macros({a.nutrition_plan_id for a in page})
    items = [_serialize_history_assignment(a, macros) for a in page]
    return JsonResponse({
        'items': items,
        'total': total,
        'offset': offset,
        'limit': limit,
        'has_more': (offset + limit) < total,
    })
