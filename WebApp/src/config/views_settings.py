from django.shortcuts import render, redirect
from django.contrib.auth.hashers import check_password, make_password

from .session_utils import get_session_user, get_session_coach, get_session_client


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
                client.save()
                return redirect(f"{request.path}?saved=profilo")

            elif action == 'sicurezza':
                active_tab = 'sicurezza'
                current_pw = request.POST.get('current_password', '')
                new_pw = request.POST.get('new_password', '')
                confirm_pw = request.POST.get('confirm_password', '')

                if not check_password(current_pw, user.password_hash):
                    error = 'La password attuale non è corretta.'
                elif len(new_pw) < 8:
                    error = 'La nuova password deve essere di almeno 8 caratteri.'
                elif new_pw != confirm_pw:
                    error = 'Le due password non coincidono.'
                else:
                    user.password_hash = make_password(new_pw)
                    user.save()
                    return redirect(f"{request.path}?saved=sicurezza")

        saved = request.GET.get('saved')
        if saved and not error:
            active_tab = saved

        return render(request, 'pages/impostazioni/dashboard.html', {
            'client': client,
            'auth_user': user,
            'is_client': True,
            'active_tab': active_tab,
            'error': error,
            'saved': saved,
            'newsletter_status': _newsletter_status(user.email),
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
                coach.profile_image = request.FILES['profile_image']
            coach.social_instagram = request.POST.get('social_instagram', '').strip() or None
            coach.social_youtube = request.POST.get('social_youtube', '').strip() or None
            coach.social_tiktok = request.POST.get('social_tiktok', '').strip() or None
            coach.social_facebook = request.POST.get('social_facebook', '').strip() or None
            coach.social_website = request.POST.get('social_website', '').strip() or None
            videos_raw = request.POST.get('professional_videos', '').strip()
            coach.professional_videos = videos_raw or None
            coach.save()
            return redirect(f"{request.path}?saved=profilo")

        elif action == 'sicurezza':
            active_tab = 'sicurezza'
            current_pw = request.POST.get('current_password', '')
            new_pw = request.POST.get('new_password', '')
            confirm_pw = request.POST.get('confirm_password', '')

            if not check_password(current_pw, user.password_hash):
                error = 'La password attuale non è corretta.'
            elif len(new_pw) < 8:
                error = 'La nuova password deve essere di almeno 8 caratteri.'
            elif new_pw != confirm_pw:
                error = 'Le due password non coincidono.'
            else:
                user.password_hash = make_password(new_pw)
                user.save()
                return redirect(f"{request.path}?saved=sicurezza")

    saved = request.GET.get('saved')
    if saved and not error:
        active_tab = saved

    return render(request, 'pages/impostazioni/dashboard.html', {
        'coach': coach,
        'auth_user': user,
        'is_coach': True,
        'active_tab': active_tab,
        'error': error,
        'saved': saved,
        'newsletter_status': _newsletter_status(user.email),
    })
