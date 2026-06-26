"""Mobile JSON API (v1) for the Athlete iOS app.

Design constraints (deliberately minimal — see CLAUDE.md "Simplicity First"):

* No DRF dependency. Plain Django views returning ``JsonResponse``.
* No new model / migration. Auth tokens are **stateless signed blobs**
  (``django.core.signing``) carrying the user id. The iOS app stores the token
  in the Keychain and sends it as ``Authorization: Bearer <token>``.
* Reuses the existing custom-auth password hashes (``User.password_hash``) and
  the same domain models the web app renders — the API is just a second
  read-mostly projection of the athlete's data.

The iOS client talks to ``http://localhost:8000/api/v1/...`` in development.
"""

import json
import logging
from datetime import date, timedelta

import sentry_sdk

from django.conf import settings
from django.contrib.auth.hashers import check_password
from django.utils.dateparse import parse_date
from django.core import signing
from django.core.files.storage import default_storage
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from domain.accounts.models import CoachProfile, DeviceToken, User
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.calendar.models import Appointment
from domain.chat.models import Conversation, Message, Notification
from domain.checks.models import AssignedCheckInstance, QuestionAttachment, QuestionnaireResponse
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import (
    ClientMacroLogEntry, Food, NutritionAssignment, SupplementProtocolAssignment,
)
from domain.workouts.models import (
    Exercise, WorkoutAssignment, WorkoutDay, WorkoutExercise, WorkoutSession, WorkoutSetLog,
)

from domain.checks.anthropometry import (
    circ_label, skin_label, circ_range, skin_range, WEIGHT_RANGE,
    measurement_options,
)
from .session_utils import get_active_relationships, client_has_active_access, enforce_client_access
from .services import ratelimit, sanitize
from .services.images import is_image, to_webp
from .services.uploads import store_attachment
from .views_check import (
    build_measurements, RESERVED_FIELD_MAP,
    create_quick_measurement, QuickMeasurementError,
)

logger = logging.getLogger(__name__)

# Tokens are signed, not encrypted: the payload (user id) is readable but cannot
# be forged without SECRET_KEY. 30-day lifetime keeps the athlete logged in.
TOKEN_SALT = 'athlynk.api.v1.token'
TOKEN_MAX_AGE = 60 * 60 * 24 * 30

# Login throttle — mirrors the web login (config/views_auth.py): per-IP and
# per-account buckets so neither a single source nor a single account can be
# brute-forced. Counters reset on a successful login.
LOGIN_RATE_LIMIT = 5
LOGIN_RATE_WINDOW_SECONDS = 15 * 60
LOGIN_EMAIL_RATE_LIMIT = 10
LOGIN_EMAIL_RATE_WINDOW_SECONDS = 15 * 60

# HTTP methods that mutate state — get the (stricter) write rate-limit bucket.
_WRITE_METHODS = frozenset({'POST', 'PUT', 'PATCH', 'DELETE'})


def _rl_conf(key, fallback):
    return int((getattr(settings, 'API_RATE_LIMITS', {}) or {}).get(key, fallback))


def _too_many_requests():
    window = _rl_conf('window_seconds', 60)
    resp = JsonResponse({'error': 'Troppe richieste. Riprova tra poco.'}, status=429)
    resp['Retry-After'] = str(window)
    return resp


def _api_throttle(request, ident, is_write):
    """Per-user + per-IP rate limit for a token-authenticated API call. Reads and
    writes use separate buckets so a write burst can't starve reads. Returns a
    429 JsonResponse when either bucket is exhausted, else None."""
    window = _rl_conf('window_seconds', 60)
    per_user = _rl_conf('write_per_min', 30) if is_write else _rl_conf('read_per_min', 120)
    ip_limit = per_user * _rl_conf('ip_multiplier', 2)
    kind = 'w' if is_write else 'r'
    user_ok, _ = ratelimit.hit(f'api_{kind}_u', ident, per_user, window)
    ip = ratelimit.client_ip(request)
    ip_ok, _ = ratelimit.hit(f'api_{kind}_ip', ip, ip_limit, window)
    if user_ok and ip_ok:
        return None
    logger.warning('api.rate_limited ident=%s ip=%s write=%s user_ok=%s ip_ok=%s',
                   ident, ip, is_write, user_ok, ip_ok)
    return _too_many_requests()


def _builder_throttle(request, ident):
    """Looser single-bucket limit for coach_dual_auth endpoints (web plan
    builders autosave frequently). Throttles abusive volume without tripping on
    legitimate editing. Keyed by the resolved coach/session, falling back to IP."""
    window = _rl_conf('window_seconds', 60)
    limit = _rl_conf('builder_per_min', 120)
    if ident:
        ok, _ = ratelimit.hit('api_builder', ident, limit, window)
        if not ok:
            logger.warning('api.builder_rate_limited ident=%s', ident)
            return _too_many_requests()
    ip = ratelimit.client_ip(request)
    ip_ok, _ = ratelimit.hit('api_builder_ip', ip, limit * _rl_conf('ip_multiplier', 2), window)
    if not ip_ok:
        logger.warning('api.builder_rate_limited ip=%s', ip)
        return _too_many_requests()
    return None


# ---------------------------------------------------------------------------
# Token + auth plumbing
# ---------------------------------------------------------------------------

def issue_token(user):
    return signing.dumps({'uid': user.id}, salt=TOKEN_SALT)


def _user_from_token(token):
    try:
        data = signing.loads(token, salt=TOKEN_SALT, max_age=TOKEN_MAX_AGE)
    except signing.BadSignature:
        return None
    try:
        return User.objects.get(id=data.get('uid'), is_active=True)
    except User.DoesNotExist:
        return None


def _bearer(request):
    header = request.META.get('HTTP_AUTHORIZATION', '')
    if header.startswith('Bearer '):
        return header[7:].strip()
    return None


# Endpoints a CLIENT may still call while access is suspended (no active
# professional): account/profile management and notifications. Every data
# endpoint (workouts, nutrition, checks, …) is blocked — parity with the web
# gate in config.middleware.ClientAccessMiddleware.
_CLIENT_BLOCKED_ALLOW = {
    'me', 'profile', 'profile_photo', 'settings', 'delete_account',
    'register_device', 'notification_read', 'notifications', 'tutorial_complete',
}


def api_view(methods):
    """Decorator: CSRF-exempt + method gate + token auth.

    Wrapped view is called as ``view(request, user, *args, **kwargs)``.
    """
    allowed = {m.upper() for m in methods}

    def decorator(view):
        @csrf_exempt
        def wrapper(request, *args, **kwargs):
            if request.method not in allowed:
                return JsonResponse({'error': 'Metodo non consentito'}, status=405)
            user = _user_from_token(_bearer(request) or '')
            if not user:
                return JsonResponse({'error': 'Non autenticato'}, status=401)
            sentry_sdk.set_user({'id': str(user.id), 'segment': user.role})
            # Suspended athlete: block every data endpoint, allow only the
            # account-management allowlist so the app can show its blocked state.
            if user.role == 'CLIENT' and view.__name__ not in _CLIENT_BLOCKED_ALLOW:
                if not client_has_active_access(getattr(user, 'client_profile', None)):
                    return JsonResponse({
                        'error': 'access_blocked',
                        'message': 'Nessun professionista attivo. Chiedi al tuo coach di '
                                   'aggiungerti o di rinnovare l’abbonamento.',
                    }, status=403)
            is_write = request.method in _WRITE_METHODS
            # Pre-parse + sanitize JSON write bodies so a malformed, oversized or
            # control-char-laden body yields a clean 400 before the view runs and
            # `_body()` can reuse the cleaned dict. Multipart/form uploads (e.g.
            # photo, chat attachment) carry a non-JSON Content-Type — leave their
            # body for the view to read so we never touch request.body too early.
            if is_write:
                ctype = (request.META.get('CONTENT_TYPE') or '').lower()
                if not ctype or 'application/json' in ctype:
                    try:
                        cleaned = sanitize.clean_payload(sanitize.safe_json(request.body))
                    except sanitize.InvalidInput as exc:
                        return JsonResponse({'error': str(exc)}, status=400)
                    request._clean_body = cleaned if isinstance(cleaned, dict) else {}
            throttled = _api_throttle(request, f'u{user.id}', is_write)
            if throttled:
                return throttled
            try:
                return view(request, user, *args, **kwargs)
            except Exception:
                logging.getLogger('django.request').exception('Unhandled exception in api_view: %s', view.__name__)
                return JsonResponse({'error': 'Errore interno del server'}, status=500)
        wrapper.__name__ = view.__name__
        return wrapper
    return decorator


def _request_coach(request):
    """Resolve the acting coach from either a mobile Bearer token or the web
    session. Returns a CoachProfile or None. Lets a single view serve both the
    iOS coach app and the browser without duplicating its body."""
    coach = getattr(request, '_mobile_coach', None)
    if coach is not None:
        return coach
    bearer = _bearer(request)
    if bearer:
        user = _user_from_token(bearer)
        if user is None:
            logging.getLogger('athlynk.api').warning(
                '_request_coach: bearer token invalid or expired'
            )
            request._mobile_coach = None
            return None
        coach = getattr(user, 'coach_profile', None)
        if coach is None:
            logging.getLogger('athlynk.api').warning(
                '_request_coach: user %s (role=%s) has no coach_profile', user.id, user.role
            )
        request._mobile_coach = coach
        return coach
    from .session_utils import get_session_coach
    return get_session_coach(request)


def coach_dual_auth(view):
    """Make an existing session-auth coach view also accept the mobile Bearer
    token. Bearer requests skip CSRF (token auth is not cookie-based and so is
    not CSRF-exposed); cookie/session requests still go through Django's CSRF
    check, so web security is unchanged. The wrapped view keeps using
    ``_request_coach(request)`` for the acting coach."""
    from django.middleware.csrf import CsrfViewMiddleware
    from django.views.decorators.csrf import csrf_exempt

    @csrf_exempt
    def wrapper(request, *args, **kwargs):
        # Skip CSRF only for a request that a *valid* token authenticates and
        # that carries no session cookie. The mere presence of an (unverified)
        # Authorization header must never disable CSRF for a cookie-auth request.
        bearer = _bearer(request)
        token_user = _user_from_token(bearer) if bearer else None
        is_token = token_user is not None and not request.session.get('user_id')
        # Rate limit by the resolved coach/session identity (IP-only as fallback)
        # before doing any work. Looser bucket than the mobile API: these back
        # the web plan builders, which autosave often.
        if is_token:
            ident = f'u{token_user.id}'
            sentry_sdk.set_user({'id': str(token_user.id), 'segment': 'COACH'})
        else:
            sid = request.session.get('user_id')
            ident = f's{sid}' if sid else ''
            if sid:
                sentry_sdk.set_user({'id': str(sid), 'segment': 'COACH'})
        throttled = _builder_throttle(request, ident)
        if throttled:
            return throttled
        try:
            if is_token:
                return view(request, *args, **kwargs)
            # Browser/session request → enforce CSRF as usual.
            reason = CsrfViewMiddleware(lambda r: None).process_view(request, view, args, kwargs)
            if reason is not None:
                return reason
            return view(request, *args, **kwargs)
        except Exception:
            logging.getLogger('django.request').exception('Unhandled exception in coach_dual_auth: %s', view.__name__)
            return JsonResponse({'error': 'Errore interno del server'}, status=500)

    wrapper.__name__ = getattr(view, '__name__', 'coach_dual_auth_view')
    return wrapper


def _body(request):
    """Return the parsed + sanitized JSON body as a dict.

    Every string value has been NFKC-normalized and stripped of control chars by
    `sanitize.clean_payload` (passwords/tokens excepted). Returns {} for a
    missing, invalid, oversized or non-object body — callers treat absent keys as
    not-provided. The api_view decorator pre-parses write requests (so it can
    surface a precise 400); this reuses that cached result when present."""
    cached = getattr(request, '_clean_body', None)
    if cached is not None:
        return cached
    try:
        data = sanitize.clean_payload(sanitize.safe_json(request.body))
    except sanitize.InvalidInput:
        data = {}
    if not isinstance(data, dict):
        data = {}
    request._clean_body = data
    return data


def _iso(dt):
    return dt.isoformat() if dt else None


def _abs_media(request, url):
    """Mobile clients can't resolve relative MEDIA paths ("/media/…") the way a
    browser does against the page origin. Promote them to absolute URLs so
    AsyncImage on iOS can load them; leave already-absolute URLs untouched."""
    if not url:
        return url
    if url.startswith('http://') or url.startswith('https://'):
        return url
    return request.build_absolute_uri(url)


# ---------------------------------------------------------------------------
# Serializers (plain dict builders)
# ---------------------------------------------------------------------------

def _coach_dict(coach):
    if not coach:
        return None
    return {
        'id': coach.id,
        'first_name': coach.first_name,
        'last_name': coach.last_name,
        'professional_type': coach.professional_type,
        'specialization': coach.specialization,
        'city': coach.city,
        'profile_image_url': coach.profile_image_url,
    }


def _user_dict(user):
    profile = getattr(user, 'client_profile', None) or getattr(user, 'coach_profile', None)
    first = getattr(profile, 'first_name', '') if profile else ''
    last = getattr(profile, 'last_name', '') if profile else ''
    return {
        'id': user.id,
        'email': user.email,
        'role': user.role,
        'first_name': first,
        'last_name': last,
        'display_name': (f'{first} {last}'.strip() or user.email),
        'chiron_seen': bool(user.chiron_intro_seen),
    }


def _exercise_dict(we):
    ex = we.exercise
    return {
        'id': we.id,
        'name': ex.name,
        'video_url': ex.video_url,
        'target_muscle_group': ex.target_muscle_group,
        'equipment': ex.equipment,
        'order_index': we.order_index,
        'set_count': we.set_count,
        'rep_count': we.rep_count,
        'rep_range': we.rep_range,
        'rir': we.rir,
        'rpe': we.rpe,
        'load_value': float(we.load_value) if we.load_value is not None else None,
        'load_unit': we.load_unit,
        'recovery_seconds': we.recovery_seconds,
        'tempo': we.tempo,
        'technique_notes': we.technique_notes,
        'set_details': we.set_details or [],
        'superset_group_id': we.superset_group_id,
    }


def _day_dict(day):
    return {
        'id': day.id,
        'day_order': day.day_order,
        'day_name': day.day_name,
        'title': day.title,
        'focus_area': day.focus_area,
        'day_type': day.day_type,
        'notes': day.notes,
        'exercises': [_exercise_dict(we) for we in day.exercises.select_related('exercise')],
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@csrf_exempt
def login(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Metodo non consentito'}, status=405)
    data = _body(request)
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    if not email or not password:
        return JsonResponse({'error': 'Email e password obbligatorie'}, status=400)

    ip = ratelimit.client_ip(request)
    ip_allowed, _ = ratelimit.hit(
        'login_ip', ip, LOGIN_RATE_LIMIT, LOGIN_RATE_WINDOW_SECONDS,
    )
    email_allowed, _ = ratelimit.hit(
        'login_email', email, LOGIN_EMAIL_RATE_LIMIT, LOGIN_EMAIL_RATE_WINDOW_SECONDS,
    )
    if not ip_allowed or not email_allowed:
        logger.warning('api.login.rate_limited ip=%s email=%s ip_ok=%s email_ok=%s',
                       ip, email, ip_allowed, email_allowed)
        return JsonResponse({'error': 'Troppi tentativi di accesso. Riprova tra qualche minuto.'}, status=429)

    # Each app declares the role it serves (CLIENT for the athlete app, COACH
    # for the coach app): the lookup itself filters by role, so a coach can't
    # log into the athlete app and vice versa — no extra logic downstream.
    lookup = {'email__iexact': email}
    expected_role = (data.get('role') or '').strip().upper()
    if expected_role in ('CLIENT', 'COACH'):
        lookup['role'] = expected_role
    try:
        user = User.objects.get(**lookup)
    except User.DoesNotExist:
        return JsonResponse({'error': 'Credenziali non valide'}, status=401)
    if not check_password(password, user.password_hash):
        return JsonResponse({'error': 'Credenziali non valide'}, status=401)
    if not user.is_verified:
        return JsonResponse({'error': 'Email non verificata'}, status=403)

    ratelimit.reset('login_ip', ip, LOGIN_RATE_WINDOW_SECONDS)
    ratelimit.reset('login_email', email, LOGIN_EMAIL_RATE_WINDOW_SECONDS)
    # Expire lapsed subscriptions / deactivate orphaned collaborations now so the
    # app immediately sees the suspended state instead of stale access.
    if user.role == 'CLIENT':
        enforce_client_access(getattr(user, 'client_profile', None))
    user.last_login_at = timezone.now()
    user.save(update_fields=['last_login_at'])
    return JsonResponse({'token': issue_token(user), 'user': _user_dict(user)})


@api_view(['GET'])
def me(request, user):
    payload = {'user': _user_dict(user), 'coach': None, 'trainer': None, 'nutritionist': None}
    client = getattr(user, 'client_profile', None)
    if client:
        payload['access_blocked'] = not client_has_active_access(client)
        rels = get_active_relationships(client)
        payload['coach'] = _coach_dict(rels['full'].coach if rels['full'] else None)
        payload['trainer'] = _coach_dict(rels['workout'].coach if rels['workout'] else None)
        payload['nutritionist'] = _coach_dict(rels['nutrition'].coach if rels['nutrition'] else None)
        payload['profile'] = {
            'profile_image_url': _abs_media(request, client.profile_image.url) if client.profile_image else None,
        }
    coach = getattr(user, 'coach_profile', None)
    if coach:
        # The coach app reads `profile.profile_image_url` for its header avatar,
        # the same shape the athlete app expects.
        img = _abs_media(request, coach.profile_image.url) if coach.profile_image else coach.profile_image_url
        payload['coach_profile'] = {
            'id': coach.id,
            'professional_type': coach.professional_type,
            'specialization': coach.specialization,
            'city': coach.city,
        }
        payload['profile'] = {
            'profile_image_url': img,
        }
    return JsonResponse(payload)


@api_view(['GET'])
def workouts(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'plans': []})

    assignments = (
        WorkoutAssignment.objects
        .filter(client=client, status='ACTIVE')
        .select_related('workout_plan', 'coach')
        .order_by('-created_at')
    )
    plans = []
    for wa in assignments:
        plan = wa.workout_plan
        plans.append({
            'assignment_id': wa.id,
            'plan_id': plan.id,
            'title': plan.title,
            'description': plan.description,
            'goal': plan.goal,
            'level': plan.level,
            'frequency_per_week': plan.frequency_per_week,
            'duration_weeks': plan.duration_weeks,
            'start_date': _iso(wa.start_date),
            'coach': _coach_dict(wa.coach),
            'days': [_day_dict(d) for d in plan.days.all().prefetch_related('exercises__exercise')],
        })
    return JsonResponse({'plans': plans})


@api_view(['GET'])
def nutrition(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'plans': []})

    assignments = (
        NutritionAssignment.objects
        .filter(client=client, status='ACTIVE')
        .select_related('nutrition_plan', 'coach')
        .order_by('-assigned_at')
    )
    plans = []
    for na in assignments:
        plan = na.nutrition_plan
        days = []
        for day in plan.days.all().prefetch_related('meals__items__food'):
            meals = []
            for meal in day.meals.all():
                items = [{
                    'id': it.id,
                    'name': it.food.nome_alimento if it.food else it.raw_name,
                    'quantity_g': it.quantity_g,
                    'kcal': it.kcal,
                    'protein': it.protein,
                    'carbs': it.carbs,
                    'fat': it.fat,
                } for it in meal.items.all()]
                meals.append({
                    'id': meal.id,
                    'name': meal.name,
                    'time_of_day': meal.time_of_day,
                    'items': items,
                })
            days.append({
                'id': day.id,
                'day_of_week': day.day_of_week,
                'target_kcal': day.target_kcal,
                'target_protein_g': day.target_protein_g,
                'target_carb_g': day.target_carb_g,
                'target_fat_g': day.target_fat_g,
                'meals': meals,
            })
        plans.append({
            'assignment_id': na.id,
            'plan_id': plan.id,
            'title': plan.title,
            'plan_mode': plan.plan_mode,
            'plan_kind': plan.plan_kind,
            'nutrition_goal': plan.nutrition_goal,
            'daily_kcal': plan.daily_kcal,
            'protein_target_g': plan.protein_target_g,
            'carb_target_g': plan.carb_target_g,
            'fat_target_g': plan.fat_target_g,
            'coach': _coach_dict(na.coach),
            'days': days,
        })
    return JsonResponse({'plans': plans})


# ---------------------------------------------------------------------------
# MACRO-mode logging: the coach sets only targets, the client records what
# they actually eat today and tracks calories/macros consumed. FOOD-mode plans
# are read-only (handled client-side) and never reach these endpoints.
# ---------------------------------------------------------------------------

_WEEKDAY_CODES = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']
_DOW_SHORT = ['LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM']


def _today_weekday_code():
    return _WEEKDAY_CODES[date.today().weekday()]


def _macro_entry_dict(e):
    food = e.food
    return {
        'id': e.id,
        'food_id': e.food_id,
        'name': food.nome_alimento if food else (e.raw_name or ''),
        'meal_name': e.meal_name or '',
        'quantity_g': e.quantity_g,
        'kcal': e.kcal,
        'protein': e.protein,
        'carbs': e.carbs,
        'fat': e.fat,
    }


def _macro_assignment(user, assignment_id):
    """Return (assignment, error_response). Error if not the client's, or not MACRO."""
    client = getattr(user, 'client_profile', None)
    if not client:
        return None, JsonResponse({'error': 'Non disponibile'}, status=403)
    a = (NutritionAssignment.objects
         .select_related('nutrition_plan')
         .filter(id=assignment_id, client=client).first())
    if not a:
        return None, JsonResponse({'error': 'Piano non trovato'}, status=404)
    if a.nutrition_plan.plan_mode != 'MACRO':
        return None, JsonResponse({'error': 'Piano non compatibile'}, status=400)
    return a, None


@api_view(['GET'])
def food_search(request, user):
    q = (request.GET.get('q') or '').strip()
    foods = Food.objects.exclude(nome_alimento__icontains='media')
    if q:
        foods = foods.filter(nome_alimento__icontains=q)
    foods = foods.order_by('-genericity_score', 'nome_alimento')[:30]
    return JsonResponse({'results': [{
        'id': f.id,
        'name': f.nome_alimento,
        'category': f.categoria_alimento or '',
        'kcal': f.energia_kcal,
        'protein': f.proteine_g,
        'carb': f.carboidrati_g,
        'fat': f.lipidi_g,
    } for f in foods]})


@api_view(['GET'])
def macro_day(request, user, assignment_id):
    """Logged foods + consumed totals + macro target for a day (today by default,
    or any past `?date=YYYY-MM-DD` so the athlete can review/edit a past day)."""
    a, err = _macro_assignment(user, assignment_id)
    if err:
        return err
    plan = a.nutrition_plan
    weekly = plan.plan_kind == 'WEEKLY'

    target_date = parse_date((request.GET.get('date') or '').strip()) or date.today()
    if target_date > date.today():
        target_date = date.today()
    day_code = _WEEKDAY_CODES[target_date.weekday()]

    qs = a.macro_log.filter(log_date=target_date).select_related('food')
    if weekly:
        qs = qs.filter(day_of_week=day_code)
    entries = list(qs.order_by('created_at', 'id'))

    target = {'kcal': plan.daily_kcal or 0, 'protein': plan.protein_target_g or 0,
              'carb': plan.carb_target_g or 0, 'fat': plan.fat_target_g or 0}
    if weekly:
        d = plan.days.filter(day_of_week=day_code).first()
        if d:
            target = {'kcal': d.target_kcal or 0, 'protein': d.target_protein_g or 0,
                      'carb': d.target_carb_g or 0, 'fat': d.target_fat_g or 0}

    consumed = {
        'kcal': round(sum(e.kcal for e in entries), 1),
        'protein': round(sum(e.protein for e in entries), 1),
        'carb': round(sum(e.carbs for e in entries), 1),
        'fat': round(sum(e.fat for e in entries), 1),
    }
    return JsonResponse({'macro_day': {
        'date': target_date.isoformat(),
        'target': target,
        'consumed': consumed,
        'entries': [_macro_entry_dict(e) for e in entries],
    }})


@api_view(['POST'])
def macro_log_create(request, user, assignment_id):
    a, err = _macro_assignment(user, assignment_id)
    if err:
        return err
    data = _body(request)
    food = Food.objects.filter(id=data.get('food_id')).first()
    if not food:
        return JsonResponse({'error': 'Alimento non trovato'}, status=400)
    try:
        qty = float(data.get('quantity_g'))
    except (TypeError, ValueError):
        return JsonResponse({'error': 'Quantità non valida'}, status=400)
    if qty <= 0:
        return JsonResponse({'error': 'La quantità deve essere positiva'}, status=400)

    log_date = parse_date((data.get('date') or '').strip()) or date.today()
    if log_date > date.today():
        return JsonResponse({'error': 'Non puoi registrare un giorno futuro'}, status=400)
    if a.start_date and log_date < a.start_date:
        return JsonResponse({'error': 'Data precedente all\'inizio del piano'}, status=400)

    day_code = _WEEKDAY_CODES[log_date.weekday()] if a.nutrition_plan.plan_kind == 'WEEKLY' else None
    entry = ClientMacroLogEntry.objects.create(
        assignment=a,
        day_of_week=day_code,
        log_date=log_date,
        food=food,
        quantity_g=qty,
        meal_name=(data.get('meal_name') or '').strip()[:100] or None,
    )
    return JsonResponse({'ok': True, 'entry': _macro_entry_dict(entry)})


@api_view(['DELETE'])
def macro_log_delete(request, user, entry_id):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Non disponibile'}, status=403)
    entry = ClientMacroLogEntry.objects.filter(id=entry_id, assignment__client=client).first()
    if not entry:
        return JsonResponse({'error': 'Voce non trovata'}, status=404)
    entry.delete()
    return JsonResponse({'ok': True})


def macro_history_payload(assignment, offset, page=14):
    """Past logged days for a MACRO assignment, grouped by log_date (desc, paginated).

    Shared by the athlete (api) and coach (api_coach) history endpoints.
    """
    plan = assignment.nutrition_plan
    weekly = plan.plan_kind == 'WEEKLY'

    day_targets = {}
    if weekly:
        for d in plan.days.all():
            day_targets[d.day_of_week] = {
                'kcal': d.target_kcal or 0, 'protein': d.target_protein_g or 0,
                'carb': d.target_carb_g or 0, 'fat': d.target_fat_g or 0,
            }
    default_target = {'kcal': plan.daily_kcal or 0, 'protein': plan.protein_target_g or 0,
                      'carb': plan.carb_target_g or 0, 'fat': plan.fat_target_g or 0}

    all_dates = list(assignment.macro_log.order_by('-log_date')
                     .values_list('log_date', flat=True).distinct())
    page_dates = all_dates[offset:offset + page]

    days = []
    for ld in page_dates:
        entries = list(assignment.macro_log.filter(log_date=ld)
                       .select_related('food').order_by('created_at', 'id'))
        target = day_targets.get(_WEEKDAY_CODES[ld.weekday()], default_target) if weekly else default_target
        days.append({
            'date': ld.isoformat(),
            'dow_short': _DOW_SHORT[ld.weekday()],
            'target': target,
            'consumed': {
                'kcal': round(sum(e.kcal for e in entries), 1),
                'protein': round(sum(e.protein for e in entries), 1),
                'carb': round(sum(e.carbs for e in entries), 1),
                'fat': round(sum(e.fat for e in entries), 1),
            },
            'entries': [_macro_entry_dict(e) for e in entries],
        })
    return {'days': days, 'has_more': offset + page < len(all_dates)}


@api_view(['GET'])
def macro_history(request, user, assignment_id):
    """Athlete's own past logged days for a MACRO plan (paginated)."""
    a, err = _macro_assignment(user, assignment_id)
    if err:
        return err
    try:
        offset = max(0, int(request.GET.get('offset') or 0))
    except (TypeError, ValueError):
        offset = 0
    return JsonResponse(macro_history_payload(a, offset))


# ---------------------------------------------------------------------------
# "Il mio percorso" — the athlete's timeline of assignments, plans and checks.
# Reuses the web's event builder so coach and athlete views stay in sync.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def journey(request, user):
    client = getattr(user, 'client_profile', None)
    empty = {'events': [], 'window_start': '', 'window_end': '', 'relationship_start': ''}
    if not client:
        return JsonResponse(empty)
    rels = get_active_relationships(client)
    rel = rels.get('full') or rels.get('workout') or rels.get('nutrition')
    if not rel:
        return JsonResponse(empty)

    today = date.today()
    start = getattr(rel, 'start_date', None)
    if start:
        rel_start = (start if isinstance(start, date) else start.date()).replace(day=1)
    else:
        rel_start = (today - timedelta(days=365)).replace(day=1)
    from .views_client import _build_percorso_events, _serialize_phases, _one_year_after_month
    # Whole history for the timeline (see coach client_percorso): clipping to the
    # relationship-start month would drop older assignments and checks.
    events = _build_percorso_events(client, rel.coach, date(2000, 1, 1), today)
    phases = _serialize_phases(client, rel.coach)

    # Open-ended forward bound: one year past the latest activity (event or phase end).
    last_activity = today
    if events:
        last_activity = max(last_activity, date.fromisoformat(events[-1]['date']))
    for ph in phases:
        ph_end = date.fromisoformat(ph['end'])
        if ph_end > last_activity:
            last_activity = ph_end
    window_end = _one_year_after_month(last_activity)
    return JsonResponse({
        'events': events,
        'phases': phases,
        'window_start': rel_start.isoformat(),
        'window_end': window_end.isoformat(),
        'relationship_start': rel_start.isoformat(),
    })


@api_view(['GET'])
def checks(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'pending': []})
    instances = (
        AssignedCheckInstance.objects
        .filter(assignment__client=client, status='pending')
        .select_related('assignment', 'assignment__template', 'assignment__coach')
        .order_by('due_date')
    )
    pending = [{
        'id': inst.id,
        'title': inst.assignment.template.title if inst.assignment.template else 'Check',
        'due_date': _iso(inst.due_date),
        'expires_at': _iso(inst.expires_at),
        'coach': _coach_dict(inst.assignment.coach),
        **_check_form(inst),
    } for inst in instances]
    return JsonResponse({'pending': pending})


# Question keys whose values land in dedicated columns (not answers_json) — must
# stay in sync with the web fill flow's RESERVED handling in views_check.
_CHECK_RESERVED = {
    'peso_corporeo', 'circ_spalle', 'circ_petto', 'circ_vita', 'circ_fianchi',
    'circ_coscia', 'circ_braccio', 'pl_petto', 'pl_addome', 'pl_coscia',
    'pl_tricipite', 'note_infortuni', 'note_limitazioni', 'note_messaggio',
    'benessere_umore', 'benessere_dieta', 'benessere_workout',
}

# Plausible ranges (cm for circumferences, kg for weight, mm for skinfolds) used
# to reject nonsense like a 1000 cm arm. Mirrors the client-side guard.
_CHECK_BOUNDS = {
    'peso_corporeo': (20.0, 400.0),
    'circ_spalle': (40.0, 200.0),
    'circ_petto': (40.0, 200.0),
    'circ_vita': (30.0, 200.0),
    'circ_fianchi': (40.0, 200.0),
    'circ_coscia': (20.0, 120.0),
    'circ_braccio': (10.0, 80.0),
    'pl_petto': (1.0, 100.0),
    'pl_addome': (1.0, 100.0),
    'pl_coscia': (1.0, 100.0),
    'pl_tricipite': (1.0, 100.0),
}


def _check_form(inst):
    """Steps + questions the athlete must fill, frozen at assignment time.

    Mirrors the web fill flow: questions come from the assignment snapshot,
    steps from the live template (falling back to a single implicit step).
    `allegato` questions are kept; the app collects images for them and uploads
    them as multipart on submit.
    """
    assignment = inst.assignment
    questions = []
    for q in (assignment.snapshot_config or []):
        item = {
            'id': q.get('id'),
            'type': q.get('type', 'aperta'),
            'label': q.get('label', q.get('id')),
            'required': bool(q.get('required')),
            'unit': q.get('unit'),
            'options': q.get('options') or [],
            'min': q.get('min'),
            'max': q.get('max'),
            'min_label': q.get('minLabel'),
            'max_label': q.get('maxLabel'),
            'placeholder': q.get('placeholder'),
            'step_id': q.get('step_id'),
        }
        if q.get('type') == 'antropometria':
            # Resolve ISAK labels server-side so the app doesn't duplicate the catalog.
            item['weight'] = q.get('weight', True)
            item['circumferences'] = [
                {'key': k, 'label': circ_label(k)} for k in (q.get('circumferences') or [])
            ]
            item['skinfolds'] = [
                {'key': k, 'label': skin_label(k)} for k in (q.get('skinfolds') or [])
            ]
        questions.append(item)
    steps = (assignment.template.steps_config if assignment.template else None) or []
    if not steps:
        steps = [{'id': '__solo', 'label': 'Check', 'icon': 'ph-list'}]
    fallback_sid = steps[0].get('id')
    for q in questions:
        if not q['step_id']:
            q['step_id'] = fallback_sid
    steps = [{'id': s.get('id'), 'label': s.get('label', 'Sezione')} for s in steps]
    return {'steps': steps, 'questions': questions}


@api_view(['GET'])
def notifications(request, user):
    # Infinite scroll: ?offset=<n> pages back through the feed, 20 at a time.
    try:
        offset = max(0, int(request.GET.get('offset', 0)))
    except ValueError:
        offset = 0
    page = 20
    qs = Notification.objects.filter(target_user=user).order_by('-created_at')
    items = list(qs[offset:offset + page])
    has_more = qs.count() > offset + page
    return JsonResponse({
        'notifications': [{
            'id': n.id,
            'type': n.notification_type,
            'title': n.title,
            'body': n.body,
            'is_read': n.is_read,
            'created_at': _iso(n.created_at),
        } for n in items],
        'has_more': has_more,
    })


def _own_conversation(user, conversation_id):
    """Fetch a conversation only if it belongs to the authenticated user.

    The athlete app authenticates CLIENT users, so a conversation is "theirs"
    only when its ``client`` is the user's own profile. Returns None otherwise —
    blocks IDOR access to other athletes' chats.
    """
    client = getattr(user, 'client_profile', None)
    if not client:
        return None
    return Conversation.objects.filter(id=conversation_id, client=client).first()


@api_view(['GET'])
def conversations(request, user):
    client = getattr(user, 'client_profile', None)
    qs = Conversation.objects.none()
    if client:
        qs = Conversation.objects.filter(client=client).select_related('coach')
    out = []
    for conv in qs:
        last = conv.messages.order_by('-sent_at').first()
        out.append({
            'id': conv.id,
            'coach': _coach_dict(conv.coach),
            'last_message': last.body if last else None,
            'last_message_at': _iso(conv.last_message_at),
        })
    return JsonResponse({'conversations': out})


def _message_dict(m, user_id):
    return {
        'id': m.id,
        'body': m.body,
        'message_type': m.message_type,
        'is_mine': m.sender_user_id == user_id,
        'sent_at': _iso(m.sent_at),
    }


@api_view(['GET'])
def messages(request, user, conversation_id):
    conv = _own_conversation(user, conversation_id)
    if not conv:
        return JsonResponse({'error': 'Conversazione non trovata'}, status=404)

    # ?since=<last_id>: while the chat is open the client polls for only the
    # messages newer than the last one it holds — tiny indexed query, empty
    # result when nothing changed (no battery/payload wasted on full reloads).
    since = request.GET.get('since')
    if since and since.isdigit():
        new = conv.messages.filter(id__gt=int(since)).order_by('sent_at')
        return JsonResponse({
            'messages': [_message_dict(m, user.id) for m in new],
            'has_more': False,
        })

    # Otherwise return one page of the most recent messages. ?before=<id> walks
    # older pages on scroll-up. We fetch newest-first, then reverse so the client
    # always receives them oldest→newest (display order).
    page = 30
    qs = conv.messages.order_by('-sent_at')
    before = request.GET.get('before')
    if before and before.isdigit():
        qs = qs.filter(id__lt=int(before))
    window = list(qs[:page])
    has_more = qs.count() > page
    window.reverse()
    return JsonResponse({
        'messages': [_message_dict(m, user.id) for m in window],
        'has_more': has_more,
    })


@api_view(['POST'])
def send_message(request, user, conversation_id):
    conv = _own_conversation(user, conversation_id)
    if not conv:
        return JsonResponse({'error': 'Conversazione non trovata'}, status=404)
    body = (_body(request).get('body') or '').strip()
    if not body:
        return JsonResponse({'error': 'Messaggio vuoto'}, status=400)
    msg = Message.objects.create(conversation=conv, sender_user=user, body=body, message_type='TEXT')
    conv.last_message_at = msg.sent_at
    conv.save(update_fields=['last_message_at'])
    # Notify the coach (parity with web chat + the coach→athlete API path), so a
    # message sent from the athlete app pushes a notification to the coach.
    client = getattr(user, 'client_profile', None)
    sender_name = (f"{client.first_name} {client.last_name}".strip() if client else '') or 'Atleta'
    Notification.objects.create(
        target_user=conv.coach.user,
        notification_type='MESSAGE',
        title=f'Nuovo messaggio da {sender_name}',
        body=body[:140],
        link_url='/chat/',
    )
    return JsonResponse({'id': msg.id, 'sent_at': _iso(msg.sent_at)}, status=201)


# ---------------------------------------------------------------------------
# Subscription — "Il Mio Abbonamento"
# ---------------------------------------------------------------------------

@api_view(['GET'])
def subscription(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'subscription': None})
    sub = (
        ClientSubscription.objects
        .filter(client=client)
        .select_related('subscription_plan', 'subscription_plan__coach')
        .order_by('-start_date')
        .first()
    )
    if not sub:
        return JsonResponse({'subscription': None})
    plan = sub.subscription_plan
    return JsonResponse({'subscription': {
        'id': sub.id,
        'status': sub.status,
        'payment_status': sub.payment_status,
        'start_date': _iso(sub.start_date),
        'end_date': _iso(sub.end_date),
        'auto_renew': sub.auto_renew,
        'plan': {
            'id': plan.id,
            'name': plan.name,
            'plan_type': plan.plan_type,
            'description': plan.description,
            'price': float(plan.price),
            'currency': plan.currency,
            'duration_days': plan.duration_days,
            'billing_interval': plan.billing_interval,
            'included_services': plan.included_services or [],
            'coach': _coach_dict(plan.coach),
        },
    }})


# ---------------------------------------------------------------------------
# Appointments — "Agenda"
# ---------------------------------------------------------------------------

@api_view(['GET'])
def appointments(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'appointments': []})
    items = (
        Appointment.objects
        .filter(client=client)
        .select_related('coach')
        .order_by('start_datetime')
    )
    out = [{
        'id': a.id,
        'type': a.appointment_type,
        'title': a.title,
        'description': a.description,
        'start': _iso(a.start_datetime),
        'end': _iso(a.end_datetime),
        'duration_minutes': a.duration_minutes,
        'location': a.location,
        'meeting_url': a.meeting_url,
        'status': a.status,
        'coach': _coach_dict(a.coach),
    } for a in items]
    return JsonResponse({'appointments': out})


# ---------------------------------------------------------------------------
# Progress — submitted check history (weight series, photos, coach feedback)
# ---------------------------------------------------------------------------

@api_view(['GET'])
def progress(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'entries': []})
    responses = (
        QuestionnaireResponse.objects
        .filter(client=client, submitted_at__isnull=False)
        .prefetch_related('photos')
        .order_by('-submitted_at')
    )
    entries = [{
        'id': r.id,
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'measurements': {k: v for k, v in (r.body_circumferences or {}).items() if v not in (None, '')},
        'skinfolds': {k: v for k, v in (r.skinfolds or {}).items() if v not in (None, '')},
        'coach_feedback': r.coach_feedback,
        'notes': r.notes,
        'photos': [{
            'id': p.id,
            'url': _abs_media(request, p.file_url),
            'type': p.photo_type,
            'captured_at': _iso(p.captured_at),
        } for p in r.photos.all()],
    } for r in responses]
    return JsonResponse({'entries': entries})


# ---------------------------------------------------------------------------
# Misurazione singola — pesata/circonferenza/plica del giorno X. Salvata come
# QuestionnaireResponse leggera, quindi compare in grafico + percorso + storico.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def measurement_catalog(request, user):
    return JsonResponse(measurement_options())


def _parse_measurement_body(request):
    """(mtype, key, value, day) | (None, error_message)."""
    data = _body(request)
    mtype = (data.get('type') or '').strip()
    key = (data.get('key') or '').strip() or None
    value = data.get('value')
    day = parse_date((data.get('date') or '').strip()) or date.today()
    if mtype not in ('weight', 'circumference', 'skinfold'):
        return None, 'Tipo di misura non valido.'
    if mtype != 'weight' and not key:
        return None, 'Seleziona il punto di misura.'
    return (mtype, key, value, day), None


@api_view(['POST'])
def progress_measurement_create(request, user):
    """L'atleta inserisce una propria misurazione singola."""
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    rels = get_active_relationships(client)
    rel = rels.get('full') or rels.get('workout') or rels.get('nutrition')
    if not rel:
        return JsonResponse({'error': 'no_coach'}, status=403)
    parsed, err = _parse_measurement_body(request)
    if err:
        return JsonResponse({'error': err}, status=400)
    mtype, key, value, day = parsed
    try:
        r = create_quick_measurement(rel.coach, client, mtype, key, value, day)
    except QuickMeasurementError as e:
        return JsonResponse({'error': str(e)}, status=400)
    return JsonResponse({'id': r.id, 'submitted_at': _iso(r.submitted_at)}, status=201)


# ---------------------------------------------------------------------------
# Single-exercise trend (per-session over time) — reuses the web builder so the
# mobile chart matches the website exactly. Scoped to the athlete's own plan.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def exercise_trend(request, user, workout_exercise_id):
    from .views_session import build_exercise_trend
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    we = (WorkoutExercise.objects
          .select_related('exercise', 'workout_day__workout_plan')
          .filter(id=workout_exercise_id).first())
    if not we:
        return JsonResponse({'error': 'not found'}, status=404)
    if not WorkoutAssignment.objects.filter(
        client=client, workout_plan=we.workout_day.workout_plan).exists():
        return JsonResponse({'error': 'forbidden'}, status=403)
    return JsonResponse(build_exercise_trend(we, client))


# ---------------------------------------------------------------------------
# Notifications — mark a single notification read
# ---------------------------------------------------------------------------

@api_view(['POST'])
def notification_read(request, user, notification_id):
    n = Notification.objects.filter(id=notification_id, target_user=user).first()
    if not n:
        return JsonResponse({'error': 'Notifica non trovata'}, status=404)
    if not n.is_read:
        n.is_read = True
        n.save(update_fields=['is_read'])
    return JsonResponse({'id': n.id, 'is_read': True})


# ---------------------------------------------------------------------------
# Profile — read / edit the athlete's own ClientProfile
# ---------------------------------------------------------------------------

def _client_profile_dict(request, client):
    return {
        'first_name': client.first_name,
        'last_name': client.last_name,
        'phone': client.phone,
        'weight_kg': float(client.current_weight_kg) if client.current_weight_kg is not None else None,
        'sport': client.sport,
        'gender': client.gender,
        'birth_date': _iso(client.birth_date),
        'profile_image_url': _abs_media(request, client.profile_image.url) if client.profile_image else None,
    }


@api_view(['GET', 'PATCH'])
def profile(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Profilo non disponibile'}, status=404)
    if request.method == 'PATCH':
        data = _body(request)
        if data.get('first_name'):
            client.first_name = data['first_name'].strip()
        if data.get('last_name'):
            client.last_name = data['last_name'].strip()
        if 'phone' in data:
            client.phone = (data.get('phone') or '').strip() or None
        if 'weight_kg' in data:
            raw = data.get('weight_kg')
            try:
                client.current_weight_kg = round(float(raw), 1) if raw not in (None, '') else None
            except (TypeError, ValueError):
                pass
        if 'sport' in data:
            client.sport = (data.get('sport') or '').strip() or None
        if 'gender' in data:
            client.gender = (data.get('gender') or '').strip() or None
        if 'birth_date' in data:
            raw = (data.get('birth_date') or '').strip()
            if raw:
                parsed = parse_date(raw)
                if parsed:
                    client.birth_date = parsed
            else:
                client.birth_date = None
        client.save()
    return JsonResponse({'profile': _client_profile_dict(request, client)})


# ---------------------------------------------------------------------------
# Profile photo — upload the athlete's own avatar (multipart, gallery pick)
# ---------------------------------------------------------------------------

@api_view(['POST'])
def profile_photo(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Profilo non disponibile'}, status=404)
    upload = request.FILES.get('photo') or request.FILES.get('file')
    if not upload:
        return JsonResponse({'error': 'Nessuna immagine inviata'}, status=400)
    # Sniff real content before re-encoding: a non-image renamed to .jpg fails
    # is_image() and is rejected rather than handed to Pillow.
    if not is_image(upload):
        return JsonResponse({'error': 'Immagine non valida'}, status=400)
    try:
        webp = to_webp(upload)
    except Exception:
        return JsonResponse({'error': 'Immagine non valida'}, status=400)
    client.profile_image.save(webp.name, webp, save=True)
    return JsonResponse({'profile_image_url': _abs_media(request, client.profile_image.url)})


# ---------------------------------------------------------------------------
# Device registration — store an APNs token for push notifications
# ---------------------------------------------------------------------------

@api_view(['POST'])
def register_device(request, user):
    data = _body(request)
    token = (data.get('token') or '').strip()
    if not token:
        return JsonResponse({'error': 'Token mancante'}, status=400)
    platform = (data.get('platform') or 'ios').strip().lower()
    bundle_id = (data.get('bundle_id') or '').strip()[:128]
    defaults = {'user': user, 'platform': platform, 'is_active': True}
    if bundle_id:
        defaults['bundle_id'] = bundle_id
    DeviceToken.objects.update_or_create(token=token, defaults=defaults)
    return JsonResponse({'ok': True})


# ---------------------------------------------------------------------------
# Workout history — completed/past training sessions ("Storico Allenamenti")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def workout_history(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'sessions': [], 'has_more': False})
    try:
        offset = max(0, int(request.GET.get('offset', 0)))
    except ValueError:
        offset = 0
    page = 20
    qs = (
        WorkoutSession.objects
        .filter(client=client)
        .select_related('workout_day')
        .prefetch_related('set_logs')
        .order_by('-started_at')
    )
    sessions = list(qs[offset:offset + page])
    has_more = qs.count() > offset + page
    out = []
    for s in sessions:
        day = s.workout_day
        logs = list(s.set_logs.all())
        out.append({
            'id': s.id,
            'day_label': day.title or day.day_name or f'Giorno {day.day_order}',
            'focus_area': day.focus_area,
            'started_at': _iso(s.started_at),
            'ended_at': _iso(s.ended_at),
            'duration_minutes': s.duration_minutes,
            'avg_rpe': s.avg_rpe,
            'completed': s.completed,
            'interrupted': s.interrupted,
            'set_count': sum(1 for x in logs if x.completed),
            'notes': s.notes,
        })
    return JsonResponse({'sessions': out, 'has_more': has_more})


@api_view(['GET'])
def workout_session_detail(request, user, session_id):
    """Full detail of one of the athlete's own past sessions (logged sets)."""
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'forbidden'}, status=403)
    from .views_session import _serialize_session_full
    s = (WorkoutSession.objects
         .select_related('workout_day')
         .filter(id=session_id, client=client).first())
    if not s:
        return JsonResponse({'error': 'Sessione non trovata'}, status=404)
    return JsonResponse(_serialize_session_full(s))


# ---------------------------------------------------------------------------
# Supplements — active supplement protocol ("Integratori")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def supplements(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'sheets': []})
    assignments = (
        SupplementProtocolAssignment.objects
        .filter(client=client, status='ACTIVE')
        .select_related('protocol', 'coach')
        .prefetch_related('protocol__items')
        .order_by('-assigned_at')
    )
    sheets = []
    for a in assignments:
        sheet = a.protocol
        items = [{
            'id': it.id,
            'name': it.name,
            'quantity': it.quantity or '',
            'unit': it.unit or '',
            'timing': it.timing or '',
            'notes': it.notes or '',
        } for it in sheet.items.order_by('order', 'id')]
        sheets.append({
            'id': sheet.id,
            'title': sheet.title,
            'notes': sheet.notes or '',
            'coach': _coach_dict(a.coach),
            'items': items,
        })
    return JsonResponse({'sheets': sheets})


# ---------------------------------------------------------------------------
# Coach detail — full profile of a coach linked to this athlete ("Profilo Coach")
# ---------------------------------------------------------------------------

def _linked_coach_ids(client):
    """Coach ids actually connected to this athlete (relationships, assignments,
    conversations). Used to gate coach-scoped reads against IDOR."""
    ids = set()
    rels = get_active_relationships(client)
    for key in ('full', 'workout', 'nutrition'):
        rel = rels.get(key)
        if rel and rel.coach_id:
            ids.add(rel.coach_id)
    ids.update(WorkoutAssignment.objects.filter(client=client).values_list('coach_id', flat=True))
    ids.update(NutritionAssignment.objects.filter(client=client).values_list('coach_id', flat=True))
    ids.update(Conversation.objects.filter(client=client).values_list('coach_id', flat=True))
    return ids


@api_view(['GET'])
def coach_detail(request, user, coach_id):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Coach non trovato'}, status=404)

    if coach_id not in _linked_coach_ids(client):
        return JsonResponse({'error': 'Coach non trovato'}, status=404)
    coach = CoachProfile.objects.filter(id=coach_id).first()
    if not coach:
        return JsonResponse({'error': 'Coach non trovato'}, status=404)

    payload = _coach_dict(coach)
    payload.update({
        'bio': coach.bio,
        'description': coach.description,
        'certifications': coach.certifications,
        'years_experience': coach.years_experience,
        'social_instagram': coach.social_instagram,
        'social_youtube': coach.social_youtube,
        'social_website': coach.social_website,
    })
    return JsonResponse({'coach': payload})


# ---------------------------------------------------------------------------
# Settings — email notification preferences ("Impostazioni")
# ---------------------------------------------------------------------------

_EMAIL_NOTIF_KEYS = [
    ('workout_assigned',   'Nuovo piano di allenamento', 'Mail quando il coach ti assegna una nuova scheda.'),
    ('nutrition_assigned', 'Nuovo piano nutrizionale',   'Mail quando ti viene assegnato un piano alimentare.'),
]


@api_view(['GET', 'PATCH'])
def settings(request, user):
    if request.method == 'PATCH':
        data = _body(request)
        prefs = dict(user.email_prefs or {})
        for key, _label, _desc in _EMAIL_NOTIF_KEYS:
            if key in data:
                prefs[key] = bool(data[key])
        user.email_prefs = prefs
        user.save(update_fields=['email_prefs', 'updated_at'])
    prefs = user.email_prefs or {}
    return JsonResponse({'settings': {
        'email': user.email,
        'notifications': [
            {'key': k, 'label': label, 'desc': desc, 'enabled': bool(prefs.get(k, True))}
            for k, label, desc in _EMAIL_NOTIF_KEYS
        ],
    }})


@api_view(['POST'])
def tutorial_complete(request, user):
    # Mark the Chiron first-login tutorial as seen so it never shows again.
    if not user.chiron_intro_seen:
        user.chiron_intro_seen = True
        user.save(update_fields=['chiron_intro_seen', 'updated_at'])
    return JsonResponse({'ok': True, 'chiron_seen': True})


@api_view(['DELETE'])
def delete_account(request, user):
    # Hard delete: cascade-wipe the account and every linked row, matching the
    # web "Elimina account". Pre-clears the one PROTECT FK (ClientSubscription →
    # SubscriptionPlan) so a coach delete doesn't 500. The auth token dies with
    # the user, logging them out everywhere.
    from domain.accounts.services import hard_delete_user
    hard_delete_user(user)
    return JsonResponse({'ok': True})


# ---------------------------------------------------------------------------
# Subscription plans on offer from the athlete's coaches ("Piani e Prezzi")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def plans(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'plans': []})
    coach_ids = _linked_coach_ids(client)
    qs = (
        SubscriptionPlan.objects
        .filter(coach_id__in=coach_ids, is_active=True)
        .select_related('coach')
        .order_by('price')
    )
    out = [{
        'id': p.id,
        'name': p.name,
        'plan_type': p.plan_type,
        'description': p.description,
        'price': float(p.price),
        'currency': p.currency,
        'duration_days': p.duration_days,
        'billing_interval': p.billing_interval,
        'included_services': p.included_services or [],
        'coach': _coach_dict(p.coach),
    } for p in qs]
    return JsonResponse({'plans': out})


# ---------------------------------------------------------------------------
# Live training session ("Sessione Attiva") — start, log a set, finish
# ---------------------------------------------------------------------------

def _logged_set_dict(sl):
    return {
        'workout_exercise_id': sl.workout_exercise_id,
        'set_number': sl.set_number,
        'reps_done': sl.reps_done,
        'load_used': float(sl.load_used) if sl.load_used is not None else None,
        'load_unit': sl.load_unit,
        'rpe': sl.rpe,
        'completed': sl.completed,
    }


@api_view(['POST'])
def session_start(request, user):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Non disponibile'}, status=403)
    data = _body(request)
    assignment = WorkoutAssignment.objects.filter(id=data.get('assignment_id'), client=client).first()
    if not assignment:
        return JsonResponse({'error': 'Assegnazione non trovata'}, status=404)
    day = WorkoutDay.objects.filter(id=data.get('day_id'), workout_plan=assignment.workout_plan).first()
    if not day:
        return JsonResponse({'error': 'Giorno non trovato'}, status=404)

    # Reuse an open session for the same (assignment, day) from the last 6 hours.
    session = (
        WorkoutSession.objects
        .filter(assignment=assignment, workout_day=day, client=client,
                ended_at__isnull=True, started_at__gte=timezone.now() - timedelta(hours=6))
        .order_by('-started_at').first()
        or WorkoutSession.objects.create(assignment=assignment, workout_day=day, client=client,
                                         started_at=timezone.now())
    )

    exercises = [{
        'workout_exercise_id': ex.id,
        'name': ex.exercise.name,
        'target_muscle_group': ex.exercise.target_muscle_group,
        'sets': ex.set_count or 3,
        'reps': ex.rep_range or (str(ex.rep_count) if ex.rep_count else '10'),
        'load_value': float(ex.load_value) if ex.load_value else None,
        'load_unit': ex.load_unit or 'KG',
        'recovery_seconds': ex.recovery_seconds or 90,
        'tempo': ex.tempo or '',
        'notes': ex.technique_notes or '',
        'set_details': ex.set_details or [],
    } for ex in day.exercises.select_related('exercise').order_by('order_index')]

    sets_logged = [_logged_set_dict(sl) for sl in session.set_logs.all() if sl.set_number != 0]

    return JsonResponse({
        'session_id': session.id,
        'exercises': exercises,
        'sets_logged': sets_logged,
        'started_at': _iso(session.started_at),
    })


@api_view(['POST'])
def session_log_set(request, user, session_id):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Non disponibile'}, status=403)
    session = WorkoutSession.objects.filter(id=session_id, client=client).first()
    if not session:
        return JsonResponse({'error': 'Sessione non trovata'}, status=404)
    data = _body(request)
    we = WorkoutExercise.objects.filter(id=data.get('workout_exercise_id'),
                                        workout_day=session.workout_day).first()
    if not we:
        return JsonResponse({'error': 'Esercizio non trovato'}, status=404)

    reps = data.get('reps_done')
    load = data.get('load_used')
    rpe = data.get('rpe')
    log, _ = WorkoutSetLog.objects.update_or_create(
        session=session, workout_exercise=we, set_number=int(data.get('set_number') or 1),
        defaults={
            'reps_done': int(reps) if reps not in (None, '') else None,
            'load_used': load if load not in (None, '') else None,
            'load_unit': data.get('load_unit') or 'KG',
            'rpe': int(rpe) if rpe not in (None, '') else None,
            'completed': bool(data.get('completed', True)),
        },
    )
    return JsonResponse({'set_id': log.id, 'success': True})


@api_view(['POST'])
def session_finish(request, user, session_id):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Non disponibile'}, status=403)
    session = WorkoutSession.objects.filter(id=session_id, client=client).first()
    if not session:
        return JsonResponse({'error': 'Sessione non trovata'}, status=404)
    data = _body(request)
    interrupted = bool(data.get('interrupted', False))
    session.notes = data.get('notes') or ''
    session.ended_at = timezone.now()
    session.completed = not interrupted
    session.interrupted = interrupted
    session.recompute_summary()
    session.save()
    return JsonResponse({
        'session_id': session.id,
        'duration_minutes': session.duration_minutes,
        'avg_rpe': session.avg_rpe,
    })


# ---------------------------------------------------------------------------
# Submit a pending check-in ("Nuovo Check")
# ---------------------------------------------------------------------------

@api_view(['POST'])
def check_submit(request, user, instance_id):
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'error': 'Non disponibile'}, status=403)
    instance = (
        AssignedCheckInstance.objects
        .select_related('assignment__template', 'assignment__coach')
        .filter(id=instance_id, assignment__client=client).first()
    )
    if not instance:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    if instance.status == 'completed':
        return JsonResponse({'error': 'Check già compilato'}, status=400)
    if instance.status == 'pending' and timezone.now() > instance.expires_at:
        instance.status = 'expired'
        instance.save(update_fields=['status'])
        return JsonResponse({'error': 'Check scaduto'}, status=400)

    assignment = instance.assignment
    if not assignment.template:
        return JsonResponse({'error': 'Modello non disponibile'}, status=400)

    # Answers arrive as a JSON body, or as a JSON string in a multipart form when
    # the submit carries image attachments.
    if request.content_type and 'multipart' in request.content_type:
        try:
            answers = sanitize.clean_payload(json.loads(request.POST.get('answers') or '{}'))
        except (json.JSONDecodeError, sanitize.InvalidInput):
            answers = None
    else:
        answers = (_body(request) or {}).get('answers') or {}
    if not isinstance(answers, dict):
        return JsonResponse({'error': 'Risposte non valide'}, status=400)

    snapshot = assignment.snapshot_config or []

    # Required-question validation (allegato → at least one uploaded file;
    # antropometria is composite → not validated as a single field).
    missing = []
    for q in snapshot:
        if not q.get('required') or q.get('type') == 'antropometria':
            continue
        if q.get('type') == 'allegato':
            if not request.FILES.getlist(f'attachment_{q.get("id")}'):
                missing.append(q.get('label', q.get('id')))
        elif str(answers.get(q.get('id')) or '').strip() == '':
            missing.append(q.get('label', q.get('id')))
    if missing:
        return JsonResponse(
            {'error': 'Compila tutte le domande obbligatorie: ' + ', '.join(missing)},
            status=400,
        )

    # Range-check measurements: legacy reserved keys keep their tuned ranges;
    # antropometria keys (peso_corporeo, circ::*, pl::*) use generic bounds.
    def _bounds_for(key):
        if key in _CHECK_BOUNDS:
            return _CHECK_BOUNDS[key]
        if key == 'peso_corporeo':
            return WEIGHT_RANGE
        if key.startswith('circ::'):
            return circ_range(key[len('circ::'):]) or (5.0, 250.0)
        if key.startswith('pl::'):
            return skin_range(key[len('pl::'):])
        return None
    for key, raw in answers.items():
        bounds = _bounds_for(key)
        if not bounds or raw in (None, ''):
            continue
        lo, hi = bounds
        try:
            val = float(str(raw).replace(',', '.'))
        except (ValueError, TypeError):
            return JsonResponse({'error': f'Valore non numerico per «{key}».'}, status=400)
        if not (lo <= val <= hi):
            return JsonResponse(
                {'error': f'Valore fuori scala per «{key}» (atteso {lo:g}–{hi:g}).'},
                status=400,
            )

    def _pm(v):
        try:
            f = float(v or 0)
            return str(round(f, 1)) if f > 0 else ''
        except (ValueError, TypeError):
            return ''

    weight, body_circ, skinfolds = build_measurements(answers, snapshot, _pm)

    answers_json = {
        'mood': answers.get('benessere_umore', ''),
        'diet_adherence': answers.get('benessere_dieta', ''),
        'workout_adherence': answers.get('benessere_workout', ''),
    }
    for k, v in answers.items():
        if k in _CHECK_RESERVED or k.startswith('circ::') or k.startswith('pl::'):
            continue
        answers_json[k] = v

    resp = QuestionnaireResponse.objects.create(
        questionnaire_template=assignment.template,
        client=client,
        coach=assignment.coach,
        submitted_at=timezone.now(),
        status='COMPLETED',
        weight_kg=weight,
        body_circumferences=body_circ,
        skinfolds=skinfolds,
        answers_json=answers_json,
        injuries=answers.get('note_infortuni', ''),
        limitations=answers.get('note_limitazioni', ''),
        notes=(answers.get('note_messaggio') or '').strip(),
    )
    instance.status = 'completed'
    instance.response = resp
    instance.save(update_fields=['status', 'response'])

    # Persist any uploaded images for `allegato` questions. The app already
    # downscales/compresses client-side; we re-encode to WebP as a backstop.
    for q in snapshot:
        if q.get('type') != 'allegato':
            continue
        for f in request.FILES.getlist(f'attachment_{q.get("id")}'):
            prefix = f'check_attachments/{client.id}/{q.get("id")}_{int(timezone.now().timestamp())}_'
            saved, kind = store_attachment(f, dir_prefix=prefix)
            if not saved:
                continue  # rejected: not a real image or video
            QuestionAttachment.objects.create(
                response=resp,
                question_id=q.get('id'),
                file_url=default_storage.url(saved),
                file_name=f.name,
                mime_type=getattr(f, 'content_type', '') or '',
            )

    Notification.objects.create(
        target_user=assignment.coach.user,
        notification_type='CHECK_SUBMITTED',
        title=f'{client.first_name} ha compilato il check',
        body=f'{client.first_name} {client.last_name} ha compilato «{assignment.template.title}».',
        link_url=f'/check/{resp.id}/',
    )
    # Email the coach — parity with the web submit flow (views_check/pages.py),
    # so checks submitted from the iOS app also notify the coach by mail.
    try:
        from .views_check.assignments import _notify_coach_check_completed
        _notify_coach_check_completed(instance)
    except Exception:
        pass
    return JsonResponse({'id': resp.id, 'status': 'completed'}, status=201)


# ---------------------------------------------------------------------------
# Prima Valutazione — athlete reads their own first-visit check summary
# ---------------------------------------------------------------------------

@api_view(['GET'])
def prima_valutazione(request, user):
    """Return the latest submitted prima_valutazione check response for the
    authenticated athlete as a structured summary for the iOS anamnesi screen.
    Returns {submitted_at: null} if no completed response exists yet."""
    client = getattr(user, 'client_profile', None)
    if not client:
        return JsonResponse({'submitted_at': None, 'data': None})

    resp = (
        QuestionnaireResponse.objects
        .filter(
            client=client,
            status='SUBMITTED',
            questionnaire_template__preset_key='prima_valutazione',
        )
        .order_by('-submitted_at')
        .first()
    )
    if not resp:
        return JsonResponse({'submitted_at': None, 'data': None})

    a = resp.answers_json or {}

    def _str(key):
        v = a.get(key)
        return str(v).strip() if v else None

    def _float(key):
        try:
            return float(a.get(key) or 0) or None
        except (TypeError, ValueError):
            return None

    def _int(key):
        try:
            return int(float(a.get(key) or 0)) or None
        except (TypeError, ValueError):
            return None

    # Anthropometry comes from the 'antropometria' compound question
    antrop = a.get('antropometria') or {}
    if isinstance(antrop, str):
        import json as _json
        try:
            antrop = _json.loads(antrop)
        except Exception:
            antrop = {}

    fabbisogni_data = None
    det_kcal = _int('det_finale_kcal') or _int('det_kcal')
    if any([det_kcal, _int('proteine_g_totale'), _int('carboidrati_g_totale')]):
        fabbisogni_data = {
            'det_kcal': det_kcal,
            'proteine_g': _int('proteine_g_totale'),
            'carboidrati_g': _int('carboidrati_g_totale'),
            'lipidi_g': _int('lipidi_g_totale'),
            'fibra_g': _int('fibra_gdie'),
            'idrico_ml': _int('idrico_mldie'),
        }

    return JsonResponse({
        'submitted_at': _iso(resp.submitted_at),
        'data': {
            'storia': {
                'patologie': _str('pv_clin_patologie'),
                'allergie': _str('pv_clin_allergie'),
                'interventi': _str('pv_clin_interventi'),
                'familiarita': _str('pv_clin_familiarita'),
                'farmaci': _str('pv_clin_farmaci'),
                'professionisti_seguiti': a.get('pv_prof_seguito'),
            },
            'antropometria': {
                'altezza_cm': _float('pv_antrop_altezza'),
                'peso_kg': float(resp.weight_kg) if resp.weight_kg else _float('pv_antrop_peso_abituale'),
                'peso_abituale_kg': _float('pv_antrop_peso_abituale'),
                'circonferenze': antrop.get('circumferences') if isinstance(antrop, dict) else None,
            },
            'allenamento': {
                'discipline': a.get('pv_all_discipline'),
                'anni_esperienza': _int('pv_all_anni'),
                'sedute_settimana': _int('pv_all_sedute'),
                'durata_media_min': _int('pv_all_durata'),
            },
            'fabbisogni': fabbisogni_data,
            'obiettivi': {
                'obiettivo_principale': _str('pv_ob_obiettivo'),
                'motivazione': _str('pv_ob_motivazione'),
                'scadenza': _str('pv_ob_scadenza'),
            },
        },
    })


# ---------------------------------------------------------------------------
# Forgot password — public, generic response ("Reset Password")
# ---------------------------------------------------------------------------

@csrf_exempt
def forgot_password(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Metodo non consentito'}, status=405)
    data = _body(request)
    email = (data.get('email') or '').strip().lower()
    ip = request.META.get('REMOTE_ADDR')
    ua = (request.META.get('HTTP_USER_AGENT') or '')[:512]
    try:
        from .views_auth import _maybe_issue_reset
        _maybe_issue_reset(email, ip, ua)
    except Exception:
        logger.exception('api forgot-password failed')
    # Always generic: never reveal whether the email exists.
    return JsonResponse({'message': "Se l'email è registrata, riceverai un link per reimpostare la password."})
