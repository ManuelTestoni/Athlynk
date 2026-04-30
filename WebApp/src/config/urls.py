"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static
from django.views.generic import TemplateView
from . import views
from . import views_workouts
from . import views_agenda
from . import views_check
from . import views_auth
from . import views_client
from . import views_settings
from . import views_nutrition

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Auth
    path('login/', views_auth.login_view, name='login'),
    path('registrati/', views_auth.signup_view, name='signup'),
    path('logout/', views_auth.logout_view, name='logout'),
    
    path('', views.dashboard_view, name='dashboard'),

    # Clienti (coach)
    path('clienti/', views_client.coach_clients_list_view, name='clienti_list'),
    path('clienti/registra/', views_client.registra_client_view, name='clienti_registra'),
    path('clienti/<int:client_id>/', views_client.coach_client_detail_view, name='clienti_detail'),

    # Il mio coach (client)
    path('il-mio-coach/', views_client.client_my_coach_view, name='client_my_coach'),

    # Nutrizione
    path('nutrizione/piani/', views_nutrition.nutrizione_piani_view, name='nutrizione_piani'),
    path('nutrizione/piani/crea/', views_nutrition.nutrizione_piano_create_view, name='nutrizione_piano_create'),
    path('nutrizione/piani/<int:plan_id>/', views_nutrition.nutrizione_piano_detail_view, name='nutrizione_piano_detail'),
    path('nutrizione/piani/<int:plan_id>/modifica/', views_nutrition.nutrizione_piano_edit_view, name='nutrizione_piano_edit'),
    path('nutrizione/dettaglio/<int:assignment_id>/', views_nutrition.nutrizione_client_detail_view, name='nutrizione_client_detail'),
    path('api/nutrizione/alimenti/', views_nutrition.api_food_search, name='nutrizione_food_search'),
    path('api/nutrizione/piani/<int:plan_id>/assegna/', views_nutrition.api_piano_assign, name='nutrizione_piano_assign'),
    path('api/nutrizione/piani/<int:plan_id>/elimina/', views_nutrition.nutrizione_piano_delete_view, name='nutrizione_piano_delete'),
    path('nutrizione/anamnesi/', TemplateView.as_view(template_name='pages/nutrizione/anamnesi_create.html'), name='nutrizione_anamnesi'),
    path('nutrizione/integratori/', TemplateView.as_view(template_name='pages/nutrizione/integratori_list.html'), name='nutrizione_integratori'),
    
    # Allenamenti
    path('allenamenti/', views_workouts.allenamenti_list_view, name='allenamenti_list'),
    path('allenamenti/crea/', views_workouts.allenamenti_create_view, name='allenamenti_create'),
    path('allenamenti/<int:assignment_id>/modifica/', views_workouts.allenamenti_edit_view, name='allenamenti_edit'),
    path('api/clients/search/', views_workouts.api_search_clients, name='api_search_clients'),
    path('api/exercises/search/', views_workouts.api_search_exercises, name='api_search_exercises'),
    path('allenamenti/dettaglio/', TemplateView.as_view(template_name='pages/allenamenti/detail.html'), name='allenamenti_detail'),
    
    # Agenda
    path('agenda/', views_agenda.agenda_dashboard_view, name='agenda_dashboard'),
    path('api/agenda/events/', views_agenda.api_agenda_events, name='api_agenda_events'),
    path('agenda/lista/', TemplateView.as_view(template_name='pages/agenda/list.html'), name='agenda_list'),
    path('agenda/dettaglio/', TemplateView.as_view(template_name='pages/agenda/detail.html'), name='agenda_detail'),
    
    # Abbonamenti
    path('abbonamenti/', views_client.abbonamenti_dashboard_view, name='abbonamenti_dashboard'),
    path('abbonamenti/dettaglio/', TemplateView.as_view(template_name='pages/abbonamenti/detail.html'), name='abbonamenti_detail'),
    path('abbonamenti/checkout/', TemplateView.as_view(template_name='pages/abbonamenti/checkout.html'), name='abbonamenti_checkout'),
    path('abbonamenti/checkout/success/', TemplateView.as_view(template_name='pages/abbonamenti/checkout_success.html'), name='abbonamenti_checkout_success'),
    path('abbonamenti/piano/crea/', views_client.subscription_plan_create_view, name='subscription_plan_create'),
    path('abbonamenti/piano/<int:plan_id>/modifica/', views_client.subscription_plan_edit_view, name='subscription_plan_edit'),
    path('api/abbonamenti/piano/<int:plan_id>/elimina/', views_client.subscription_plan_delete_view, name='subscription_plan_delete'),
    path('api/abbonamenti/piano/<int:plan_id>/assegna/', views_client.assign_plan_to_client_view, name='subscription_plan_assign'),
    path('abbonamenti/piano/<int:plan_id>/clienti/', views_client.subscription_plan_detail_view, name='subscription_plan_detail'),
    
    # Check Progressi
    path('check/', views_check.check_dashboard_view, name='check_dashboard'),
    path('check/crea/', views_check.check_create_view, name='check_create'),
    path('check/trova-coach/', views_client.find_coach_list_view, name='check_coach_directory'),
    path('check/cliente/<int:client_id>/', views_check.client_check_history_view, name='check_client_history'),
    path('check/<int:response_id>/', views_check.check_detail_view, name='check_detail'),
    path('api/check/trova-coach/', views_client.find_coach_api, name='check_coach_api'),
    path('api/check/cerca-cliente/', views_check.api_check_search, name='check_search_api'),
    path('api/check/pianifica/', views_check.api_check_schedule, name='check_schedule_api'),
    path('api/check/<int:response_id>/revisiona/', views_check.api_check_review, name='check_review_api'),
    path('check/trova-coach/<int:coach_id>/', views_client.coach_detail_view, name='check_coach_detail'),
    path('check/trova-coach/<int:coach_id>/connetti/', views_client.connect_coach_view, name='check_connect_coach'),
    
    # Impostazioni
    path('impostazioni/', views_settings.impostazioni_view, name='impostazioni_dashboard'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
