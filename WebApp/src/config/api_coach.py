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

from datetime import date, timedelta

from django.db.models import Q, Max, Count
from django.http import JsonResponse
from django.utils import timezone
from django.utils.dateparse import parse_date

from domain.accounts.models import ClientProfile, CoachProfile
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.calendar.models import Appointment
from domain.chat.models import Conversation, Message, Notification
from domain.checks.models import QuestionnaireResponse, QuestionnaireTemplate
from domain.coaching.models import ClientAnamnesis, CoachingRelationship
from domain.nutrition.models import NutritionAssignment, NutritionPlan, SupplementAssignment, SupplementSheet
from domain.workouts.models import WorkoutAssignment, WorkoutPlan

from .api import (
    api_view, _body, _iso, _abs_media, _coach_dict, _message_dict,
)

logger = __import__('logging').getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _require_coach(user):
    """Return (coach, error_response). Error if the token isn't a coach's."""
    coach = getattr(user, 'coach_profile', None)
    if not coach:
        return None, JsonResponse({'error': 'Solo per professionisti'}, status=403)
    return coach, None


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
        'primary_goal': client.primary_goal,
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
    items = (
        Appointment.objects
        .filter(coach=coach, start_datetime__gte=now - timedelta(hours=12))
        .select_related('client', 'client__user')
        .order_by('start_datetime')[:80]
    )
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
    return JsonResponse({'appointments': out})


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

    rels = list(qs)
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
        'total': len(out),
        'active': sum(1 for r in rels if r.status == 'ACTIVE'),
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
        'id': sa.sheet.id,
        'title': sa.sheet.title,
    } for sa in (
        SupplementAssignment.objects.filter(client=client, coach=coach, status='ACTIVE')
        .select_related('sheet')
    )]

    anamnesis = ClientAnamnesis.objects.filter(client=client, coach=coach).order_by('-anamnesis_date').first()
    conv = Conversation.objects.filter(coach=coach, client=client).first()

    brief = _client_brief(request, client)
    brief.update({
        'phone': client.phone,
        'gender': client.gender,
        'birth_date': _iso(client.birth_date),
        'height_cm': client.height_cm,
        'weight_kg': float(client.current_weight_kg) if client.current_weight_kg is not None else None,
        'activity_level': client.activity_level,
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
        'active_nutrition': {'assignment_id': an.id, 'title': an.nutrition_plan.title} if an else None,
        'active_subscription': {
            'id': sub.id, 'name': sub.subscription_plan.name,
            'price': float(sub.subscription_plan.price), 'status': sub.status,
            'end_date': _iso(sub.end_date),
        } if sub else None,
        'checks': checks,
        'supplement_sheets': sheets,
        'has_anamnesis': anamnesis is not None,
        'conversation_id': conv.id if conv else None,
    })


# ---------------------------------------------------------------------------
# Check-in review ("Revisione Check-in")
# ---------------------------------------------------------------------------

def _measurements(r):
    return {k: v for k, v in (r.body_circumferences or {}).items() if v not in (None, '')}


@api_view(['GET'])
def checks_review(request, user):
    """Submitted check-ins. ?filter=pending (default) | all."""
    coach, err = _require_coach(user)
    if err:
        return err
    which = (request.GET.get('filter') or 'pending').strip()
    qs = (
        QuestionnaireResponse.objects
        .filter(coach=coach, submitted_at__isnull=False)
        .select_related('client', 'client__user', 'questionnaire_template')
        .order_by('-submitted_at')
    )
    if which == 'pending':
        qs = qs.filter(Q(coach_feedback__isnull=True) | Q(coach_feedback=''))

    out = [{
        'id': r.id,
        'title': r.questionnaire_template.title if r.questionnaire_template else 'Check',
        'submitted_at': _iso(r.submitted_at),
        'weight_kg': float(r.weight_kg) if r.weight_kg is not None else None,
        'reviewed': bool(r.coach_feedback),
        'client': _client_brief(request, r.client),
    } for r in qs[:60]]
    return JsonResponse({'checks': out, 'pending_count': _pending_review_qs(coach).count()})


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


# ---------------------------------------------------------------------------
# Workout / Nutrition management ("Gestione Allenamenti / Nutrizione")
# ---------------------------------------------------------------------------

@api_view(['GET'])
def workouts(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    plans = [{
        'id': p.id,
        'title': p.title,
        'goal': p.goal,
        'level': p.level,
        'duration_weeks': p.duration_weeks,
        'frequency_per_week': p.frequency_per_week,
        'assigned_count': p.assigned,
    } for p in (
        WorkoutPlan.objects.filter(coach=coach)
        .annotate(assigned=Count('assignments', filter=Q(assignments__status='ACTIVE')))
        .order_by('-created_at')
    )]
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
    return JsonResponse({'plans': plans, 'assignments': assignments})


@api_view(['GET'])
def nutrition(request, user):
    coach, err = _require_coach(user)
    if err:
        return err
    plans = [{
        'id': p.id,
        'title': p.title,
        'plan_mode': p.plan_mode,
        'plan_kind': p.plan_kind,
        'daily_kcal': p.daily_kcal,
        'assigned_count': p.assigned,
    } for p in (
        NutritionPlan.objects.filter(coach=coach)
        .annotate(assigned=Count('assignments', filter=Q(assignments__status='ACTIVE')))
        .order_by('-created_at')
    )]
    assignments = [{
        'id': na.id,
        'title': na.nutrition_plan.title,
        'client': _client_brief(request, na.client),
    } for na in (
        NutritionAssignment.objects.filter(coach=coach, status='ACTIVE')
        .select_related('nutrition_plan', 'client', 'client__user')
        .order_by('-assigned_at')[:50]
    )]
    return JsonResponse({'plans': plans, 'assignments': assignments})


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
    subs_qs = (
        ClientSubscription.objects
        .filter(subscription_plan__coach=coach)
        .select_related('client', 'client__user', 'subscription_plan')
        .order_by('-start_date')
    )
    active = subs_qs.filter(status='ACTIVE')
    revenue = float(sum(s.subscription_plan.price for s in active))
    subs = [{
        'id': s.id,
        'client': _client_brief(request, s.client),
        'plan_name': s.subscription_plan.name,
        'price': float(s.subscription_plan.price),
        'status': s.status,
        'payment_status': s.payment_status,
        'start_date': _iso(s.start_date),
        'end_date': _iso(s.end_date),
    } for s in subs_qs[:60]]
    return JsonResponse({
        'plans': plans,
        'subscriptions': subs,
        'active_count': active.count(),
        'monthly_revenue': revenue,
        'currency': 'EUR',
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
                     for p in WorkoutPlan.objects.filter(coach=coach).order_by('-created_at')[:80]]
    nutrition_plans = [{'id': p.id, 'title': p.title, 'plan_mode': p.plan_mode}
                       for p in NutritionPlan.objects.filter(coach=coach).order_by('-created_at')[:80]]
    templates = [{'id': t.id, 'title': t.title, 'type': t.questionnaire_type, 'active': t.is_active}
                 for t in QuestionnaireTemplate.objects.filter(coach=coach).order_by('-created_at')[:80]]
    sheets = [{'id': s.id, 'title': s.title}
              for s in SupplementSheet.objects.filter(coach=coach).order_by('-created_at')[:80]]
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
    out = []
    for conv in (
        Conversation.objects.filter(coach=coach)
        .select_related('client', 'client__user')
        .order_by('-last_message_at')
    ):
        last = conv.messages.order_by('-sent_at').first()
        unread = conv.messages.filter(read_at__isnull=True).exclude(sender_user=coach.user).count()
        out.append({
            'id': conv.id,
            'client': _client_brief(request, conv.client),
            'last_message': last.body if last else None,
            'last_message_at': _iso(conv.last_message_at),
            'unread': unread,
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
                      'certifications', 'social_instagram', 'social_youtube',
                      'social_tiktok', 'social_website'):
            if field in data:
                setattr(coach, field, (data.get(field) or '').strip() or None)
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
    from config.services.images import to_webp
    try:
        webp = to_webp(upload)
    except Exception:
        return JsonResponse({'error': 'Immagine non valida'}, status=400)
    coach.profile_image.save(webp.name, webp, save=True)
    return JsonResponse({'profile_image_url': _coach_avatar(request, coach)})
