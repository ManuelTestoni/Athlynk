import json
from datetime import timedelta

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

        total_clients = ClientProfile.objects.filter(coaching_relationships_as_client__coach=coach).distinct().count()
        checks_to_review = QuestionnaireResponse.objects.filter(coach=coach, status='PENDING').count()
        expiring_subscriptions = ClientSubscription.objects.filter(
            client__coaching_relationships_as_client__coach=coach,
            status='ACTIVE',
            end_date__lte=timezone.now().date() + timedelta(days=7),
        ).distinct().count()
        appointments_today = Appointment.objects.filter(
            coach=coach,
            start_datetime__date=timezone.now().date(),
        ).count()

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
            today = timezone.now().date()

            # Peso attuale + delta vs check precedente.
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

            # Sessioni di allenamento completate questa settimana (lun-oggi).
            week_start = today - timedelta(days=today.weekday())
            sessions_this_week = WorkoutSession.objects.filter(
                client=client, completed=True, started_at__date__gte=week_start,
            ).count()

            # Target kcal del piano nutrizionale attivo.
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

            # Giorni al rinnovo dell'abbonamento col coach principale.
            subscription = ClientSubscription.objects.filter(
                client=client, status='ACTIVE', subscription_plan__coach=active_relationship.coach,
            ).select_related('subscription_plan').first()
            days_to_renewal = (
                (subscription.end_date - today).days
                if subscription and subscription.end_date else None
            )

            # Sparkline: ultime rilevazioni di peso (in ordine cronologico).
            weight_points = list(
                QuestionnaireResponse.objects
                .filter(client=client, weight_kg__isnull=False)
                .order_by('-submitted_at')
                .values_list('submitted_at', 'weight_kg')[:10]
            )
            weight_points.reverse()

            context.update({
                'weight_current': weight_current,
                'weight_delta': weight_delta,
                'sessions_this_week': sessions_this_week,
                'kcal_target': kcal_target,
                'days_to_renewal': days_to_renewal,
            })
            if len(weight_points) >= 2:
                context['weight_chart_json'] = json.dumps({
                    'labels': [d.strftime('%d/%m') for d, _ in weight_points],
                    'values': [float(w) for _, w in weight_points],
                })

        return render(request, 'pages/dashboard_client.html', context)

    return redirect('login')


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
