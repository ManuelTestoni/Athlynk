"""Mobile JSON API (v1) — coach side, for the *Athlynk Coach* iOS app.

Companion to ``config/api.py`` (the athlete API). Same design constraints:
no DRF, plain ``JsonResponse``, stateless signed Bearer tokens, no new models.
Every endpoint is scoped to the authenticated **coach** (``user.coach_profile``)
and mirrors the read logic the web coach views already use, so the two clients
stay in sync.

Endpoints are mounted under ``/api/v1/coach/...`` (see ``config/urls.py``).
Shared, role-agnostic endpoints (notifications, settings, device registration,
account deletion) are reused from the athlete API and are not duplicated here.
"""

import json
import logging
from datetime import date, timedelta

from django.db import transaction
from django.db.models import Q, Max, Count, Sum, OuterRef, Subquery
from django.http import JsonResponse, StreamingHttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime

from domain.accounts.models import ClientProfile, CoachProfile
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.calendar.models import Appointment
from domain.chat.models import AutomaticMessageTemplate, Conversation, Message, Notification
from domain.checks.models import QuestionnaireResponse, QuestionnaireTemplate
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import (
    DietDay, Food, Meal, MealItem,
    NutritionAssignment, NutritionPlan, SupplementProtocol, SupplementItem,
    SupplementProtocolAssignment,
)
from domain.workouts.models import (
    Exercise, WorkoutAssignment, WorkoutDay, WorkoutExercise, WorkoutPlan,
    WorkoutSession,
)

from .api import (
    api_view, _body, _iso, _abs_media, _coach_dict, _message_dict,
    coach_dual_auth, _request_coach, _parse_measurement_body,
    _bearer, _user_from_token, _day_dict, macro_history_payload,
)
from .http_utils import safe_int
from .session_utils import can_manage_nutrition, can_manage_workouts
from .views_check import (
    create_quick_measurement, QuickMeasurementError,
    build_measurements, RESERVED_FIELD_MAP,
)
from .views_check.helpers import _response_config, _build_prefill
from .views_check.templates_admin import _ensure_preset_clones, PRESET_ORDER
from .views_check.assignments import _create_instance
from .views_client import (
    _create_client_subscription, _rel_type_for,
    _build_percorso_events, _serialize_phases, _one_year_after_month,
)
from .views_nutrition import WEEKDAY_REVERSE, _serialize_protocol, _parse_supplement_items
from .views_session import (
    build_exercise_trend, _serialize_session_brief, _serialize_session_full,
)
from .views_workouts import _serialize_plan_for_wizard

from domain.analytics.models import (
    CoachBusinessMetricsDaily, DailyFeatureStore, RiskScoreDaily,
)
from domain.analytics.services import rules_engine as _rules
from .services import password_reset as pwd_reset
from .services.email import send_account_activation
from .services.tokens import get_client_ip
from domain.accounts.models import User
from domain.checks.models import AssignedCheck
from domain.checks.preset_templates import PRESETS, build_template_payload
from domain.checks.anthropometry import catalog_json, circ_label, skin_label
from django.contrib.auth.hashers import make_password
from chiron.agent import run_chiron, run_chiron_stream
from chiron.memory import build_context, reset as reset_chiron_memory
from chiron.actions import execute_action as chiron_execute_action
from domain.chiron.models import ChironMessage

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _require_coach(user):
    """Return (coach, error_response). Error if the token isn't a coach's."""
    coach = getattr(user, 'coach_profile', None)
    if not coach:
        return None, JsonResponse({'error': 'Solo per professionisti'}, status=403)
    return coach, None


def _coach_or_401(request):
    """Return (coach, error_response) for dual-auth (bearer OR session) coach views.
    Gives specific 401 messages so iOS can distinguish invalid-token from missing-profile."""
    coach = _request_coach(request)
    if coach:
        return coach, None
    bearer = _bearer(request)
    if bearer:
        user = _user_from_token(bearer)
        if user is None:
            return None, JsonResponse({'error': 'Token non valido o scaduto. Effettua nuovamente l\'accesso.'}, status=401)
        return None, JsonResponse({'error': 'Profilo coach non trovato. Contatta il supporto.'}, status=401)
    return None, JsonResponse({'error': 'Non autenticato'}, status=401)


def _coach_avatar(request, coach):
    """Prefer the uploaded file; fall back to the stored URL."""
    if coach.profile_image:
        return _abs_media(request, coach.profile_image.url)
    return coach.profile_image_url


def _client_avatar(request, client):
    return _abs_media(request, client.profile_image.url) if client.profile_image else None


def _client_brief(request, client):
    first, last = client.first_name, client.last_name
    return {
        'id': client.id,
        'first_name': first,
        'last_name': last,
        'display_name': (f'{first} {last}'.strip() or 'Atleta'),
        'profile_image_url': _client_avatar(request, client),
        'sport': client.sport,
    }


def _coach_profile_dict(request, coach):
    return {
        'id': coach.id,
        'first_name': coach.first_name,
        'last_name': coach.last_name,
        'professional_type': coach.professional_type,
        'specialization': coach.specialization,
        'city': coach.city,
        'phone': coach.phone,
        'bio': coach.bio,
        'description': coach.description,
        'certifications': coach.certifications,
        'years_experience': coach.years_experience,
        'profile_image_url': _coach_avatar(request, coach),
        'social_instagram': coach.social_instagram,
        'social_youtube': coach.social_youtube,
        'social_tiktok': coach.social_tiktok,
        'social_website': coach.social_website,
        'email': coach.user.email,
    }


def _pending_review_qs(coach):
    """Submitted check-ins still awaiting the coach's written feedback."""
    return (
        QuestionnaireResponse.objects
        .filter(coach=coach, submitted_at__isnull=False)
        .filter(Q(coach_feedback__isnull=True) | Q(coach_feedback=''))
    )


def _unread_messages_qs(coach):
    """Client → coach messages not yet read by the coach."""
    return (
        Message.objects
        .filter(conversation__coach=coach, read_at__isnull=True)
        .exclude(sender_user=coach.user)
    )


# ---------------------------------------------------------------------------
# Dashboard ("Dashboard Coach")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def dashboard(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    today = date.today()

    active_clients = CoachingRelationship.objects.filter(coach=coach, status='ACTIVE').count()
    pending_checks = _pending_review_qs(coach).count()
    appts_today = Appointment.objects.filter(coach=coach, start_datetime__date=today).count()
    unread = _unread_messages_qs(coach).count()

    agenda = [{
        'id': a.id,
        'title': a.title,
        'type': a.appointment_type,
        'start': _iso(a.start_datetime),
        'duration_minutes': a.duration_minutes,
        'location': a.location,
        'meeting_url': a.meeting_url,
        'client': _client_brief(request, a.client),
    } for a in (
        Appointment.objects
        .filter(coach=coach, start_datetime__date=today)
        .select_related('client', 'client__user')
        .order_by('start_datetime')
    )]

    activity = [{
        'id': n.id,
        'type': n.notification_type,
        'title': n.title,
        'body': n.body,
        'created_at': _iso(n.created_at),
    } for n in Notification.objects.filter(target_user=user).order_by('-created_at')[:8]]

    # A real, lightweight performance line: checks reviewed this week.
    week_start = today - timedelta(days=today.weekday())
    checks_this_week = QuestionnaireResponse.objects.filter(
        coach=coach, submitted_at__date__gte=week_start
    ).count()

    return JsonResponse({
        'coach': _coach_profile_dict(request, coach),
        'stats': {
            'active_clients': active_clients,
            'pending_checks': pending_checks,
            'appointments_today': appts_today,
            'unread_messages': unread,
        },
        'agenda': agenda,
        'activity': activity,
        'insight': {
            'checks_this_week': checks_this_week,
            'text': (
                f'{checks_this_week} check ricevuti questa settimana.'
                if checks_this_week else 'Nessun nuovo check questa settimana.'
            ),
        },
    })


# ---------------------------------------------------------------------------
# Agenda ("Agenda") — upcoming appointments for the coach.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def agenda(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    now = timezone.now()
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    qs = (
        Appointment.objects
        .filter(coach=coach, start_datetime__gte=now - timedelta(hours=12))
        .select_related('client', 'client__user')
        .order_by('start_datetime')
    )
    total = qs.count()
    items = qs[offset:offset + PAGE]
    out = [{
        'id': a.id,
        'title': a.title,
        'type': a.appointment_type,
        'description': a.description,
        'start': _iso(a.start_datetime),
        'duration_minutes': a.duration_minutes,
        'location': a.location,
        'meeting_url': a.meeting_url,
        'status': a.status,
        'client': _client_brief(request, a.client),
    } for a in items]
    return JsonResponse({'appointments': out, 'has_more': offset + PAGE < total})


# ---------------------------------------------------------------------------
# Clients ("Lista Clienti Coach")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def clients(request, user):
    coach, err = _require_coach(user)
    if err:
        return err

    search = (request.GET.get('q') or '').strip()
    status_filter = (request.GET.get('status') or '').strip().upper()

    qs = (
        CoachingRelationship.objects
        .filter(coach=coach)
        .select_related('client', 'client__user')
        .order_by('-start_date', '-created_at')
    )
    if status_filter:
        qs = qs.filter(status=status_filter)
    if search:
        qs = qs.filter(Q(client__first_name__icontains=search) | Q(client__last_name__icontains=search))

    # Page the list (10 per page) but keep the header counts over the full set.
    total = qs.count()
    active = qs.filter(status='ACTIVE').count()
    offset = max(0, safe_int(request.GET, 'offset', 0))
    # Default page is 10 (the list view); the check-form client picker passes a
    # large `limit` to fetch the full active roster in one go.
    try:
        page = min(max(int(request.GET.get('limit') or 10), 1), 500)
    except (ValueError, TypeError):
        page = 10
    rels = list(qs[offset:offset + page])
    client_ids = [r.client_id for r in rels]

    active_workouts = {
        wa.client_id: wa.workout_plan.title
        for wa in WorkoutAssignment.objects
        .filter(client_id__in=client_ids, coach=coach, status='ACTIVE')
        .select_related('workout_plan')
    }
    last_check = dict(
        QuestionnaireResponse.objects
        .filter(client_id__in=client_ids, coach=coach)
        .values('client_id').annotate(d=Max('submitted_at'))
        .values_list('client_id', 'd')
    )
    active_subs = {
        s.client_id: s.subscription_plan.name
        for s in ClientSubscription.objects
        .filter(client_id__in=client_ids, subscription_plan__coach=coach, status='ACTIVE')
        .select_related('subscription_plan')
    }

    out = []
    for r in rels:
        brief = _client_brief(request, r.client)
        brief.update({
            'relationship_id': r.id,
            'relationship_type': r.relationship_type,
            'status': r.status,
            'start_date': _iso(r.start_date),
            'active_workout': active_workouts.get(r.client_id),
            'active_plan': active_subs.get(r.client_id),
            'last_check_at': _iso(last_check.get(r.client_id)),
        })
        out.append(brief)

    return JsonResponse({
        'clients': out,
        'total': total,
        'active': active,
        'has_more': offset + page < total,
    })


def _own_relationship(coach, client_id):
    return (
        CoachingRelationship.objects
        .select_related('client', 'client__user')
        .filter(coach=coach, client_id=client_id)
        .first()
    )


@api_view(['GET'])
def client_detail(request, user, client_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    client = rel.client

    aw = (WorkoutAssignment.objects.filter(client=client, coach=coach, status='ACTIVE')
          .select_related('workout_plan').first())
    an = (NutritionAssignment.objects.filter(client=client, coach=coach, status='ACTIVE')
          .select_related('nutrition_plan').first())
    sub = (ClientSubscription.objects.filter(client=client, subscription_plan__coach=coach, status='ACTIVE')
           .select_related('subscription_plan').order_by('-start_date').first())

    checks = [{
        'id': r.id,
        'title': r.questionnaire_template.title if r.questionnaire_template else 'Check',
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'reviewed': bool(r.coach_feedback),
    } for r in (
        QuestionnaireResponse.objects
        .filter(client=client, coach=coach, submitted_at__isnull=False)
        .select_related('questionnaire_template')
        .order_by('-submitted_at')[:10]
    )]

    sheets = [{
        'id': sa.protocol.id,
        'title': sa.protocol.title,
    } for sa in (
        SupplementProtocolAssignment.objects.filter(client=client, coach=coach, status='ACTIVE')
        .select_related('protocol')
    )]

    conv = Conversation.objects.filter(coach=coach, client=client).first()

    brief = _client_brief(request, client)
    brief.update({
        'phone': client.phone,
        'gender': client.gender,
        'birth_date': _iso(client.birth_date),
        'weight_kg': float(client.current_weight_kg) if client.current_weight_kg is not None else None,
        'email': client.user.email,
    })

    return JsonResponse({
        'client': brief,
        'relationship': {
            'id': rel.id,
            'type': rel.relationship_type,
            'status': rel.status,
            'start_date': _iso(rel.start_date),
            'internal_notes': rel.internal_notes,
        },
        'active_workout': {'assignment_id': aw.id, 'title': aw.workout_plan.title} if aw else None,
        'active_nutrition': {'assignment_id': an.id, 'title': an.nutrition_plan.title,
                             'plan_mode': an.nutrition_plan.plan_mode} if an else None,
        'active_subscription': {
            'id': sub.id, 'name': sub.subscription_plan.name,
            'price': float(sub.subscription_plan.price), 'status': sub.status,
            'end_date': _iso(sub.end_date),
        } if sub else None,
        'checks': checks,
        'supplement_sheets': sheets,
        'conversation_id': conv.id if conv else None,
    })


# ---------------------------------------------------------------------------
# Check-in review ("Revisione Check-in")
# ---------------------------------------------------------------------------

def _measurements(r):
    return {k: v for k, v in (r.body_circumferences or {}).items() if v not in (None, '')}


@api_view(['GET'])
def checks_review(request, user):
    """Submitted check-ins. ?filter=pending (default) | all. ?offset=N for pagination."""
    coach, err = _require_coach(user)
    if err:
        return err
    which = (request.GET.get('filter') or 'pending').strip()
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    qs = (
        QuestionnaireResponse.objects
        .filter(coach=coach, submitted_at__isnull=False)
        .defer('answers_json', 'questions_snapshot', 'steps_snapshot',
               'body_circumferences', 'skinfolds')
        .select_related('client', 'client__user', 'questionnaire_template')
        .order_by('-submitted_at')
    )
    if which == 'pending':
        qs = qs.filter(Q(coach_feedback__isnull=True) | Q(coach_feedback=''))

    window = list(qs[offset:offset + PAGE + 1])
    out = [{
        'id': r.id,
        'title': r.questionnaire_template.title if r.questionnaire_template else 'Check',
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'reviewed': bool(r.coach_feedback),
        'client': _client_brief(request, r.client),
    } for r in window[:PAGE]]
    return JsonResponse({
        'checks': out,
        'pending_count': _pending_review_qs(coach).count(),
        'has_more': len(window) > PAGE,
    })


@api_view(['GET'])
def check_detail(request, user, response_id):
    coach, err = _require_coach(user)
    if err:
        return err
    r = (
        QuestionnaireResponse.objects
        .filter(id=response_id, coach=coach)
        .select_related('client', 'client__user', 'questionnaire_template')
        .prefetch_related('photos', 'attachments').first()
    )
    if not r:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    return JsonResponse({'check': {
        'id': r.id,
        'title': r.questionnaire_template.title if r.questionnaire_template else 'Check',
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'measurements': _measurements(r),
        'skinfolds': {k: v for k, v in (r.skinfolds or {}).items() if v not in (None, '')},
        'answers': r.answers_json or {},
        'notes': r.notes,
        'injuries': r.injuries,
        'limitations': r.limitations,
        'coach_feedback': r.coach_feedback or '',
        'coach_private_notes': r.coach_private_notes or '',
        'client': _client_brief(request, r.client),
        'photos': [{
            'id': p.id,
            'url': _abs_media(request, p.file_url),
            'type': p.photo_type,
            'captured_at': _iso(p.captured_at),
        } for p in r.photos.all()],
    }})


@api_view(['POST'])
def check_feedback(request, user, response_id):
    coach, err = _require_coach(user)
    if err:
        return err
    r = QuestionnaireResponse.objects.filter(id=response_id, coach=coach).select_related('client', 'client__user').first()
    if not r:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    data = _body(request)
    feedback = (data.get('feedback') or '').strip()
    if not feedback:
        return JsonResponse({'error': 'Feedback vuoto'}, status=400)
    r.coach_feedback = feedback
    if 'private_notes' in data:
        r.coach_private_notes = (data.get('private_notes') or '').strip()
    r.save(update_fields=['coach_feedback', 'coach_private_notes', 'updated_at'])

    Notification.objects.create(
        target_user=r.client.user,
        notification_type='CHECK_REVIEWED',
        title='Il tuo coach ha revisionato il check',
        body=f'{coach.first_name} ha lasciato un feedback sul tuo ultimo check.',
        link_url='/progressi/',
    )
    return JsonResponse({'id': r.id, 'coach_feedback': r.coach_feedback})


@coach_dual_auth
def client_fabbisogni(request, client_id):
    """Ultimi fabbisogni calcolati per il cliente: prima risposta (più recente)
    che contiene lo strumento «Calcolo Fabbisogni» (<90gg = fresh).
    Dual-auth: usato dall'app coach (token) e dal builder web (sessione)."""
    coach = _request_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autenticato'}, status=401)
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    cutoff = timezone.now() - timedelta(days=90)
    resp = None
    recent = (QuestionnaireResponse.objects
              .filter(client_id=client_id, coach=coach)
              .select_related('questionnaire_template')
              .order_by('-submitted_at')[:80])
    for r in recent:
        qcfg, _ = _response_config(r)
        if any(q.get('type') == 'strumento_fabbisogni' for q in qcfg):
            resp = r
            break
    if not resp:
        return JsonResponse({'fresh': False, 'submitted_at': None, 'data': None})
    fresh = resp.submitted_at is not None and resp.submitted_at >= cutoff
    answers = resp.answers_json or {}
    def _int(key):
        try:
            return int(float(answers.get(key) or 0)) or None
        except (TypeError, ValueError):
            return None
    return JsonResponse({
        'fresh': fresh,
        'submitted_at': _iso(resp.submitted_at),
        'data': {
            'det_kcal':        _int('det_finale_kcal') or _int('det_kcal'),
            'proteine_g':      _int('proteine_g_totale'),
            'carboidrati_g':   _int('carboidrati_g_totale'),
            'lipidi_g':        _int('lipidi_g_totale'),
            'fibra_g':         _int('fibra_gdie'),
            'idrico_ml':       _int('idrico_mldie'),
        },
    })


@api_view(['POST'])
def client_measurement_create(request, user, client_id):
    """Coach inserisce una misurazione singola per un proprio cliente."""
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    parsed, perr = _parse_measurement_body(request)
    if perr:
        return JsonResponse({'error': perr}, status=400)
    mtype, key, value, day = parsed
    try:
        r = create_quick_measurement(coach, rel.client, mtype, key, value, day)
    except QuickMeasurementError as e:
        return JsonResponse({'error': str(e)}, status=400)
    return JsonResponse({'id': r.id, 'submitted_at': _iso(r.submitted_at)}, status=201)


# ---------------------------------------------------------------------------
# Onboarding cliente — il coach crea un atleta dall'app (come nella web app).
# L'atleta riceve un'email per impostare la propria password.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def subscription_plans(request, user):
    """Piani di abbonamento attivi del coach, per il picker di onboarding."""
    coach, err = _require_coach(user)
    if err:
        return err
    plans = SubscriptionPlan.objects.filter(coach=coach, is_active=True).order_by('name')
    return JsonResponse({'plans': [{
        'id': p.id,
        'name': p.name,
        'price': float(p.price),
        'duration_days': p.duration_days,
    } for p in plans]})


@api_view(['POST'])
def create_client(request, user):
    """Crea un nuovo atleta + relazione + abbonamento e invia l'email di attivazione.
    Rispecchia il ramo "nuovo atleta" di registra_client_view (web)."""
    coach, err = _require_coach(user)
    if err:
        return err
    data = _body(request)
    first_name = (data.get('first_name') or '').strip()
    last_name = (data.get('last_name') or '').strip()
    email = (data.get('email') or '').strip().lower()
    phone = (data.get('phone') or '').strip() or None
    gender = (data.get('gender') or '').strip() or None
    plan_id = str(data.get('subscription_plan_id') or '').strip()
    payment_notes = (data.get('payment_notes') or '').strip() or None
    birth_date = parse_date((data.get('birth_date') or '').strip()) if data.get('birth_date') else None

    errors = {}
    if not first_name:
        errors['first_name'] = 'Il nome è obbligatorio.'
    if not last_name:
        errors['last_name'] = 'Il cognome è obbligatorio.'
    if not email:
        errors['email'] = "L'email è obbligatoria."
    elif User.objects.filter(email__iexact=email).exists():
        errors['email'] = 'Questa email è già registrata sulla piattaforma.'
    if not plan_id:
        errors['subscription_plan_id'] = 'Seleziona un piano di abbonamento.'
    if errors:
        return JsonResponse({'error': 'Dati non validi', 'fields': errors}, status=400)

    with transaction.atomic():
        new_user = User.objects.create(
            email=email,
            password_hash=make_password(None),
            role='CLIENT',
            is_active=True,
            is_verified=True,
        )
        client = ClientProfile.objects.create(
            user=new_user,
            first_name=first_name,
            last_name=last_name,
            phone=phone,
            birth_date=birth_date,
            gender=gender,
            client_status='ACTIVE',
            onboarding_status='REGISTERED',
        )
        CoachingRelationship.objects.create(
            coach=coach, client=client, status='ACTIVE',
            start_date=timezone.now().date(), relationship_type=_rel_type_for(coach),
        )
        _create_client_subscription(coach, client, plan_id, payment_notes)

    token = pwd_reset.issue_token(
        new_user,
        ip=get_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        ttl_minutes=pwd_reset.ACTIVATION_TTL_MINUTES,
    )
    send_account_activation(new_user, token, coach_name=f"{coach.first_name} {coach.last_name}".strip())

    return JsonResponse({
        'id': client.id,
        'display_name': f"{first_name} {last_name}".strip(),
        'message': 'Email di attivazione inviata.',
    }, status=201)


# ---------------------------------------------------------------------------
# Gestione modelli check (parità con la web app): lista, dettaglio, crea,
# modifica, duplica, elimina, ripristina preset, assegna, compila, modifica valori.
# Riusa la logica del dominio check già usata dalle view web.
# ---------------------------------------------------------------------------

def _template_summary(t):
    return {
        'id': t.id,
        'title': t.title,
        'description': t.description or '',
        'preset_key': t.preset_key or '',
        'is_modified_preset': bool(t.is_modified_preset),
        'questionnaire_type': t.questionnaire_type,
        'questions_count': len(t.questions_config or []),
        'steps_count': len(t.steps_config or []),
        'updated_at': _iso(t.updated_at),
    }


def _own_template(coach, template_id):
    return QuestionnaireTemplate.objects.filter(id=template_id, coach=coach, is_active=True).first()


def _resolve_questions(questions_config):
    """Questions in the same shape the athlete fill form consumes: ISAK labels for
    antropometria are resolved server-side. Mirrors api._check_form."""
    out = []
    for q in (questions_config or []):
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
            item['weight'] = q.get('weight', True)
            item['circumferences'] = [
                {'key': k, 'label': circ_label(k)} for k in (q.get('circumferences') or [])
            ]
            item['skinfolds'] = [
                {'key': k, 'label': skin_label(k)} for k in (q.get('skinfolds') or [])
            ]
        out.append(item)
    return out


def _parse_metric(val):
    try:
        v = float(val or 0)
        return str(round(v, 1)) if v > 0 else ''
    except (ValueError, TypeError):
        return ''


def _answers_to_fields(raw_answers, questions_config):
    """Da raw_answers (chiavi web: peso_corporeo, circ::k, pl::k, benessere_*,
    note_*, custom) ai campi della QuestionnaireResponse. Mirror del web."""
    weight_kg, circ, skin = build_measurements(raw_answers, questions_config, _parse_metric)
    answers_json = {
        'mood': raw_answers.get('benessere_umore', ''),
        'diet_adherence': raw_answers.get('benessere_dieta', ''),
        'workout_adherence': raw_answers.get('benessere_workout', ''),
    }
    for k, v in raw_answers.items():
        if k == 'peso_corporeo' or k in RESERVED_FIELD_MAP \
                or k.startswith('circ::') or k.startswith('pl::'):
            continue
        answers_json.setdefault(k, v)
    return {
        'weight_kg': weight_kg,
        'body_circumferences': circ,
        'skinfolds': skin,
        'answers_json': answers_json,
        'injuries': raw_answers.get('note_infortuni', ''),
        'limitations': raw_answers.get('note_limitazioni', ''),
        'notes': raw_answers.get('note_messaggio', ''),
    }


@api_view(['GET'])
def check_catalog(request, user):
    """Catalogo antropometrico ISAK per il builder mobile (circ/pliche/peso)."""
    coach, err = _require_coach(user)
    if err:
        return err
    return JsonResponse(catalog_json())


@api_view(['GET'])
def check_templates(request, user):
    """Modelli del coach: preset (clonati lazy) + custom."""
    coach, err = _require_coach(user)
    if err:
        return err
    _ensure_preset_clones(coach)
    all_t = list(QuestionnaireTemplate.objects.filter(coach=coach, is_active=True)
                 .exclude(questionnaire_type='quick_measurement')
                 .defer('report_config'))
    by_key = {t.preset_key: t for t in all_t if t.preset_key}
    presets = [_template_summary(by_key[k]) for k in PRESET_ORDER if k in by_key]
    customs = [_template_summary(t) for t in
               sorted((t for t in all_t if not t.preset_key),
                      key=lambda t: t.updated_at, reverse=True)]
    return JsonResponse({'presets': presets, 'customs': customs})


@api_view(['GET'])
def check_template_detail(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    return JsonResponse({
        **_template_summary(t),
        'questions_config': t.questions_config or [],   # raw, per il builder a blocchi
        'questions': _resolve_questions(t.questions_config),  # risolte, per il form di compilazione
        'steps_config': t.steps_config or [],
    })


@api_view(['POST'])
def check_template_create(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    data = _body(request)
    title = (data.get('title') or '').strip() or 'Nuovo modello'
    t = QuestionnaireTemplate.objects.create(
        coach=coach,
        title=title,
        questionnaire_type='custom_check',
        is_active=True,
        steps_config=data.get('steps_config') or [],
        questions_config=data.get('questions_config') or [],
    )
    return JsonResponse(_template_summary(t), status=201)


@api_view(['PATCH', 'POST'])
def check_template_update(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    data = _body(request)
    if 'title' in data:
        t.title = (data.get('title') or '').strip() or t.title
    if 'steps_config' in data:
        t.steps_config = data.get('steps_config') or []
    if 'questions_config' in data:
        t.questions_config = data.get('questions_config') or []
    if t.preset_key:
        t.is_modified_preset = True
    t.save()
    return JsonResponse(_template_summary(t))


@api_view(['POST'])
def check_template_duplicate(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    copy = QuestionnaireTemplate.objects.create(
        coach=coach,
        title=f'Copia di {t.title}',
        description=t.description,
        questionnaire_type='custom_check',
        is_active=True,
        steps_config=t.steps_config,
        questions_config=t.questions_config,
    )
    return JsonResponse(_template_summary(copy), status=201)


@api_view(['POST'])
def check_template_delete(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    t.is_active = False
    t.save(update_fields=['is_active', 'updated_at'])
    return JsonResponse({'success': True})


@api_view(['POST'])
def check_template_restore(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    if not t.preset_key or t.preset_key not in PRESETS:
        return JsonResponse({'error': 'Solo i preset di sistema possono essere ripristinati.'}, status=400)
    payload = build_template_payload(t.preset_key)
    t.title = payload['title']
    t.description = payload['description']
    t.steps_config = payload['steps_config']
    t.questions_config = payload['questions_config']
    t.is_modified_preset = False
    t.save()
    return JsonResponse(_template_summary(t))


@api_view(['POST'])
def check_template_assign(request, user, template_id):
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    data = _body(request)
    client_ids = data.get('client_ids')
    if client_ids is None and data.get('client_id'):
        client_ids = [data.get('client_id')]
    recurrence = data.get('recurrence_type', 'once')
    notes = (data.get('notes') or '').strip()
    if not client_ids:
        return JsonResponse({'error': 'Seleziona almeno un atleta.'}, status=400)
    try:
        duration_hrs = max(1, int(data.get('duration_hours', 72)))
        weekly_day = int(data.get('weekly_day')) if data.get('weekly_day') not in (None, '') else None
        monthly_day = int(data.get('monthly_day')) if data.get('monthly_day') not in (None, '') else None
    except (TypeError, ValueError):
        return JsonResponse({'error': 'Valore numerico non valido'}, status=400)

    clients = list(ClientProfile.objects.filter(
        id__in=client_ids,
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).distinct())
    if not clients:
        return JsonResponse({'error': 'Nessun atleta valido selezionato.'}, status=400)

    assignment_ids = []
    for client in clients:
        assignment = AssignedCheck.objects.create(
            template=t,
            snapshot_config=t.questions_config,
            client=client,
            coach=coach,
            recurrence_type=recurrence,
            weekly_day=weekly_day if recurrence == 'weekly' else None,
            monthly_day=monthly_day if recurrence == 'monthly' else None,
            duration_hours=duration_hrs,
            notes=notes,
        )
        assignment_ids.append(assignment.id)
        if recurrence == 'once':
            _create_instance(assignment, timezone.localdate())
        Notification.objects.create(
            target_user=client.user,
            notification_type='CHECK_SUBMITTED',
            title='Nuovo check da compilare',
            body=f'Il tuo coach ti ha assegnato il check «{t.title}».',
            link_url='/check/i-miei-check/',
        )
    return JsonResponse({'success': True, 'assigned_count': len(assignment_ids),
                         'assignment_ids': assignment_ids})


@api_view(['POST'])
def check_template_fill(request, user, template_id):
    """Il coach compila un modello per un atleta → check già revisionato."""
    coach, err = _require_coach(user)
    if err:
        return err
    t = _own_template(coach, template_id)
    if not t:
        return JsonResponse({'error': 'Template non trovato'}, status=404)
    data = _body(request)
    rel = _own_relationship(coach, data.get('client_id'))
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    raw_answers = data.get('answers') or {}
    questions_config = t.questions_config or []
    fields = _answers_to_fields(raw_answers, questions_config)

    submitted_at = timezone.now()
    day = parse_date((data.get('date') or '').strip()) if data.get('date') else None
    if day:
        from datetime import datetime as _dt, time as _time
        naive = _dt.combine(day, _time(12, 0))
        submitted_at = timezone.make_aware(naive) if timezone.is_naive(naive) else naive

    r = QuestionnaireResponse.objects.create(
        questionnaire_template=t,
        client=rel.client,
        coach=coach,
        submitted_at=submitted_at,
        status='REVIEWED',
        questions_snapshot=questions_config,
        steps_snapshot=t.steps_config or [],
        **fields,
    )
    return JsonResponse({'id': r.id}, status=201)


@api_view(['GET'])
def check_values_prefill(request, user, response_id):
    """Snapshot domande + valori correnti per il form di modifica valori."""
    coach, err = _require_coach(user)
    if err:
        return err
    r = (QuestionnaireResponse.objects
         .select_related('questionnaire_template')
         .filter(id=response_id, coach=coach).first())
    if not r:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    questions_cfg, steps_cfg = _response_config(r)
    return JsonResponse({
        'questions': _resolve_questions(questions_cfg),
        'steps_config': steps_cfg,
        'prefill': _build_prefill(r),
    })


@api_view(['PATCH', 'POST'])
def check_values_update(request, user, response_id):
    """Il coach corregge i valori di un check compilato. submitted_at invariato."""
    coach, err = _require_coach(user)
    if err:
        return err
    r = (QuestionnaireResponse.objects
         .select_related('questionnaire_template')
         .filter(id=response_id, coach=coach).first())
    if not r:
        return JsonResponse({'error': 'Check non trovato'}, status=404)
    questions_cfg, _ = _response_config(r)
    raw_answers = (_body(request).get('answers')) or {}
    fields = _answers_to_fields(raw_answers, questions_cfg)
    r.weight_kg = fields['weight_kg']
    r.body_circumferences = fields['body_circumferences']
    r.skinfolds = fields['skinfolds']
    r.answers_json = fields['answers_json']
    r.injuries = fields['injuries']
    r.limitations = fields['limitations']
    r.notes = fields['notes']
    r.save(update_fields=[
        'weight_kg', 'body_circumferences', 'skinfolds', 'answers_json',
        'injuries', 'limitations', 'notes', 'updated_at',
    ])
    return JsonResponse({'id': r.id, 'success': True})


# ---------------------------------------------------------------------------
# Workout / Nutrition management ("Gestione Allenamenti / Nutrizione")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def workouts(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    q = (request.GET.get('q') or '').strip()
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    plans_qs = (
        WorkoutPlan.objects.filter(coach=coach)
        .annotate(assigned=Count('assignments', filter=Q(assignments__status='ACTIVE')))
        .order_by('-created_at')
    )
    if q:
        plans_qs = plans_qs.filter(title__icontains=q)
    total = plans_qs.count()
    plans = [{
        'id': p.id,
        'title': p.title,
        'goal': p.goal,
        'level': p.level,
        'duration_weeks': p.duration_weeks,
        'frequency_per_week': p.frequency_per_week,
        'assigned_count': p.assigned,
    } for p in plans_qs[offset:offset + PAGE]]
    assignments = [{
        'id': wa.id,
        'title': wa.workout_plan.title,
        'client': _client_brief(request, wa.client),
        'start_date': _iso(wa.start_date),
    } for wa in (
        WorkoutAssignment.objects.filter(coach=coach, status='ACTIVE')
        .select_related('workout_plan', 'client', 'client__user')
        .order_by('-created_at')[:50]
    )]
    return JsonResponse({'plans': plans, 'assignments': assignments, 'has_more': offset + PAGE < total})


@api_view(['GET'])
def nutrition(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    q = (request.GET.get('q') or '').strip()
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    plans_qs = (
        NutritionPlan.objects.filter(coach=coach)
        .annotate(assigned=Count('assignments', filter=Q(assignments__status='ACTIVE')))
        .order_by('-created_at')
    )
    if q:
        plans_qs = plans_qs.filter(title__icontains=q)
    total = plans_qs.count()
    plans = [{
        'id': p.id,
        'title': p.title,
        'plan_mode': p.plan_mode,
        'plan_kind': p.plan_kind,
        'daily_kcal': p.daily_kcal,
        'assigned_count': p.assigned,
    } for p in plans_qs[offset:offset + PAGE]]
    assignments = [{
        'id': na.id,
        'title': na.nutrition_plan.title,
        'client': _client_brief(request, na.client),
    } for na in (
        NutritionAssignment.objects.filter(coach=coach, status='ACTIVE')
        .select_related('nutrition_plan', 'client', 'client__user')
        .order_by('-assigned_at')[:50]
    )]
    return JsonResponse({'plans': plans, 'assignments': assignments, 'has_more': offset + PAGE < total})


# ---------------------------------------------------------------------------
# Subscriptions ("Gestione Abbonamenti")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def subscriptions(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    plans = [{
        'id': p.id,
        'name': p.name,
        'plan_type': p.plan_type,
        'price': float(p.price),
        'currency': p.currency,
        'billing_interval': p.billing_interval,
        'is_active': p.is_active,
        'active_count': p.active_count,
    } for p in (
        SubscriptionPlan.objects.filter(coach=coach)
        .annotate(active_count=Count('client_subscriptions',
                                     filter=Q(client_subscriptions__status='ACTIVE')))
        .order_by('-created_at')
    )]
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    subs_qs = (
        ClientSubscription.objects
        .filter(subscription_plan__coach=coach)
        .select_related('client', 'client__user', 'subscription_plan')
        .order_by('-start_date')
    )
    active_agg = subs_qs.filter(status='ACTIVE').aggregate(
        total=Sum('subscription_plan__price'), n=Count('id'))
    revenue = float(active_agg['total'] or 0)
    window = list(subs_qs[offset:offset + PAGE + 1])
    subs = [{
        'id': s.id,
        'client': _client_brief(request, s.client),
        'plan_name': s.subscription_plan.name,
        'price': float(s.subscription_plan.price),
        'status': s.status,
        'payment_status': s.payment_status,
        'start_date': _iso(s.start_date),
        'end_date': _iso(s.end_date),
    } for s in window[:PAGE]]
    return JsonResponse({
        'plans': plans,
        'subscriptions': subs,
        'active_count': active_agg['n'],
        'monthly_revenue': revenue,
        'currency': 'EUR',
        'has_more': len(window) > PAGE,
    })


# ---------------------------------------------------------------------------
# Resource library ("Libreria / Gestione Risorse") — the coach's reusable
# content: workout & nutrition plans, check templates, supplement sheets.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def resources(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    workout_plans = [{'id': p.id, 'title': p.title, 'goal': p.goal}
                     for p in WorkoutPlan.objects.filter(coach=coach).only('id', 'title', 'goal').order_by('-created_at')[:80]]
    nutrition_plans = [{'id': p.id, 'title': p.title, 'plan_mode': p.plan_mode}
                       for p in NutritionPlan.objects.filter(coach=coach).only('id', 'title', 'plan_mode').order_by('-created_at')[:80]]
    templates = [{'id': t.id, 'title': t.title, 'type': t.questionnaire_type, 'active': t.is_active}
                 for t in QuestionnaireTemplate.objects.filter(coach=coach).only('id', 'title', 'questionnaire_type', 'is_active').order_by('-created_at')[:80]]
    sheets = [{'id': s.id, 'title': s.title}
              for s in SupplementProtocol.objects.filter(coach=coach).only('id', 'title').order_by('-updated_at')[:80]]
    return JsonResponse({
        'sections': [
            {'key': 'workouts', 'label': 'Schede Allenamento', 'icon': 'dumbbell.fill',
             'count': len(workout_plans), 'items': workout_plans},
            {'key': 'nutrition', 'label': 'Piani Nutrizionali', 'icon': 'flame.fill',
             'count': len(nutrition_plans), 'items': nutrition_plans},
            {'key': 'checks', 'label': 'Modelli Check', 'icon': 'checkmark.seal.fill',
             'count': len(templates), 'items': templates},
            {'key': 'supplements', 'label': 'Schede Integratori', 'icon': 'pills.fill',
             'count': len(sheets), 'items': sheets},
        ],
    })


# ---------------------------------------------------------------------------
# Analytics ("Analisi Progressi") — practice-wide aggregates.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def analytics(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    today = date.today()
    active_clients = CoachingRelationship.objects.filter(coach=coach, status='ACTIVE').count()
    total_checks = QuestionnaireResponse.objects.filter(coach=coach, submitted_at__isnull=False).count()
    reviewed = QuestionnaireResponse.objects.filter(coach=coach, submitted_at__isnull=False).exclude(
        Q(coach_feedback__isnull=True) | Q(coach_feedback='')).count()
    review_rate = round(100 * reviewed / total_checks, 1) if total_checks else 0.0

    # Checks per week over the last 8 weeks (oldest → newest).
    series = []
    for w in range(7, -1, -1):
        start = today - timedelta(days=today.weekday() + 7 * w)
        end = start + timedelta(days=7)
        n = QuestionnaireResponse.objects.filter(
            coach=coach, submitted_at__date__gte=start, submitted_at__date__lt=end
        ).count()
        series.append({'week_start': start.isoformat(), 'count': n})

    return JsonResponse({
        'active_clients': active_clients,
        'total_checks': total_checks,
        'reviewed_checks': reviewed,
        'review_rate': review_rate,
        'checks_series': series,
    })


# ---------------------------------------------------------------------------
# Messaging ("Centro Messaggi") — coach-scoped conversations.
# ---------------------------------------------------------------------------

def _own_conversation(coach, conversation_id):
    return Conversation.objects.filter(id=conversation_id, coach=coach).select_related('client', 'client__user').first()


@api_view(['GET'])
def conversations(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    last_msg = Message.objects.filter(conversation=OuterRef('pk')).order_by('-sent_at')
    out = []
    for conv in (
        Conversation.objects.filter(coach=coach)
        .select_related('client', 'client__user')
        .annotate(
            last_message_id=Subquery(last_msg.values('id')[:1]),
            last_message_body=Subquery(last_msg.values('body')[:1]),
            unread=Count('messages', filter=Q(messages__read_at__isnull=True)
                         & ~Q(messages__sender_user=coach.user)),
        )
        .order_by('-last_message_at')
    ):
        # Skip empty threads — only real conversations belong in the list. New
        # threads are started explicitly via /messageable-clients + /start.
        if conv.last_message_id is None:
            continue
        out.append({
            'id': conv.id,
            'client': _client_brief(request, conv.client),
            'last_message': conv.last_message_body,
            'last_message_at': _iso(conv.last_message_at),
            'unread': conv.unread,
        })
    return JsonResponse({'conversations': out})


@api_view(['GET'])
def messages(request, user, conversation_id):
    coach, err = _require_coach(user)
    if err:
        return err
    conv = _own_conversation(coach, conversation_id)
    if not conv:
        return JsonResponse({'error': 'Conversazione non trovata'}, status=404)

    since = request.GET.get('since')
    if since and since.isdigit():
        new = conv.messages.filter(id__gt=int(since)).order_by('sent_at')
        return JsonResponse({'messages': [_message_dict(m, user.id) for m in new], 'has_more': False})

    page = 30
    qs = conv.messages.order_by('-sent_at')
    before = request.GET.get('before')
    if before and before.isdigit():
        qs = qs.filter(id__lt=int(before))
    window = list(qs[:page])
    has_more = qs.count() > page
    window.reverse()

    # Mark the client's messages as read now that the coach has opened the thread.
    conv.messages.filter(read_at__isnull=True).exclude(sender_user=user).update(read_at=timezone.now())

    return JsonResponse({
        'messages': [_message_dict(m, user.id) for m in window],
        'has_more': has_more,
        'client': _client_brief(request, conv.client),
    })


@api_view(['POST'])
def send_message(request, user, conversation_id):
    coach, err = _require_coach(user)
    if err:
        return err
    conv = _own_conversation(coach, conversation_id)
    if not conv:
        return JsonResponse({'error': 'Conversazione non trovata'}, status=404)
    body = (_body(request).get('body') or '').strip()
    if not body:
        return JsonResponse({'error': 'Messaggio vuoto'}, status=400)
    msg = Message.objects.create(conversation=conv, sender_user=user, body=body, message_type='TEXT')
    conv.last_message_at = msg.sent_at
    conv.save(update_fields=['last_message_at'])
    Notification.objects.create(
        target_user=conv.client.user,
        notification_type='MESSAGE',
        title=f'Nuovo messaggio da {coach.first_name}',
        body=body[:140],
        link_url='/chat/',
    )
    return JsonResponse({'id': msg.id, 'sent_at': _iso(msg.sent_at)}, status=201)


# ---------------------------------------------------------------------------
# Coach profile ("Profilo Coach" / "Modifica Profilo")
# ---------------------------------------------------------------------------

@api_view(['GET', 'PATCH'])
def profile(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    if request.method == 'PATCH':
        data = _body(request)
        for field in ('first_name', 'last_name'):
            if data.get(field):
                setattr(coach, field, data[field].strip())
        for field in ('phone', 'specialization', 'city', 'bio', 'description',
                      'certifications', 'social_instagram',
                      'social_youtube', 'social_tiktok', 'social_website'):
            if field in data:
                setattr(coach, field, (data.get(field) or '').strip() or None)
        if 'professional_type' in data:
            value = (data.get('professional_type') or '').strip()
            valid_types = dict(CoachProfile.PROFESSIONAL_TYPES)
            if value in valid_types:
                coach.professional_type = value
        if 'years_experience' in data:
            raw = data.get('years_experience')
            try:
                coach.years_experience = int(raw) if raw not in (None, '') else None
            except (TypeError, ValueError):
                pass
        coach.save()
    return JsonResponse({'profile': _coach_profile_dict(request, coach)})


@api_view(['POST'])
def profile_photo(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    upload = request.FILES.get('photo') or request.FILES.get('file')
    if not upload:
        return JsonResponse({'error': 'Nessuna immagine inviata'}, status=400)
    from config.services.images import is_image, to_webp
    # Sniff real content first: a non-image renamed to .jpg fails is_image()
    # and is rejected instead of being handed to Pillow.
    if not is_image(upload):
        return JsonResponse({'error': 'Immagine non valida'}, status=400)
    try:
        webp = to_webp(upload)
    except Exception:
        return JsonResponse({'error': 'Immagine non valida'}, status=400)
    coach.profile_image.save(webp.name, webp, save=True)
    return JsonResponse({'profile_image_url': _coach_avatar(request, coach)})


# ---------------------------------------------------------------------------
# Client progress / charts — the coach reads a single athlete's check history
# (weight + measurements series, photos, feedback) for the in-app charts.
# Mirrors the athlete ``progress`` endpoint, scoped to the coach's own client.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def client_progress(request, user, client_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    responses = (
        QuestionnaireResponse.objects
        .filter(client_id=client_id, coach=coach, submitted_at__isnull=False)
        .defer('answers_json', 'questions_snapshot', 'steps_snapshot', 'coach_private_notes')
        .prefetch_related('photos')
        .order_by('-submitted_at')
    )
    entries = [{
        'id': r.id,
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'measurements': _measurements(r),
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
# Client exercise trend — the coach reads one athlete's per-exercise trend
# (volume / top set / weighted avg per session). Reuses the web builder.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def client_exercise_trend(request, user, client_id, workout_exercise_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    we = (WorkoutExercise.objects
          .select_related('exercise', 'workout_day__workout_plan')
          .filter(id=workout_exercise_id).first())
    if not we:
        return JsonResponse({'error': 'Esercizio non trovato'}, status=404)
    if not WorkoutAssignment.objects.filter(
        client=rel.client, workout_plan=we.workout_day.workout_plan).exists():
        return JsonResponse({'error': 'Esercizio non assegnato'}, status=404)
    return JsonResponse(build_exercise_trend(we, rel.client))


@api_view(['GET'])
def client_sessions(request, user, client_id):
    """Paged list of a client's past training sessions (most recent first)."""
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    offset = max(0, safe_int(request.GET, 'offset', 0))
    page = 20
    qs = (WorkoutSession.objects
          .filter(client=rel.client)
          .select_related('workout_day')
          .order_by('-started_at'))
    sessions = list(qs[offset:offset + page])
    return JsonResponse({
        'sessions': [_serialize_session_brief(s) for s in sessions],
        'has_more': qs.count() > offset + page,
    })


@api_view(['GET'])
def session_detail(request, user, session_id):
    """Full detail of one session belonging to one of the coach's clients."""
    coach, err = _require_coach(user)
    if err:
        return err
    s = (WorkoutSession.objects
         .select_related('workout_day', 'client')
         .filter(id=session_id).first())
    if not s:
        return JsonResponse({'error': 'Sessione non trovata'}, status=404)
    if not _own_relationship(coach, s.client_id):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    return JsonResponse(_serialize_session_full(s))


# ---------------------------------------------------------------------------
# Client percorso (journey) — the coach reads an athlete's timeline and can add
# or remove phases. Reuses the web event/phase builders so views stay in sync.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def client_percorso(request, user, client_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    client = rel.client
    today = date.today()
    start = getattr(rel, 'start_date', None)
    if start:
        rel_start = (start if isinstance(start, date) else start.date()).replace(day=1)
    else:
        rel_start = (today - timedelta(days=365)).replace(day=1)
    offset = max(0, safe_int(request.GET, 'offset', 0))
    PAGE = 10
    # Collect the whole history for the timeline, not just from the (possibly
    # renewed) relationship start — otherwise older plans/checks silently vanish.
    all_events = _build_percorso_events(client, coach, date(2000, 1, 1), today)
    # Paginate newest-first so the app sees the most recent events first.
    all_events_desc = list(reversed(all_events))
    events = all_events_desc[offset:offset + PAGE]
    has_more = offset + PAGE < len(all_events_desc)
    phases = _serialize_phases(client, coach)
    last_activity = today
    if all_events:
        last_activity = max(last_activity, date.fromisoformat(all_events[-1]['date']))
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
        'has_more': has_more,
    })


@api_view(['POST'])
def phase_create(request, user, client_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    from domain.coaching.models import CoachingPhase
    payload = _body(request)
    title = (payload.get('title') or '').strip()
    note = (payload.get('note') or '').strip()
    start_str = (payload.get('start_date') or '').strip()
    unit = (payload.get('duration_unit') or 'WEEKS').strip().upper()
    if not title:
        return JsonResponse({'error': 'Il titolo è obbligatorio.'}, status=400)
    try:
        start_date = date.fromisoformat(start_str)
    except ValueError:
        return JsonResponse({'error': 'Data di inizio non valida.'}, status=400)
    try:
        duration_value = int(payload.get('duration_value'))
    except (TypeError, ValueError):
        duration_value = 0
    if duration_value < 1:
        return JsonResponse({'error': 'La durata deve essere almeno 1.'}, status=400)
    if unit not in ('WEEKS', 'MONTHS'):
        unit = 'WEEKS'
    phase = CoachingPhase.objects.create(
        coach=coach, client=rel.client, title=title[:120], note=note,
        start_date=start_date, duration_value=duration_value, duration_unit=unit,
    )
    return JsonResponse({
        'id': phase.id,
        'title': phase.title,
        'note': phase.note or '',
        'start': phase.start_date.isoformat(),
        'end': phase.end_date.isoformat(),
        'duration_value': phase.duration_value,
        'duration_unit': phase.duration_unit,
    })


@api_view(['PATCH', 'PUT', 'DELETE'])
def phase_detail(request, user, client_id, phase_id):
    """Update (PATCH/PUT) or remove (DELETE) one coaching phase."""
    coach, err = _require_coach(user)
    if err:
        return err
    from domain.coaching.models import CoachingPhase
    phase = CoachingPhase.objects.filter(id=phase_id, coach=coach, client_id=client_id).first()
    if not phase:
        return JsonResponse({'error': 'Fase non trovata'}, status=404)

    if request.method == 'DELETE':
        phase.delete()
        return JsonResponse({'success': True})

    payload = _body(request)
    title = (payload.get('title') or '').strip()
    if not title:
        return JsonResponse({'error': 'Il titolo è obbligatorio.'}, status=400)
    try:
        start_date = date.fromisoformat((payload.get('start_date') or '').strip())
    except ValueError:
        return JsonResponse({'error': 'Data di inizio non valida.'}, status=400)
    try:
        duration_value = int(payload.get('duration_value'))
    except (TypeError, ValueError):
        duration_value = 0
    if duration_value < 1:
        return JsonResponse({'error': 'La durata deve essere almeno 1.'}, status=400)
    unit = (payload.get('duration_unit') or 'WEEKS').strip().upper()
    if unit not in ('WEEKS', 'MONTHS'):
        unit = 'WEEKS'
    phase.title = title[:120]
    phase.note = (payload.get('note') or '').strip()
    phase.start_date = start_date
    phase.duration_value = duration_value
    phase.duration_unit = unit
    phase.save(update_fields=['title', 'note', 'start_date', 'duration_value', 'duration_unit'])
    return JsonResponse({
        'id': phase.id,
        'title': phase.title,
        'note': phase.note or '',
        'start': phase.start_date.isoformat(),
        'end': phase.end_date.isoformat(),
        'duration_value': phase.duration_value,
        'duration_unit': phase.duration_unit,
    })


# ---------------------------------------------------------------------------
# Client active workout — days + exercises (with workout_exercise ids) so the
# coach can drill into a single exercise's trend. Reuses the athlete serializers.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def client_workout(request, user, client_id):
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    # Prefer the active plan, but fall back to the most recent assignment of any
    # status: the athlete may have logged sessions under a plan that's since been
    # completed/replaced, and the coach still needs to drill into those trends
    # (otherwise the app says "nessun allenamento" while the web shows charts).
    base = WorkoutAssignment.objects.filter(client=rel.client).select_related('workout_plan')
    asg = (base.filter(status='ACTIVE').order_by('-created_at').first()
           or base.order_by('-created_at').first())
    if not asg:
        return JsonResponse({'plan': None, 'days': []})
    plan = asg.workout_plan
    return JsonResponse({
        'plan': {'id': plan.id, 'title': plan.title},
        'days': [_day_dict(d) for d in plan.days.all().prefetch_related('exercises__exercise')],
    })


# ---------------------------------------------------------------------------
# Agenda CRUD — the coach books, edits and cancels appointments from mobile.
# Mirrors config/views_agenda.py (the web calendar) for consistent behaviour.
# ---------------------------------------------------------------------------

_APPT_TYPES = {'check', 'prima_visita', 'visita', 'consulenza'}
_APPT_STATUSES = {'SCHEDULED', 'CANCELLED', 'COMPLETED'}


def _appointment_dict(request, a):
    return {
        'id': a.id,
        'title': a.title,
        'type': a.appointment_type,
        'description': a.description or '',
        'start': _iso(a.start_datetime),
        'end': _iso(a.end_datetime),
        'duration_minutes': a.duration_minutes,
        'location': a.location,
        'meeting_url': a.meeting_url or '',
        'status': a.status,
        'client': _client_brief(request, a.client) if a.client_id else None,
    }


@api_view(['POST'])
def agenda_create(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    data = _body(request)
    title = (data.get('title') or '').strip()
    appt_type = (data.get('appointment_type') or 'visita').strip().lower()
    start = parse_datetime(data.get('start_datetime') or '')
    try:
        duration = int(data.get('duration_minutes') or 60)
    except (TypeError, ValueError):
        duration = 60
    client_id = data.get('client_id')

    if not title or not start or not client_id:
        return JsonResponse({'error': 'Campi obbligatori mancanti'}, status=400)
    if appt_type not in _APPT_TYPES:
        appt_type = 'visita'
    if duration < 1:
        return JsonResponse({'error': 'Durata non valida'}, status=400)

    client = ClientProfile.objects.filter(
        id=client_id, coaching_relationships_as_client__coach=coach
    ).first()
    if not client:
        return JsonResponse({'error': 'Atleta non trovato'}, status=400)

    appt = Appointment.objects.create(
        coach=coach, client=client, title=title, appointment_type=appt_type,
        start_datetime=start, duration_minutes=duration,
        description=(data.get('description') or '').strip(),
        meeting_url=(data.get('meeting_url') or '').strip() if appt_type == 'consulenza' else '',
        status='SCHEDULED',
    )
    return JsonResponse({'appointment': _appointment_dict(request, appt)}, status=201)


@api_view(['PATCH', 'DELETE'])
def agenda_detail(request, user, appointment_id):
    coach, err = _require_coach(user)
    if err:
        return err
    appt = (Appointment.objects.select_related('client', 'client__user')
            .filter(id=appointment_id, coach=coach).first())
    if not appt:
        return JsonResponse({'error': 'Appuntamento non trovato'}, status=404)

    if request.method == 'DELETE':
        appt.delete()
        return JsonResponse({'ok': True})

    data = _body(request)
    if 'title' in data:
        appt.title = (data.get('title') or '').strip() or appt.title
    if 'appointment_type' in data:
        t = (data.get('appointment_type') or '').strip().lower()
        if t in _APPT_TYPES:
            appt.appointment_type = t
    if 'start_datetime' in data:
        start = parse_datetime(data.get('start_datetime') or '')
        if start:
            appt.start_datetime = start
    if 'duration_minutes' in data:
        try:
            appt.duration_minutes = max(1, int(data.get('duration_minutes')))
        except (TypeError, ValueError):
            pass
    if 'description' in data:
        appt.description = (data.get('description') or '').strip()
    if 'meeting_url' in data:
        appt.meeting_url = (data.get('meeting_url') or '').strip()
    if 'status' in data and data.get('status'):
        s = (data.get('status') or '').strip().upper()
        if s in _APPT_STATUSES:
            appt.status = s
    if 'client_id' in data and data.get('client_id'):
        c = ClientProfile.objects.filter(
            id=data['client_id'], coaching_relationships_as_client__coach=coach
        ).first()
        if c:
            appt.client = c
    appt.save()
    return JsonResponse({'appointment': _appointment_dict(request, appt)})


# ---------------------------------------------------------------------------
# Plan detail — full structure of a workout / nutrition plan, for the in-app
# detail views. Read-only projections of the same models the web renders.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def workout_detail(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    plan = (WorkoutPlan.objects.filter(id=plan_id, coach=coach)
            .prefetch_related('days__exercises__exercise').first())
    if not plan:
        return JsonResponse({'error': 'Scheda non trovata'}, status=404)
    days = [{
        'id': d.id,
        'name': d.day_name or d.title or f'Giorno {d.day_order}',
        'order': d.day_order,
        'focus': d.focus_area,
        'notes': d.notes,
        'exercises': [{
            'id': we.id,
            'name': we.exercise.name,
            'sets': we.set_count,
            'reps': we.rep_count,
            'rep_range': we.rep_range,
            'rir': we.rir,
            'rpe': we.rpe,
            'recovery_seconds': we.recovery_seconds,
            'tempo': we.tempo,
            'notes': getattr(we, 'notes', None),
            'set_details': we.set_details or [],
        } for we in d.exercises.order_by('order_index')],
    } for d in plan.days.order_by('day_order')]
    return JsonResponse({'plan': {
        'id': plan.id, 'title': plan.title, 'goal': plan.goal, 'level': plan.level,
        'duration_weeks': plan.duration_weeks, 'frequency_per_week': plan.frequency_per_week,
        'plan_kind': plan.plan_kind, 'description': plan.description, 'status': plan.status,
        'days': days,
    }})


def _food_macros(item):
    """kcal/protein/carb/fat for a MealItem from its Food per-100g values."""
    f = item.food
    if not f:
        return {'kcal': None, 'protein': None, 'carb': None, 'fat': None,
                'name': item.raw_name or 'Alimento'}
    factor = (item.quantity_g or 0) / 100.0
    return {
        'name': f.nome_alimento,
        'kcal': round(f.energia_kcal * factor, 1),
        'protein': round(f.proteine_g * factor, 1),
        'carb': round(f.carboidrati_g * factor, 1),
        'fat': round(f.lipidi_g * factor, 1),
    }


# Output key -> Food per-100g attribute. Mirrors the web micro flip card
# (nutrition_wizard.js microDefs); the iOS coach card reuses the same keys.
_MICRO_FIELDS = {
    'iron': 'fe_mg', 'calcium': 'ca_mg', 'sodium': 'na_mg', 'potassium': 'k_mg',
    'phosphorus': 'p_mg', 'zinc': 'zn_mg', 'magnesium': 'mg_mg', 'copper': 'cu_mg',
    'selenium': 'se_ug', 'iodine': 'i_ug', 'manganese': 'mn_mg',
    'vit_b1': 'vit_b1_mg', 'vit_b2': 'vit_b2_mg', 'vit_c': 'vit_c_mg',
    'niacin': 'niacina_mg', 'vit_b6': 'vit_b6_mg', 'folate': 'folati_ug',
    'vit_b12': 'vit_b12_ug', 'isoleucine': 'isoleucina_mg', 'leucine': 'leucina_mg',
    'valine': 'valina_mg', 'lactose': 'lattosio_g',
}


def _accumulate_micros(item, acc):
    """Add a MealItem's micronutrients (per-100g * quantity) into acc in place."""
    f = item.food
    if not f:
        return
    factor = (item.quantity_g or 0) / 100.0
    for key, attr in _MICRO_FIELDS.items():
        acc[key] += (getattr(f, attr, None) or 0) * factor


@api_view(['GET'])
def nutrition_detail(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    plan = (NutritionPlan.objects.filter(id=plan_id, coach=coach)
            .prefetch_related('meals__items__food', 'meals__day', 'days').first())
    if not plan:
        return JsonResponse({'error': 'Piano non trovato'}, status=404)


    def meal_dict(m):
        items = [{
            'id': it.id,
            'quantity_g': it.quantity_g,
            **_food_macros(it),
        } for it in m.items.all()]
        return {'id': m.id, 'name': m.name, 'order': m.order,
                'day_of_week': WEEKDAY_REVERSE.get(m.day.day_of_week) if m.day else None,
                'notes': m.notes, 'items': items}

    meals = [meal_dict(m) for m in plan.meals.all()]
    total = {'kcal': 0.0, 'protein': 0.0, 'carb': 0.0, 'fat': 0.0}
    for m in meals:
        for it in m['items']:
            for k in total:
                total[k] += it.get(k) or 0
    micros = {k: 0.0 for k in _MICRO_FIELDS}
    for m in plan.meals.all():
        for it in m.items.all():
            _accumulate_micros(it, micros)
    day_targets = [{
        'day_of_week': WEEKDAY_REVERSE.get(d.day_of_week, d.day_of_week),
        'kcal': d.target_kcal,
        'protein': d.target_protein_g,
        'carb': d.target_carb_g,
        'fat': d.target_fat_g,
    } for d in plan.days.order_by('order')] if plan.plan_mode == 'MACRO' else []
    return JsonResponse({'plan': {
        'id': plan.id, 'title': plan.title, 'plan_mode': plan.plan_mode,
        'plan_kind': plan.plan_kind, 'daily_kcal': plan.daily_kcal,
        'protein_target_g': plan.protein_target_g,
        'carb_target_g': plan.carb_target_g,
        'fat_target_g': plan.fat_target_g,
        'description': plan.description, 'status': plan.status,
        'meals': meals,
        'day_targets': day_targets,
        'totals': {
            **{k: round(v, 1) for k, v in total.items()},
            'micros': {k: round(v, 2) for k, v in micros.items()},
        },
    }})


@api_view(['GET'])
def client_macro_history(request, user, client_id):
    """Read-only view of the athlete's compiled meal log (active MACRO plan)."""
    coach, err = _require_coach(user)
    if err:
        return err
    rel = _own_relationship(coach, client_id)
    if not rel:
        return JsonResponse({'error': 'Cliente non trovato'}, status=404)
    a = (NutritionAssignment.objects
         .select_related('nutrition_plan')
         .filter(client=rel.client, coach=coach, status='ACTIVE',
                 nutrition_plan__plan_mode='MACRO').first())
    if not a:
        return JsonResponse({'days': [], 'has_more': False})
    offset = max(0, safe_int(request.GET, 'offset', 0))
    return JsonResponse(macro_history_payload(a, offset))


# ---------------------------------------------------------------------------
# Builder payloads — edit-ready projections for the mobile plan builders. The
# actual writes go through the web save endpoints (coach_dual_auth), so the
# two clients share one code path; these GETs only prefill the mobile editor.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def workout_builder(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    plan = WorkoutPlan.objects.filter(id=plan_id, coach=coach).first()
    if not plan:
        return JsonResponse({'error': 'Scheda non trovata'}, status=404)
    return JsonResponse({'plan': _serialize_plan_for_wizard(plan)})


@api_view(['GET'])
def nutrition_builder(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    plan = (
        NutritionPlan.objects.filter(id=plan_id, coach=coach)
        .prefetch_related('meals__day', 'meals__items__food',
                          'meals__items__substitutions__food', 'days')
        .first()
    )
    if not plan:
        return JsonResponse({'error': 'Piano non trovato'}, status=404)


    meals = []
    for meal in plan.meals.all():
        items = []
        for item in meal.items.all():
            if not item.food:
                continue
            items.append({
                'food_id': item.food_id,
                'food_name': item.food.nome_alimento,
                'quantity_g': item.quantity_g,
                'kcal_per_100g': item.food.energia_kcal,
                'protein_per_100g': item.food.proteine_g,
                'carb_per_100g': item.food.carboidrati_g,
                'fat_per_100g': item.food.lipidi_g,
                'notes': item.notes or '',
                # Round-tripped opaquely by the mobile editor so a save from
                # mobile doesn't drop substitutions built on the web.
                'substitutions': [{
                    'food_id': s.food_id,
                    'mode': s.mode,
                    'quantity_g': s.quantity_g,
                } for s in item.substitutions.all()],
            })
        meals.append({
            'name': meal.name,
            'time_of_day': meal.time_of_day or '',
            'notes': meal.notes or '',
            'day_of_week': WEEKDAY_REVERSE.get(meal.day.day_of_week) if meal.day else None,
            'items': items,
        })

    day_targets = []
    if plan.plan_mode == 'MACRO' and plan.plan_kind == 'WEEKLY':
        day_targets = [{
            'day_of_week': WEEKDAY_REVERSE.get(d.day_of_week, d.day_of_week),
            'kcal': d.target_kcal,
            'protein': d.target_protein_g,
            'carb': d.target_carb_g,
            'fat': d.target_fat_g,
        } for d in plan.days.all()]

    supplement = _serialize_protocol(plan.supplement_sheet) if plan.supplement_sheet else None

    return JsonResponse({'plan': {
        'id': plan.id,
        'title': plan.title,
        'description': plan.description or '',
        'plan_kind': plan.plan_kind,
        'plan_mode': plan.plan_mode,
        'daily_kcal': plan.daily_kcal,
        'protein_target_g': plan.protein_target_g,
        'carb_target_g': plan.carb_target_g,
        'fat_target_g': plan.fat_target_g,
        'meals': meals,
        'day_targets': day_targets,
        'supplement_sheet': supplement,
    }})


# ---------------------------------------------------------------------------
# Lightweight manual builders — quick from-scratch plans on mobile. The full
# multi-week / food-DB builder stays on the web; Chiron import covers the rest.
# ---------------------------------------------------------------------------

@api_view(['POST'])
def workout_create(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    if not can_manage_workouts(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    data = _body(request)
    title = (data.get('title') or '').strip()[:200]
    if not title:
        return JsonResponse({'error': 'Titolo obbligatorio'}, status=400)
    days_in = data.get('days') or []

    with transaction.atomic():
        plan = WorkoutPlan.objects.create(
            coach=coach, title=title,
            goal=(data.get('goal') or '').strip()[:200] or None,
            level=(data.get('level') or '').strip()[:50] or None,
            status=WorkoutPlan.STATUS_DRAFT, is_template=False,
        )
        for d_idx, day in enumerate(days_in):
            wd = WorkoutDay.objects.create(
                workout_plan=plan, day_order=d_idx + 1,
                day_name=(day.get('name') or f'Giorno {d_idx + 1}')[:100],
                notes=(day.get('notes') or '').strip() or None,
            )
            for e_idx, ex in enumerate(day.get('exercises') or []):
                exercise = Exercise.objects.filter(id=ex.get('exercise_id')).first()
                if not exercise:
                    continue
                _sd = ex.get('set_details')
                WorkoutExercise.objects.create(
                    workout_day=wd, exercise=exercise, order_index=e_idx,
                    set_count=ex.get('sets'), rep_count=ex.get('reps'),
                    rep_range=(ex.get('rep_range') or None),
                    recovery_seconds=ex.get('recovery_seconds'),
                    rir=ex.get('rir'), rpe=ex.get('rpe'),
                    tempo=(ex.get('tempo') or None),
                    technique_notes=(ex.get('notes') or '').strip() or None,
                    set_details=(_sd[:30] if isinstance(_sd, list) else []),
                )
    return JsonResponse({'plan_id': plan.id, 'title': plan.title}, status=201)


@api_view(['POST'])
def nutrition_create(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    if not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    data = _body(request)
    title = (data.get('title') or '').strip()[:200]
    if not title:
        return JsonResponse({'error': 'Titolo obbligatorio'}, status=400)
    meals_in = data.get('meals') or []

    with transaction.atomic():
        plan = NutritionPlan.objects.create(
            coach=coach, title=title, plan_kind='DAILY', plan_mode='FOOD',
            daily_kcal=data.get('daily_kcal') or None,
            status='DRAFT', is_template=False,
        )
        saved_meals = 0
        for meal in meals_in:
            # Resolve real items first; a meal with no foods is never persisted —
            # we don't fill the DB with empty meals.
            valid_items = []
            for food in meal.get('items') or []:
                food_obj = Food.objects.filter(id=food.get('food_id')).first()
                name = (food.get('name') or '').strip()
                if not food_obj and not name:
                    continue
                try:
                    qty = float(food.get('quantity_g') or 0)
                except (TypeError, ValueError):
                    qty = 0.0
                valid_items.append((food_obj, qty, name))
            if not valid_items:
                continue
            meal_obj = Meal.objects.create(
                plan=plan, name=(meal.get('name') or f'Pasto {saved_meals + 1}')[:100],
                order=saved_meals, notes=(meal.get('notes') or '').strip() or None,
                time_of_day=(meal.get('time_of_day') or '').strip()[:10] or None,
            )
            saved_meals += 1
            for food_obj, qty, name in valid_items:
                MealItem.objects.create(
                    meal=meal_obj, food=food_obj, quantity_g=qty,
                    raw_name=name or None if not food_obj else None,
                    uncertain=food_obj is None,
                )
    return JsonResponse({'plan_id': plan.id, 'title': plan.title}, status=201)


# ---------------------------------------------------------------------------
# Supplement protocols (Integratori) — coach builder, mobile
# ---------------------------------------------------------------------------

@api_view(['GET'])
def coach_supplements(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    protocols = (
        coach.supplement_protocols
        .annotate(
            item_count=Count('items', distinct=True),
            assigned_count=Count('assignments', filter=Q(assignments__status='ACTIVE'), distinct=True),
        )
        .order_by('-updated_at')
    )
    return JsonResponse({'protocols': [{
        'id': p.id,
        'title': p.title,
        'item_count': p.item_count,
        'assigned_count': p.assigned_count,
    } for p in protocols]})


@api_view(['GET'])
def coach_supplement_detail(request, user, protocol_id):
    coach, err = _require_coach(user)
    if err:
        return err
    p = SupplementProtocol.objects.filter(id=protocol_id, coach=coach).first()
    if not p:
        return JsonResponse({'error': 'Protocollo non trovato'}, status=404)
    return JsonResponse(_serialize_protocol(p))


@api_view(['POST'])
def coach_supplement_save(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    if not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    data = _body(request)
    title = (data.get('title') or '').strip()
    if not title:
        return JsonResponse({'error': 'Inserisci un titolo per il protocollo.'}, status=400)
    items = _parse_supplement_items(data.get('items'))
    if not items:
        return JsonResponse({'error': 'Aggiungi almeno un integratore.'}, status=400)

    with transaction.atomic():
        pid = data.get('id')
        if pid:
            p = SupplementProtocol.objects.filter(id=pid, coach=coach).first()
            if not p:
                return JsonResponse({'error': 'Protocollo non trovato'}, status=404)
            p.title = title[:200]
            p.notes = data.get('notes') or ''
            p.save(update_fields=['title', 'notes', 'updated_at'])
            p.items.all().delete()
        else:
            p = SupplementProtocol.objects.create(coach=coach, title=title[:200], notes=data.get('notes') or '')
        for order, it in enumerate(items):
            SupplementItem.objects.create(protocol=p, order=order, **it)

    return JsonResponse(_serialize_protocol(p))


@api_view(['POST'])
def coach_supplement_delete(request, user, protocol_id):
    coach, err = _require_coach(user)
    if err:
        return err
    p = SupplementProtocol.objects.filter(id=protocol_id, coach=coach).first()
    if not p:
        return JsonResponse({'error': 'Protocollo non trovato'}, status=404)
    p.delete()
    return JsonResponse({'ok': True})


@api_view(['POST'])
def coach_supplement_assign(request, user, protocol_id):
    coach, err = _require_coach(user)
    if err:
        return err
    p = SupplementProtocol.objects.filter(id=protocol_id, coach=coach).first()
    if not p:
        return JsonResponse({'error': 'Protocollo non trovato'}, status=404)
    data = _body(request)
    try:
        client_id = int(data.get('client_id') or 0)
    except (TypeError, ValueError):
        return JsonResponse({'error': 'Dati non validi'}, status=400)
    client = ClientProfile.objects.filter(id=client_id).first()
    if not client or not CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').exists():
        return JsonResponse({'error': 'Atleta non associato'}, status=403)
    SupplementProtocolAssignment.objects.filter(client=client, coach=coach, status='ACTIVE').update(status='CANCELLED')
    a = SupplementProtocolAssignment.objects.create(protocol=p, client=client, coach=coach, status='ACTIVE')
    try:
        Notification.objects.create(
            target_user=client.user,
            notification_type='SUPPLEMENT_ASSIGNED',
            title='Nuovo protocollo integratori',
            body=f'Ti è stato assegnato il protocollo "{p.title}".',
            link_url='/nutrizione/integratori/',
        )
    except Exception:
        logger.exception('supplement_assigned_notification.failed assignment_id=%s', a.id)
    return JsonResponse({'ok': True, 'assignment_id': a.id})


@api_view(['POST'])
def coach_nutrition_supplements(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    if not can_manage_nutrition(coach):
        return JsonResponse({'error': 'Non autorizzato'}, status=403)
    plan = NutritionPlan.objects.filter(id=plan_id, coach=coach).first()
    if not plan:
        return JsonResponse({'error': 'Piano non trovato'}, status=404)
    data = _body(request)
    notes = data.get('notes') or ''
    items = _parse_supplement_items(data.get('items'))

    with transaction.atomic():
        sheet = plan.supplement_sheet
        if not items:
            if sheet:
                plan.supplement_sheet = None
                plan.save(update_fields=['supplement_sheet'])
                if not sheet.assignments.exists():
                    sheet.delete()
            return JsonResponse({'ok': True, 'sheet': None})
        if sheet is None:
            sheet = SupplementProtocol.objects.create(
                coach=coach, title=f'Integrazione · {plan.title}'[:200], notes=notes)
            plan.supplement_sheet = sheet
            plan.save(update_fields=['supplement_sheet'])
        else:
            sheet.notes = notes
            sheet.save(update_fields=['notes', 'updated_at'])
            sheet.items.all().delete()
        for order, it in enumerate(items):
            SupplementItem.objects.create(protocol=sheet, order=order, **it)

        # Propagate to all athletes who have this plan actively assigned
        active_clients = NutritionAssignment.objects.filter(
            nutrition_plan=plan, status='ACTIVE'
        ).values_list('client', flat=True)
        for client_id in active_clients:
            SupplementProtocolAssignment.objects.filter(
                client_id=client_id, coach=coach, status='ACTIVE'
            ).exclude(protocol=sheet).update(status='CANCELLED')
            SupplementProtocolAssignment.objects.get_or_create(
                protocol=sheet, client_id=client_id, coach=coach,
                defaults={'status': 'ACTIVE'}
            )

    return JsonResponse({'ok': True, 'sheet': _serialize_protocol(sheet)})


@api_view(['GET'])
def coach_nutrition_assignable_clients(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    exclude_plan_id = request.GET.get('exclude_plan_id', '').strip()

    clients = list(ClientProfile.objects.filter(
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).distinct().order_by('first_name', 'last_name'))

    active_map = {}
    if clients:
        active_qs = NutritionAssignment.objects.filter(
            client_id__in=[c.id for c in clients], coach=coach, status='ACTIVE',
        ).select_related('nutrition_plan').order_by('-id')
        if exclude_plan_id:
            try:
                active_qs = active_qs.exclude(nutrition_plan_id=int(exclude_plan_id))
            except (ValueError, TypeError):
                pass
        for a in active_qs:
            if a.client_id in active_map:
                continue
            active_map[a.client_id] = {
                'assignment_id': a.id,
                'plan_id': a.nutrition_plan_id,
                'plan_title': a.nutrition_plan.title,
            }

    return JsonResponse([{
        'id': c.id,
        'name': f"{c.first_name} {c.last_name}".strip(),
        'active_assignment': active_map.get(c.id),
    } for c in clients], safe=False)


@api_view(['GET'])
def coach_supplement_assignable_clients(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    exclude_protocol_id = request.GET.get('exclude_protocol_id', '').strip()

    clients = list(ClientProfile.objects.filter(
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).distinct().order_by('first_name', 'last_name'))

    active_map = {}
    if clients:
        active_qs = SupplementProtocolAssignment.objects.filter(
            client_id__in=[c.id for c in clients], coach=coach, status='ACTIVE',
        ).select_related('protocol').order_by('-id')
        if exclude_protocol_id:
            try:
                active_qs = active_qs.exclude(protocol_id=int(exclude_protocol_id))
            except (ValueError, TypeError):
                pass
        for a in active_qs:
            if a.client_id in active_map:
                continue
            active_map[a.client_id] = {
                'assignment_id': a.id,
                'protocol_id': a.protocol_id,
                'protocol_title': a.protocol.title,
            }

    return JsonResponse([{
        'id': c.id,
        'name': f"{c.first_name} {c.last_name}".strip(),
        'active_assignment': active_map.get(c.id),
    } for c in clients], safe=False)


@api_view(['POST'])
def workout_assign(request, user, plan_id):
    coach, err = _require_coach(user)
    if err:
        return err
    plan = WorkoutPlan.objects.filter(id=plan_id, coach=coach).first()
    if not plan:
        return JsonResponse({'error': 'Scheda non trovata'}, status=404)
    data = _body(request)
    client = ClientProfile.objects.filter(
        id=data.get('client_id'),
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).first()
    if not client:
        return JsonResponse({'error': 'Atleta non associato'}, status=403)

    start_date = date.today()
    if data.get('start_date'):
        parsed = parse_date(data.get('start_date'))
        if not parsed:
            return JsonResponse({'error': 'Data non valida'}, status=400)
        start_date = parsed

    WorkoutAssignment.objects.filter(client=client, coach=coach, status='ACTIVE').update(status='CANCELLED')
    a = WorkoutAssignment.objects.create(
        workout_plan=plan, client=client, coach=coach,
        start_date=start_date, status='ACTIVE',
    )
    Notification.objects.create(
        target_user=client.user, notification_type='WORKOUT_ASSIGNED',
        title='Nuova scheda di allenamento',
        body=f'Ti è stata assegnata la scheda "{plan.title}".',
        link_url='/allenamenti/',
    )
    # Fire-and-forget email (silenced if user opted out) — parity with the web
    # assign flow in views_workouts so mobile-assigned plans also notify by mail.
    try:
        from django.conf import settings as _settings
        from .services.email import send_workout_assigned
        plan_url = f"{_settings.SITE_URL}/allenamenti/"
        send_workout_assigned(client, coach, plan, plan_url)
    except Exception:
        logger.exception('workout_assigned_email.failed plan_id=%s', plan.id)
    return JsonResponse({'ok': True, 'assignment_id': a.id})


# ---------------------------------------------------------------------------
# Automatic chat replies — per-event canned messages the coach can edit from
# mobile. Same model the web "Messaggi automatici" settings page writes.
# ---------------------------------------------------------------------------

_AUTO_MSG_LABELS = dict(AutomaticMessageTemplate.EVENT_TYPES)


@api_view(['GET', 'PATCH'])
def auto_messages(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    if request.method == 'PATCH':
        for entry in (_body(request).get('messages') or []):
            event_type = entry.get('event_type')
            if event_type not in _AUTO_MSG_LABELS:
                continue
            tpl, _ = AutomaticMessageTemplate.objects.get_or_create(coach=coach, event_type=event_type)
            if 'body' in entry:
                tpl.body = (entry.get('body') or '')[:2000]
            if 'is_enabled' in entry:
                tpl.is_enabled = bool(entry.get('is_enabled'))
            tpl.save()

    existing = {t.event_type: t for t in AutomaticMessageTemplate.objects.filter(coach=coach)}
    out = []
    for event_type, label in AutomaticMessageTemplate.EVENT_TYPES:
        tpl = existing.get(event_type)
        out.append({
            'event_type': event_type,
            'label': label,
            'body': tpl.body if tpl else '',
            'is_enabled': tpl.is_enabled if tpl else False,
            'attachment_url': _abs_media(request, tpl.attachment.url) if (tpl and tpl.attachment) else None,
        })
    return JsonResponse({'messages': out})


# ---------------------------------------------------------------------------
# New conversation — start a thread with an athlete the coach has never written
# to. Lists messageable clients, then creates the conversation on first send.
# ---------------------------------------------------------------------------

@api_view(['GET'])
def messageable_clients(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    rels = (CoachingRelationship.objects.filter(coach=coach, status='ACTIVE')
            .select_related('client', 'client__user'))
    convo_client_ids = set(
        Conversation.objects.filter(coach=coach, messages__isnull=False)
        .values_list('client_id', flat=True)
    )
    out = [{
        **_client_brief(request, r.client),
        'has_conversation': r.client_id in convo_client_ids,
    } for r in rels]
    return JsonResponse({'clients': out})


@api_view(['POST'])
def start_conversation(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    data = _body(request)
    body = (data.get('body') or '').strip()
    if not body:
        return JsonResponse({'error': 'Messaggio vuoto'}, status=400)
    client = ClientProfile.objects.filter(
        id=data.get('client_id'),
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    ).select_related('user').first()
    if not client:
        return JsonResponse({'error': 'Atleta non associato'}, status=403)

    conv, _ = Conversation.objects.get_or_create(coach=coach, client=client)
    msg = Message.objects.create(conversation=conv, sender_user=user, body=body, message_type='TEXT')
    conv.last_message_at = msg.sent_at
    conv.save(update_fields=['last_message_at'])
    Notification.objects.create(
        target_user=client.user, notification_type='MESSAGE',
        title=f'Nuovo messaggio da {coach.first_name}', body=body[:140], link_url='/chat/',
    )
    return JsonResponse({'conversation_id': conv.id, 'message_id': msg.id}, status=201)


# ---------------------------------------------------------------------------
# Business analytics + churn risk (coach dashboard)
#
# Dual-auth: the same endpoints serve the iOS coach app (Bearer token) and the
# web dashboard (session cookie) via ``coach_dual_auth`` + ``_request_coach``.
# Numbers come from the nightly rollups (``domain.analytics``); this layer only
# reads and shapes them for the UI.
# ---------------------------------------------------------------------------

_BUSINESS_FIELDS = [
    'active_clients_count', 'renewals_due_7d', 'renewals_completed_30d',
    'churn_rate_30d', 'avg_first_response_minutes', 'sla_adherence_rate',
    'backlog_open_reviews', 'payment_failure_rate', 'at_risk_clients_count',
    'avg_risk_score', 'monthly_revenue', 'revenue_per_active_client',
]


def _reasons_payload(codes):
    return [{'code': c, 'label': _rules.label_for(c)} for c in (codes or [])]


@coach_dual_auth
def analytics_business(request):
    """Latest KPI snapshot + a 30-day trend series for the acting coach."""
    coach = _request_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    latest = (CoachBusinessMetricsDaily.objects
              .filter(coach=coach).order_by('-snapshot_date').first())
    kpis = {f: None for f in _BUSINESS_FIELDS}
    snapshot = None
    if latest:
        snapshot = latest.snapshot_date.isoformat()
        for f in _BUSINESS_FIELDS:
            v = getattr(latest, f)
            kpis[f] = float(v) if hasattr(v, 'is_finite') or isinstance(v, float) else v

    series = list(
        CoachBusinessMetricsDaily.objects
        .filter(coach=coach).order_by('-snapshot_date')[:30]
        .values('snapshot_date', 'active_clients_count', 'at_risk_clients_count',
                'avg_risk_score', 'monthly_revenue')
    )[::-1]
    for p in series:
        p['snapshot_date'] = p['snapshot_date'].isoformat()
        p['monthly_revenue'] = float(p['monthly_revenue'])

    return JsonResponse({'snapshot_date': snapshot, 'kpis': kpis, 'series': series})


@coach_dual_auth
def analytics_risk(request):
    """At-risk clients from the latest scored day. ?class=high|medium|all&offset=0 (default all)."""
    coach = _request_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    latest_day = (RiskScoreDaily.objects.filter(coach=coach)
                  .order_by('-snapshot_date').values_list('snapshot_date', flat=True).first())
    _empty_bd = {'all': 0, 'high': 0, 'medium': 0, 'low': 0}
    if not latest_day:
        return JsonResponse({'snapshot_date': None, 'clients': [], 'has_more': False, 'breakdown': _empty_bd})

    all_rows = RiskScoreDaily.objects.filter(coach=coach, snapshot_date=latest_day)
    bd_qs = all_rows.values('risk_class').annotate(n=Count('id'))
    breakdown = {'all': all_rows.count(), 'high': 0, 'medium': 0, 'low': 0}
    for b in bd_qs:
        if b['risk_class'] in breakdown:
            breakdown[b['risk_class']] = b['n']

    LIMIT = 10
    offset = max(0, safe_int(request.GET, 'offset', 0))
    rows = all_rows.select_related('client', 'client__user').order_by('-risk_score_rule_based')
    wanted = (request.GET.get('class') or 'all').lower()
    if wanted in ('high', 'medium', 'low'):
        rows = rows.filter(risk_class=wanted)
    total = rows.count()
    page_rows = rows[offset:offset + LIMIT]

    out = []
    for r in page_rows:
        brief = _client_brief(request, r.client)
        brief.update({
            'risk_score': r.risk_score_rule_based,
            'risk_class': r.risk_class,
            'risk_probability_ml': r.risk_probability_ml,
            'model_version': r.model_version or None,
            'reasons': _reasons_payload(r.top_reason_codes),
        })
        out.append(brief)
    return JsonResponse({
        'snapshot_date': latest_day.isoformat(),
        'clients': out,
        'has_more': total > offset + LIMIT,
        'breakdown': breakdown,
    })


@coach_dual_auth
def analytics_client_risk(request, client_id):
    """Per-client risk history (sparkline) for the acting coach."""
    coach = _request_coach(request)
    if not coach:
        return JsonResponse({'error': 'Non autenticato'}, status=401)

    history = list(
        RiskScoreDaily.objects
        .filter(coach=coach, client_id=client_id).order_by('snapshot_date')
        .values('snapshot_date', 'risk_score_rule_based', 'risk_class', 'risk_probability_ml')
    )
    for h in history:
        h['snapshot_date'] = h['snapshot_date'].isoformat()
    return JsonResponse({'client_id': client_id, 'history': history})


# ---------------------------------------------------------------------------
# Chiron mobile API — same logic as views_chiron.py but via token auth
# ---------------------------------------------------------------------------

def _chiron_role(coach) -> str:
    mapping = {'COACH': 'coach', 'ALLENATORE': 'allenatore', 'NUTRIZIONISTA': 'nutrizionista'}
    return mapping.get(getattr(coach, 'professional_type', ''), 'utente')


@coach_dual_auth
def chiron_chat(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach, err = _coach_or_401(request)
    if err:
        return err
    user = coach.user
    body = _body(request)
    message = (body.get('message') or '').strip()
    if not message:
        return JsonResponse({'error': 'message required'}, status=400)
    history, memory_summary = build_context(user)
    ChironMessage.objects.create(user=user, role='user', content=message)
    try:
        result = run_chiron(
            message=message,
            user_role=_chiron_role(coach),
            history=history,
            coach_id=coach.id,
            memory_summary=memory_summary,
        )
    except Exception:
        logger.exception('CHIRON mobile chat: errore')
        return JsonResponse({'error': 'CHIRON non disponibile. Riprova tra poco.'}, status=500)
    ChironMessage.objects.create(
        user=user, role='assistant', content=result.response,
        sources=[s.model_dump() for s in result.sources],
        actions=[a.model_dump() for a in result.actions],
        used_web_search=result.used_web_search,
    )
    return JsonResponse({
        'response': result.response,
        'sources': [s.model_dump() for s in result.sources],
        'actions': [a.model_dump() for a in result.actions],
        'used_web_search': result.used_web_search,
        'pending_action': result.pending_action.model_dump() if result.pending_action else None,
    })


@coach_dual_auth
def chiron_chat_stream(request):
    """Token-by-token streaming twin of `chiron_chat` (SSE over WSGI).

    Emits `data: {"token": "..."}` per chunk as the model writes, then a final
    `data: {"done": true, ...}` with sources/actions/pending_action. The non-stream
    `chiron_chat` stays as a fallback for older clients.
    """
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach, err = _coach_or_401(request)
    if err:
        return err
    user = coach.user
    body = _body(request)
    message = (body.get('message') or '').strip()
    if not message:
        return JsonResponse({'error': 'message required'}, status=400)
    history, memory_summary = build_context(user)
    ChironMessage.objects.create(user=user, role='user', content=message)
    user_role = _chiron_role(coach)
    coach_id = coach.id

    def _sse(obj):
        return f'data: {json.dumps(obj)}\n\n'

    def stream():
        try:
            for evt in run_chiron_stream(
                message=message, user_role=user_role, history=history,
                coach_id=coach_id, memory_summary=memory_summary,
            ):
                if 'token' in evt:
                    yield _sse({'token': evt['token']})
                elif 'done' in evt:
                    result = evt['done']
                    ChironMessage.objects.create(
                        user=user, role='assistant', content=result.response,
                        sources=[s.model_dump() for s in result.sources],
                        actions=[a.model_dump() for a in result.actions],
                        used_web_search=result.used_web_search,
                    )
                    yield _sse({
                        'done': True,
                        'response': result.response,
                        'sources': [s.model_dump() for s in result.sources],
                        'actions': [a.model_dump() for a in result.actions],
                        'used_web_search': result.used_web_search,
                        'pending_action': (result.pending_action.model_dump()
                                           if result.pending_action else None),
                    })
        except Exception:
            logger.exception('CHIRON mobile chat stream: errore')
            yield _sse({'error': 'CHIRON non disponibile. Riprova tra poco.'})

    resp = StreamingHttpResponse(stream(), content_type='text/event-stream')
    resp['Cache-Control'] = 'no-cache'
    resp['X-Accel-Buffering'] = 'no'   # defeat proxy buffering so tokens flush
    return resp


@coach_dual_auth
def chiron_history(request):
    if request.method != 'GET':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach, err = _coach_or_401(request)
    if err:
        return err
    try:
        limit = min(int(request.GET.get('limit', 20)), 50)
    except (ValueError, TypeError):
        limit = 20
    qs = ChironMessage.objects.filter(user=coach.user)
    before = request.GET.get('before')
    if before:
        try:
            qs = qs.filter(id__lt=int(before))
        except (ValueError, TypeError):
            pass
    rows = list(qs.order_by('-id')[:limit + 1])
    has_more = len(rows) > limit
    rows = rows[:limit]
    rows.reverse()
    return JsonResponse({
        'messages': [
            {
                'id': r.id, 'role': r.role, 'content': r.content,
                'sources': r.sources or [], 'actions': r.actions or [],
                'used_web_search': r.used_web_search,
                'created_at': r.created_at.isoformat(),
            }
            for r in rows
        ],
        'has_more': has_more,
    })


@coach_dual_auth
def chiron_execute(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach, err = _coach_or_401(request)
    if err:
        return err
    body = _body(request)
    try:
        ok, message, link = chiron_execute_action(coach, body or {})
    except Exception:
        logger.exception('CHIRON mobile execute: errore')
        return JsonResponse({'ok': False, 'message': 'Azione non riuscita.'}, status=500)
    if ok:
        ChironMessage.objects.create(user=coach.user, role='assistant',
                                     content=f'✓ {message}', actions=[link] if link else [])
    return JsonResponse({'ok': ok, 'message': message, 'action': link},
                        status=200 if ok else 400)


@coach_dual_auth
def chiron_clear(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    coach, err = _coach_or_401(request)
    if err:
        return err
    deleted, _ = ChironMessage.objects.filter(user=coach.user).delete()
    reset_chiron_memory(coach.user)
    return JsonResponse({'status': 'ok', 'deleted': deleted})
