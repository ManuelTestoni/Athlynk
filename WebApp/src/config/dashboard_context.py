"""Per-widget template-context builders for the customizable dashboard.

One builder per widget type. ``dashboard_view`` runs only the builders for
widgets actually present in the user's layout (skipping the rest is the perf
win of the customizable grid), and ``dashboard_widget_html`` runs a single
one when a widget is added live in edit mode.

Chart-heavy coach widgets (business_kpis, churn_risk, revenue_chart,
checks_volume_chart) and the athlete progress charts (training_loads,
weekly_volume) fetch their data client-side from the existing analytics /
progress endpoints — their builders return static context only.
"""

import json
from datetime import date, timedelta

from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.billing.models import SubscriptionPlan
from domain.calendar.models import Appointment
from domain.chat.models import Message, Notification
from domain.checks.models import AssignedCheckInstance, QuestionnaireResponse
from domain.nutrition.models import NutritionAssignment
from domain.workouts.models import WorkoutAssignment

from .session_utils import (
    get_session_coach, get_session_client, get_active_relationship,
)

_WEEKDAY_CODES = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY',
                  'SATURDAY', 'SUNDAY']


# --- coach builders ---------------------------------------------------------

def _coach_recent_clients(request, coach):
    return {'recent_clients': (
        ClientProfile.objects
        .filter(coaching_relationships_as_client__coach=coach)
        .distinct().order_by('-created_at')[:5]
    )}


def _coach_subscription_plans(request, coach):
    return {'subscription_plans':
            SubscriptionPlan.objects.filter(coach=coach, is_active=True)}


def _coach_pinned_athletes(request, coach, config=None):
    from .api_coach import pinned_athletes_payload
    ids = (config or {}).get('client_ids') or []
    return {
        'pinned_athletes': pinned_athletes_payload(request, coach, ids),
        'pinned_ids': ids,
    }


def _coach_agenda_today(request, coach):
    return {'agenda_appointments': (
        Appointment.objects
        .filter(coach=coach, start_datetime__date=timezone.now().date())
        .select_related('client')
        .order_by('start_datetime')
    )}


def _coach_pending_checks(request, coach):
    from .api_coach import _pending_review_qs
    return {'pending_check_rows': (
        _pending_review_qs(coach)
        .select_related('client')
        .order_by('-submitted_at')[:6]
    )}


def _coach_activity_feed(request, coach):
    return {'activity_items': (
        Notification.objects
        .filter(target_user=coach.user)
        .order_by('-created_at')[:8]
    )}


def _coach_unread_messages(request, coach):
    from .api_coach import _unread_messages_qs
    return {'unread_messages_count': _unread_messages_qs(coach).count()}


def _coach_business_kpis(request, coach):
    from domain.analytics.models import CoachBusinessMetricsDaily
    latest = (CoachBusinessMetricsDaily.objects
              .filter(coach=coach).order_by('-snapshot_date').first())
    if not latest:
        return {'business_kpis': None}
    return {'business_kpis': {
        'snapshot_date': latest.snapshot_date,
        'active_clients': latest.active_clients_count,
        'at_risk': latest.at_risk_clients_count,
        'monthly_revenue': float(latest.monthly_revenue),
        'churn_rate_30d': latest.churn_rate_30d,
    }}


def _coach_churn_risk(request, coach):
    from domain.analytics.models import RiskScoreDaily
    latest_day = (RiskScoreDaily.objects.filter(coach=coach)
                  .order_by('-snapshot_date')
                  .values_list('snapshot_date', flat=True).first())
    if not latest_day:
        return {'churn_rows': [], 'churn_snapshot': None}
    rows = (
        RiskScoreDaily.objects
        .filter(coach=coach, snapshot_date=latest_day,
                risk_class__in=['high', 'medium'])
        .select_related('client')
        .order_by('-risk_score_rule_based')[:5]
    )
    return {'churn_rows': rows, 'churn_snapshot': latest_day}


def _coach_revenue_chart(request, coach):
    from domain.analytics.models import CoachBusinessMetricsDaily
    series = list(
        CoachBusinessMetricsDaily.objects
        .filter(coach=coach).order_by('-snapshot_date')[:30]
        .values_list('snapshot_date', 'monthly_revenue')
    )[::-1]
    if len(series) < 2:
        return {'revenue_chart_json': None}
    return {'revenue_chart_json': json.dumps({
        'labels': [d.strftime('%d/%m') for d, _ in series],
        'values': [float(v) for _, v in series],
    })}


def _coach_checks_volume(request, coach):
    # Same 8-week series as GET /api/v1/coach/analytics (api_coach.analytics),
    # computed server-side because that endpoint is Bearer-only.
    today = date.today()
    labels, values = [], []
    for w in range(7, -1, -1):
        start = today - timedelta(days=today.weekday() + 7 * w)
        end = start + timedelta(days=7)
        n = QuestionnaireResponse.objects.filter(
            coach=coach, submitted_at__date__gte=start, submitted_at__date__lt=end
        ).count()
        labels.append(start.strftime('%d/%m'))
        values.append(n)
    return {'checks_volume_json': json.dumps({'labels': labels, 'values': values})}


# --- athlete builders -------------------------------------------------------

def _client_weight_trend(request, client):
    points = list(
        QuestionnaireResponse.objects
        .filter(client=client, weight_kg__isnull=False)
        .order_by('-submitted_at')
        .values_list('submitted_at', 'weight_kg')[:10]
    )
    points.reverse()
    ctx = {}
    if len(points) >= 2:
        ctx['weight_chart_json'] = json.dumps({
            'labels': [d.strftime('%d/%m') for d, _ in points],
            'values': [float(w) for _, w in points],
        })
    return ctx


def _client_next_workout(request, client):
    wa = (
        WorkoutAssignment.objects
        .filter(client=client, status='ACTIVE')
        .select_related('workout_plan')
        .prefetch_related('workout_plan__days__exercises')
        .order_by('-created_at')
        .first()
    )
    if not wa:
        return {'next_workout_day': None, 'next_workout_plan': None}
    days = list(wa.workout_plan.days.all())
    # No per-weekday mapping on WorkoutDay: rotate by ISO weekday so the
    # highlighted session advances through the plan over the week.
    day = days[date.today().weekday() % len(days)] if days else None
    return {'next_workout_plan': wa.workout_plan, 'next_workout_day': day}


def _client_next_meal(request, client):
    na = (
        NutritionAssignment.objects
        .filter(client=client, status='ACTIVE', nutrition_plan__plan_mode='FOOD')
        .select_related('nutrition_plan')
        .prefetch_related('nutrition_plan__days__meals__items__food')
        .order_by('-assigned_at')
        .first()
    )
    if not na:
        return {'next_meal': None}
    today_code = _WEEKDAY_CODES[date.today().weekday()]
    today_day = next(
        (d for d in na.nutrition_plan.days.all() if d.day_of_week == today_code),
        None,
    )
    if not today_day:
        return {'next_meal': None}
    meals = list(today_day.meals.all())
    now_hm = timezone.localtime().strftime('%H:%M')
    upcoming = next(
        (m for m in meals if (m.time_of_day or '') >= now_hm), None
    )
    return {'next_meal': upcoming or (meals[-1] if meals else None)}


def _client_coach_message(request, client):
    msg = (
        Message.objects
        .filter(conversation__client=client)
        .exclude(sender_user=client.user)
        .select_related('sender_user', 'conversation', 'conversation__coach')
        .order_by('-created_at')
        .first()
    )
    return {'coach_last_message': msg}


def _client_journey_timeline(request, client):
    rel = get_active_relationship(client)
    if not rel:
        return {'journey_events': []}
    from .views_client import _build_percorso_events
    events = _build_percorso_events(client, rel.coach, date(2000, 1, 1), date.today())
    return {'journey_events': list(reversed(events))[:6]}


def _client_checks_due(request, client):
    return {'checks_due': (
        AssignedCheckInstance.objects
        .filter(assignment__client=client, status='pending')
        .select_related('assignment', 'assignment__template')
        .order_by('due_date')[:5]
    )}


_STATIC = lambda request, owner: {}  # noqa: E731 — data arrives client-side or is static markup

_COACH_BUILDERS = {
    'recent_clients': _coach_recent_clients,
    'subscription_plans': _coach_subscription_plans,
    'pinned_athletes': _coach_pinned_athletes,
    'agenda_today': _coach_agenda_today,
    'pending_checks': _coach_pending_checks,
    'activity_feed': _coach_activity_feed,
    'unread_messages': _coach_unread_messages,
    'business_kpis': _coach_business_kpis,
    'churn_risk': _coach_churn_risk,
    'revenue_chart': _coach_revenue_chart,
    'checks_volume_chart': _coach_checks_volume,
    'quick_actions': _STATIC,
}

_CLIENT_BUILDERS = {
    'weight_trend': _client_weight_trend,
    'training_loads': _STATIC,
    'weekly_volume': _STATIC,
    'next_workout': _client_next_workout,
    'next_meal': _client_next_meal,
    'coach_message': _client_coach_message,
    'journey_timeline': _client_journey_timeline,
    'checks_due': _client_checks_due,
    'nav_shortcuts': _STATIC,
    'quick_actions': _STATIC,
}


def build_widget_context(request, user, widget_type, config=None):
    """Context dict for one widget, or None when the user's profile can't
    serve it (e.g. athlete with no coach). Always includes ``widget_type``
    and ``widget_config`` so the frame partial can render chrome."""
    base = {'widget_type': widget_type, 'widget_config': config or {}}

    if user.role == 'COACH':
        builder = _COACH_BUILDERS.get(widget_type)
        coach = get_session_coach(request)
        if builder is None or coach is None:
            return None
        if widget_type == 'pinned_athletes':
            base.update(builder(request, coach, config=config))
        else:
            base.update(builder(request, coach))
        base['is_coach'] = True
        return base

    builder = _CLIENT_BUILDERS.get(widget_type)
    client = get_session_client(request)
    if builder is None or client is None:
        return None
    base.update(builder(request, client))
    base['is_client'] = True
    return base


def build_widget_item(request, user, spec):
    """One renderable grid item: resolved size/dims, registry chrome info and
    the widget body pre-rendered to HTML (partials read plain context names,
    so rendering happens here rather than via nested {% include %})."""
    from django.template.loader import render_to_string
    from . import dashboard_widgets

    wtype = spec['type']
    ctx = build_widget_context(request, user, wtype, config=spec.get('config'))
    if ctx is None:
        return None
    entry = dashboard_widgets.WIDGET_REGISTRY[wtype]
    size, w, h = dashboard_widgets.widget_dims(wtype, spec.get('size'))
    html = render_to_string(f'partials/dashboard/_{wtype}.html', ctx, request=request)
    return {
        'id': spec.get('id') or f'wg_{wtype}',
        'type': wtype,
        'x': spec.get('x', 0), 'y': spec.get('y', 0),
        'size': size, 'w': w, 'h': h,
        'title': entry['title'], 'icon': entry['icon'],
        'sizes': list(entry['sizes'].keys()),
        'config_json': json.dumps(spec.get('config') or {}),
        'html': html,
    }


def build_dashboard_widgets(request, user, layout):
    """Renderable items for every widget in the layout, ready for the
    dashboard template loop. Widgets whose builder returns None are skipped."""
    out = []
    for spec in layout.get('widgets', []):
        item = build_widget_item(request, user, spec)
        if item is not None:
            out.append(item)
    return out
