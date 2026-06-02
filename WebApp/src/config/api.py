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

from django.contrib.auth.hashers import check_password
from django.core import signing
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from domain.accounts.models import User
from domain.chat.models import Conversation, Message, Notification
from domain.checks.models import AssignedCheckInstance
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import NutritionAssignment
from domain.workouts.models import WorkoutAssignment

from .session_utils import get_active_relationships

logger = logging.getLogger(__name__)

# Tokens are signed, not encrypted: the payload (user id) is readable but cannot
# be forged without SECRET_KEY. 30-day lifetime keeps the athlete logged in.
TOKEN_SALT = 'athlynk.api.v1.token'
TOKEN_MAX_AGE = 60 * 60 * 24 * 30


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
            return view(request, user, *args, **kwargs)
        wrapper.__name__ = view.__name__
        return wrapper
    return decorator


def _body(request):
    try:
        return json.loads(request.body or b'{}')
    except (ValueError, TypeError):
        return {}


def _iso(dt):
    return dt.isoformat() if dt else None


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
    try:
        user = User.objects.get(email__iexact=email)
    except User.DoesNotExist:
        return JsonResponse({'error': 'Credenziali non valide'}, status=401)
    if not check_password(password, user.password_hash):
        return JsonResponse({'error': 'Credenziali non valide'}, status=401)
    if not user.is_verified:
        return JsonResponse({'error': 'Email non verificata'}, status=403)

    user.last_login_at = timezone.now()
    user.save(update_fields=['last_login_at'])
    return JsonResponse({'token': issue_token(user), 'user': _user_dict(user)})


@api_view(['GET'])
def me(request, user):
    payload = {'user': _user_dict(user), 'coach': None, 'trainer': None, 'nutritionist': None}
    client = getattr(user, 'client_profile', None)
    if client:
        rels = get_active_relationships(client)
        payload['coach'] = _coach_dict(rels['full'].coach if rels['full'] else None)
        payload['trainer'] = _coach_dict(rels['workout'].coach if rels['workout'] else None)
        payload['nutritionist'] = _coach_dict(rels['nutrition'].coach if rels['nutrition'] else None)
        payload['profile'] = {
            'height_cm': client.height_cm,
            'primary_goal': client.primary_goal,
            'activity_level': client.activity_level,
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
    } for inst in instances]
    return JsonResponse({'pending': pending})


@api_view(['GET'])
def notifications(request, user):
    items = Notification.objects.filter(target_user=user).order_by('-created_at')[:50]
    return JsonResponse({'notifications': [{
        'id': n.id,
        'type': n.notification_type,
        'title': n.title,
        'body': n.body,
        'is_read': n.is_read,
        'created_at': _iso(n.created_at),
    } for n in items]})


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


@api_view(['GET'])
def messages(request, user, conversation_id):
    conv = _own_conversation(user, conversation_id)
    if not conv:
        return JsonResponse({'error': 'Conversazione non trovata'}, status=404)
    msgs = conv.messages.order_by('sent_at')[:200]
    return JsonResponse({'messages': [{
        'id': m.id,
        'body': m.body,
        'message_type': m.message_type,
        'is_mine': m.sender_user_id == user.id,
        'sent_at': _iso(m.sent_at),
    } for m in msgs]})


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
    return JsonResponse({'id': msg.id, 'sent_at': _iso(msg.sent_at)}, status=201)
