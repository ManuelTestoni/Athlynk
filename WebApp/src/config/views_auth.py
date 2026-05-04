from django.shortcuts import render, redirect
from django.contrib.auth.hashers import make_password, check_password
from domain.accounts.models import User, CoachProfile, ClientProfile
import logging

logger = logging.getLogger(__name__)

def login_view(request):
    if request.method == 'POST':
        email = request.POST.get('email')
        password = request.POST.get('password')
        
        try:
            user = User.objects.get(email=email)
            if check_password(password, user.password_hash):
                request.session['user_id'] = user.id
                request.session['user_role'] = user.role
                return redirect('dashboard')
            else:
                return render(request, 'pages/auth/login.html', {'error': 'Password non corretta'})
        except User.DoesNotExist:
            return render(request, 'pages/auth/login.html', {'error': 'Email non trovata. Registrati!'})
            
    return render(request, 'pages/auth/login.html')

def signup_view(request):
    if request.method == 'POST':
        email = request.POST.get('email')
        first_name = request.POST.get('first_name')
        last_name = request.POST.get('last_name')
        password = request.POST.get('password')
        confirm_password = request.POST.get('confirm_password')
        role = request.POST.get('role')  # COACH o CLIENT
        professional_type = request.POST.get('professional_type', 'COACH')  # COACH, ALLENATORE, NUTRIZIONISTA

        if password != confirm_password:
            return render(request, 'pages/auth/signup.html', {'error': 'Le password non coincidono.'})

        if len(password) < 8:
            return render(request, 'pages/auth/signup.html', {'error': 'La password deve essere di almeno 8 caratteri.'})

        if User.objects.filter(email=email).exists():
            return render(request, 'pages/auth/signup.html', {'error': 'Email già in uso. Accedi.'})

        hashed_pw = make_password(password)

        user = User.objects.create(
            email=email,
            password_hash=hashed_pw,
            role=role,
            is_active=True
        )

        if role == 'COACH':
            CoachProfile.objects.create(
                user=user,
                first_name=first_name,
                last_name=last_name,
                professional_type=professional_type,
                platform_subscription_status='ACTIVE'
            )
        elif role == 'CLIENT':
            ClientProfile.objects.create(
                user=user,
                first_name=first_name,
                last_name=last_name
            )

        # Login automatico
        request.session['user_id'] = user.id
        request.session['user_role'] = user.role

        return redirect('dashboard')

    return render(request, 'pages/auth/signup.html')

def logout_view(request):
    request.session.flush()
    return redirect('login')
