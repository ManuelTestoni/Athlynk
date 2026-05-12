import json
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.db import transaction

from config.session_utils import get_session_user, get_session_coach, get_session_client
from domain.coaching.models import CoachingRelationship, ClientAnamnesis
from domain.chat.models import Notification
from domain.nutrition.models import (
    Food, NutritionPlan, Meal, MealItem, NutritionAssignment,
    Supplement, SupplementSheet, SupplementSheetItem, SupplementAssignment,
)
from domain.accounts.models import ClientProfile


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
        .prefetch_related('meals__items__food', 'assignments')
        .order_by('-created_at')
    )

    plans_data = []
    for plan in plans:
        total_kcal = 0
        total_prot = 0
        total_carb = 0
        total_fat = 0
        for meal in plan.meals.all():
            for item in meal.items.all():
                total_kcal += item.kcal
                total_prot += item.protein
                total_carb += item.carbs
                total_fat += item.fat

        assigned_count = plan.assignments.count()
        plans_data.append({
            'plan': plan,
            'computed_kcal': round(total_kcal),
            'computed_prot': round(total_prot),
            'computed_carb': round(total_carb),
            'computed_fat': round(total_fat),
            'assigned_count': assigned_count,
        })

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
        'plans_data': plans_data,
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

    return render(request, 'pages/nutrizione/piano_create.html', {
        'clients_json': clients_json,
        'plan': None,
        'meals_json': '[]',
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
        return JsonResponse({'error': 'Cliente non associato'}, status=403)

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
    for s in sheets:
        sheets_data.append({
            'sheet': s,
            'item_count': s.items.count(),
            'assigned_count': s.assignments.filter(status='ACTIVE').count(),
        })

    return render(request, 'pages/nutrizione/integratori_list.html', {
        'sheets_data': sheets_data,
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
        return JsonResponse({'error': 'Cliente non associato'}, status=403)

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
