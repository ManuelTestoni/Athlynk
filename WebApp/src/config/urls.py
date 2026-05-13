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
from . import views_anamnesi
from . import views_chat
from . import views_notifications
from . import views_session
from . import views_progression
from . import views_search
from . import views_newsletter
from . import views_legal
from . import views_consent

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Auth
    path('login/', views_auth.login_view, name='login'),
    path('registrati/', views_auth.signup_view, name='signup'),
    path('logout/', views_auth.logout_view, name='logout'),
    path('verify/<str:token>/', views_auth.verify_email_view, name='verify_email'),
    path('verify/reinvia/', views_auth.resend_verification_view, name='resend_verification'),

    # Legal
    path('privacy/', views_legal.privacy_view, name='privacy'),
    path('cookie/', views_legal.cookie_view, name='cookie_policy'),
    path('cookie/preferenze/', views_legal.cookie_preferences_view, name='cookie_preferences'),
    path('api/consent/', views_consent.consent_api, name='api_consent'),

    # Newsletter
    path('newsletter/conferma/<str:token>/', views_newsletter.confirm_subscription, name='newsletter_confirm'),
    path('newsletter/disiscriviti/<str:token>/', views_newsletter.unsubscribe, name='newsletter_unsubscribe'),
    path('api/newsletter/toggle/', views_newsletter.toggle_subscription, name='newsletter_toggle'),
    
    path('', views.dashboard_view, name='dashboard'),

    # Clienti (coach)
    path('clienti/', views_client.coach_clients_list_view, name='clienti_list'),
    path('clienti/registra/', views_client.registra_client_view, name='clienti_registra'),
    path('clienti/<int:client_id>/', views_client.coach_client_detail_view, name='clienti_detail'),

    # Il mio specialista (client)
    path('il-mio-coach/', views_client.client_my_coach_view, name='client_my_coach'),
    path('il-mio-specialista/<int:rel_id>/', views_client.client_specialist_detail_view, name='client_specialist_detail'),
    path('il-mio-specialista/<int:rel_id>/lascia/', views_client.client_disconnect_coach_view, name='client_disconnect_coach'),

    # Nutrizione
    path('nutrizione/piani/', views_nutrition.nutrizione_piani_view, name='nutrizione_piani'),
    path('nutrizione/piani/crea/', views_nutrition.nutrizione_piano_create_view, name='nutrizione_piano_create'),
    path('nutrizione/piani/<int:plan_id>/', views_nutrition.nutrizione_piano_detail_view, name='nutrizione_piano_detail'),
    path('nutrizione/piani/<int:plan_id>/modifica/', views_nutrition.nutrizione_piano_edit_view, name='nutrizione_piano_edit'),
    path('nutrizione/dettaglio/<int:assignment_id>/', views_nutrition.nutrizione_client_detail_view, name='nutrizione_client_detail'),
    path('api/nutrizione/alimenti/', views_nutrition.api_food_search, name='nutrizione_food_search'),
    path('api/nutrizione/piani/<int:plan_id>/assegna/', views_nutrition.api_piano_assign, name='nutrizione_piano_assign'),
    path('api/nutrizione/piani/<int:plan_id>/elimina/', views_nutrition.nutrizione_piano_delete_view, name='nutrizione_piano_delete'),
    path('nutrizione/anamnesi/', views_anamnesi.anamnesi_view, name='nutrizione_anamnesi'),
    path('nutrizione/anamnesi/crea/<int:client_id>/', views_anamnesi.anamnesi_create_view, name='nutrizione_anamnesi_crea'),
    path('nutrizione/anamnesi/<int:anamnesis_id>/', views_anamnesi.anamnesi_detail_view, name='nutrizione_anamnesi_detail'),
    path('nutrizione/integratori/', views_nutrition.integratori_view, name='nutrizione_integratori'),
    path('nutrizione/integratori/crea/', views_nutrition.integratori_create_view, name='nutrizione_integratori_crea'),
    path('nutrizione/integratori/<int:sheet_id>/', views_nutrition.integratori_detail_view, name='nutrizione_integratori_detail'),
    path('nutrizione/integratori/<int:sheet_id>/modifica/', views_nutrition.integratori_edit_view, name='nutrizione_integratori_edit'),
    path('api/nutrizione/integratori/', views_nutrition.api_supplement_search, name='nutrizione_supplement_search'),
    path('api/nutrizione/integratori/schede/<int:sheet_id>/assegna/', views_nutrition.api_sheet_assign, name='nutrizione_sheet_assign'),
    path('api/nutrizione/integratori/schede/<int:sheet_id>/elimina/', views_nutrition.api_sheet_delete, name='nutrizione_sheet_delete'),
    
    # Allenamenti
    path('allenamenti/', views_workouts.allenamenti_list_view, name='allenamenti_list'),
    path('allenamenti/wizard/', views_workouts.allenamenti_wizard_view, name='allenamenti_wizard'),
    path('allenamenti/wizard/<int:plan_id>/', views_workouts.allenamenti_wizard_view, name='allenamenti_wizard_resume'),
    path('allenamenti/assegnazione/<int:assignment_id>/dettagli/', views_session.client_assignment_detail_view, name='client_assignment_detail'),
    path('allenamenti/assegnazione/<int:assignment_id>/volume/', views_session.client_assignment_volume_view, name='client_assignment_volume'),
    path('allenamenti/assegnazione/<int:assignment_id>/sessione/<int:day_id>/', views_session.client_session_active_view, name='client_session_active'),
    path('api/allenamenti/assegnazione/<int:assignment_id>/sessioni/', views_session.api_assignment_sessions_list, name='api_assignment_sessions_list'),
    path('clienti/<int:client_id>/progressi/', views_session.coach_client_progressi_view, name='coach_client_progressi'),
    path('allenamenti/<int:plan_id>/', views_workouts.allenamenti_plan_detail_view, name='allenamenti_plan_detail'),
    # Session APIs
    path('api/sessioni/avvia/', views_session.api_session_start, name='api_session_start'),
    path('api/sessioni/<int:session_id>/serie/', views_session.api_session_log_set, name='api_session_log_set'),
    path('api/sessioni/<int:session_id>/concludi/', views_session.api_session_finish, name='api_session_finish'),
    path('api/sessioni/<int:session_id>/media/', views_session.api_session_upload_media, name='api_session_upload_media'),
    path('api/sessioni/<int:session_id>/dettaglio/', views_session.api_session_detail, name='api_session_detail'),
    path('api/sessioni/<int:session_id>/nota-coach/', views_session.api_session_coach_note, name='api_session_coach_note'),
    path('api/media/<int:media_id>/commento/', views_session.api_media_comment, name='api_media_comment'),
    # Coach progress APIs
    path('api/coach/clienti/<int:client_id>/progressi/kpi/', views_session.api_progress_kpi, name='api_progress_kpi'),
    path('api/coach/clienti/<int:client_id>/progressi/carichi/', views_session.api_progress_loads, name='api_progress_loads'),
    path('api/coach/clienti/<int:client_id>/progressi/volume/', views_session.api_progress_volume, name='api_progress_volume'),
    path('api/coach/clienti/<int:client_id>/progressi/aderenza/', views_session.api_progress_adherence, name='api_progress_adherence'),
    path('api/coach/clienti/<int:client_id>/progressi/rpe/', views_session.api_progress_rpe, name='api_progress_rpe'),
    path('api/coach/clienti/<int:client_id>/progressi/sessioni/', views_session.api_progress_sessions, name='api_progress_sessions'),
    path('api/coach/clienti/<int:client_id>/progressi/media/', views_session.api_progress_media_gallery, name='api_progress_media'),
    path('api/allenamenti/save/', views_workouts.api_plan_save, name='api_plan_save_new'),
    path('api/allenamenti/<int:plan_id>/save/', views_workouts.api_plan_save, name='api_plan_save'),
    path('api/allenamenti/<int:plan_id>/finalize/', views_workouts.api_plan_finalize, name='api_plan_finalize'),
    path('api/allenamenti/<int:plan_id>/elimina/', views_workouts.api_plan_delete, name='api_plan_delete'),
    path('api/allenamenti/<int:plan_id>/progression/preview/', views_progression.api_progression_preview, name='api_progression_preview'),
    path('api/allenamenti/<int:plan_id>/progression/week/<int:week_number>/special/', views_progression.api_progression_special_week, name='api_progression_special_week'),
    path('api/clients/search/', views_workouts.api_search_clients, name='api_search_clients'),
    path('api/exercises/search/', views_workouts.api_search_exercises, name='api_search_exercises'),
    path('api/exercises/filters/', views_workouts.api_exercise_filters, name='api_exercise_filters'),
    # Legacy
    path('allenamenti/crea/', views_workouts.allenamenti_create_view, name='allenamenti_create'),
    path('allenamenti/legacy/<int:assignment_id>/modifica/', views_workouts.allenamenti_edit_view, name='allenamenti_edit'),
    path('allenamenti/dettaglio/', TemplateView.as_view(template_name='pages/allenamenti/detail.html'), name='allenamenti_detail'),
    
    # Agenda
    path('agenda/', views_agenda.agenda_dashboard_view, name='agenda_dashboard'),
    path('api/agenda/events/', views_agenda.api_agenda_events, name='api_agenda_events'),
    
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
    path('check/andamento/', views_check.check_progress_charts_view, name='check_progress_charts'),
    path('check/andamento/<int:client_id>/', views_check.check_progress_charts_view, name='check_progress_charts_client'),
    path('check/comparatore/', views_check.check_comparator_view, name='check_comparator'),
    path('check/comparatore/<int:client_id>/', views_check.check_comparator_view, name='check_comparator_client'),
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

    # Chat
    path('chat/', views_chat.chat_list_view, name='chat_list'),
    path('chat/<int:conversation_id>/', views_chat.chat_detail_view, name='chat_detail'),
    path('api/chat/<int:conversation_id>/send/', views_chat.api_send_message, name='chat_send'),
    path('api/chat/<int:conversation_id>/read/', views_chat.api_mark_read, name='chat_mark_read'),
    path('api/chat/<int:conversation_id>/messages/', views_chat.api_messages_since, name='chat_messages_since'),
    path('api/chat/<int:conversation_id>/messages/older/', views_chat.api_messages_before, name='chat_messages_before'),
    path('api/chat/<int:conversation_id>/appointment/', views_chat.api_appointment_request, name='chat_appointment_request'),
    path('api/chat/<int:conversation_id>/appointment/<int:appointment_id>/respond/', views_chat.api_appointment_respond, name='chat_appointment_respond'),

    # Global search
    path('api/search/', views_search.search_api, name='api_search'),

    # Notifications
    path('api/notifications/', views_notifications.api_notifications_list, name='notifications_list'),
    path('api/notifications/unread-count/', views_notifications.api_notifications_unread_count, name='notifications_unread_count'),
    path('api/notifications/<int:notification_id>/read/', views_notifications.api_notification_mark_read, name='notification_mark_read'),
    path('api/notifications/read-all/', views_notifications.api_notifications_mark_all_read, name='notifications_mark_all_read'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
