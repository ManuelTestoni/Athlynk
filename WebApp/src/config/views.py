import json
from datetime import timedelta

from django.core.cache import cache
from django.db import connection
from django.http import JsonResponse
from django.shortcuts import render, redirect
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.checks.models import QuestionnaireResponse
from domain.billing.models import SubscriptionPlan, ClientSubscription
from domain.calendar.models import Appointment
from domain.workouts.models import WorkoutSession
from domain.nutrition.models import NutritionAssignment

from .services import cachekeys
from .session_utils import (
    get_session_user, get_session_coach, get_session_client, get_active_relationship,
    get_nutrition_coach,
)
from .views_nutrition import _bulk_plan_macros, _plan_macro_targets


def healthz_view(request):
    """Readiness probe: confirms the app can reach the database."""
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1')
    return JsonResponse({'status': 'ok'})


def _client_dashboard_kpis(client, active_relationship):
    """Shared KPI block for the CLIENT dashboard: weight+delta, sessions this
    week, active plan's kcal target, days to subscription renewal. Used by both
    the web dashboard and the mobile `GET /api/v1/dashboard/summary` endpoint
    so the numbers always match.

    Cached 60s per client (TTL-only: the write surface — checks, sessions,
    plans, subscriptions — is too broad for event invalidation, and KPIs a
    minute stale are fine). Caching here covers both surfaces at once.
    """
    _key = cachekeys.client_dashboard(client.id)
    cached = cache.get(_key)
    if cached is not None:
        return cached

    today = timezone.now().date()

    last_two_weights = list(
        QuestionnaireResponse.objects
        .filter(client=client, weight_kg__isnull=False)
        .order_by('-submitted_at')
        .values_list('weight_kg', flat=True)[:2]
    )
    weight_current = float(last_two_weights[0]) if last_two_weights else None
    weight_delta = (
        round(float(last_two_weights[0]) - float(last_two_weights[1]), 1)
        if len(last_two_weights) == 2 else None
    )

    week_start = today - timedelta(days=today.weekday())
    sessions_this_week = WorkoutSession.objects.filter(
        client=client, completed=True, started_at__date__gte=week_start,
    ).count()

    kcal_target = None
    nutrition_coach = get_nutrition_coach(client)
    if nutrition_coach:
        active_assignment = (
            NutritionAssignment.objects
            .select_related('nutrition_plan')
            .filter(client=client, coach=nutrition_coach, status='ACTIVE')
            .order_by('-created_at')
            .first()
        )
        if active_assignment:
            plan = active_assignment.nutrition_plan
            if plan.plan_mode == 'MACRO':
                kcal_target = _plan_macro_targets(plan)['avg']['kcal']
            else:
                kcal_target = _bulk_plan_macros({plan.id}).get(plan.id, {}).get('kcal', 0)

    subscription = ClientSubscription.objects.filter(
        client=client, status='ACTIVE', subscription_plan__coach=active_relationship.coach,
    ).select_related('subscription_plan').first()
    days_to_renewal = (
        (subscription.end_date - today).days
        if subscription and subscription.end_date else None
    )

    kpis = {
        'weight_current': weight_current,
        'weight_delta': weight_delta,
        'sessions_this_week': sessions_this_week,
        'kcal_target': kcal_target,
        'days_to_renewal': days_to_renewal,
    }
    cache.set(_key, kpis, 60)
    return kpis


def dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')

        if request.method == 'POST':
            if 'plan_name' in request.POST:
                plan_name = request.POST.get('plan_name')
                price = request.POST.get('price')
                duration = request.POST.get('duration')

                if plan_name and price and duration:
                    SubscriptionPlan.objects.create(
                        coach=coach,
                        name=plan_name,
                        price=price,
                        duration_days=duration,
                        plan_type='RECURRING',
                        is_active=True,
                    )
                return redirect('dashboard')

        # Four aggregate COUNTs on every dashboard hit — 60s TTL keeps them
        # near-live without event invalidation (write surface too broad).
        _key = cachekeys.coach_dashboard(coach.id, 'web')
        counts = cache.get(_key)
        if counts is None:
            counts = {
                'total_clients': ClientProfile.objects.filter(coaching_relationships_as_client__coach=coach).distinct().count(),
                'checks_to_review': QuestionnaireResponse.objects.filter(coach=coach, status='PENDING').count(),
                'expiring_subscriptions': ClientSubscription.objects.filter(
                    client__coaching_relationships_as_client__coach=coach,
                    status='ACTIVE',
                    end_date__lte=timezone.now().date() + timedelta(days=7),
                ).distinct().count(),
                'appointments_today': Appointment.objects.filter(
                    coach=coach,
                    start_datetime__date=timezone.now().date(),
                ).count(),
            }
            cache.set(_key, counts, 60)
        total_clients = counts['total_clients']
        checks_to_review = counts['checks_to_review']
        expiring_subscriptions = counts['expiring_subscriptions']
        appointments_today = counts['appointments_today']

        recent_clients = ClientProfile.objects.filter(coaching_relationships_as_client__coach=coach).distinct().order_by('-created_at')[:5]
        subscription_plans = SubscriptionPlan.objects.filter(coach=coach, is_active=True)

        context = {
            'coach': coach,
            'is_coach': True,
            'total_clients': total_clients,
            'checks_to_review': checks_to_review,
            'expiring_subscriptions': expiring_subscriptions,
            'appointments_today': appointments_today,
            'recent_clients': recent_clients,
            'subscription_plans': subscription_plans,
        }
        return render(request, 'pages/dashboard.html', context)

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')

        active_relationship = get_active_relationship(client)
        context = {
            'client': client,
            'is_client': True,
            'has_coach': active_relationship is not None,
            'coach': active_relationship.coach if active_relationship else None,
        }

        if active_relationship is not None:
            context.update(_client_dashboard_kpis(client, active_relationship))

            # Sparkline: ultime rilevazioni di peso (in ordine cronologico).
            weight_points = list(
                QuestionnaireResponse.objects
                .filter(client=client, weight_kg__isnull=False)
                .order_by('-submitted_at')
                .values_list('submitted_at', 'weight_kg')[:10]
            )
            weight_points.reverse()

            if len(weight_points) >= 2:
                context['weight_chart_json'] = json.dumps({
                    'labels': [d.strftime('%d/%m') for d, _ in weight_points],
                    'values': [float(w) for _, w in weight_points],
                })

        return render(request, 'pages/dashboard_client.html', context)

    return redirect('login')


# ---------------------------------------------------------------------------
# Customizable dashboard — session-auth JSON endpoints for the web grid.
# Thin wrappers over config.dashboard_widgets (the same core the mobile
# Bearer endpoints use) so validation and cache invalidation cannot diverge
# between surfaces. CSRF enforced by Django middleware; the client attaches
# the token via static/js/csrf.js.
# ---------------------------------------------------------------------------

def dashboard_layout_api(request):
    from . import dashboard_widgets

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    if request.method == 'PUT':
        try:
            payload = json.loads(request.body.decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            return JsonResponse({'error': 'JSON non valido'}, status=400)
        try:
            layout = dashboard_widgets.validate_and_save_layout(user, payload)
        except dashboard_widgets.LayoutValidationError as e:
            return JsonResponse({'error': str(e)}, status=e.status)
    elif request.method == 'DELETE':
        layout = dashboard_widgets.reset_layout(user)
    elif request.method == 'GET':
        layout = dashboard_widgets.get_layout(user)
    else:
        return JsonResponse({'error': 'Metodo non consentito'}, status=405)

    resp = JsonResponse({
        'layout': layout,
        'catalog': dashboard_widgets.catalog_for(user),
    })
    resp['Cache-Control'] = 'no-store'
    return resp


def dashboard_widget_html(request, widget_type):
    """Server-rendered HTML fragment for one widget — used when the user adds
    a widget in edit mode, so the grid can inject real content without a full
    page reload."""
    from . import dashboard_widgets
    from .dashboard_context import build_widget_context

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    entry = dashboard_widgets.WIDGET_REGISTRY.get(widget_type)
    if not entry or user.role not in entry['roles']:
        return JsonResponse({'error': 'Widget non trovato'}, status=404)

    ctx = build_widget_context(request, user, widget_type)
    if ctx is None:
        return JsonResponse({'error': 'Widget non disponibile'}, status=404)
    resp = render(request, f'partials/dashboard/_{widget_type}.html', ctx)
    resp['Cache-Control'] = 'no-store'
    return resp


def pinned_athletes_web(request):
    """Session twin of the mobile /api/v1/coach/pinned-athletes endpoint."""
    from .api_coach import pinned_athletes_payload

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    ids = []
    for part in (request.GET.get('ids') or '').split(','):
        try:
            ids.append(int(part.strip()))
        except ValueError:
            continue
    resp = JsonResponse({'athletes': pinned_athletes_payload(request, coach, ids)})
    resp['Cache-Control'] = 'no-store'
    return resp


def coach_analytics_view(request):
    """Business analytics + churn-risk dashboard. Data is fetched client-side
    from /api/v1/coach/analytics/* (see static/js/coach_business_analytics.js)."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')
    return render(request, 'pages/analytics/business.html', {'coach': coach})
