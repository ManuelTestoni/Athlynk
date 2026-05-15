from django.http import JsonResponse
from django.db.models import Q
from django.views.decorators.http import require_GET
from django.urls import reverse

from domain.accounts.models import ClientProfile
from domain.workouts.models import WorkoutPlan, WorkoutAssignment
from domain.nutrition.models import NutritionPlan, NutritionAssignment

from .session_utils import get_session_user, get_session_coach, get_session_client


@require_GET
def search_api(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthenticated'}, status=401)

    q = (request.GET.get('q') or '').strip()
    if len(q) < 2:
        return JsonResponse({'results': [], 'groups': []})

    results = []

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return JsonResponse({'error': 'Forbidden'}, status=403)

        clients = (
            ClientProfile.objects
            .filter(
                coaching_relationships_as_client__coach=coach,
                coaching_relationships_as_client__status='ACTIVE',
            )
            .filter(
                Q(first_name__icontains=q)
                | Q(last_name__icontains=q)
                | Q(user__email__icontains=q)
            )
            .distinct()[:6]
        )
        for c in clients:
            results.append({
                'type': 'client',
                'group': 'Atleti',
                'icon': 'ph ph-user',
                'label': f"{c.first_name} {c.last_name}",
                'sublabel': c.user.email,
                'url': reverse('clienti_detail', args=[c.id]),
            })

        workouts = WorkoutPlan.objects.filter(coach=coach, title__icontains=q)[:6]
        for w in workouts:
            results.append({
                'type': 'workout',
                'group': 'Allenamenti',
                'icon': 'ph ph-barbell',
                'label': w.title,
                'sublabel': w.get_status_display() if hasattr(w, 'get_status_display') else (w.status or ''),
                'url': reverse('allenamenti_plan_detail', args=[w.id]),
            })

        nutrition = NutritionPlan.objects.filter(coach=coach, title__icontains=q)[:6]
        for n in nutrition:
            results.append({
                'type': 'nutrition',
                'group': 'Nutrizione',
                'icon': 'ph ph-leaf',
                'label': n.title,
                'sublabel': n.nutrition_goal or '',
                'url': reverse('nutrizione_piano_detail', args=[n.id]),
            })

    elif user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return JsonResponse({'error': 'Forbidden'}, status=403)

        wa = (
            WorkoutAssignment.objects
            .filter(client=client, workout_plan__title__icontains=q)
            .select_related('workout_plan')[:6]
        )
        for a in wa:
            results.append({
                'type': 'workout',
                'group': 'I miei Allenamenti',
                'icon': 'ph ph-barbell',
                'label': a.workout_plan.title,
                'sublabel': a.status or '',
                'url': reverse('client_assignment_detail', args=[a.id]),
            })

        na = (
            NutritionAssignment.objects
            .filter(client=client, nutrition_plan__title__icontains=q)
            .select_related('nutrition_plan')[:6]
        )
        for a in na:
            results.append({
                'type': 'nutrition',
                'group': 'La mia Nutrizione',
                'icon': 'ph ph-leaf',
                'label': a.nutrition_plan.title,
                'sublabel': a.nutrition_plan.nutrition_goal or '',
                'url': reverse('nutrizione_client_detail', args=[a.id]),
            })

    groups_order = []
    seen = set()
    for r in results:
        if r['group'] not in seen:
            groups_order.append(r['group'])
            seen.add(r['group'])

    return JsonResponse({'results': results, 'groups': groups_order})
