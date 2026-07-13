"""Daily feature engineering.

``build_features_for(client, snapshot_date)`` returns a flat dict — one client's
row in the feature store. PostgreSQL is the source of truth; PostHog only fills
the two behavioural counts (`login_count_*`, `feature_usage_count_*`) when a
personal API key is configured, and falls back to DB activity proxies otherwise
so the nightly job never hard-depends on PostHog being reachable.

``build_and_store(snapshot_date)`` upserts every active client's row. It uses a
bulk-fetch path (`_build_features_bulk`) rather than calling
``build_features_for`` once per client: that per-client function issues ~20-28
queries on its own, which against a Supabase pooler means ~20-28×N queries for
the whole batch. The bulk path fetches every sub-metric for all clients in one
grouped query each (~15 total, independent of N) and does the per-client math
in memory. ``build_features_for`` stays as-is for the single-client use case
(tests, ad-hoc debugging).
"""

import logging
from collections import defaultdict
from datetime import datetime, time, timedelta

from django.db.models import Count, F, Max, Q
from django.utils import timezone

from domain.accounts.models import ClientProfile
from domain.billing.models import ClientSubscription
from domain.chat.models import Conversation, Message, Notification
from domain.checks.models import AssignedCheckInstance, QuestionnaireResponse
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import ClientMacroLogEntry, NutritionAssignment
from domain.workouts.models import WorkoutAssignment, WorkoutSession

from .identity import current_environment, resolve_flags

logger = logging.getLogger(__name__)

_FAILED_PAYMENT_STATES = {'FAILED', 'OVERDUE', 'PAST_DUE', 'UNPAID'}
_REMINDER_NOTIF_TYPES = ('MACRO_REMINDER', 'CHECK_DUE', 'CHECK_REMINDER', 'APPOINTMENT_REMINDER')


def _ref_dt(snapshot_date):
    """End-of-snapshot-day datetime, never in the future (avoids label leakage)."""
    end = timezone.make_aware(datetime.combine(snapshot_date, time.max))
    now = timezone.now()
    return min(end, now)


def _active_relationship(client):
    return (CoachingRelationship.objects
            .filter(client=client, status='ACTIVE')
            .select_related('coach')
            .order_by('-start_date').first())


def _active_subscription(client, ref_date):
    return (ClientSubscription.objects
            .filter(client=client, status='ACTIVE')
            .select_related('subscription_plan')
            .order_by('-start_date').first())


# --- activity (shared by engagement delta + login proxy) -------------------

def _activity_events(client, since_dt, until_dt):
    """Timestamps of meaningful client activity in [since, until)."""
    user = client.user
    stamps = []
    stamps += list(Message.objects.filter(
        conversation__client=client, sender_user=user,
        sent_at__gte=since_dt, sent_at__lt=until_dt,
    ).values_list('sent_at', flat=True))
    stamps += list(WorkoutSession.objects.filter(
        client=client, started_at__gte=since_dt, started_at__lt=until_dt,
    ).values_list('started_at', flat=True))
    stamps += list(ClientMacroLogEntry.objects.filter(
        assignment__client=client, created_at__gte=since_dt, created_at__lt=until_dt,
    ).values_list('created_at', flat=True))
    stamps += list(QuestionnaireResponse.objects.filter(
        client=client, submitted_at__gte=since_dt, submitted_at__lt=until_dt,
    ).values_list('submitted_at', flat=True))
    return stamps


def _distinct_active_days(stamps):
    return len({s.date() for s in stamps if s})


# --- coach service quality --------------------------------------------------

def _response_gaps_minutes(msgs, coach_user_id):
    """Gap (minutes) from each client message to the coach's next reply.

    ``msgs`` is an iterable of ``{'sender_user_id', 'sent_at'}`` ordered by
    ``sent_at``. Shared by the single-client and bulk code paths.
    """
    gaps = []
    awaiting = None  # timestamp of the first unanswered client message
    for m in msgs:
        is_coach = m['sender_user_id'] == coach_user_id
        if not is_coach:
            if awaiting is None:
                awaiting = m['sent_at']
        else:
            if awaiting is not None:
                gaps.append((m['sent_at'] - awaiting).total_seconds() / 60.0)
                awaiting = None
    return gaps


def _avg_first_response_minutes(client, since_dt, until_dt):
    """Average gap from a client message to the coach's next reply, last 30d."""
    convo = Conversation.objects.filter(client=client).first()
    if not convo:
        return None
    msgs = list(Message.objects.filter(
        conversation=convo, sent_at__gte=since_dt, sent_at__lt=until_dt,
    ).select_related('sender_user').order_by('sent_at')
        .values('sender_user_id', 'sent_at'))
    gaps = _response_gaps_minutes(msgs, convo.coach.user_id)
    if not gaps:
        return None
    return round(sum(gaps) / len(gaps), 1)


def _review_durations_seconds(rows):
    """Submission-to-feedback durations (seconds), capped to a day.

    ``rows`` is an iterable of ``{'submitted_at', 'updated_at'}``. Shared by the
    single-client and bulk code paths.
    """
    durs = []
    for r in rows:
        if r['submitted_at'] and r['updated_at']:
            d = (r['updated_at'] - r['submitted_at']).total_seconds()
            if 0 <= d <= 86400:
                durs.append(d)
    return durs


def _avg_review_duration_seconds(client, since_dt, until_dt):
    """Best-effort fallback: time from check submission to feedback being saved.

    Real review duration comes from the PostHog
    ``checkin_review_started → checkin_review_completed`` pair; this DB proxy
    only approximates it and is capped to a day to stay sane.
    """
    rows = QuestionnaireResponse.objects.filter(
        client=client, submitted_at__gte=since_dt, submitted_at__lt=until_dt,
    ).exclude(Q(coach_feedback__isnull=True) | Q(coach_feedback='')).values('submitted_at', 'updated_at')
    durs = _review_durations_seconds(rows)
    if not durs:
        return None
    return round(sum(durs) / len(durs), 1)


# --- PostHog enrichment (optional, isolated) -------------------------------

def _posthog_behaviour(client, snapshot_date):
    """Return ``{'login_count_7d','login_count_30d','feature_usage_count_7d'}``
    from PostHog HogQL, or ``None`` when disabled/unavailable. Never raises."""
    from django.conf import settings
    key = getattr(settings, 'POSTHOG_PERSONAL_API_KEY', '')
    project = getattr(settings, 'POSTHOG_PROJECT_ID', '')
    if not key or not project:
        return None
    try:
        import requests
        host = getattr(settings, 'POSTHOG_HOST', 'https://eu.i.posthog.com')
        distinct = f'client:{client.id}'
        d7 = (snapshot_date - timedelta(days=7)).isoformat()
        d30 = (snapshot_date - timedelta(days=30)).isoformat()
        end = snapshot_date.isoformat()
        hogql = (
            "SELECT "
            f"countIf(event='app_opened' AND timestamp>='{d7}' AND timestamp<'{end}'), "
            f"countIf(event='app_opened' AND timestamp>='{d30}' AND timestamp<'{end}'), "
            f"countIf(event='screen_viewed' AND timestamp>='{d7}' AND timestamp<'{end}') "
            f"FROM events WHERE distinct_id='{distinct}'"
        )
        resp = requests.post(
            f'{host}/api/projects/{project}/query/',
            headers={'Authorization': f'Bearer {key}'},
            json={'query': {'kind': 'HogQLQuery', 'query': hogql}},
            timeout=8,
        )
        row = (resp.json().get('results') or [[0, 0, 0]])[0]
        return {'login_count_7d': int(row[0]), 'login_count_30d': int(row[1]),
                'feature_usage_count_7d': int(row[2])}
    except Exception as exc:
        logger.info('PostHog enrichment skipped for client %s: %s', client.id, exc)
        return None


# --- the builder (single client) --------------------------------------------

def build_features_for(client, snapshot_date, enrich=True):
    """Compute one client's feature dict for ``snapshot_date``.

    Standalone, per-client — issues its own queries. Kept for single-client
    callers (tests, ad-hoc debugging); ``build_and_store`` uses the bulk path
    below instead of looping this, to avoid O(N) queries over all clients.
    """
    ref_dt = _ref_dt(snapshot_date)
    d7 = ref_dt - timedelta(days=7)
    d30 = ref_dt - timedelta(days=30)
    user = client.user
    flags = resolve_flags(user)

    rel = _active_relationship(client)
    coach = rel.coach if rel else None
    sub = _active_subscription(client, snapshot_date)

    # Recency
    last_login = user.last_login_at
    days_since_last_login = (ref_dt - last_login).days if last_login else None

    last_checkin = (QuestionnaireResponse.objects
                    .filter(client=client, submitted_at__isnull=False)
                    .order_by('-submitted_at').values_list('submitted_at', flat=True).first())
    days_since_last_checkin = (ref_dt - last_checkin).days if last_checkin else None

    checkins_completed_7d = AssignedCheckInstance.objects.filter(
        assignment__client=client, status='completed', due_date__gte=d7.date(), due_date__lte=ref_dt.date(),
    ).count()
    checkins_missed_30d = AssignedCheckInstance.objects.filter(
        assignment__client=client, status='expired', due_date__gte=d30.date(), due_date__lte=ref_dt.date(),
    ).count()

    messages_7d = Message.objects.filter(
        conversation__client=client, sender_user=user, sent_at__gte=d7, sent_at__lt=ref_dt,
    ).count()

    ignored_reminders_30d = Notification.objects.filter(
        target_user=user, is_read=False, notification_type__in=_REMINDER_NOTIF_TYPES,
        created_at__gte=d30, created_at__lt=ref_dt,
    ).count()

    plan_updates_30d = (
        WorkoutAssignment.objects.filter(client=client, created_at__gte=d30, created_at__lt=ref_dt).count()
        + NutritionAssignment.objects.filter(client=client, assigned_at__gte=d30, assigned_at__lt=ref_dt).count()
    )

    # Engagement delta: per-day activity rate, 7d vs 30d.
    act7 = len(_activity_events(client, d7, ref_dt))
    act30 = len(_activity_events(client, d30, ref_dt))
    rate7, rate30 = act7 / 7.0, act30 / 30.0
    engagement_delta = round(rate7 / rate30 - 1.0, 3) if rate30 > 0 else (0.0 if rate7 == 0 else None)

    # Coach service quality
    avg_response = _avg_first_response_minutes(client, d30, ref_dt)
    avg_review = _avg_review_duration_seconds(client, d30, ref_dt)

    # Commercial
    days_to_renewal = (sub.end_date - snapshot_date).days if (sub and sub.end_date) else None
    payment_failures_30d = 1 if (sub and (sub.payment_status or '').upper() in _FAILED_PAYMENT_STATES) else 0
    relationship_age_days = (snapshot_date - rel.start_date).days if (rel and rel.start_date) else None
    active_package_price = sub.subscription_plan.price if sub else None

    # Behavioural counts: PostHog if available, else DB activity-day proxy.
    behaviour = _posthog_behaviour(client, snapshot_date) if enrich else None
    if behaviour is None:
        behaviour = {
            'login_count_7d': _distinct_active_days(_activity_events(client, d7, ref_dt)),
            'login_count_30d': _distinct_active_days(_activity_events(client, d30, ref_dt)),
            'feature_usage_count_7d': act7,
        }

    return {
        'client_id': client.id,
        'coach_id': coach.id if coach else None,
        'snapshot_date': snapshot_date,
        'days_since_last_login': days_since_last_login,
        'login_count_7d': behaviour['login_count_7d'],
        'login_count_30d': behaviour['login_count_30d'],
        'days_since_last_checkin': days_since_last_checkin,
        'checkins_completed_7d': checkins_completed_7d,
        'checkins_missed_30d': checkins_missed_30d,
        'messages_7d': messages_7d,
        'ignored_reminders_30d': ignored_reminders_30d,
        'feature_usage_count_7d': behaviour['feature_usage_count_7d'],
        'plan_updates_30d': plan_updates_30d,
        'engagement_delta_7d_vs_30d': engagement_delta,
        'avg_coach_response_minutes_30d': avg_response,
        'avg_review_duration_seconds_30d': avg_review,
        'days_to_renewal': days_to_renewal,
        'payment_failures_30d': payment_failures_30d,
        'relationship_age_days': relationship_age_days,
        'active_package_price': active_package_price,
        'is_internal_user': flags['is_internal_user'],
        'is_test_account': flags['is_test_account'],
        'environment': current_environment(),
    }


# --- the builder (bulk) ------------------------------------------------------

def _build_features_bulk(clients, snapshot_date, enrich=True):
    """Bulk equivalent of calling ``build_features_for`` once per client.

    Same output values as the per-client function, but every sub-metric is
    fetched with one grouped query across all clients (``client_id__in=...``)
    instead of one query per client — ``ref_dt``/``d7``/``d30`` are the same
    for every client in a given snapshot, so a single 30d-window query per
    source model covers the whole batch; the 7d slice is a Python filter on
    the already-fetched timestamps rather than a second query.

    Returns ``{client_id: feature_dict}``. PostHog enrichment is still done
    per-client (external HTTP call behind a feature flag, not a DB query).
    """
    clients = list(clients)
    if not clients:
        return {}
    client_ids = [c.id for c in clients]
    user_id_by_client = {c.id: c.user_id for c in clients}

    ref_dt = _ref_dt(snapshot_date)
    d7 = ref_dt - timedelta(days=7)
    d30 = ref_dt - timedelta(days=30)

    # --- latest ACTIVE relationship / subscription per client ---------------
    rel_by_client = {
        r.client_id: r
        for r in (CoachingRelationship.objects
                  .filter(client_id__in=client_ids, status='ACTIVE')
                  .select_related('coach')
                  .order_by('client_id', '-start_date')
                  .distinct('client_id'))
    }
    sub_by_client = {
        s.client_id: s
        for s in (ClientSubscription.objects
                  .filter(client_id__in=client_ids, status='ACTIVE')
                  .select_related('subscription_plan')
                  .order_by('client_id', '-start_date')
                  .distinct('client_id'))
    }

    # --- recency / counts, one grouped query each ----------------------------
    last_checkin_by_client = dict(
        QuestionnaireResponse.objects.filter(client_id__in=client_ids, submitted_at__isnull=False)
        .values('client_id').annotate(last=Max('submitted_at')).values_list('client_id', 'last')
    )
    checkins_completed_by_client = dict(
        AssignedCheckInstance.objects.filter(
            assignment__client_id__in=client_ids, status='completed',
            due_date__gte=d7.date(), due_date__lte=ref_dt.date(),
        ).values('assignment__client_id').annotate(n=Count('id')).values_list('assignment__client_id', 'n')
    )
    checkins_missed_by_client = dict(
        AssignedCheckInstance.objects.filter(
            assignment__client_id__in=client_ids, status='expired',
            due_date__gte=d30.date(), due_date__lte=ref_dt.date(),
        ).values('assignment__client_id').annotate(n=Count('id')).values_list('assignment__client_id', 'n')
    )
    reminders_by_user = dict(
        Notification.objects.filter(
            target_user_id__in=list(user_id_by_client.values()), is_read=False,
            notification_type__in=_REMINDER_NOTIF_TYPES, created_at__gte=d30, created_at__lt=ref_dt,
        ).values('target_user_id').annotate(n=Count('id')).values_list('target_user_id', 'n')
    )
    workout_updates_by_client = dict(
        WorkoutAssignment.objects.filter(client_id__in=client_ids, created_at__gte=d30, created_at__lt=ref_dt)
        .values('client_id').annotate(n=Count('id')).values_list('client_id', 'n')
    )
    nutrition_updates_by_client = dict(
        NutritionAssignment.objects.filter(client_id__in=client_ids, assigned_at__gte=d30, assigned_at__lt=ref_dt)
        .values('client_id').annotate(n=Count('id')).values_list('client_id', 'n')
    )

    # --- activity: one query per source model for the full 30d window -------
    activity_by_client = defaultdict(list)
    message_stamps_by_client = defaultdict(list)  # client's own messages only (for messages_7d reuse)

    for cid, sent_at in Message.objects.filter(
        conversation__client_id__in=client_ids,
        sender_user_id=F('conversation__client__user_id'),  # only the client's own messages
        sent_at__gte=d30, sent_at__lt=ref_dt,
    ).values_list('conversation__client_id', 'sent_at'):
        activity_by_client[cid].append(sent_at)
        message_stamps_by_client[cid].append(sent_at)

    for cid, started_at in WorkoutSession.objects.filter(
        client_id__in=client_ids, started_at__gte=d30, started_at__lt=ref_dt,
    ).values_list('client_id', 'started_at'):
        activity_by_client[cid].append(started_at)

    for cid, created_at in ClientMacroLogEntry.objects.filter(
        assignment__client_id__in=client_ids, created_at__gte=d30, created_at__lt=ref_dt,
    ).values_list('assignment__client_id', 'created_at'):
        activity_by_client[cid].append(created_at)

    for cid, submitted_at in QuestionnaireResponse.objects.filter(
        client_id__in=client_ids, submitted_at__gte=d30, submitted_at__lt=ref_dt,
    ).values_list('client_id', 'submitted_at'):
        activity_by_client[cid].append(submitted_at)

    # --- coach response gap: conversations + messages, one query each -------
    coach_user_id_by_client = dict(
        Conversation.objects.filter(client_id__in=client_ids)
        .order_by('client_id', 'id').distinct('client_id')
        .values_list('client_id', 'coach__user_id')
    )
    msgs_by_client = defaultdict(list)
    for cid, sender_user_id, sent_at in Message.objects.filter(
        conversation__client_id__in=client_ids, sent_at__gte=d30, sent_at__lt=ref_dt,
    ).order_by('conversation__client_id', 'sent_at').values_list('conversation__client_id', 'sender_user_id', 'sent_at'):
        msgs_by_client[cid].append({'sender_user_id': sender_user_id, 'sent_at': sent_at})

    # --- review duration: one query -----------------------------------------
    review_rows_by_client = defaultdict(list)
    for cid, submitted_at, updated_at in QuestionnaireResponse.objects.filter(
        client_id__in=client_ids, submitted_at__gte=d30, submitted_at__lt=ref_dt,
    ).exclude(Q(coach_feedback__isnull=True) | Q(coach_feedback='')).values_list(
        'client_id', 'submitted_at', 'updated_at'
    ):
        review_rows_by_client[cid].append({'submitted_at': submitted_at, 'updated_at': updated_at})

    # --- assemble per-client dicts (pure in-memory from here) ---------------
    result = {}
    for client in clients:
        cid = client.id
        user = client.user
        flags = resolve_flags(user)

        rel = rel_by_client.get(cid)
        coach = rel.coach if rel else None
        sub = sub_by_client.get(cid)

        last_login = user.last_login_at
        days_since_last_login = (ref_dt - last_login).days if last_login else None

        last_checkin = last_checkin_by_client.get(cid)
        days_since_last_checkin = (ref_dt - last_checkin).days if last_checkin else None

        checkins_completed_7d = checkins_completed_by_client.get(cid, 0)
        checkins_missed_30d = checkins_missed_by_client.get(cid, 0)

        stamps30 = activity_by_client.get(cid, [])
        stamps7 = [s for s in stamps30 if s >= d7]
        messages_7d = len([s for s in message_stamps_by_client.get(cid, []) if s >= d7])
        ignored_reminders_30d = reminders_by_user.get(user_id_by_client[cid], 0)
        plan_updates_30d = workout_updates_by_client.get(cid, 0) + nutrition_updates_by_client.get(cid, 0)

        act7, act30 = len(stamps7), len(stamps30)
        rate7, rate30 = act7 / 7.0, act30 / 30.0
        engagement_delta = round(rate7 / rate30 - 1.0, 3) if rate30 > 0 else (0.0 if act7 == 0 else None)

        coach_user_id = coach_user_id_by_client.get(cid)
        if coach_user_id is None:
            avg_response = None
        else:
            gaps = _response_gaps_minutes(msgs_by_client.get(cid, []), coach_user_id)
            avg_response = round(sum(gaps) / len(gaps), 1) if gaps else None

        durs = _review_durations_seconds(review_rows_by_client.get(cid, []))
        avg_review = round(sum(durs) / len(durs), 1) if durs else None

        days_to_renewal = (sub.end_date - snapshot_date).days if (sub and sub.end_date) else None
        payment_failures_30d = 1 if (sub and (sub.payment_status or '').upper() in _FAILED_PAYMENT_STATES) else 0
        relationship_age_days = (snapshot_date - rel.start_date).days if (rel and rel.start_date) else None
        active_package_price = sub.subscription_plan.price if sub else None

        behaviour = _posthog_behaviour(client, snapshot_date) if enrich else None
        if behaviour is None:
            behaviour = {
                'login_count_7d': _distinct_active_days(stamps7),
                'login_count_30d': _distinct_active_days(stamps30),
                'feature_usage_count_7d': act7,
            }

        result[cid] = {
            'client_id': cid,
            'coach_id': coach.id if coach else None,
            'snapshot_date': snapshot_date,
            'days_since_last_login': days_since_last_login,
            'login_count_7d': behaviour['login_count_7d'],
            'login_count_30d': behaviour['login_count_30d'],
            'days_since_last_checkin': days_since_last_checkin,
            'checkins_completed_7d': checkins_completed_7d,
            'checkins_missed_30d': checkins_missed_30d,
            'messages_7d': messages_7d,
            'ignored_reminders_30d': ignored_reminders_30d,
            'feature_usage_count_7d': behaviour['feature_usage_count_7d'],
            'plan_updates_30d': plan_updates_30d,
            'engagement_delta_7d_vs_30d': engagement_delta,
            'avg_coach_response_minutes_30d': avg_response,
            'avg_review_duration_seconds_30d': avg_review,
            'days_to_renewal': days_to_renewal,
            'payment_failures_30d': payment_failures_30d,
            'relationship_age_days': relationship_age_days,
            'active_package_price': active_package_price,
            'is_internal_user': flags['is_internal_user'],
            'is_test_account': flags['is_test_account'],
            'environment': current_environment(),
        }
    return result


def build_and_store(snapshot_date, enrich=True):
    """Upsert a feature row for every client with an active coaching relationship.

    Returns the number of rows written.
    """
    from ..models import DailyFeatureStore

    client_ids = (CoachingRelationship.objects.filter(status='ACTIVE')
                  .values_list('client_id', flat=True).distinct())
    clients = ClientProfile.objects.filter(id__in=list(client_ids)).select_related('user')

    feats_by_client = _build_features_bulk(clients, snapshot_date, enrich=enrich)

    written = 0
    for feats in feats_by_client.values():
        if feats['coach_id'] is None:
            continue
        DailyFeatureStore.objects.update_or_create(
            client_id=feats['client_id'], snapshot_date=snapshot_date,
            defaults={k: v for k, v in feats.items() if k not in ('client_id', 'snapshot_date')},
        )
        written += 1
    return written
