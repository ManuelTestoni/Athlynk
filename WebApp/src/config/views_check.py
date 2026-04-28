from django.shortcuts import render, redirect
from django.http import HttpResponse
from django.utils import timezone
from django.core.files.storage import FileSystemStorage
from domain.accounts.models import CoachProfile, ClientProfile
from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto
import json

def check_create_view(request):
    if request.method == 'GET':
        return render(request, 'pages/check/create.html')
        
    elif request.method == 'POST':
        # Default mock objects
        coach = CoachProfile.objects.first()
        client = ClientProfile.objects.first()
        
        # Recupera o crea un template di base se non esiste
        template, _ = QuestionnaireTemplate.objects.get_or_create(
            coach=coach,
            title="Check Settimanale Standard",
            defaults={
                'questionnaire_type': 'weekly_check',
                'phase': 'Generica',
                'is_active': True
            }
        )
        
        # === SALVATAGGIO DATI BASE ===
        weight_kg = request.POST.get('weight_kg')
        if not weight_kg:
            weight_kg = None
        if weight_kg:
            try:
                weight_kg = float(weight_kg)
            except ValueError:
                weight_kg = None
            
        # === JSON CIRCONFERENZE ===
        body_circumferences = {
            'shoulders': request.POST.get('circ_spalle', ''),
            'chest': request.POST.get('circ_petto', ''),
            'waist': request.POST.get('circ_vita', ''),
            'hips': request.POST.get('circ_fianchi', ''),
            'thigh_right': request.POST.get('circ_coscia', ''),
            'arm_right': request.POST.get('circ_braccio', '')
        }
        
        # === JSON PLICHE ===
        skinfolds = {
            'chest': request.POST.get('pl_petto', ''),
            'abdomen': request.POST.get('pl_addome', ''),
            'thigh': request.POST.get('pl_coscia', ''),
            'tricep': request.POST.get('pl_tricipite', '')
        }
        
        # === JSON RISPOSTE/FEEDBACK ===
        answers_json = {
            'mood': request.POST.get('ans_mood', ''),
            'diet_adherence': request.POST.get('ans_diet', ''),
            'workout_adherence': request.POST.get('ans_workout', '')
        }
        
        injuries = request.POST.get('injuries', '')
        limitations = request.POST.get('limitations', '')
        notes = request.POST.get('notes', '')
        
        # Crea la risposta
        response = QuestionnaireResponse.objects.create(
            questionnaire_template=template,
            client=client,
            coach=coach,
            submitted_at=timezone.now(),
            status='COMPLETED',
            weight_kg=weight_kg,
            body_circumferences=body_circumferences,
            skinfolds=skinfolds,
            answers_json=answers_json,
            injuries=injuries,
            limitations=limitations,
            notes=notes
        )
        
        # === SALVATAGGIO FOTO PROGRESSI ===
        fs = FileSystemStorage()
        
        for key, photo_type in [('photo_front', 'Front'), ('photo_side', 'Side'), ('photo_back', 'Back')]:
            file = request.FILES.get(key)
            if file:
                filename = fs.save(f"progress_photos/{client.id}/{file.name}", file)
                file_url = fs.url(filename)
                
                ProgressPhoto.objects.create(
                    client=client,
                    coach=coach,
                    questionnaire_response=response,
                    file_url=file_url,
                    photo_type=photo_type,
                    captured_at=timezone.now()
                )
                
        # Redirect the user securely using PRG pattern
        return redirect('check_dashboard')

def check_dashboard_view(request):
    coach = CoachProfile.objects.first()
    
    # Prendi tutte le risposte associate ai clienti di questo coach, ordinandole per data piÃ¹ recente
    responses = QuestionnaireResponse.objects.filter(coach=coach).order_by('-submitted_at')
    
    # Dividiamo i check tra quelli giÃ  revisionati o meno (mock, basatiullo stato. Se 'COMPLETED' Ã¨ da revisionare, 'REVIEWED' approvato)
    to_review = responses.filter(status='COMPLETED')
    reviewed = responses.filter(status='REVIEWED')
    
    context = {
        'to_review_count': to_review.count(),
        'reviewed_count': reviewed.count(),
        'responses': responses,
    }
    return render(request, 'pages/check/dashboard.html', context)
