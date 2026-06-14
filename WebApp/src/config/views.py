from datetime import timedelta

from django.shortcuts import render, redirect
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.checks.models import QuestionnaireResponse
from domain.billing.models import SubscriptionPlan, ClientSubscription
from domain.calendar.models import Appointment

from .session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship


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
