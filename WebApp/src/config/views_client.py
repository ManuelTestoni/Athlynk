from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.db.models import Count, Max, Q
from django.shortcuts import render, redirect, get_object_or_404
from django.utils import timezone
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
import json

from domain.accounts.models import ClientProfile, User
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.checks.models import QuestionnaireResponse
from domain.coaching.models import CoachingRelationship, CoachingPhase, ClientLabel
from domain.nutrition.models import NutritionAssignment, SupplementAssignment
from domain.workouts.models import WorkoutAssignment

from .session_utils import (
    get_session_client, get_session_coach, get_session_user, get_active_relationship,
    client_has_active_access,
)
from .services import password_reset as pwd_reset
from .services.email import send_account_activation
from .services.tokens import get_client_ip
from .forms import SubscriptionPlanForm
from .views_check.helpers import _build_chart_data
from .views_check import create_quick_measurement, QuickMeasurementError


def coach_clients_list_view(request):
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    search = request.GET.get('q', '').strip()
    status_filter = request.GET.get('status', '')
    plan_filter = request.GET.get('plan', '').strip()

    relationships_qs = (
        CoachingRelationship.objects
        .filter(coach=coach)
        .select_related('client', 'client__user')
        .prefetch_related('labels')
        .order_by('-start_date', '-created_at')
    )
    if status_filter:
        relationships_qs = relationships_qs.filter(status=status_filter)
    if search:
        relationships_qs = relationships_qs.filter(
            Q(client__first_name__icontains=search)
            | Q(client__last_name__icontains=search)
        )

    if plan_filter.isdigit():
        plan_client_ids = ClientSubscription.objects.filter(
            subscription_plan_id=int(plan_filter),
            subscription_plan__coach=coach,
            status='ACTIVE',
        ).values_list('client_id', flat=True)
        relationships_qs = relationships_qs.filter(client_id__in=list(plan_client_ids))

    # One row per client: a coach can hold several relationship records for the
    # same athlete (e.g. re-added after a lapse). Keep the most relevant one
    # (qs is ordered -start_date) so the table — and its Alpine x-for :key=id —
    # never sees duplicate client ids.
    seen = set()
    relationships = []
    for r in relationships_qs:
        if r.client_id in seen:
            continue
        seen.add(r.client_id)
        relationships.append(r)
    client_ids = [r.client_id for r in relationships]

    active_workouts = {
        wa.client_id: wa
        for wa in WorkoutAssignment.objects.filter(
            client_id__in=client_ids, coach=coach, status='ACTIVE'
        ).select_related('workout_plan')
    }
    last_check_dates = dict(
        QuestionnaireResponse.objects
        .filter(client_id__in=client_ids, coach=coach)
        .values('client_id')
        .annotate(last_date=Max('created_at'))
        .values_list('client_id', 'last_date')
    )
    active_subs = {
        sub.client_id: sub
        for sub in ClientSubscription.objects.filter(
            client_id__in=client_ids,
            subscription_plan__coach=coach,
            status='ACTIVE'
        ).select_related('subscription_plan')
    }
    active_nutrition = {
        na.client_id: na
        for na in NutritionAssignment.objects.filter(
            client_id__in=client_ids, coach=coach, status='ACTIVE'
        ).select_related('nutrition_plan')
    }

    clients_data = [
        {
            'client': rel.client,
            'relationship': rel,
            'active_workout': active_workouts.get(rel.client_id),
            'last_check_date': last_check_dates.get(rel.client_id),
            'active_subscription': active_subs.get(rel.client_id),
            'active_nutrition': active_nutrition.get(rel.client_id),
            'labels': list(rel.labels.all()),
        }
        for rel in relationships
    ]

    all_plans = list(
        coach.subscription_plans.filter(is_active=True).order_by('name').values('id', 'name')
    )

    # Serialized rows for the Alpine table: filtering happens client-side (no page
    # reload), so the whole roster ships once and the view drives search/filters.
    clients_json = [
        {
            'id': item['client'].id,
            'name': f"{item['client'].first_name} {item['client'].last_name}".strip(),
            'email': item['client'].user.email,
            'initials': (item['client'].first_name[:1] + item['client'].last_name[:1]).upper(),
            'status': item['relationship'].status or '',
            'workout_title': item['active_workout'].workout_plan.title if item['active_workout'] else '',
            'workout_level': (item['active_workout'].workout_plan.level or '') if item['active_workout'] else '',
            'nutrition_title': item['active_nutrition'].nutrition_plan.title if item['active_nutrition'] else '',
            'last_check': item['last_check_date'].isoformat() if item['last_check_date'] else '',
            'sub_name': item['active_subscription'].subscription_plan.name if item['active_subscription'] else '',
            'sub_price': str(item['active_subscription'].subscription_plan.price) if item['active_subscription'] else '',
            'plan_id': str(item['active_subscription'].subscription_plan_id) if item['active_subscription'] else '',
            'url': f"/clienti/{item['client'].id}/",
            'label_ids': [l.id for l in item['labels']],
            'labels': [{'id': l.id, 'name': l.name, 'color': l.color} for l in item['labels']],
        }
        for item in clients_data
    ]

    all_labels = list(coach.client_labels.values('id', 'name', 'color'))

    response = render(request, 'pages/clienti/list.html', {
        'coach': coach,
        'clients_data': clients_data,
        'clients_json': json.dumps(clients_json),
        'all_plans': all_plans,
        'all_labels': all_labels,
        'all_labels_json': json.dumps(all_labels),
        'total_count': len(clients_data),
        'active_count': sum(1 for r in relationships if r.status == 'ACTIVE'),
    })
    response['Cache-Control'] = 'no-store'
    return response


def coach_client_detail_view(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    relationship = get_object_or_404(
        CoachingRelationship.objects.select_related('client', 'client__user').prefetch_related('labels'),
        coach=coach,
        client_id=client_id,
    )
    client = relationship.client

    workout_assignments = (
        WorkoutAssignment.objects
        .filter(client=client, coach=coach)
        .select_related('workout_plan')
        .order_by('-created_at')
    )
    nutrition_assignments = (
        NutritionAssignment.objects
        .filter(client=client, coach=coach)
        .select_related('nutrition_plan')
        .order_by('-created_at')
    )
    subscriptions = (
        ClientSubscription.objects
        .filter(client=client, subscription_plan__coach=coach)
        .select_related('subscription_plan')
        .order_by('-created_at')
    )
    all_checks = (
        QuestionnaireResponse.objects
        .filter(client=client, coach=coach)
        .select_related('questionnaire_template')
        .defer('answers_json', 'body_circumferences', 'skinfolds',
               'coach_feedback', 'coach_private_notes',
               'questionnaire_template__questions_config',
               'questionnaire_template__steps_config',
               'questionnaire_template__report_config')
        .order_by('-created_at')
    )
    recent_checks = all_checks[:5]
    supplement_assignments = (
        SupplementAssignment.objects
        .filter(client=client, coach=coach)
        .select_related('sheet')
        .order_by('-assigned_at')
    )

    # Andamento antropometrico: stessa serie usata dalla vista atleta e dallo
    # storico check (peso / circonferenze / pliche, per atleta — non per coach).
    chart_data = _build_chart_data(client)

    from django.urls import reverse
    from domain.checks.anthropometry import measurement_options

    return render(request, 'pages/clienti/detail.html', {
        'coach': coach,
        'client': client,
        'relationship': relationship,
        'chart_data_json': json.dumps(chart_data),
        'total_checks': len(chart_data['labels']),
        'measurement_options_json': json.dumps(measurement_options()),
        'measurement_post_url': reverse('api_coach_measurement', args=[client.id]),
        'active_workout': workout_assignments.filter(status='ACTIVE').first(),
        'workout_assignments': workout_assignments,
        'active_nutrition': nutrition_assignments.filter(status='ACTIVE').first(),
        'nutrition_assignments': nutrition_assignments,
        'active_subscription': subscriptions.filter(status='ACTIVE').first(),
        'subscriptions': subscriptions,
        'recent_checks': recent_checks,
        'all_checks': all_checks,
        'supplement_assignments': supplement_assignments,
        'assigned_labels': list(relationship.labels.all()),
        'all_labels': list(coach.client_labels.all()),
        'all_labels_json': json.dumps([{'id': l.id, 'name': l.name, 'color': l.color} for l in coach.client_labels.all()]),
        'assigned_labels_json': json.dumps([{'id': l.id, 'name': l.name, 'color': l.color} for l in relationship.labels.all()]),
    })


# Map a professional's type to the collaboration type they open with an athlete.
PRO_TYPE_TO_REL = {'COACH': 'FULL', 'ALLENATORE': 'WORKOUT', 'NUTRIZIONISTA': 'NUTRITION'}


def _rel_type_for(coach):
    return PRO_TYPE_TO_REL.get(coach.professional_type, 'FULL')


def _pairing_conflict(existing_rels, new_rel_type):
    """Return an error string if opening a `new_rel_type` collaboration conflicts
    with the athlete's existing active relationships, else None.

    A FULL coach (allenamento + nutrizione) is exclusive; an Allenatore (WORKOUT)
    and a Nutrizionista (NUTRITION) may coexist, but neither type may be doubled.
    """
    for rel in existing_rels:
        rel_type = rel.relationship_type or 'FULL'
        if rel_type == 'FULL':
            return 'Questo atleta è già seguito da un Coach completo (allenamento + nutrizione).'
        if new_rel_type == 'FULL':
            return ('Questo atleta ha già un professionista attivo e non può essere '
                    'preso in carico da un Coach completo.')
        if new_rel_type == rel_type:
            label = {'WORKOUT': 'un Allenatore', 'NUTRITION': 'un Nutrizionista'}.get(new_rel_type, 'un professionista')
            return f'Questo atleta ha già {label} attivo.'
    return None


def _create_client_subscription(coach, client, plan_id, payment_notes):
    """Attach a manual (paid-in-studio) subscription for this coach's plan."""
    try:
        plan = SubscriptionPlan.objects.get(id=int(plan_id), coach=coach, is_active=True)
    except (SubscriptionPlan.DoesNotExist, ValueError):
        return
    end_date = None
    if plan.duration_days:
        end_date = timezone.now().date() + timedelta(days=plan.duration_days)
    ClientSubscription.objects.create(
        client=client,
        subscription_plan=plan,
        status='ACTIVE',
        payment_status='PAID',
        start_date=timezone.now().date(),
        end_date=end_date,
        auto_renew=False,
        external_payment_provider='manual',
        external_reference=payment_notes or 'Pagamento diretto in studio',
    )


def registra_client_view(request):
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plans = SubscriptionPlan.objects.filter(coach=coach, is_active=True).order_by('name')

    if request.method == 'GET':
        # Determine cancel return URL from ?next= or HTTP referer (fallback: dashboard)
        cancel_url = request.GET.get('next', '').strip()
        if not cancel_url:
            ref = request.META.get('HTTP_REFERER', '')
            if ref:
                from urllib.parse import urlparse
                parsed = urlparse(ref)
                if parsed.path and parsed.path != request.path:
                    cancel_url = parsed.path
        if not cancel_url or not cancel_url.startswith('/'):
            cancel_url = '/'
        return render(request, 'pages/clienti/registra.html', {
            'coach': coach,
            'is_coach': True,
            'plans': plans,
            'no_plans_modal': not plans.exists(),
            'cancel_url': cancel_url,
        })

    # POST — add athlete: brand-new account or an athlete already on the platform.
    mode = (request.POST.get('mode') or 'new').strip().lower()
    plan_id = request.POST.get('subscription_plan_id', '').strip()
    payment_notes = request.POST.get('payment_notes', '').strip() or None
    new_rel_type = _rel_type_for(coach)

    if mode == 'existing':
        email = request.POST.get('email', '').strip().lower()
        errors = {}
        client = None
        if not email:
            errors['email'] = "Inserisci l'email dell'atleta già registrato."
        else:
            client = (
                ClientProfile.objects
                .filter(user__email__iexact=email, user__role='CLIENT')
                .select_related('user')
                .first()
            )
            if not client:
                errors['email'] = 'Nessun atleta registrato con questa email.'
            elif CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').exists():
                errors['email'] = 'Hai già una collaborazione attiva con questo atleta.'
            else:
                conflict = _pairing_conflict(
                    CoachingRelationship.objects.filter(client=client, status='ACTIVE'),
                    new_rel_type,
                )
                if conflict:
                    errors['email'] = conflict
        if not plan_id:
            errors['subscription_plan_id'] = 'Seleziona un piano di abbonamento.'

        if errors:
            return render(request, 'pages/clienti/registra.html', {
                'coach': coach, 'is_coach': True, 'plans': plans,
                'errors': errors, 'post_data': request.POST, 'mode': 'existing',
            })

        CoachingRelationship.objects.create(
            coach=coach, client=client, status='ACTIVE',
            start_date=timezone.now().date(), relationship_type=new_rel_type,
        )
        _create_client_subscription(coach, client, plan_id, payment_notes)
        return redirect('clienti_detail', client_id=client.id)

    # --- new athlete ---
    first_name = request.POST.get('first_name', '').strip()
    last_name = request.POST.get('last_name', '').strip()
    email = request.POST.get('email', '').strip().lower()
    phone = request.POST.get('phone', '').strip() or None
    birth_date_str = request.POST.get('birth_date', '').strip()
    gender = request.POST.get('gender', '').strip() or None

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

    birth_date = None
    if birth_date_str:
        from datetime import datetime as _dt
        try:
            birth_date = _dt.strptime(birth_date_str, '%d-%m-%Y').date()
        except ValueError:
            errors['birth_date'] = 'Usa il formato GG-MM-AAAA (es. 15-03-1990).'

    if errors:
        return render(request, 'pages/clienti/registra.html', {
            'coach': coach,
            'is_coach': True,
            'plans': plans,
            'errors': errors,
            'post_data': request.POST,
        })

    # No password is set by the coach: the account starts with an unusable hash
    # and the athlete creates their own password via the activation email below.
    # The coach typed the address, so it is trusted → is_verified=True (the
    # activation link is the proof of mailbox ownership, not a separate confirm).
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
        coach=coach,
        client=client,
        status='ACTIVE',
        start_date=timezone.now().date(),
        relationship_type=new_rel_type,
    )
    _create_client_subscription(coach, client, plan_id, payment_notes)

    # Invite the athlete to set their own password.
    token = pwd_reset.issue_token(
        new_user,
        ip=get_client_ip(request),
        user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:512],
        ttl_minutes=pwd_reset.ACTIVATION_TTL_MINUTES,
    )
    send_account_activation(new_user, token, coach_name=f"{coach.first_name} {coach.last_name}".strip())

    return redirect('clienti_detail', client_id=client.id)


@require_http_methods(["POST"])
def coach_end_relationship_view(request, client_id):
    """A professional ends their collaboration with an athlete from the athlete's
    profile (mirrors the athlete-side 'termina collaborazione'). The athlete loses
    access unless another professional still follows them."""
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    relationship = get_object_or_404(
        CoachingRelationship, coach=coach, client_id=client_id, status='ACTIVE',
    )
    relationship.status = 'INACTIVE'
    relationship.end_date = timezone.now().date()
    relationship.save(update_fields=['status', 'end_date'])
    return redirect('clienti_detail', client_id=client_id)


def client_blocked_view(request):
    """Landing page for an athlete with no active professional collaboration
    (never added, collaboration ended, or subscription lapsed). Reachable even
    while blocked; bounces back to the app once access is restored."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    if user.role != 'CLIENT':
        return redirect('dashboard')

    client = get_session_client(request)
    if client and client_has_active_access(client):
        return redirect('dashboard')

    return render(request, 'pages/clienti/accesso_sospeso.html', {
        'client': client,
        'is_client': True,
    })


def _require_client(request):
    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        return None, redirect('login')

    client = get_session_client(request)
    if not client:
        return None, redirect('login')

    return client, None


def client_my_coach_view(request):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    relationships = CoachingRelationship.objects.filter(
        client=client, status='ACTIVE'
    ).select_related('coach').order_by('created_at')

    if not relationships.exists():
        return redirect('client_blocked')

    if relationships.count() == 1:
        return redirect('client_specialist_detail', rel_id=relationships.first().id)

    # Multiple specialists → list page
    specialists = []
    for rel in relationships:
        coach = rel.coach
        rel_label = {'FULL': 'Coach', 'WORKOUT': 'Allenatore', 'NUTRITION': 'Nutrizionista'}.get(rel.relationship_type or 'FULL', 'Specialista')
        specialists.append({'relationship': rel, 'coach': coach, 'rel_label': rel_label})

    return render(request, 'pages/clienti/il_miei_specialisti.html', {'specialists': specialists})


def client_specialist_detail_view(request, rel_id):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    relationship = get_object_or_404(CoachingRelationship, id=rel_id, client=client, status='ACTIVE')
    coach = relationship.coach

    active_plans = coach.subscription_plans.filter(is_active=True).order_by('price')
    my_subscription = ClientSubscription.objects.filter(
        client=client, status='ACTIVE', subscription_plan__coach=coach
    ).select_related('subscription_plan').first()
    total_checks = QuestionnaireResponse.objects.filter(client=client, coach=coach).count()

    social_links = [
        ('ph-instagram-logo', 'text-pink-500', coach.social_instagram),
        ('ph-youtube-logo', 'text-red-500', coach.social_youtube),
        ('ph-tiktok-logo', 'text-slate-800', coach.social_tiktok),
        ('ph-facebook-logo', 'text-blue-600', coach.social_facebook),
        ('ph-globe', 'text-accent', coach.social_website),
    ]
    social_links = [(icon, color, url) for icon, color, url in social_links if url]

    video_urls = []
    if coach.professional_videos:
        video_urls = [u.strip() for u in coach.professional_videos.splitlines() if u.strip()][:3]

    context = {
        'coach': coach,
        'coach_name': f'{coach.first_name} {coach.last_name}'.strip(),
        'relationship': relationship,
        'active_plans': active_plans,
        'my_subscription': my_subscription,
        'total_checks': total_checks,
        'social_links': social_links,
        'video_urls': video_urls,
    }
    return render(request, 'pages/clienti/il_mio_coach.html', context)


def client_disconnect_coach_view(request, rel_id):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    if request.method != 'POST':
        return redirect('client_my_coach')

    relationship = get_object_or_404(CoachingRelationship, id=rel_id, client=client, status='ACTIVE')
    relationship.status = 'INACTIVE'
    relationship.end_date = timezone.now().date()
    relationship.save(update_fields=['status', 'end_date'])
    return redirect('client_blocked')


def nutrizione_piani_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('client_blocked')

        assignments = (
            NutritionAssignment.objects
            .select_related('nutrition_plan', 'coach')
            .filter(client=client, coach=relationship.coach)
            .order_by('-created_at')
        )
        return render(request, 'pages/nutrizione/client_piani.html', {
            'is_client': True,
            'client': client,
            'coach': relationship.coach,
            'nutrition_assignments': assignments,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plans = coach.nutrition_plans.order_by('-created_at')
    assignments = NutritionAssignment.objects.filter(coach=coach).select_related('nutrition_plan', 'client').order_by('-created_at')
    return render(request, 'pages/nutrizione/piani_list.html', {
        'is_coach': True,
        'coach': coach,
        'nutrition_plans': plans,
        'nutrition_assignments': assignments,
    })


@require_http_methods(["POST"])
def assign_plan_to_client_view(request, plan_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    plan = get_object_or_404(SubscriptionPlan, id=plan_id, coach=coach, is_active=True)
    client_id = request.POST.get('client_id', '').strip()
    payment_notes = request.POST.get('payment_notes', '').strip()

    if not client_id:
        return JsonResponse({'error': 'Seleziona un atleta.'}, status=400)

    client = get_object_or_404(
        ClientProfile,
        id=client_id,
        coaching_relationships_as_client__coach=coach,
        coaching_relationships_as_client__status='ACTIVE',
    )

    if ClientSubscription.objects.filter(client=client, subscription_plan__coach=coach, status='ACTIVE').exists():
        return JsonResponse({'error': 'Questo atleta ha già un abbonamento attivo con te.'}, status=400)

    end_date = None
    if plan.duration_days:
        end_date = timezone.now().date() + timedelta(days=plan.duration_days)

    ClientSubscription.objects.create(
        client=client,
        subscription_plan=plan,
        status='ACTIVE',
        payment_status='PAID',
        start_date=timezone.now().date(),
        end_date=end_date,
        auto_renew=False,
        external_payment_provider='manual',
        external_reference=payment_notes or 'Assegnato manualmente',
    )
    return JsonResponse({'success': True})


@require_http_methods(['POST'])
def api_subscription_mark_paid(request, subscription_id):
    """Azione rapida coach: marca PAID lo stato pagamento di un'iscrizione."""
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    sub = get_object_or_404(
        ClientSubscription, id=subscription_id, subscription_plan__coach=coach,
    )
    sub.payment_status = 'PAID'
    sub.save(update_fields=['payment_status', 'updated_at'])
    return JsonResponse({'success': True})


def abbonamenti_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('client_blocked')

        plans = SubscriptionPlan.objects.filter(coach=relationship.coach, is_active=True).order_by('-created_at')
        active_subscription = ClientSubscription.objects.filter(client=client, subscription_plan__coach=relationship.coach).select_related('subscription_plan').order_by('-created_at').first()
        return render(request, 'pages/abbonamenti/client_dashboard.html', {
            'is_client': True,
            'client': client,
            'coach': relationship.coach,
            'available_plans': plans,
            'active_subscription': active_subscription,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plans = (
        SubscriptionPlan.objects.filter(coach=coach)
        .annotate(active_subscribers=Count(
            'client_subscriptions',
            filter=Q(client_subscriptions__status='ACTIVE'),
            distinct=True,
        ))
        .order_by('-is_active', '-created_at')
    )
    subscriptions = ClientSubscription.objects.filter(subscription_plan__coach=coach).select_related('client', 'subscription_plan').order_by('-created_at')
    active_subs = subscriptions.filter(status='ACTIVE').count()
    total_revenue = sum(s.subscription_plan.price for s in subscriptions.filter(status='ACTIVE'))
    pending_payments = subscriptions.filter(status='ACTIVE', payment_status='PENDING').count()

    # Clients available for manual plan assignment
    coach_clients = list(
        ClientProfile.objects
        .filter(coaching_relationships_as_client__coach=coach, coaching_relationships_as_client__status='ACTIVE')
        .order_by('first_name', 'last_name')
        .values('id', 'first_name', 'last_name')
    )

    already_subscribed_ids = list(
        ClientSubscription.objects.filter(subscription_plan__coach=coach, status='ACTIVE')
        .values_list('client_id', flat=True).distinct()
    )

    return render(request, 'pages/abbonamenti/dashboard.html', {
        'is_coach': True,
        'coach': coach,
        'subscription_plans': plans,
        'subscriptions': subscriptions,
        'active_subs': active_subs,
        'total_revenue': total_revenue,
        'pending_payments': pending_payments,
        'coach_clients_json': json.dumps(coach_clients),
        'already_subscribed_ids_json': json.dumps(already_subscribed_ids),
    })


# ===== SUBSCRIPTION PLAN MANAGEMENT (Coach) =====
def subscription_plan_create_view(request):
    """Crea un nuovo piano di abbonamento"""
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    if request.method == 'POST':
        form = SubscriptionPlanForm(request.POST)
        if form.is_valid():
            plan = form.save(commit=False)
            plan.coach = coach
            plan.save()
            return redirect('abbonamenti_dashboard')
    else:
        form = SubscriptionPlanForm()

    return render(request, 'pages/abbonamenti/plan_form.html', {
        'form': form,
        'coach': coach,
        'action': 'Crea',
    })


def subscription_plan_edit_view(request, plan_id):
    """Modifica un piano di abbonamento esistente"""
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plan = get_object_or_404(SubscriptionPlan, id=plan_id, coach=coach)

    if request.method == 'POST':
        form = SubscriptionPlanForm(request.POST, instance=plan)
        if form.is_valid():
            form.save()
            return redirect('abbonamenti_dashboard')
    else:
        form = SubscriptionPlanForm(instance=plan)

    return render(request, 'pages/abbonamenti/plan_form.html', {
        'form': form,
        'plan': plan,
        'coach': coach,
        'action': 'Modifica',
    })


@require_http_methods(["DELETE"])
def subscription_plan_delete_view(request, plan_id):
    """Elimina un piano di abbonamento"""
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    plan = get_object_or_404(SubscriptionPlan, id=plan_id, coach=coach)
    
    # Controlla se ci sono clienti attivi con questo piano
    active_subs = ClientSubscription.objects.filter(subscription_plan=plan, status='ACTIVE')
    if active_subs.exists():
        return JsonResponse({
            'error': f'Impossibile eliminare: {active_subs.count()} atleti attivi su questo piano'
        }, status=400)
    
    plan.delete()
    return JsonResponse({'success': True})


def subscription_plan_detail_view(request, plan_id):
    """Dettagli di un piano e clienti affiliati"""
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    plan = get_object_or_404(SubscriptionPlan, id=plan_id, coach=coach)
    subscriptions = ClientSubscription.objects.filter(subscription_plan=plan).select_related('client').order_by('-created_at')

    return render(request, 'pages/abbonamenti/plan_detail.html', {
        'plan': plan,
        'coach': coach,
        'subscriptions': subscriptions,
        'active_count': subscriptions.filter(status='ACTIVE').count(),
        'total_revenue': sum([s.subscription_plan.price for s in subscriptions.filter(status='ACTIVE')]),
    })


# ── Timeline "Percorso" ──────────────────────────────────────────────────────

def _build_percorso_events(client, coach, window_start, window_end):
    """Collect and merge timeline events for a client in [window_start, window_end]."""
    from datetime import date as date_type
    events = []

    # Workout assignments
    for wa in (WorkoutAssignment.objects
               .filter(client=client, coach=coach)
               .select_related('workout_plan')
               .filter(created_at__date__gte=window_start, created_at__date__lte=window_end)):
        events.append({
            'id': f'allenamento-{wa.id}',
            'type': 'allenamento',
            'date': wa.created_at.date().isoformat(),
            'title': wa.workout_plan.title,
            'subtitle': 'Piano assegnato',
            'status': wa.status,
            'status_label': 'Attivo' if wa.status == 'ACTIVE' else wa.status.capitalize(),
            'url': f'/allenamenti/legacy/{wa.id}/modifica/',
        })

    # Nutrition assignments
    for na in (NutritionAssignment.objects
               .filter(client=client, coach=coach)
               .select_related('nutrition_plan')
               .filter(assigned_at__date__gte=window_start, assigned_at__date__lte=window_end)):
        events.append({
            'id': f'nutrizione-{na.id}',
            'type': 'nutrizione',
            'date': na.assigned_at.date().isoformat(),
            'title': na.nutrition_plan.title,
            'subtitle': 'Piano nutrizionale',
            'status': na.status,
            'status_label': 'Attivo' if na.status == 'ACTIVE' else na.status.capitalize(),
            'url': f'/nutrizione/piani/{na.nutrition_plan_id}/',
        })

    # Check responses
    for qr in (QuestionnaireResponse.objects
               .filter(client=client, coach=coach)
               .select_related('questionnaire_template')
               .defer('answers_json', 'body_circumferences', 'skinfolds',
                      'coach_feedback', 'coach_private_notes')
               .filter(created_at__date__gte=window_start, created_at__date__lte=window_end)):
        ref_date = (qr.submitted_at.date() if qr.submitted_at else qr.created_at.date())
        events.append({
            'id': f'check-{qr.id}',
            'type': 'check',
            'date': ref_date.isoformat(),
            'title': qr.questionnaire_template.title,
            'subtitle': 'Check compilato',
            'status': qr.status,
            'status_label': 'Revisionato' if qr.status == 'REVIEWED' else 'Da revisionare',
            'url': f'/check/{qr.id}/',
        })

    events.sort(key=lambda e: e['date'])
    return events


def _serialize_phases(client, coach):
    """Phases (coach notes spanning a period) for this client/coach pair."""
    phases = []
    for ph in CoachingPhase.objects.filter(client=client, coach=coach):
        phases.append({
            'id': ph.id,
            'title': ph.title,
            'note': ph.note or '',
            'start': ph.start_date.isoformat(),
            'end': ph.end_date.isoformat(),
            'duration_value': ph.duration_value,
            'duration_unit': ph.duration_unit,
        })
    return phases


def api_coach_client_percorso(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    relationship = CoachingRelationship.objects.filter(
        coach=coach, client_id=client_id
    ).select_related('client').first()
    if not relationship:
        return JsonResponse({'error': 'Not found'}, status=404)

    return _percorso_response(request, relationship.client, coach, relationship.start_date)


@require_http_methods(["POST"])
def api_coach_phase_create(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    relationship = CoachingRelationship.objects.filter(coach=coach, client_id=client_id).first()
    if not relationship:
        return JsonResponse({'error': 'Not found'}, status=404)

    from datetime import date as date_type
    try:
        payload = json.loads(request.body or '{}')
    except (ValueError, json.JSONDecodeError):
        return JsonResponse({'error': 'Body non valido.'}, status=400)

    title = (payload.get('title') or '').strip()
    note = (payload.get('note') or '').strip()
    start_str = (payload.get('start_date') or '').strip()
    unit = (payload.get('duration_unit') or 'WEEKS').strip().upper()

    if not title:
        return JsonResponse({'error': 'Il titolo è obbligatorio.'}, status=400)
    try:
        start_date = date_type.fromisoformat(start_str)
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
        coach=coach,
        client_id=client_id,
        title=title[:120],
        note=note,
        start_date=start_date,
        duration_value=duration_value,
        duration_unit=unit,
    )
    return JsonResponse({
        'id': phase.id,
        'title': phase.title,
        'note': phase.note,
        'start': phase.start_date.isoformat(),
        'end': phase.end_date.isoformat(),
        'duration_value': phase.duration_value,
        'duration_unit': phase.duration_unit,
    })


def _parse_measurement_payload(request):
    """(mtype, key, value, day) | (None, error_message). Shared web parser."""
    from datetime import date as date_type
    try:
        payload = json.loads(request.body or '{}')
    except (ValueError, json.JSONDecodeError):
        return None, 'Body non valido.'
    mtype = (payload.get('type') or '').strip()
    key = (payload.get('key') or '').strip() or None
    value = payload.get('value')
    date_str = (payload.get('date') or '').strip()
    if mtype not in ('weight', 'circumference', 'skinfold'):
        return None, 'Tipo di misura non valido.'
    if mtype != 'weight' and not key:
        return None, 'Seleziona il punto di misura.'
    if date_str:
        try:
            day = date_type.fromisoformat(date_str)
        except ValueError:
            return None, 'Data non valida.'
    else:
        day = timezone.localdate()
    return (mtype, key, value, day), None


@require_http_methods(["POST"])
def api_client_measurement_create(request):
    """L'atleta inserisce una propria misurazione singola (peso/circ/plica)."""
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    rel = get_active_relationship(client)
    if not rel:
        return JsonResponse({'error': 'Nessun coach attivo.'}, status=403)
    parsed, err = _parse_measurement_payload(request)
    if err:
        return JsonResponse({'error': err}, status=400)
    mtype, key, value, day = parsed
    try:
        r = create_quick_measurement(rel.coach, client, mtype, key, value, day)
    except QuickMeasurementError as e:
        return JsonResponse({'error': str(e)}, status=400)
    return JsonResponse({'success': True, 'id': r.id})


@require_http_methods(["POST"])
def api_coach_measurement_create(request, client_id):
    """Il coach inserisce una misurazione singola per un proprio cliente."""
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    relationship = CoachingRelationship.objects.filter(
        coach=coach, client_id=client_id, status='ACTIVE').select_related('client').first()
    if not relationship:
        return JsonResponse({'error': 'Not found'}, status=404)
    parsed, err = _parse_measurement_payload(request)
    if err:
        return JsonResponse({'error': err}, status=400)
    mtype, key, value, day = parsed
    try:
        r = create_quick_measurement(coach, relationship.client, mtype, key, value, day)
    except QuickMeasurementError as e:
        return JsonResponse({'error': str(e)}, status=400)
    return JsonResponse({'success': True, 'id': r.id})


@require_http_methods(["DELETE"])
def api_coach_phase_delete(request, client_id, phase_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    phase = CoachingPhase.objects.filter(id=phase_id, coach=coach, client_id=client_id).first()
    if not phase:
        return JsonResponse({'error': 'Not found'}, status=404)
    phase.delete()
    return JsonResponse({'success': True})


def api_client_my_percorso(request):
    client = get_session_client(request)
    if not client:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    rel = get_active_relationship(client)
    if not rel:
        return JsonResponse({
            'events': [], 'window_start': '', 'window_end': '',
            'has_more': False, 'relationship_start': '',
        })

    return _percorso_response(request, client, rel.coach, rel.start_date)


def _one_year_after_month(d):
    """First day of the month one year + one month past d — a trailing year of
    scroll room past the latest activity, snapped to a clean month boundary."""
    import datetime
    base = d.replace(day=1)
    plus = base.replace(year=base.year + 1)
    if plus.month == 12:
        return datetime.date(plus.year + 1, 1, 1)
    return datetime.date(plus.year, plus.month + 1, 1)


def _percorso_response(request, client, coach, relationship_start=None):
    import datetime
    from datetime import date as date_type

    today = date_type.today()

    # Relationship start: floor to first of that month. This is the backward
    # bound — the track never scrolls before it.
    if relationship_start:
        rel_start = relationship_start if isinstance(relationship_start, date_type) else relationship_start.date()
        rel_start = rel_start.replace(day=1)
    else:
        rel_start = (today - datetime.timedelta(days=365)).replace(day=1)

    window_start = rel_start

    # All recorded activity is past-dated, so collect everything up to today;
    # phases may reach into the future and are folded in below.
    events = _build_percorso_events(client, coach, window_start, today)
    phases = _serialize_phases(client, coach)

    # Forward bound is open-ended: one year past the latest activity (last event
    # or phase end), not a fixed one-year window. The span grows with the
    # athlete's history and planned phases; the client scrolls horizontally.
    last_activity = today
    if events:
        last_activity = max(last_activity, date_type.fromisoformat(events[-1]['date']))
    for ph in phases:
        ph_end = date_type.fromisoformat(ph['end'])
        if ph_end > last_activity:
            last_activity = ph_end
    window_end = _one_year_after_month(last_activity)

    return JsonResponse({
        'events': events,
        'phases': phases,
        'window_start': window_start.isoformat(),
        'window_end': window_end.isoformat(),
        'has_more': False,
        'relationship_start': rel_start.isoformat(),
    })


def il_mio_percorso_view(request):
    client = get_session_client(request)
    if not client:
        return redirect('login')

    rel = get_active_relationship(client)
    return render(request, 'pages/profilo/il_mio_percorso.html', {
        'client': client,
        'relationship': rel,
        'is_client': True,
    })


# ---------------------------------------------------------------------------
# Labels (Etichette) API
# ---------------------------------------------------------------------------

@require_http_methods(["GET", "POST"])
def api_coach_labels(request):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    if request.method == 'GET':
        labels = list(coach.client_labels.values('id', 'name', 'color'))
        return JsonResponse({'labels': labels})

    data = json.loads(request.body or '{}')
    name = (data.get('name') or '').strip()
    color = (data.get('color') or 'bronze').strip()
    if not name:
        return JsonResponse({'error': 'Nome obbligatorio.'}, status=400)
    label, created = ClientLabel.objects.get_or_create(
        coach=coach, name=name,
        defaults={'color': color},
    )
    if not created:
        return JsonResponse({'error': 'Etichetta già esistente.'}, status=400)
    return JsonResponse({'id': label.id, 'name': label.name, 'color': label.color}, status=201)


@require_http_methods(["DELETE"])
def api_coach_label_delete(request, label_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    label = get_object_or_404(ClientLabel, id=label_id, coach=coach)
    label.delete()
    return JsonResponse({'ok': True})


@require_http_methods(["POST"])
def api_coach_client_label_assign(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    relationship = get_object_or_404(CoachingRelationship, coach=coach, client_id=client_id)
    data = json.loads(request.body or '{}')
    label_id = data.get('label_id')
    label = get_object_or_404(ClientLabel, id=label_id, coach=coach)
    if relationship.labels.filter(id=label_id).exists():
        return JsonResponse({'error': 'Etichetta già assegnata.'}, status=400)
    relationship.labels.add(label)
    return JsonResponse({'ok': True})


@require_http_methods(["DELETE"])
def api_coach_client_label_remove(request, client_id, label_id):
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    relationship = get_object_or_404(CoachingRelationship, coach=coach, client_id=client_id)
    label = get_object_or_404(ClientLabel, id=label_id, coach=coach)
    relationship.labels.remove(label)
    return JsonResponse({'ok': True})
