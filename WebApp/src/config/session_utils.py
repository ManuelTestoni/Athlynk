import logging
import re

from domain.accounts.models import User, CoachProfile, ClientProfile
from domain.coaching.models import CoachingRelationship

logger = logging.getLogger(__name__)

_UNSET = object()

# Per-user branding (Impostazioni → Aspetto): default Athlynk primary/accent,
# matching --al-primary-rgb / --al-accent-rgb in athlynk.css.
BRAND_DEFAULT_PRIMARY = '#1E3A5F'
BRAND_DEFAULT_ACCENT = '#5B89B6'
_HEX_RE = re.compile(r'^#[0-9A-Fa-f]{6}$')


def _rgb_triplet(hex_color, default=BRAND_DEFAULT_PRIMARY):
    """'#1E3A5F' -> '30 58 95' (the space-separated form CSS custom
    properties use so rgb(var(--x) / <alpha>) works). Invalid hex -> default."""
    if not hex_color or not _HEX_RE.match(hex_color):
        hex_color = default
    r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
    return f'{r} {g} {b}'


def _shade(hex_color, factor=0.72, default=BRAND_DEFAULT_PRIMARY):
    """Darkened RGB triplet of hex_color — the hover/pressed variant, so a
    single primary picker is enough (no second "dark primary" swatch)."""
    if not hex_color or not _HEX_RE.match(hex_color):
        hex_color = default
    r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
    clamp = lambda v: max(0, min(255, round(v * factor)))
    return f'{clamp(r)} {clamp(g)} {clamp(b)}'


def brand_dict(user):
    """Per-user branding, same shape web `impostazioni` (tab aspetto) reads/writes."""
    return {
        'brand_name': user.brand_name or '',
        'brand_primary': user.brand_primary or '',
        'brand_accent': user.brand_accent or '',
    }


def apply_brand_update(user, data):
    """Mobile counterpart of views_settings._save_brand — validates the two
    hex colors (interpolated server-side into CSS, so untrusted input is a
    trust boundary) and saves. Returns an error string, or None on success."""
    if data.get('reset'):
        name, primary, accent = '', '', ''
    else:
        name = (data.get('brand_name') or '').strip()[:40]
        primary = (data.get('brand_primary') or '').strip()
        accent = (data.get('brand_accent') or '').strip()
        for hex_value in (primary, accent):
            if hex_value and not _HEX_RE.match(hex_value):
                return 'Colore non valido.'
    user.brand_name = name
    user.brand_primary = primary
    user.brand_accent = accent
    user.save(update_fields=['brand_name', 'brand_primary', 'brand_accent', 'updated_at'])
    return None


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
    # Memoized per-request like get_session_user above: middleware, the
    # identity_context processor, and the view itself each call this, so an
    # un-cached lookup re-fetches the same CoachProfile row 3x per page.
    cached = getattr(request, '_session_coach', _UNSET)
    if cached is not _UNSET:
        return cached

    user = get_session_user(request)
    if not user or user.role != 'COACH':
        request._session_coach = None
        return None

    try:
        coach = CoachProfile.objects.get(user=user)
    except CoachProfile.DoesNotExist:
        coach = None
    request._session_coach = coach
    return coach


def get_session_client(request):
    cached = getattr(request, '_session_client', _UNSET)
    if cached is not _UNSET:
        return cached

    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        request._session_client = None
        return None

    try:
        client = ClientProfile.objects.get(user=user)
    except ClientProfile.DoesNotExist:
        client = None
    request._session_client = client
    return client


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
    collaboration exists (regardless of payment status — an unpaid athlete is
    gated per-domain by client_domain_has_paid_access, not blocked outright).
    False only for a true orphan: never added, or the coach ended the
    collaboration."""
    if not client:
        return False
    return CoachingRelationship.objects.filter(client=client, status='ACTIVE').exists()


def client_domain_has_paid_access(client, domain):
    """Whether the athlete may use a payment-gated domain ('workout' or
    'nutrition'). No relationship covering that domain at all -> nothing to
    gate, True (there's no coach to pay). A relationship exists -> True only
    if that coach has a currently-ACTIVE ClientSubscription for this client."""
    rels = get_active_relationships(client)
    rel = rels['full'] or rels[domain]
    if not rel:
        return True
    from domain.billing.models import ClientSubscription
    return ClientSubscription.objects.filter(
        client=client, subscription_plan__coach=rel.coach, status='ACTIVE',
    ).exists()


def coach_has_active_platform_access(coach):
    """A coach/allenatore/nutrizionista may use the platform only while their
    linked PlatformPurchase is paid and not past its billing period end.
    Computed live (no cached/cron-flipped status needed): access self-corrects
    the instant `current_period_end` passes, and cancel_at_period_end
    subscriptions stay valid until then (see views_payments._sync_subscription).

    A coach with NO linked purchase at all is grandfathered in (access code
    redemption postdates this account) rather than blocked — the gate only
    applies to accounts created through the new code-redemption signup, not
    to every pre-existing coach the day this shipped.
    """
    from django.utils import timezone
    from domain.billing.models import PlatformPurchase

    if not coach:
        return False
    purchase = getattr(coach, 'platform_purchase', None)
    if purchase is None:
        return True
    if purchase.status == PlatformPurchase.STATUS_CANCELED:
        return False
    if purchase.current_period_end and purchase.current_period_end < timezone.now():
        return False
    return True


def coach_can_sell_online(coach):
    """Whether this coach's Stripe Connect account can currently accept
    payments — gates Stripe Product/Price sync on plan create/edit and the
    "Acquista Online" CTA on athlete-facing plan pages. Independent of
    coach_has_active_platform_access (that's the coach's own Athlynk bill)."""
    if not coach:
        return False
    return bool(coach.stripe_connect_account_id) and coach.stripe_connect_charges_enabled


def coach_has_chiron_access(coach):
    """Chiron is an add-on: requires an active platform subscription AND
    has_chiron=True on the linked purchase."""
    if not coach_has_active_platform_access(coach):
        return False
    purchase = getattr(coach, 'platform_purchase', None)
    return bool(purchase and purchase.has_chiron)


def enforce_client_access(client):
    """Lazy, idempotent sweep run at login. Expires the client's lapsed
    subscriptions (end_date in the past). The collaboration itself
    (CoachingRelationship) is never touched here — a lapsed subscription no
    longer ends access to the app; it only re-gates the specific domain
    (workout/nutrition) via client_domain_has_paid_access until the athlete
    pays again. Returns the number of subscriptions expired."""
    if not client:
        return 0
    from datetime import date
    from domain.billing.models import ClientSubscription

    today = date.today()
    lapsed = (
        ClientSubscription.objects
        .filter(client=client, status='ACTIVE', end_date__isnull=False, end_date__lt=today)
    )
    return lapsed.update(status='EXPIRED')


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
            'has_chiron': False,
            'trainer': None,
            'nutritionist': None,
            'has_any_professional': False,
            'display_name': 'Utente',
            'brand_name': 'Athlynk',
            'brand_css_vars': '',
        }

    # Per-user branding: role-independent (lives on User, not on
    # CoachProfile/ClientProfile), so both a coach and an athlete can retint
    # their own app the same way. Empty fields -> no override, page renders
    # the default Athlynk theme exactly as before.
    brand_name = user.brand_name or 'Athlynk'
    brand_css_vars = ''
    if user.brand_primary or user.brand_accent:
        parts = []
        if user.brand_primary:
            parts.append(f'--al-primary-rgb:{_rgb_triplet(user.brand_primary)};')
            parts.append(f'--al-primary-d-rgb:{_shade(user.brand_primary)};')
        if user.brand_accent:
            parts.append(f'--al-accent-rgb:{_rgb_triplet(user.brand_accent)};')
        brand_css_vars = ' '.join(parts)

    context = {
        'current_user': user,
        'user_role': user.role,
        'brand_name': brand_name,
        'brand_css_vars': brand_css_vars,
        'is_coach': False,
        'is_client': False,
        'coach': None,
        'client': None,
        'active_relationship': None,
        'has_coach': False,
        'can_manage_workouts': False,
        'can_manage_nutrition': False,
        'has_chiron': False,
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
        context['has_chiron'] = coach_has_chiron_access(coach)
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
