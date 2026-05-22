import json
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.db import transaction

from config.session_utils import (
    get_session_user, get_session_coach, get_session_client, can_manage_nutrition,
)
from domain.coaching.models import CoachingRelationship, ClientAnamnesis
from domain.chat.models import Notification
from django.db.models import Count
from domain.nutrition.models import (
    Food, NutritionPlan, NutritionFolder, Meal, MealItem, NutritionAssignment, DietDay,
    Supplement, SupplementSheet, SupplementSheetItem, SupplementAssignment,
)
from domain.accounts.models import ClientProfile
from config.services.email import send_nutrition_assigned


def _get_active_relationship(client):
    return CoachingRelationship.objects.filter(client=client, status='ACTIVE').select_related('coach').first()


# ─── Coach views ────────────────────────────────────────────────────────────────

def nutrizione_piani_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')
        rel = _get_active_relationship(client)
        if not rel:
            return redirect('check_coach_directory')
        if not ClientAnamnesis.objects.filter(client=client).exists():
            return render(request, 'pages/nutrizione/no_prima_visita.html', {})

        assignments = (
            NutritionAssignment.objects
            .select_related('nutrition_plan', 'coach')
            .prefetch_related('nutrition_plan__meals__items__food')
            .filter(client=client, coach=rel.coach)
            .order_by('-created_at')
        )
        assignments_data = []
        for a in assignments:
            kcal = prot = carb = fat = 0
            for meal in a.nutrition_plan.meals.all():
                for item in meal.items.all():
                    kcal += item.kcal
                    prot += item.protein
                    carb += item.carbs
                    fat += item.fat
            assignments_data.append({
                'assignment': a,
                'kcal': round(kcal),
                'prot': round(prot),
                'carb': round(carb),
                'fat': round(fat),
            })
        supp_assignment = (
            SupplementAssignment.objects
            .filter(client=client, coach=rel.coach, status='ACTIVE')
            .select_related('sheet')
            .prefetch_related('sheet__items__supplement')
            .order_by('-assigned_at')
            .first()
        )

        return render(request, 'pages/nutrizione/client_piani.html', {
            'assignments_data': assignments_data,
            'coach': rel.coach,
            'supp_assignment': supp_assignment,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plans = (
        coach.nutrition_plans
        .select_related('folder')
        .prefetch_related('meals__items__food', 'assignments')
        .order_by('-updated_at')
    )

    active_assignments = (
        NutritionAssignment.objects
        .filter(coach=coach, status='ACTIVE')
        .values_list('nutrition_plan_id', 'client_id')
    )
    assigned_map: dict = {}
    for plan_id, client_id in active_assignments:
        assigned_map.setdefault(plan_id, []).append(client_id)

    plans_payload = []
    for plan in plans:
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
            'status': plan.status or '',
            'is_template': plan.is_template,
            'folder_id': plan.folder_id,
            'kcal': round(total_kcal),
            'prot': round(total_prot),
            'carb': round(total_carb),
            'fat': round(total_fat),
            'assigned_count': plan.assignments.count(),
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

    return render(request, 'pages/nutrizione/piano_create.html', {
        'clients_json': clients_json,
        'plan': None,
        'meals_json': '[]',
        'initial_folder_id': initial_folder_id,
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

    meals_data = []
    for meal in plan.meals.prefetch_related('items__food').all():
        items_data = []
        for item in meal.items.all():
            items_data.append({
                'food_id': item.food_id,
                'food_name': item.food.nome_alimento,
                'quantity_g': item.quantity_g,
                'kcal_per_100g': item.food.energia_kcal,
                'protein_per_100g': item.food.proteine_g,
                'carb_per_100g': item.food.carboidrati_g,
                'fat_per_100g': item.food.lipidi_g,
                'notes': item.notes or '',
            })
        meals_data.append({
            'name': meal.name,
            'time_of_day': meal.time_of_day or '',
            'notes': meal.notes or '',
            'items': items_data,
        })

    return render(request, 'pages/nutrizione/piano_create.html', {
        'clients_json': clients_json,
        'plan': plan,
        'meals_json': json.dumps(meals_data),
    })


def nutrizione_piano_detail_view(request, plan_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    plan = get_object_or_404(NutritionPlan, id=plan_id, coach=coach)
    meals = plan.meals.prefetch_related('items__food').all()

    total_kcal = total_prot = total_carb = total_fat = total_fiber = 0
    meals_detail = []
    for meal in meals:
        m_kcal = m_prot = m_carb = m_fat = 0
        items = []
        for item in meal.items.all():
            m_kcal += item.kcal
            m_prot += item.protein
            m_carb += item.carbs
            m_fat += item.fat
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
    plan.delete()
    return JsonResponse({'ok': True})


# ─── API ────────────────────────────────────────────────────────────────────────

def api_food_search(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    q = request.GET.get('q', '').strip()
    category = request.GET.get('cat', '').strip()

    foods = Food.objects.all()
    if q:
        foods = foods.filter(nome_alimento__icontains=q)
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
        body=f'Ti è stato assegnato il piano "{plan.name}".',
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
    meals = plan.meals.prefetch_related('items__food').all()

    total_kcal = total_prot = total_carb = total_fat = 0
    meals_detail = []
    for meal in meals:
        m_kcal = m_prot = m_carb = m_fat = 0
        items = list(meal.items.all())
        for item in items:
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

    with transaction.atomic():
        if plan is None:
            plan = NutritionPlan.objects.create(
                coach=coach,
                title=title,
                description=data.get('description', ''),
                plan_type=data.get('plan_type', ''),
                nutrition_goal=data.get('nutrition_goal', ''),
                daily_kcal=data.get('daily_kcal') or None,
                protein_target_g=data.get('protein_target_g') or None,
                carb_target_g=data.get('carb_target_g') or None,
                fat_target_g=data.get('fat_target_g') or None,
                meals_per_day=len(meals_raw) or None,
                status='PUBLISHED',
                is_template=data.get('is_template', False),
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
            if 'folder_id' in data:
                plan.folder = folder_obj
            plan.save()
            plan.meals.all().delete()

        for order, meal_data in enumerate(meals_raw):
            meal = Meal.objects.create(
                plan=plan,
                name=meal_data.get('name', f'Pasto {order + 1}'),
                order=order,
                time_of_day=meal_data.get('time_of_day', '') or None,
                notes=meal_data.get('notes', '') or None,
            )
            for item_data in meal_data.get('items', []):
                food_id = item_data.get('food_id')
                qty = item_data.get('quantity_g', 0)
                if not food_id or not qty:
                    continue
                try:
                    food = Food.objects.get(id=food_id)
                except Food.DoesNotExist:
                    continue
                MealItem.objects.create(
                    meal=meal,
                    food=food,
                    quantity_g=float(qty),
                    notes=item_data.get('notes', '') or None,
                )

    return JsonResponse({'ok': True, 'plan_id': plan.id})


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

    # Persistenza atomica
    try:
        with transaction.atomic():
            plan = NutritionPlan.objects.create(
                coach=coach,
                title=plan_title,
                description=diet_json.get('extraction_notes') or None,
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
                        MealItem.objects.create(
                            meal=meal_obj,
                            food=food_obj,
                            quantity_g=qty_g,
                            notes=food.get('notes') or None,
                            uncertain=bool(food.get('uncertain')) or food_obj is None,
                            raw_name=raw_name if not food_obj else None,
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
