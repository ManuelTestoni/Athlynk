import json
from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.db import transaction

from config.session_utils import get_session_user, get_session_coach, get_session_client
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import Food, NutritionPlan, Meal, MealItem, NutritionAssignment
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
        assignments = (
            NutritionAssignment.objects
            .select_related('nutrition_plan', 'coach')
            .filter(client=client, coach=rel.coach)
            .order_by('-created_at')
        )
        return render(request, 'pages/nutrizione/client_piani.html', {
            'nutrition_assignments': assignments,
            'coach': rel.coach,
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
            coaching_relationships__coach=coach,
            coaching_relationships__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.user.first_name} {c.user.last_name}'.strip() or c.user.email}
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
            coaching_relationships__coach=coach,
            coaching_relationships__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.user.first_name} {c.user.last_name}'.strip() or c.user.email}
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
            coaching_relationships__coach=coach,
            coaching_relationships__status='ACTIVE'
        ).select_related('user')
    )
    clients_json = json.dumps([
        {'id': c.id, 'name': f'{c.user.first_name} {c.user.last_name}'.strip() or c.user.email}
        for c in clients
    ])

    meals_data = []
    for meal in plan.meals.prefetch_related('items__food').all():
        items_data = []
        for item in meal.items.all():
            items_data.append({
                'food_id': item.food_id,
                'food_name': item.food.name,
                'quantity_g': item.quantity_g,
                'kcal_per_100g': item.food.kcal_per_100g,
                'protein_per_100g': item.food.protein_per_100g,
                'carb_per_100g': item.food.carb_per_100g,
                'fat_per_100g': item.food.fat_per_100g,
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

    return render(request, 'pages/nutrizione/piano_detail.html', {
        'plan': plan,
        'meals_detail': meals_detail,
        'total_kcal': round(total_kcal),
        'total_prot': round(total_prot),
        'total_carb': round(total_carb),
        'total_fat': round(total_fat),
        'total_fiber': round(total_fiber),
        'assignments': assignments,
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
        foods = foods.filter(name__icontains=q)
    if category:
        foods = foods.filter(category=category)
    foods = foods[:30]

    return JsonResponse({
        'results': [
            {
                'id': f.id,
                'name': f.name,
                'category': f.category or '',
                'kcal': f.kcal_per_100g,
                'protein': f.protein_per_100g,
                'carb': f.carb_per_100g,
                'fat': f.fat_per_100g,
                'fiber': f.fiber_per_100g,
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
