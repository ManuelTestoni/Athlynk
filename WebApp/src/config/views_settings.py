from django.shortcuts import render, redirect
from django.contrib.auth.hashers import check_password
from django.views.decorators.http import require_POST
from django.db import transaction

from .session_utils import get_session_user, get_session_coach, get_session_client
from .services.images import to_webp, is_image


def _newsletter_status(email):
    try:
        from domain.newsletter.models import Subscriber
        sub = Subscriber.objects.filter(email=email).first()
        return sub.status if sub else 'NONE'
    except Exception:
        return 'NONE'


def impostazioni_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    error = None
    active_tab = 'profilo'

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')

        if request.method == 'POST':
            action = request.POST.get('action')

            if action == 'profilo':
                client.first_name = request.POST.get('first_name', '').strip() or client.first_name
                client.last_name = request.POST.get('last_name', '').strip() or client.last_name
                client.phone = request.POST.get('phone', '').strip() or None
                birth = request.POST.get('birth_date', '').strip()
                client.birth_date = birth if birth else client.birth_date
                client.gender = request.POST.get('gender', '').strip() or None
                height = request.POST.get('height_cm', '').strip()
                client.height_cm = int(height) if height.isdigit() else client.height_cm
                client.primary_goal = request.POST.get('primary_goal', '').strip() or None
                if 'profile_image' in request.FILES:
                    raw = request.FILES['profile_image']
                    if is_image(raw):
                        client.profile_image = to_webp(raw)
                client.save()
                return redirect(f"{request.path}?saved=profilo")

        saved = request.GET.get('saved')
        if saved and not error:
            active_tab = saved

        reset_request_sent = request.session.pop('reset_request_sent', False)
        if reset_request_sent:
            active_tab = 'sicurezza'

        return render(request, 'pages/impostazioni/dashboard.html', {
            'client': client,
            'auth_user': user,
            'is_client': True,
            'active_tab': active_tab,
            'error': error,
            'saved': saved,
            'newsletter_status': _newsletter_status(user.email),
            'reset_request_sent': reset_request_sent,
        })

    # COACH
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    if request.method == 'POST':
        action = request.POST.get('action')

        if action == 'profilo':
            coach.first_name = request.POST.get('first_name', '').strip() or coach.first_name
            coach.last_name = request.POST.get('last_name', '').strip() or coach.last_name
            coach.phone = request.POST.get('phone', '').strip() or None
            coach.city = request.POST.get('city', '').strip() or None
            coach.bio = request.POST.get('bio', '').strip() or None
            coach.specialization = request.POST.get('specialization', '').strip() or None
            coach.certifications = request.POST.get('certifications', '').strip() or None
            years = request.POST.get('years_experience', '').strip()
            coach.years_experience = int(years) if years.isdigit() else None
            if 'profile_image' in request.FILES:
                raw = request.FILES['profile_image']
                if is_image(raw):
                    coach.profile_image = to_webp(raw)
            coach.social_instagram = request.POST.get('social_instagram', '').strip() or None
            coach.social_youtube = request.POST.get('social_youtube', '').strip() or None
            coach.social_tiktok = request.POST.get('social_tiktok', '').strip() or None
            coach.social_facebook = request.POST.get('social_facebook', '').strip() or None
            coach.social_website = request.POST.get('social_website', '').strip() or None
            videos_raw = request.POST.get('professional_videos', '').strip()
            coach.professional_videos = videos_raw or None
            coach.save()
            return redirect(f"{request.path}?saved=profilo")

    saved = request.GET.get('saved')
    if saved and not error:
        active_tab = saved

    reset_request_sent = request.session.pop('reset_request_sent', False)
    if reset_request_sent:
        active_tab = 'sicurezza'

    return render(request, 'pages/impostazioni/dashboard.html', {
        'coach': coach,
        'auth_user': user,
        'is_coach': True,
        'active_tab': active_tab,
        'error': error,
        'saved': saved,
        'newsletter_status': _newsletter_status(user.email),
        'reset_request_sent': reset_request_sent,
    })


def my_profile_view(request):
    """Self-view: show coach/client their own profile in public-style layout."""
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'COACH':
        coach = get_session_coach(request)
        if not coach:
            return redirect('login')
        return render(request, 'pages/profilo/me_coach.html', {
            'coach': coach,
            'coach_name': f'{coach.first_name} {coach.last_name}'.strip(),
            'auth_user': user,
            'is_self': True,
        })

    client = get_session_client(request)
    if not client:
        return redirect('login')
    return render(request, 'pages/profilo/me_client.html', {
        'client': client,
        'auth_user': user,
        'is_self': True,
    })


@require_POST
def delete_account_view(request):
    """Hard delete the currently logged-in user account.

    Requires the current password as confirmation. Cascades to profile and
    all related domain rows via Django FK CASCADE. Flushes the session.
    """
    user = get_session_user(request)
    if not user:
        return redirect('login')

    password = request.POST.get('confirm_password', '')
    confirm_text = request.POST.get('confirm_text', '').strip().upper()

    error = None
    if not check_password(password, user.password_hash):
        error = 'Password non corretta.'
    elif confirm_text != 'ELIMINA':
        error = 'Digita ELIMINA per confermare.'

    if error:
        active_tab = 'elimina'
        ctx = {
            'auth_user': user,
            'active_tab': active_tab,
            'error': error,
            'newsletter_status': _newsletter_status(user.email),
        }
        if user.role == 'COACH':
            ctx['coach'] = get_session_coach(request)
            ctx['is_coach'] = True
        else:
            ctx['client'] = get_session_client(request)
            ctx['is_client'] = True
        return render(request, 'pages/impostazioni/dashboard.html', ctx)

    with transaction.atomic():
        user.delete()

    request.session.flush()
    return redirect('login')
