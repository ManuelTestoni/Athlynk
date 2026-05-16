from datetime import timedelta

from django.contrib.auth.hashers import make_password
from django.db.models import Count, Max, Q
from django.shortcuts import render, redirect, get_object_or_404
from django.utils import timezone
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
import json

from domain.accounts.models import CoachProfile, ClientProfile, User
from domain.billing.models import ClientSubscription, SubscriptionPlan
from domain.checks.models import QuestionnaireResponse
from domain.coaching.models import CoachingRelationship
from domain.nutrition.models import NutritionAssignment, SupplementAssignment
from domain.workouts.models import WorkoutAssignment

from .session_utils import get_session_client, get_session_coach, get_session_user, get_active_relationship
from .forms import SubscriptionPlanForm


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

    relationships = list(relationships_qs)
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

    clients_data = [
        {
            'client': rel.client,
            'relationship': rel,
            'active_workout': active_workouts.get(rel.client_id),
            'last_check_date': last_check_dates.get(rel.client_id),
            'active_subscription': active_subs.get(rel.client_id),
        }
        for rel in relationships
    ]

    all_plans = list(
        coach.subscription_plans.filter(is_active=True).order_by('name').values('id', 'name')
    )

    return render(request, 'pages/clienti/list.html', {
        'coach': coach,
        'clients_data': clients_data,
        'search': search,
        'status_filter': status_filter,
        'plan_filter': plan_filter,
        'all_plans': all_plans,
        'total_count': len(clients_data),
        'active_count': sum(1 for r in relationships if r.status == 'ACTIVE'),
    })


def coach_client_detail_view(request, client_id):
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    relationship = get_object_or_404(
        CoachingRelationship.objects.select_related('client', 'client__user'),
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
        .order_by('-created_at')
    )
    recent_checks = all_checks[:5]
    supplement_assignments = (
        SupplementAssignment.objects
        .filter(client=client, coach=coach)
        .select_related('sheet')
        .order_by('-assigned_at')
    )

    return render(request, 'pages/clienti/detail.html', {
        'coach': coach,
        'client': client,
        'relationship': relationship,
        'active_workout': workout_assignments.filter(status='ACTIVE').first(),
        'workout_assignments': workout_assignments,
        'active_nutrition': nutrition_assignments.filter(status='ACTIVE').first(),
        'nutrition_assignments': nutrition_assignments,
        'active_subscription': subscriptions.filter(status='ACTIVE').first(),
        'subscriptions': subscriptions,
        'recent_checks': recent_checks,
        'all_checks': all_checks,
        'supplement_assignments': supplement_assignments,
    })


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

    # POST — registrazione cliente
    first_name = request.POST.get('first_name', '').strip()
    last_name = request.POST.get('last_name', '').strip()
    email = request.POST.get('email', '').strip()
    password = request.POST.get('password', '').strip()
    confirm_password = request.POST.get('confirm_password', '').strip()
    phone = request.POST.get('phone', '').strip() or None
    birth_date_str = request.POST.get('birth_date', '').strip()
    gender = request.POST.get('gender', '').strip() or None
    height_str = request.POST.get('height_cm', '').strip()
    primary_goal = request.POST.get('primary_goal', '').strip() or None
    activity_level = request.POST.get('activity_level', '').strip() or None
    medical_notes = request.POST.get('medical_notes_summary', '').strip() or None
    plan_id = request.POST.get('subscription_plan_id', '').strip()
    payment_notes = request.POST.get('payment_notes', '').strip() or None

    errors = {}
    if not first_name:
        errors['first_name'] = 'Il nome è obbligatorio.'
    if not last_name:
        errors['last_name'] = 'Il cognome è obbligatorio.'
    if not email:
        errors['email'] = "L'email è obbligatoria."
    elif User.objects.filter(email=email).exists():
        errors['email'] = 'Questa email è già registrata sulla piattaforma.'
    if not password or len(password) < 8:
        errors['password'] = 'La password temporanea deve essere di almeno 8 caratteri.'
    elif password != confirm_password:
        errors['password'] = 'Le password non coincidono.'

    if not plan_id:
        errors['subscription_plan_id'] = 'Seleziona un piano di abbonamento.'

    if errors:
        return render(request, 'pages/clienti/registra.html', {
            'coach': coach,
            'is_coach': True,
            'plans': plans,
            'errors': errors,
            'post_data': request.POST,
        })

    birth_date = None
    if birth_date_str:
        from datetime import date as date_type
        try:
            birth_date = date_type.fromisoformat(birth_date_str)
        except ValueError:
            pass

    height_cm = int(height_str) if height_str.isdigit() else None

    new_user = User.objects.create(
        email=email,
        password_hash=make_password(password),
        role='CLIENT',
        is_active=True,
    )
    client = ClientProfile.objects.create(
        user=new_user,
        first_name=first_name,
        last_name=last_name,
        phone=phone,
        birth_date=birth_date,
        gender=gender,
        height_cm=height_cm,
        primary_goal=primary_goal,
        activity_level=activity_level,
        medical_notes_summary=medical_notes,
        client_status='ACTIVE',
        onboarding_status='REGISTERED',
    )
    CoachingRelationship.objects.create(
        coach=coach,
        client=client,
        status='ACTIVE',
        start_date=timezone.now().date(),
    )

    try:
        plan = SubscriptionPlan.objects.get(id=int(plan_id), coach=coach, is_active=True)
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
    except (SubscriptionPlan.DoesNotExist, ValueError):
        pass

    return redirect('clienti_detail', client_id=client.id)


def _require_client(request):
    user = get_session_user(request)
    if not user or user.role != 'CLIENT':
        return None, redirect('login')

    client = get_session_client(request)
    if not client:
        return None, redirect('login')

    return client, None


def _active_client_coach(client):
    relationship = get_active_relationship(client)
    return relationship.coach if relationship else None


def find_coach_list_view(request):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    search = request.GET.get('q', '').strip()
    coaches = (
        CoachProfile.objects
        .select_related('user')
        .annotate(
            active_clients=Count('coaching_relationships_as_coach', filter=Q(coaching_relationships_as_coach__status='ACTIVE'), distinct=True),
            active_plans=Count('subscription_plans', filter=Q(subscription_plans__is_active=True), distinct=True),
        )
        .order_by('first_name', 'last_name')
    )

    if search:
        coaches = coaches.filter(
            Q(first_name__icontains=search)
            | Q(last_name__icontains=search)
            | Q(city__icontains=search)
            | Q(specialization__icontains=search)
            | Q(bio__icontains=search)
        )

    coach_cards = []
    for coach in coaches:
        active_plan = coach.subscription_plans.filter(is_active=True).order_by('-created_at').first()
        coach_cards.append({
            'id': coach.id,
            'name': f'{coach.first_name} {coach.last_name}'.strip(),
            'professional_type': coach.professional_type,
            'title': coach.specialization or 'Coach certificato',
            'city': coach.city or 'Online',
            'bio': coach.bio or coach.description or 'Profilo disponibile nella directory della piattaforma.',
            'avatar': coach.profile_image_url or 'https://i.pravatar.cc/160?u=coach.%s' % coach.id,
            'clients': coach.active_clients,
            'plans': coach.active_plans,
            'focus': coach.specialization or 'Allenamento',
            'price': f"€ {active_plan.price}" if active_plan else 'Prezzi su richiesta',
            'plan_name': active_plan.name if active_plan else 'Nessun piano attivo',
            'services': [
                active_plan.plan_type if active_plan else 'Supporto personalizzato',
                f"{coach.years_experience}+ anni" if coach.years_experience else 'Esperienza non indicata',
                'Agenda e check' if coach.active_clients else 'Nuovo coach sulla piattaforma',
            ],
        })

    context = {
        'coaches': coach_cards,
        'search': search,
        'selected_coach': coach_cards[0] if coach_cards else None,
        'has_coach': _active_client_coach(client) is not None,
        'client': client,
    }
    return render(request, 'pages/check/coach_finder.html', context)


def coach_detail_view(request, coach_id):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    coach = get_object_or_404(CoachProfile.objects.select_related('user'), id=coach_id)
    active_plans = coach.subscription_plans.filter(is_active=True).order_by('-created_at')
    nutrition_plans = coach.nutrition_plans.filter(status='PUBLISHED').order_by('-created_at')
    workout_plans = coach.workout_plans.order_by('-created_at')
    active_relationship = get_active_relationship(client)

    context = {
        'coach': coach,
        'coach_name': f'{coach.first_name} {coach.last_name}'.strip(),
        'active_plans': active_plans,
        'nutrition_plans': nutrition_plans,
        'workout_plans': workout_plans,
        'active_relationship': active_relationship,
        'has_coach': active_relationship is not None,
        'client': client,
    }
    return render(request, 'pages/check/coach_detail.html', context)


def client_my_coach_view(request):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    relationships = CoachingRelationship.objects.filter(
        client=client, status='ACTIVE'
    ).select_related('coach').order_by('created_at')

    if not relationships.exists():
        return redirect('check_coach_directory')

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
    relationship.save(update_fields=['status'])
    return redirect('check_coach_directory')


def connect_coach_view(request, coach_id):
    client, redirect_response = _require_client(request)
    if redirect_response:
        return redirect_response

    if request.method != 'POST':
        return redirect('check_coach_detail', coach_id=coach_id)

    coach = get_object_or_404(CoachProfile, id=coach_id)

    # Determine relationship type based on coach's professional_type
    if coach.professional_type == 'COACH':
        new_rel_type = 'FULL'
    elif coach.professional_type == 'ALLENATORE':
        new_rel_type = 'WORKOUT'
    elif coach.professional_type == 'NUTRIZIONISTA':
        new_rel_type = 'NUTRITION'
    else:
        new_rel_type = 'FULL'

    # Get existing active relationships
    existing_rels = CoachingRelationship.objects.filter(client=client, status='ACTIVE')

    # Validation: pairing rules
    for rel in existing_rels:
        rel_type = rel.relationship_type or 'FULL'

        # If client has FULL (Coach), can't add anything else
        if rel_type == 'FULL':
            return redirect('check_coach_detail', coach_id=coach_id)

        # If connecting to COACH (FULL), must not have existing relationships
        if new_rel_type == 'FULL':
            return redirect('check_coach_detail', coach_id=coach_id)

        # If connecting to ALLENATORE (WORKOUT), can't have another WORKOUT
        if new_rel_type == 'WORKOUT' and rel_type == 'WORKOUT':
            return redirect('check_coach_detail', coach_id=coach_id)

        # If connecting to NUTRIZIONISTA (NUTRITION), can't have another NUTRITION
        if new_rel_type == 'NUTRITION' and rel_type == 'NUTRITION':
            return redirect('check_coach_detail', coach_id=coach_id)

    # If connecting to COACH (FULL), remove existing WORKOUT and NUTRITION relationships
    if new_rel_type == 'FULL':
        existing_rels.delete()

    # Create or update relationship
    CoachingRelationship.objects.create(
        coach=coach,
        client=client,
        status='ACTIVE',
        start_date=timezone.now().date(),
        relationship_type=new_rel_type,
    )

    return redirect('dashboard')


def nutrizione_piani_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')

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


def abbonamenti_dashboard_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        relationship = get_active_relationship(client)
        if not relationship:
            return redirect('check_coach_directory')

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

    plans = SubscriptionPlan.objects.filter(coach=coach).order_by('-created_at')
    subscriptions = ClientSubscription.objects.filter(subscription_plan__coach=coach).select_related('client', 'subscription_plan').order_by('-created_at')
    active_subs = subscriptions.filter(status='ACTIVE').count()
    total_revenue = sum(s.subscription_plan.price for s in subscriptions.filter(status='ACTIVE'))

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


def find_coach_api(request):
    """API AJAX per ricerca coach in tempo reale"""
    client, redirect_response = _require_client(request)
    if redirect_response:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    search = request.GET.get('q', '').strip()
    coaches = (
        CoachProfile.objects
        .select_related('user')
        .annotate(
            active_clients=Count('coaching_relationships_as_coach', filter=Q(coaching_relationships_as_coach__status='ACTIVE'), distinct=True),
            active_plans=Count('subscription_plans', filter=Q(subscription_plans__is_active=True), distinct=True),
        )
        .order_by('first_name', 'last_name')
    )

    if search:
        coaches = coaches.filter(
            Q(first_name__icontains=search)
            | Q(last_name__icontains=search)
            | Q(city__icontains=search)
            | Q(specialization__icontains=search)
            | Q(bio__icontains=search)
        )

    coach_cards = []
    for coach in coaches:
        active_plan = coach.subscription_plans.filter(is_active=True).order_by('-created_at').first()
        coach_cards.append({
            'id': coach.id,
            'name': f'{coach.first_name} {coach.last_name}'.strip(),
            'professional_type': coach.professional_type,
            'title': coach.specialization or 'Coach certificato',
            'city': coach.city or 'Online',
            'bio': coach.bio or coach.description or 'Profilo disponibile nella directory della piattaforma.',
            'avatar': coach.profile_image_url or 'https://i.pravatar.cc/160?u=coach.%s' % coach.id,
            'clients': coach.active_clients,
            'plans': coach.active_plans,
            'focus': coach.specialization or 'Allenamento',
            'price': f"€ {active_plan.price}" if active_plan else 'Prezzi su richiesta',
            'plan_name': active_plan.name if active_plan else 'Nessun piano attivo',
            'services': [
                active_plan.plan_type if active_plan else 'Supporto personalizzato',
                f"{coach.years_experience}+ anni" if coach.years_experience else 'Esperienza non indicata',
                'Agenda e check' if coach.active_clients else 'Nuovo coach sulla piattaforma',
            ],
        })

    return JsonResponse({'coaches': coach_cards})
