import logging

from django.db.models import Q

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship

logger = logging.getLogger(__name__)

_UNSET = object()


def get_session_user(request):
    # Memoized per-request: identity_context, get_session_coach/client, and
    # middleware each call this, so an un-cached lookup re-fetches the same
    # User row 3-5x per page.
    cached = getattr(request, '_session_user', _UNSET)
    if cached is not _UNSET:
        return cached

    user_id = request.session.get('user_id')
    if not user_id:
        # Mobile fallback: the iOS apps authenticate with a signed Bearer token
        # instead of the session cookie. Resolving it here lets the existing
        # coach web views (import, assign, …) serve both clients unchanged.
        from config.api import _bearer, _user_from_token
        bearer = _bearer(request)
        user = _user_from_token(bearer) if bearer else None
        request._session_user = user
        return user

    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        request.session.flush()
        user = None
    request._session_user = user
    return user


def get_session_coach(request):
    user = get_session_user(request)
    if not user or user.role != 'COACH':
        return None

    try:
        return CoachProfile.objects.get(user=user)
    except CoachProfile.DoesNotExist:
        return None


def get_session_client(request):
    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        return None

    try:
        return ClientProfile.objects.get(user=user)
    except ClientProfile.DoesNotExist:
        return None


def can_manage_workouts(coach):
    if not coach:
        return False
    return coach.professional_type in ('COACH', 'ALLENATORE')


def can_manage_nutrition(coach):
    if not coach:
        return False
    return coach.professional_type in ('COACH', 'NUTRIZIONISTA')


def get_active_relationship(client):
    """DEPRECATED: use get_active_relationships instead"""
    if not client:
        return None

    return (
        CoachingRelationship.objects
        .select_related('coach', 'client')
        .filter(client=client, status='ACTIVE')
        .first()
    )


def get_active_relationships(client):
    """Returns dict of active relationships keyed by type: {'full': rel, 'workout': rel, 'nutrition': rel}"""
    if not client:
        return {'full': None, 'workout': None, 'nutrition': None}

    rels = (
        CoachingRelationship.objects
        .select_related('coach', 'client')
        .filter(client=client, status='ACTIVE')
    )

    result = {'full': None, 'workout': None, 'nutrition': None}
    for rel in rels:
        rel_type = rel.relationship_type or 'FULL'
        if rel_type == 'FULL':
            result['full'] = rel
        elif rel_type == 'WORKOUT':
            result['workout'] = rel
        elif rel_type == 'NUTRITION':
            result['nutrition'] = rel

    return result


def get_workout_coach(client):
    """Coach responsible for the client's training: the FULL coach, else the
    dedicated WORKOUT one. None if neither exists."""
    rels = get_active_relationships(client)
    rel = rels['full'] or rels['workout']
    return rel.coach if rel else None


def get_nutrition_coach(client):
    """Coach responsible for the client's nutrition: the FULL coach, else the
    dedicated NUTRITION one. None if neither exists."""
    rels = get_active_relationships(client)
    rel = rels['full'] or rels['nutrition']
    return rel.coach if rel else None


def client_has_active_access(client):
    """An athlete may use the app only while at least one professional
    collaboration is active. Read-only: relies on `enforce_client_access`
    (called at login) and the deactivate_lapsed command to flip lapsed
    relationships to INACTIVE."""
    if not client:
        return False
    return CoachingRelationship.objects.filter(client=client, status='ACTIVE').exists()


def enforce_client_access(client):
    """Lazy, idempotent sweep run at login. Expires the client's lapsed
    subscriptions (end_date in the past) and, when a coach is left without any
    valid subscription for this client, deactivates that collaboration so the
    athlete loses access until it is renewed/re-added. Returns the number of
    relationships deactivated."""
    if not client:
        return 0
    from datetime import date
    from domain.billing.models import ClientSubscription

    today = date.today()
    lapsed = (
        ClientSubscription.objects
        .filter(client=client, status='ACTIVE', end_date__isnull=False, end_date__lt=today)
        .select_related('subscription_plan', 'subscription_plan__coach')
    )

    deactivated_total = 0
    for sub in lapsed:
        coach = sub.subscription_plan.coach
        sub.status = 'EXPIRED'
        sub.save(update_fields=['status', 'updated_at'])

        # Another still-valid subscription with the same coach keeps the
        # collaboration alive (e.g. renewed early under a different plan).
        still_covered = (
            ClientSubscription.objects
            .filter(client=client, subscription_plan__coach=coach, status='ACTIVE')
            .filter(Q(end_date__isnull=True) | Q(end_date__gte=today))
            .exists()
        )
        if still_covered:
            continue

        deactivated = CoachingRelationship.objects.filter(
            client=client, coach=coach, status='ACTIVE',
        ).update(status='INACTIVE', end_date=today)
        if deactivated:
            deactivated_total += deactivated
            try:
                from domain.chat.services import send_automatic_message
                send_automatic_message(coach, client, 'SUBSCRIPTION_EXPIRING')
            except Exception:
                logger.exception('subscription_expiring_message.failed client_id=%s', client.id)

    return deactivated_total


def build_identity_context(request):
    user = get_session_user(request)
    if not user:
        return {
            'current_user': None,
            'user_role': None,
            'is_coach': False,
            'is_client': False,
            'coach': None,
            'client': None,
            'active_relationship': None,
            'has_coach': False,
            'can_manage_workouts': False,
            'can_manage_nutrition': False,
            'trainer': None,
            'nutritionist': None,
            'has_any_professional': False,
            'display_name': 'Utente',
        }

    context = {
        'current_user': user,
        'user_role': user.role,
        'is_coach': False,
        'is_client': False,
        'coach': None,
        'client': None,
        'active_relationship': None,
        'has_coach': False,
        'can_manage_workouts': False,
        'can_manage_nutrition': False,
        'trainer': None,
        'nutritionist': None,
        'has_any_professional': False,
        'display_name': user.email,
    }

    if user.role == 'COACH':
        coach = get_session_coach(request)
        context['is_coach'] = True
        context['coach'] = coach
        context['can_manage_workouts'] = can_manage_workouts(coach)
        context['can_manage_nutrition'] = can_manage_nutrition(coach)
        context['display_name'] = f"{coach.first_name} {coach.last_name}".strip() if coach else user.email
    elif user.role == 'CLIENT':
        client = get_session_client(request)
        relationships = get_active_relationships(client)

        context['is_client'] = True
        context['client'] = client
        context['active_relationship'] = relationships['full'] or relationships['workout'] or relationships['nutrition']

        context['has_coach'] = relationships['full'] is not None
        context['coach'] = relationships['full'].coach if relationships['full'] else None
        context['trainer'] = relationships['workout'].coach if relationships['workout'] else None
        context['nutritionist'] = relationships['nutrition'].coach if relationships['nutrition'] else None
        context['has_any_professional'] = any([relationships['full'], relationships['workout'], relationships['nutrition']])

        context['display_name'] = f"{client.first_name} {client.last_name}".strip() if client else user.email

    return context
