from django.shortcuts import render, redirect
from django.contrib.auth.hashers import check_password, make_password

from .session_utils import get_session_user, get_session_coach


def impostazioni_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    error = None
    active_tab = 'profilo'

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
    })
