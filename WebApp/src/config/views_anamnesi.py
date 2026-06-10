from datetime import date
from django.shortcuts import render, redirect, get_object_or_404

from config.session_utils import get_session_user, get_session_coach, get_session_client
from domain.coaching.models import CoachingRelationship, ClientAnamnesis
from domain.accounts.models import ClientProfile


def anamnesi_view(request):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')
        anamnesis = (
            ClientAnamnesis.objects
            .filter(client=client)
            .select_related('coach')
            .order_by('-anamnesis_date')
            .first()
        )
        if not anamnesis:
            return render(request, 'pages/nutrizione/no_prima_visita.html', {})
        return render(request, 'pages/nutrizione/anamnesi_detail.html', {
            'anamnesis': anamnesis,
            'is_client': True,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')

    relationships = (
        CoachingRelationship.objects
        .filter(coach=coach, status='ACTIVE')
        .select_related('client__user')
        .prefetch_related('client__anamnesis')
        .order_by('client__last_name')
    )

    clients_data = []
    for rel in relationships:
        c = rel.client
        all_anamnesi = list(c.anamnesis.order_by('-anamnesis_date', '-id'))
        anamnesis = all_anamnesi[0] if all_anamnesi else None
        clients_data.append({
            'client': c,
            'anamnesis': anamnesis,
            'anamnesis_count': len(all_anamnesi),
        })

    return render(request, 'pages/nutrizione/anamnesi_list.html', {
        'clients_data': clients_data,
    })


def anamnesi_create_view(request, client_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')

    client = get_object_or_404(ClientProfile, id=client_id)
    rel = CoachingRelationship.objects.filter(coach=coach, client=client, status='ACTIVE').first()
    if not rel:
        return redirect('nutrizione_anamnesi')

    if request.method == 'POST':
        def _int(val):
            try:
                return int(val) if val and str(val).strip() else None
            except ValueError:
                return None

        def _dec(val):
            try:
                return float(val) if val and str(val).strip() else None
            except ValueError:
                return None

        anamnesis = ClientAnamnesis.objects.create(
            client=client,
            coach=coach,
            anamnesis_date=request.POST.get('anamnesis_date') or date.today(),
            age=_int(request.POST.get('age')),
            weight_kg=_dec(request.POST.get('weight_kg')),
            height_cm=_dec(request.POST.get('height_cm')),
            medical_history=request.POST.get('medical_history', '').strip() or None,
            medications=request.POST.get('medications', '').strip() or None,
            injuries=request.POST.get('injuries', '').strip() or None,
            allergies=request.POST.get('allergies', '').strip() or None,
            intolerances=request.POST.get('intolerances', '').strip() or None,
            lifestyle_notes=request.POST.get('lifestyle_notes', '').strip() or None,
            sleep_quality=request.POST.get('sleep_quality', '').strip() or None,
            stress_level=request.POST.get('stress_level', '').strip() or None,
            food_habits=request.POST.get('food_habits', '').strip() or None,
            weight_history=request.POST.get('weight_history', '').strip() or None,
            path_goal=request.POST.get('path_goal', '').strip() or None,
            professional_notes=request.POST.get('professional_notes', '').strip() or None,
        )
        return redirect('nutrizione_anamnesi_detail', anamnesis_id=anamnesis.id)

    existing = ClientAnamnesis.objects.filter(client=client).order_by('-anamnesis_date').first()
    return render(request, 'pages/nutrizione/anamnesi_create.html', {
        'client': client,
        'existing': existing,
        'today': date.today().isoformat(),
    })


def anamnesi_detail_view(request, anamnesis_id):
    user = get_session_user(request)
    if not user:
        return redirect('login')

    if user.role == 'CLIENT':
        client = get_session_client(request)
        if not client:
            return redirect('login')
        anamnesis = get_object_or_404(ClientAnamnesis, id=anamnesis_id, client=client)
        history = list(ClientAnamnesis.objects.filter(client=client)
                       .order_by('-anamnesis_date', '-id'))
        return render(request, 'pages/nutrizione/anamnesi_detail.html', {
            'anamnesis': anamnesis,
            'history': history,
            'is_client': True,
        })

    coach = get_session_coach(request)
    if not coach:
        return redirect('login')
    anamnesis = get_object_or_404(ClientAnamnesis, id=anamnesis_id, coach=coach)
    history = list(ClientAnamnesis.objects.filter(client=anamnesis.client)
                   .order_by('-anamnesis_date', '-id'))
    return render(request, 'pages/nutrizione/anamnesi_detail.html', {
        'anamnesis': anamnesis,
        'history': history,
        'is_coach': True,
    })
