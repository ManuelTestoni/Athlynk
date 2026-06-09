from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship


def get_session_user(request):
    user_id = request.session.get('user_id')
    if not user_id:
        # Mobile fallback: the iOS apps authenticate with a signed Bearer token
        # instead of the session cookie. Resolving it here lets the existing
        # coach web views (import, assign, …) serve both clients unchanged.
        from config.api import _bearer, _user_from_token
        bearer = _bearer(request)
        if bearer:
            return _user_from_token(bearer)
        return None

    try:
        return User.objects.get(id=user_id)
    except User.DoesNotExist:
        request.session.flush()
        return None


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
