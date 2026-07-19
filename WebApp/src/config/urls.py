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
from django.views.generic import TemplateView, RedirectView
from . import views
from . import views_errors

handler400 = 'config.views_errors.bad_request'
handler403 = 'config.views_errors.forbidden'
handler404 = 'config.views_errors.not_found'
handler500 = 'config.views_errors.server_error'
from . import views_workouts
from . import views_workouts_taxonomy
from . import views_agenda
from . import views_check
from . import views_check_taxonomy
from . import views_auth
from . import views_client
from . import views_settings
from . import views_nutrition
from . import views_nutrition_taxonomy
from . import views_chat
from . import views_notifications
from . import views_session
from . import views_progression
from . import views_search
from . import views_newsletter
from . import views_legal
from . import views_consent
from . import views_seo
from . import views_chiron
from . import views_payments
from . import views_connect
from . import views_checkout
from . import api as mobile_api
from . import api_coach as coach_api
from .api import coach_dual_auth

urlpatterns = [
    path('admin/', admin.site.urls),
    path('healthz/', views.healthz_view, name='healthz'),

    # Auth
    path('login/', views_auth.login_view, name='login'),
    path('registrati/', views_auth.signup_view, name='signup'),
    path('logout/', views_auth.logout_view, name='logout'),
    # 'reinvia' must precede the <token> catch-all, otherwise it is captured as a token.
    path('verify/reinvia/', views_auth.resend_verification_view, name='resend_verification'),
    path('verify/<str:token>/', views_auth.verify_email_view, name='verify_email'),
    path('password-dimenticata/', views_auth.forgot_password_view, name='forgot_password'),
    path('reset-password/', views_auth.reset_password_view, name='reset_password'),
    path('attiva-account/', views_auth.activate_account_view, name='activate_account'),
    path('impostazioni/richiedi-reset/', views_auth.request_password_reset_view, name='request_password_reset'),

    # Legal
    path('privacy/', views_legal.privacy_view, name='privacy'),
    path('cookie/', views_legal.cookie_view, name='cookie_policy'),
    path('cookie/preferenze/', views_legal.cookie_preferences_view, name='cookie_preferences'),
    path('ai-trasparenza/', views_legal.ai_transparency_view, name='ai_transparency'),
    path('termini-di-servizio/', views_legal.tos_view, name='tos'),
    path('termini-duso/', views_legal.terms_use_view, name='terms_use'),
    path('api/consent/', views_consent.consent_api, name='api_consent'),

    # SEO / AI discoverability
    path('robots.txt', views_seo.robots_txt, name='robots_txt'),
    path('sitemap.xml', views_seo.sitemap_xml, name='sitemap_xml'),
    path('llms.txt', views_seo.llms_txt, name='llms_txt'),
    path('favicon.ico', RedirectView.as_view(url=settings.STATIC_URL + 'img/favicon.png', permanent=True), name='favicon'),

    # Newsletter
    path('newsletter/conferma/<str:token>/', views_newsletter.confirm_subscription, name='newsletter_confirm'),
    path('newsletter/disiscriviti/<str:token>/', views_newsletter.unsubscribe, name='newsletter_unsubscribe'),
    path('api/newsletter/toggle/', views_newsletter.toggle_subscription, name='newsletter_toggle'),

    # Pagamenti piattaforma (coach -> Athlynk) — avviati dal sito marketing
    path('acquista/checkout/', views_payments.checkout_page, name='platform_checkout_start'),
    path('acquista/esito/', views_payments.checkout_return, name='platform_checkout_return'),
    path('webhooks/stripe/', views_payments.stripe_webhook, name='stripe_webhook'),

    path('', views.dashboard_view, name='dashboard'),
    path('dashboard/layout', views.dashboard_layout_api, name='dashboard_layout'),
    path('dashboard/widget/<slug:widget_type>', views.dashboard_widget_html, name='dashboard_widget_html'),
    path('dashboard/pinned-athletes', views.pinned_athletes_web, name='dashboard_pinned_athletes'),
    path('analisi/', views.coach_analytics_view, name='analytics_business_page'),

    # Clienti (coach)
    path('clienti/', views_client.coach_clients_list_view, name='clienti_list'),
    path('clienti/registra/', views_client.registra_client_view, name='clienti_registra'),
    path('clienti/<int:client_id>/', views_client.coach_client_detail_view, name='clienti_detail'),
    path('clienti/<int:client_id>/termina/', views_client.coach_end_relationship_view, name='clienti_termina'),

    # Accesso sospeso (atleta senza professionista attivo / abbonamento scaduto)
    path('accesso-sospeso/', views_client.client_blocked_view, name='client_blocked'),

    # Abbonamento scaduto (coach/allenatore/nutrizionista senza piattaforma attiva)
    path('abbonamento-scaduto/', views_auth.coach_subscription_lapsed_view, name='coach_subscription_lapsed'),

    # Nutrizione
    path('nutrizione/piani/', views_nutrition.nutrizione_piani_view, name='nutrizione_piani'),
    path('nutrizione/piani/importa/', views_nutrition.nutrizione_import_view, name='nutrizione_import'),
    path('nutrizione/piani/importa-pdf/', views_nutrition.nutrizione_import_pdf_view, name='nutrizione_import_pdf'),
    path('nutrizione/piani/crea/', coach_dual_auth(views_nutrition.nutrizione_piano_create_view), name='nutrizione_piano_create'),
    path('nutrizione/piani/<int:plan_id>/', views_nutrition.nutrizione_piano_detail_view, name='nutrizione_piano_detail'),
    path('nutrizione/piani/<int:plan_id>/modifica/', coach_dual_auth(views_nutrition.nutrizione_piano_edit_view), name='nutrizione_piano_edit'),
    path('nutrizione/dettaglio/<int:assignment_id>/', views_nutrition.nutrizione_client_detail_view, name='nutrizione_client_detail'),
    path('clienti/<int:client_id>/nutrizione/dettaglio/<int:assignment_id>/', views_nutrition.coach_client_nutrition_detail_view, name='coach_client_nutrition_detail'),
    path('api/nutrizione/dettaglio/<int:assignment_id>/log/', views_nutrition.api_macro_log_create, name='api_macro_log_create'),
    path('api/nutrizione/dettaglio/<int:assignment_id>/storico/', views_nutrition.api_macro_log_history, name='api_macro_log_history'),
    path('api/coach/nutrizione/dettaglio/<int:assignment_id>/storico/', views_nutrition.api_coach_macro_log_history, name='api_coach_macro_log_history'),
    path('nutrizione/dettaglio/<int:assignment_id>/log/<str:date_str>/', views_nutrition.macro_log_day_view, name='macro_log_day'),
    path('api/nutrizione/log/<int:entry_id>/', views_nutrition.api_macro_log_detail, name='api_macro_log_detail'),
    path('api/nutrizione/cliente/storico/', views_nutrition.api_client_nutrition_history, name='api_client_nutrition_history'),
    path('api/nutrizione/alimenti/', views_nutrition.api_food_search, name='nutrizione_food_search'),
    path('api/nutrizione/import/excel/', coach_dual_auth(views_nutrition.api_diet_import_excel), name='api_diet_import_excel'),
    path('api/nutrizione/import/pdf/', coach_dual_auth(views_nutrition.api_diet_import_pdf), name='api_diet_import_pdf'),
    path('api/nutrizione/import/pdf/status/', views_nutrition.api_diet_import_pdf_status, name='api_diet_import_pdf_status'),
    path('api/nutrizione/import/conferma/', coach_dual_auth(views_nutrition.api_diet_import_confirm), name='api_diet_import_confirm'),
    path('api/nutrizione/piani/<int:plan_id>/assegna/', coach_dual_auth(views_nutrition.api_piano_assign), name='nutrizione_piano_assign'),
    path('api/nutrizione/piani/<int:plan_id>/elimina/', coach_dual_auth(views_nutrition.nutrizione_piano_delete_view), name='nutrizione_piano_delete'),
    path('api/nutrizione/piani/<int:plan_id>/duplica/', coach_dual_auth(views_nutrition.nutrizione_piano_duplicate_view), name='nutrizione_piano_duplicate'),
    path('api/nutrizione/cartelle/', coach_dual_auth(views_nutrition_taxonomy.api_nutrition_folders), name='api_nutrition_folders'),
    path('api/nutrizione/cartelle/riordina/', coach_dual_auth(views_nutrition_taxonomy.api_nutrition_folders_reorder), name='api_nutrition_folders_reorder'),
    path('api/nutrizione/cartelle/<int:folder_id>/', coach_dual_auth(views_nutrition_taxonomy.api_nutrition_folder_detail), name='api_nutrition_folder_detail'),
    path('api/nutrizione/piani/<int:plan_id>/cartella/', coach_dual_auth(views_nutrition_taxonomy.api_nutrition_plan_folder), name='api_nutrition_plan_folder'),
    # Wizard CRUD endpoints (Sezione 9.3)
    path('api/nutrizione/piani/<int:plan_id>/', views_nutrition.api_plan_patch, name='api_plan_patch'),
    path('api/nutrizione/piani/<int:plan_id>/pasti/', views_nutrition.api_plan_meal_create, name='api_plan_meal_create'),
    path('api/nutrizione/pasti/<int:meal_id>/', views_nutrition.api_meal_detail, name='api_meal_detail'),
    path('api/nutrizione/pasti/<int:meal_id>/alimenti/', views_nutrition.api_meal_item_create, name='api_meal_item_create'),
    path('api/nutrizione/alimenti-pasto/<int:item_id>/', views_nutrition.api_meal_item_detail, name='api_meal_item_detail'),
    path('api/nutrizione/piani/<int:plan_id>/giorni/<str:dest_day>/copia-da/<str:src_day>/', views_nutrition.api_plan_copy_day, name='api_plan_copy_day'),
    path('api/nutrizione/piani/<int:plan_id>/integratori/', views_nutrition.api_plan_supplements, name='api_plan_supplements'),
    path('api/nutrizione/piani/<int:plan_id>/assegnazioni/', views_nutrition.api_nutrition_plan_assignments_list, name='api_nutrition_plan_assignments_list'),
    path('api/nutrizione/integratori-assegnati/<int:assignment_id>/items/', views_nutrition.api_supplement_protocol_items, name='api_supplement_protocol_items'),
    path('nutrizione/integratori/', views_nutrition.integratori_view, name='nutrizione_integratori'),
    path('nutrizione/integratori/crea/', views_nutrition.integratori_create_view, name='nutrizione_integratori_crea'),
    path('nutrizione/integratori/<int:sheet_id>/', views_nutrition.integratori_detail_view, name='nutrizione_integratori_detail'),
    path('nutrizione/integratori/<int:sheet_id>/modifica/', views_nutrition.integratori_edit_view, name='nutrizione_integratori_edit'),
    path('api/nutrizione/integratori/schede/lista/', views_nutrition.api_supplement_protocols_list, name='nutrizione_supplement_protocols_list'),
    path('api/nutrizione/integratori/schede/<int:sheet_id>/assegna/', views_nutrition.api_sheet_assign, name='nutrizione_sheet_assign'),
    path('api/nutrizione/integratori/schede/<int:sheet_id>/elimina/', views_nutrition.api_sheet_delete, name='nutrizione_sheet_delete'),
    
    # Allenamenti
    path('allenamenti/', views_workouts.allenamenti_list_view, name='allenamenti_list'),
    path('allenamenti/importa/', views_workouts.allenamenti_import_view, name='allenamenti_import'),
    path('allenamenti/importa-pdf/', views_workouts.allenamenti_import_pdf_view, name='allenamenti_import_pdf'),
    path('api/allenamenti/import/excel/', coach_dual_auth(views_workouts.api_workout_import_excel), name='api_workout_import_excel'),
    path('api/allenamenti/import/pdf/', coach_dual_auth(views_workouts.api_workout_import_pdf), name='api_workout_import_pdf'),
    path('api/allenamenti/import/pdf/status/', views_workouts.api_workout_import_pdf_status, name='api_workout_import_pdf_status'),
    path('api/allenamenti/import/conferma/', coach_dual_auth(views_workouts.api_workout_import_confirm), name='api_workout_import_confirm'),
    path('allenamenti/wizard/', views_workouts.allenamenti_wizard_view, name='allenamenti_wizard'),
    path('allenamenti/wizard/<int:plan_id>/', views_workouts.allenamenti_wizard_view, name='allenamenti_wizard_resume'),
    path('allenamenti/assegnazione/<int:assignment_id>/dettagli/', views_session.client_assignment_detail_view, name='client_assignment_detail'),
    path('allenamenti/assegnazione/<int:assignment_id>/sessione/<int:day_id>/', views_session.client_session_active_view, name='client_session_active'),
    path('api/allenamenti/assegnazione/<int:assignment_id>/sessioni/', views_session.api_assignment_sessions_list, name='api_assignment_sessions_list'),
    path('api/allenamenti/esercizio/<int:workout_exercise_id>/andamento/', views_session.api_client_exercise_trend, name='api_client_exercise_trend'),
    path('api/allenamenti/cliente/storico/', views_workouts.api_client_workout_history, name='api_client_workout_history'),
    path('clienti/<int:client_id>/progressi/', views_session.coach_client_progressi_view, name='coach_client_progressi'),
    path('clienti/<int:client_id>/storico-allenamenti/', views_workouts.coach_client_workout_history_view, name='coach_client_workout_history'),
    path('clienti/<int:client_id>/storico-diete/', views_nutrition.coach_client_nutrition_history_view, name='coach_client_nutrition_history'),
    path('allenamenti/<int:plan_id>/', views_workouts.allenamenti_plan_detail_view, name='allenamenti_plan_detail'),
    path('api/allenamenti/<int:plan_id>/assegnazioni/', views_workouts.api_plan_assignments_list, name='api_plan_assignments_list'),
    # Session APIs
    path('api/allenamenti/esercizi/ricerca/', views_session.api_client_exercise_search, name='api_client_exercise_search'),
    path('api/allenamenti/esercizi/storico/', views_session.api_client_progress_exercises, name='api_client_progress_exercises'),
    path('api/allenamenti/esercizi/andamento-per-nome/', views_session.api_client_trend_by_name, name='api_client_trend_by_name'),
    path('api/sessioni/<int:session_id>/modifiche/', views_session.api_session_overrides, name='api_session_overrides'),
    path('api/sessioni/avvia/', views_session.api_session_start, name='api_session_start'),
    path('api/sessioni/<int:session_id>/serie/', views_session.api_session_log_set, name='api_session_log_set'),
    path('api/sessioni/<int:session_id>/concludi/', views_session.api_session_finish, name='api_session_finish'),
    path('api/sessioni/<int:session_id>/media/', views_session.api_session_upload_media, name='api_session_upload_media'),
    path('api/sessioni/<int:session_id>/dettaglio/', views_session.api_session_detail, name='api_session_detail'),
    path('api/sessioni/<int:session_id>/nota-coach/', views_session.api_session_coach_note, name='api_session_coach_note'),
    path('api/media/<int:media_id>/commento/', views_session.api_media_comment, name='api_media_comment'),
    # Percorso (journey timeline)
    path('il-mio-percorso/', views_client.il_mio_percorso_view, name='il_mio_percorso'),
    path('api/coach/clienti/<int:client_id>/percorso/', views_client.api_coach_client_percorso, name='api_coach_percorso'),
    path('api/coach/clienti/<int:client_id>/attivita/', views_client.api_coach_client_activity_feed, name='api_coach_client_activity_feed'),
    path('api/coach/clienti/<int:client_id>/percorso/fasi/', views_client.api_coach_phase_create, name='api_coach_phase_create'),
    path('api/coach/clienti/<int:client_id>/percorso/fasi/<int:phase_id>/', views_client.api_coach_phase_delete, name='api_coach_phase_delete'),
    path('api/cliente/percorso/', views_client.api_client_my_percorso, name='api_client_percorso'),
    path('api/cliente/misurazione/', views_client.api_client_measurement_create, name='api_client_measurement'),
    path('api/coach/clienti/<int:client_id>/misurazione/', views_client.api_coach_measurement_create, name='api_coach_measurement'),
    path('api/coach/etichette/', views_client.api_coach_labels, name='api_coach_labels'),
    path('api/coach/etichette/<int:label_id>/', views_client.api_coach_label_delete, name='api_coach_label_delete'),
    path('api/coach/clienti/<int:client_id>/etichette/', views_client.api_coach_client_label_assign, name='api_coach_client_label_assign'),
    path('api/coach/clienti/<int:client_id>/etichette/<int:label_id>/', views_client.api_coach_client_label_remove, name='api_coach_client_label_remove'),

    # Coach progress APIs
    path('api/coach/clienti/<int:client_id>/progressi/kpi/', views_session.api_progress_kpi, name='api_progress_kpi'),
    path('api/coach/clienti/<int:client_id>/progressi/carichi/', views_session.api_progress_loads, name='api_progress_loads'),
    path('api/coach/clienti/<int:client_id>/progressi/volume/', views_session.api_progress_volume, name='api_progress_volume'),
    path('api/coach/clienti/<int:client_id>/progressi/aderenza/', views_session.api_progress_adherence, name='api_progress_adherence'),
    path('api/coach/clienti/<int:client_id>/progressi/rpe/', views_session.api_progress_rpe, name='api_progress_rpe'),
    path('api/coach/clienti/<int:client_id>/progressi/sessioni/', views_session.api_progress_sessions, name='api_progress_sessions'),
    path('api/coach/clienti/<int:client_id>/progressi/media/', views_session.api_progress_media_gallery, name='api_progress_media'),

    # Athlete self-service progress APIs (dashboard widget)
    path('api/mie/progressi/carichi/', views_session.api_my_progress_loads, name='api_my_progress_loads'),
    path('api/mie/progressi/volume/', views_session.api_my_progress_volume, name='api_my_progress_volume'),

    path('api/allenamenti/save/', coach_dual_auth(views_workouts.api_plan_save), name='api_plan_save_new'),
    path('api/allenamenti/<int:plan_id>/save/', coach_dual_auth(views_workouts.api_plan_save), name='api_plan_save'),
    path('api/allenamenti/<int:plan_id>/finalize/', coach_dual_auth(views_workouts.api_plan_finalize), name='api_plan_finalize'),
    path('api/allenamenti/<int:plan_id>/elimina/', coach_dual_auth(views_workouts.api_plan_delete), name='api_plan_delete'),
    path('api/allenamenti/<int:plan_id>/duplica/', coach_dual_auth(views_workouts.api_plan_duplicate), name='api_plan_duplicate'),
    path('api/allenamenti/<int:plan_id>/progression/preview/', views_progression.api_progression_preview, name='api_progression_preview'),
    path('api/allenamenti/<int:plan_id>/progression/week/<int:week_number>/special/', views_progression.api_progression_special_week, name='api_progression_special_week'),
    path('api/allenamenti/<int:plan_id>/progression/day/<int:day_id>/grid/', coach_dual_auth(views_progression.api_progression_day_grid), name='api_progression_day_grid'),
    path('api/allenamenti/<int:plan_id>/progression/cell/', coach_dual_auth(views_progression.api_progression_cell), name='api_progression_cell'),
    path('api/allenamenti/<int:plan_id>/progression/add-exercise/', views_progression.api_progression_add_exercise, name='api_progression_add_exercise'),
    path('api/allenamenti/<int:plan_id>/progression/exercise/<int:exercise_id>/delete-cell/', views_progression.api_progression_delete_cell, name='api_progression_delete_cell'),
    path('api/clients/search/', views_workouts.api_search_clients, name='api_search_clients'),
    path('api/exercises/search/', views_workouts.api_search_exercises, name='api_search_exercises'),
    path('api/exercises/filters/', views_workouts.api_exercise_filters, name='api_exercise_filters'),

    # Workouts redesign — Iterazione 1 foundation APIs
    path('api/allenamenti/cartelle/', coach_dual_auth(views_workouts_taxonomy.api_folders), name='api_workout_folders'),
    path('api/allenamenti/cartelle/riordina/', coach_dual_auth(views_workouts_taxonomy.api_folders_reorder), name='api_workout_folders_reorder'),
    path('api/allenamenti/cartelle/<int:folder_id>/', coach_dual_auth(views_workouts_taxonomy.api_folder_detail), name='api_workout_folder_detail'),
    path('api/allenamenti/piani/<int:plan_id>/cartella/', coach_dual_auth(views_workouts_taxonomy.api_workout_plan_folder), name='api_workout_plan_folder'),
    path('api/muscle-groups/', views_workouts_taxonomy.api_muscle_groups, name='api_muscle_groups'),
    path('api/exercises/custom/', views_workouts_taxonomy.api_custom_exercises, name='api_custom_exercises'),
    path('api/exercises/custom/<int:exercise_id>/', views_workouts_taxonomy.api_custom_exercise_detail, name='api_custom_exercise_detail'),
    path('api/exercises/<int:exercise_id>/', views_workouts_taxonomy.api_exercise_detail, name='api_exercise_detail'),
    path('api/allenamenti/<int:plan_id>/volume/', views_workouts_taxonomy.api_plan_volume, name='api_plan_volume'),
    # Legacy
    path('allenamenti/crea/', views_workouts.allenamenti_create_view, name='allenamenti_create'),
    path('allenamenti/legacy/<int:assignment_id>/modifica/', views_workouts.allenamenti_edit_view, name='allenamenti_edit'),
    path('allenamenti/dettaglio/', TemplateView.as_view(template_name='pages/allenamenti/detail.html'), name='allenamenti_detail'),
    
    # Agenda
    path('agenda/', views_agenda.agenda_dashboard_view, name='agenda_dashboard'),
    path('api/agenda/events/', views_agenda.api_agenda_events, name='api_agenda_events'),
    path('api/agenda/events/<int:event_id>/', views_agenda.api_agenda_event_detail, name='api_agenda_event_detail'),
    
    # Abbonamenti
    path('abbonamenti/', views_client.abbonamenti_dashboard_view, name='abbonamenti_dashboard'),
    path('abbonamenti/disdici/', views_client.athlete_cancel_subscription_view, name='athlete_cancel_subscription'),
    path('abbonamenti/acquista/<int:plan_id>/', views_checkout.athlete_checkout_start_view, name='athlete_checkout_start'),
    path('abbonamenti/acquista/pacchetto/<int:bundle_id>/', views_checkout.athlete_checkout_bundle_start_view, name='athlete_checkout_bundle_start'),
    path('abbonamenti/checkout/success/', views_checkout.athlete_checkout_success_view, name='abbonamenti_checkout_success'),
    path('abbonamenti/checkout/annullato/', views_checkout.athlete_checkout_cancel_view, name='abbonamenti_checkout_cancel'),
    path('abbonamenti/piano/crea/', views_client.subscription_plan_create_view, name='subscription_plan_create'),
    path('abbonamenti/piano/<int:plan_id>/modifica/', views_client.subscription_plan_edit_view, name='subscription_plan_edit'),
    path('api/abbonamenti/piano/<int:plan_id>/elimina/', views_client.subscription_plan_delete_view, name='subscription_plan_delete'),
    path('api/abbonamenti/piano/<int:plan_id>/assegna/', views_client.assign_plan_to_client_view, name='subscription_plan_assign'),
    path('api/abbonamenti/iscrizioni/<int:subscription_id>/pagato/', views_client.api_subscription_mark_paid, name='subscription_mark_paid'),
    path('abbonamenti/piano/<int:plan_id>/clienti/', views_client.subscription_plan_detail_view, name='subscription_plan_detail'),
    path('abbonamenti/pacchetti/', views_client.bundle_list_view, name='bundle_list'),
    path('abbonamenti/pacchetti/crea/', views_client.bundle_create_view, name='bundle_create'),
    path('abbonamenti/pacchetti/<int:bundle_id>/modifica/', views_client.bundle_edit_view, name='bundle_edit'),
    path('api/abbonamenti/pacchetti/<int:bundle_id>/elimina/', views_client.bundle_delete_view, name='bundle_delete'),
    path('abbonamenti/connetti/', views_connect.connect_onboarding_start_view, name='connect_onboarding_start'),
    path('abbonamenti/connetti/ritorno/', views_connect.connect_onboarding_return_view, name='connect_onboarding_return'),
    path('abbonamenti/connetti/refresh/', views_connect.connect_onboarding_refresh_view, name='connect_onboarding_refresh'),
    path('webhooks/stripe/connect/', views_connect.stripe_connect_webhook, name='stripe_connect_webhook'),

    # Check Progressi
    path('check/', views_check.check_dashboard_view, name='check_dashboard'),
    path('check/crea/', views_check.check_create_view, name='check_create'),
    path('check/modelli/', views_check.check_templates_list_view, name='check_templates_list'),
    path('check/modelli/nuovo/', views_check.check_template_new_view, name='check_template_new'),
    path('check/modelli/<int:template_id>/', views_check.check_template_edit_view, name='check_template_edit'),
    path('api/check/modelli/<int:template_id>/ripristina/', views_check.api_check_template_restore, name='api_check_template_restore'),
    path('api/check/modelli/<int:template_id>/duplica/', views_check.api_check_template_duplicate, name='api_check_template_duplicate'),
    path('api/check/modelli/<int:template_id>/elimina/', views_check.api_check_template_delete, name='api_check_template_delete'),
    path('api/check/formule-mb/', views_check.api_bmr_formula_create, name='api_bmr_formula_create'),
    path('api/check/modelli/custom/', views_check.check_templates_api, name='check_templates_api'),
    path('api/check/cartelle/', coach_dual_auth(views_check_taxonomy.api_check_folders), name='api_check_folders'),
    path('api/check/cartelle/riordina/', coach_dual_auth(views_check_taxonomy.api_check_folders_reorder), name='api_check_folders_reorder'),
    path('api/check/cartelle/<int:folder_id>/', coach_dual_auth(views_check_taxonomy.api_check_folder_detail), name='api_check_folder_detail'),
    path('api/check/modelli/<int:template_id>/cartella/', coach_dual_auth(views_check_taxonomy.api_check_template_folder), name='api_check_template_folder'),
    path('check/andamento/', views_check.check_progress_charts_view, name='check_progress_charts'),
    path('check/andamento/<int:client_id>/', views_check.check_progress_charts_view, name='check_progress_charts_client'),
    path('check/comparatore/', views_check.check_comparator_view, name='check_comparator'),
    path('check/comparatore/<int:client_id>/', views_check.check_comparator_view, name='check_comparator_client'),
    path('api/check/foto/<int:photo_id>/', views_check.api_check_photo_proxy, name='api_check_photo_proxy'),
    path('api/check/allegato-foto/<int:attachment_id>/', views_check.api_check_attachment_photo_proxy, name='api_check_attachment_photo_proxy'),
    path('check/cliente/<int:client_id>/', views_check.client_check_history_view, name='check_client_history'),
    path('check/<int:response_id>/modifica/', views_check.check_edit_view, name='check_edit'),
    path('check/<int:response_id>/', views_check.check_detail_view, name='check_detail'),
    path('api/check/cerca-cliente/', views_check.api_check_search, name='check_search_api'),
    path('api/check/clienti-stato/', views_check.api_coach_clients_check_status, name='check_clients_status_api'),
    path('api/check/pianifica/', views_check.api_check_schedule, name='check_schedule_api'),
    path('api/check/<int:response_id>/revisiona/', views_check.api_check_review, name='check_review_api'),
    path('check/i-miei-check/', views_check.client_assigned_checks_view, name='client_assigned_checks'),
    path('check/assegnato/<int:instance_id>/compila/', views_check.fill_assigned_check_view, name='fill_assigned_check'),
    path('api/check/assegna/', views_check.api_check_assign, name='check_assign_api'),
    path('api/check/assegnazione/<int:assignment_id>/ics/', views_check.api_check_assignment_ics, name='check_assignment_ics'),
    
    # Impostazioni
    path('impostazioni/', views_settings.impostazioni_view, name='impostazioni_dashboard'),
    path('profilo/', views_settings.my_profile_view, name='my_profile'),
    path('impostazioni/elimina-account/', views_settings.delete_account_view, name='delete_account'),
    path('impostazioni/notifiche/', views_settings.notifications_view, name='settings_notifications'),
    path('impostazioni/calendario/', views_settings.calendar_view, name='settings_calendar'),
    path('impostazioni/messaggi-automatici/', views_settings.automatic_messages_view, name='settings_automatic_messages'),
    path('impostazioni/abbonamento/portale/', views_settings.billing_portal_view, name='settings_billing_portal'),
    path('api/agenda/calendar-token/', views_agenda.api_coach_calendar_token, name='api_coach_calendar_token'),
    path('calendar/coach/<str:token>.ics', views_agenda.coach_calendar_feed, name='coach_calendar_feed'),
    path('calendar/client/<str:token>.ics', views_agenda.client_calendar_feed, name='client_calendar_feed'),

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

    # CHIRON (assistente AI)
    path('api/chiron/chat/', views_chiron.api_chiron_chat, name='api_chiron_chat'),
    path('api/chiron/history/', views_chiron.api_chiron_history, name='api_chiron_history'),
    path('api/chiron/azione/esegui/', views_chiron.api_chiron_action_execute, name='api_chiron_action_execute'),
    path('api/chiron/clear/', views_chiron.api_chiron_clear, name='api_chiron_clear'),

    # Notifications
    path('api/notifications/', views_notifications.api_notifications_list, name='notifications_list'),
    path('api/notifications/unread-count/', views_notifications.api_notifications_unread_count, name='notifications_unread_count'),
    path('api/notifications/<int:notification_id>/read/', views_notifications.api_notification_mark_read, name='notification_mark_read'),
    path('api/notifications/read-all/', views_notifications.api_notifications_mark_all_read, name='notifications_mark_all_read'),

    # Mobile API v1 (Athlete iOS app) — token auth, JSON only
    path('api/v1/auth/login', mobile_api.login, name='api_v1_login'),
    path('api/v1/me', mobile_api.me, name='api_v1_me'),
    path('api/v1/accept-terms', mobile_api.accept_terms, name='api_v1_accept_terms'),
    path('api/v1/workouts', mobile_api.workouts, name='api_v1_workouts'),
    path('api/v1/nutrition', mobile_api.nutrition, name='api_v1_nutrition'),
    path('api/v1/checks', mobile_api.checks, name='api_v1_checks'),
    path('api/v1/checks/<int:response_id>', mobile_api.check_detail, name='api_v1_check_detail'),
    path('api/v1/notifications', mobile_api.notifications, name='api_v1_notifications'),
    path('api/v1/conversations', mobile_api.conversations, name='api_v1_conversations'),
    path('api/v1/conversations/<int:conversation_id>/messages', mobile_api.messages, name='api_v1_messages'),
    path('api/v1/conversations/<int:conversation_id>/send', mobile_api.send_message, name='api_v1_send_message'),
    path('api/v1/conversations/<int:conversation_id>/appointment', mobile_api.request_appointment, name='api_v1_request_appointment'),
    path('api/v1/conversations/<int:conversation_id>/appointment/<int:appointment_id>/respond', mobile_api.respond_appointment, name='api_v1_respond_appointment'),
    path('api/v1/subscription', mobile_api.subscription, name='api_v1_subscription'),
    path('api/v1/subscription/<int:id>/billing-portal', mobile_api.subscription_billing_portal, name='api_v1_subscription_billing_portal'),
    path('api/v1/calendar-feed', mobile_api.calendar_feed, name='api_v1_calendar_feed'),
    path('api/v1/dashboard/summary', mobile_api.dashboard_summary, name='api_v1_dashboard_summary'),
    path('api/v1/appointments', mobile_api.appointments, name='api_v1_appointments'),
    path('api/v1/progress', mobile_api.progress, name='api_v1_progress'),
    path('api/v1/progress/measurement', mobile_api.progress_measurement_create, name='api_v1_progress_measurement'),
    path('api/v1/progress/measurement-sites', mobile_api.measurement_sites, name='api_v1_measurement_sites'),
    path('api/v1/measurement-catalog', mobile_api.measurement_catalog, name='api_v1_measurement_catalog'),
    path('api/v1/exercises/<int:workout_exercise_id>/trend', mobile_api.exercise_trend, name='api_v1_exercise_trend'),
    path('api/v1/profile', mobile_api.profile, name='api_v1_profile'),
    path('api/v1/profile/photo', mobile_api.profile_photo, name='api_v1_profile_photo'),
    path('api/v1/devices/register', mobile_api.register_device, name='api_v1_register_device'),
    path('api/v1/notifications/<int:notification_id>/read', mobile_api.notification_read, name='api_v1_notification_read'),
    path('api/v1/workout-history', mobile_api.workout_history, name='api_v1_workout_history'),
    path('api/v1/workout-history/<int:session_id>', mobile_api.workout_session_detail, name='api_v1_workout_session_detail'),
    path('api/v1/supplements', mobile_api.supplements, name='api_v1_supplements'),
    path('api/v1/coaches/<int:coach_id>', mobile_api.coach_detail, name='api_v1_coach_detail'),
    path('api/v1/settings', mobile_api.notification_settings, name='api_v1_settings'),
    path('api/v1/dashboard/layout', mobile_api.dashboard_layout, name='api_v1_dashboard_layout'),
    path('api/v1/account', mobile_api.delete_account, name='api_v1_delete_account'),
    path('api/v1/tutorial/complete', mobile_api.tutorial_complete, name='api_v1_tutorial_complete'),
    path('api/v1/nutrition/foods', mobile_api.food_search, name='api_v1_food_search'),
    path('api/v1/nutrition/assignments/<int:assignment_id>/macro-day', mobile_api.macro_day, name='api_v1_macro_day'),
    path('api/v1/nutrition/assignments/<int:assignment_id>/macro-history', mobile_api.macro_history, name='api_v1_macro_history'),
    path('api/v1/nutrition/assignments/<int:assignment_id>/macro-log', mobile_api.macro_log_create, name='api_v1_macro_log_create'),
    path('api/v1/nutrition/macro-log/<int:entry_id>', mobile_api.macro_log_delete, name='api_v1_macro_log_delete'),
    path('api/v1/journey', mobile_api.journey, name='api_v1_journey'),
    path('api/v1/plans', mobile_api.plans, name='api_v1_plans'),
    path('api/v1/checkout/start', mobile_api.checkout_start, name='api_v1_checkout_start'),
    path('api/v1/auth/forgot-password', mobile_api.forgot_password, name='api_v1_forgot_password'),
    path('api/v1/sessions/start', mobile_api.session_start, name='api_v1_session_start'),
    path('api/v1/sessions/<int:session_id>/log-set', mobile_api.session_log_set, name='api_v1_session_log_set'),
    path('api/v1/sessions/<int:session_id>/finish', mobile_api.session_finish, name='api_v1_session_finish'),
    path('api/v1/sessions/<int:session_id>/overrides', mobile_api.session_overrides, name='api_v1_session_overrides'),
    path('api/v1/exercises/search', mobile_api.exercises_search, name='api_v1_exercises_search'),
    path('api/v1/exercises/trend-by-name', mobile_api.exercise_trend_by_name, name='api_v1_exercise_trend_by_name'),
    path('api/v1/progress/exercises', mobile_api.progress_exercises, name='api_v1_progress_exercises'),
    path('api/v1/checks/<int:instance_id>/submit', mobile_api.check_submit, name='api_v1_check_submit'),
    path('api/v1/prima-valutazione', mobile_api.prima_valutazione, name='api_v1_prima_valutazione'),

    # --- Coach app (Athlynk Coach) ---------------------------------------
    path('api/v1/coach/dashboard', coach_api.dashboard, name='api_v1_coach_dashboard'),
    path('api/v1/coach/pinned-athletes', coach_api.pinned_athletes, name='api_v1_coach_pinned_athletes'),
    path('api/v1/coach/agenda', coach_api.agenda, name='api_v1_coach_agenda'),
    path('api/v1/coach/clients', coach_api.clients, name='api_v1_coach_clients'),
    path('api/v1/coach/clients/create', coach_api.create_client, name='api_v1_coach_client_create'),
    path('api/v1/coach/subscription-plans', coach_api.subscription_plans, name='api_v1_coach_subscription_plans'),
    path('api/v1/coach/subscription-plans/create', coach_api.subscription_plan_create, name='api_v1_coach_subscription_plan_create'),
    path('api/v1/coach/subscription-plans/<int:plan_id>', coach_api.subscription_plan_edit, name='api_v1_coach_subscription_plan_edit'),
    path('api/v1/coach/clients/<int:client_id>', coach_api.client_detail, name='api_v1_coach_client_detail'),
    path('api/v1/coach/clients/<int:client_id>/progress', coach_api.client_progress, name='api_v1_coach_client_progress'),
    path('api/v1/coach/clients/<int:client_id>/measurement', coach_api.client_measurement_create, name='api_v1_coach_client_measurement'),
    path('api/v1/coach/clients/<int:client_id>/checks', coach_api.client_checks_review, name='api_v1_coach_client_checks'),
    path('api/v1/coach/clients/<int:client_id>/fabbisogni', coach_api.client_fabbisogni, name='api_v1_coach_client_fabbisogni'),
    path('api/v1/coach/clients/<int:client_id>/macro-history', coach_api.client_macro_history, name='api_v1_coach_client_macro_history'),
    path('api/v1/coach/agenda/create', coach_api.agenda_create, name='api_v1_coach_agenda_create'),
    path('api/v1/coach/agenda/<int:appointment_id>', coach_api.agenda_detail, name='api_v1_coach_agenda_detail'),
    path('api/v1/coach/checks', coach_api.checks_review, name='api_v1_coach_checks'),
    path('api/v1/coach/check-catalog', coach_api.check_catalog, name='api_v1_coach_check_catalog'),
    path('api/v1/coach/check-templates', coach_api.check_templates, name='api_v1_coach_check_templates'),
    path('api/v1/coach/check-templates/page', coach_api.check_templates_page, name='api_v1_coach_check_templates_page'),
    path('api/v1/coach/check-templates/create', coach_api.check_template_create, name='api_v1_coach_check_template_create'),
    path('api/v1/coach/check-templates/<int:template_id>', coach_api.check_template_detail, name='api_v1_coach_check_template_detail'),
    path('api/v1/coach/check-templates/<int:template_id>/update', coach_api.check_template_update, name='api_v1_coach_check_template_update'),
    path('api/v1/coach/check-templates/<int:template_id>/duplicate', coach_api.check_template_duplicate, name='api_v1_coach_check_template_duplicate'),
    path('api/v1/coach/check-templates/<int:template_id>/delete', coach_api.check_template_delete, name='api_v1_coach_check_template_delete'),
    path('api/v1/coach/check-templates/<int:template_id>/restore', coach_api.check_template_restore, name='api_v1_coach_check_template_restore'),
    path('api/v1/coach/check-templates/<int:template_id>/assign', coach_api.check_template_assign, name='api_v1_coach_check_template_assign'),
    path('api/v1/coach/check-templates/<int:template_id>/fill', coach_api.check_template_fill, name='api_v1_coach_check_template_fill'),
    path('api/v1/coach/checks/<int:response_id>', coach_api.check_detail, name='api_v1_coach_check_detail'),
    path('api/v1/coach/checks/<int:response_id>/feedback', coach_api.check_feedback, name='api_v1_coach_check_feedback'),
    path('api/v1/coach/checks/<int:response_id>/values', coach_api.check_values_prefill, name='api_v1_coach_check_values'),
    path('api/v1/coach/checks/<int:response_id>/values/update', coach_api.check_values_update, name='api_v1_coach_check_values_update'),
    path('api/v1/coach/workouts', coach_api.workouts, name='api_v1_coach_workouts'),
    path('api/v1/coach/workouts/create', coach_api.workout_create, name='api_v1_coach_workout_create'),
    path('api/v1/coach/workouts/<int:plan_id>', coach_api.workout_detail, name='api_v1_coach_workout_detail'),
    path('api/v1/coach/workouts/<int:plan_id>/builder', coach_api.workout_builder, name='api_v1_coach_workout_builder'),
    path('api/v1/coach/workouts/<int:plan_id>/assign', coach_api.workout_assign, name='api_v1_coach_workout_assign'),
    path('api/v1/coach/nutrition', coach_api.nutrition, name='api_v1_coach_nutrition'),
    path('api/v1/coach/nutrition/create', coach_api.nutrition_create, name='api_v1_coach_nutrition_create'),
    path('api/v1/coach/nutrition/<int:plan_id>', coach_api.nutrition_detail, name='api_v1_coach_nutrition_detail'),
    path('api/v1/coach/nutrition/<int:plan_id>/builder', coach_api.nutrition_builder, name='api_v1_coach_nutrition_builder'),
    path('api/v1/coach/nutrition/<int:plan_id>/supplements', coach_api.coach_nutrition_supplements, name='api_v1_coach_nutrition_supplements'),
    path('api/v1/coach/nutrition/assignable-clients', coach_api.coach_nutrition_assignable_clients, name='api_v1_coach_nutrition_assignable_clients'),
    path('api/v1/coach/supplements', coach_api.coach_supplements, name='api_v1_coach_supplements'),
    path('api/v1/coach/supplements/save', coach_api.coach_supplement_save, name='api_v1_coach_supplement_save'),
    path('api/v1/coach/supplements/assignable-clients', coach_api.coach_supplement_assignable_clients, name='api_v1_coach_supplement_assignable_clients'),
    path('api/v1/coach/supplements/<int:protocol_id>', coach_api.coach_supplement_detail, name='api_v1_coach_supplement_detail'),
    path('api/v1/coach/supplements/<int:protocol_id>/delete', coach_api.coach_supplement_delete, name='api_v1_coach_supplement_delete'),
    path('api/v1/coach/supplements/<int:protocol_id>/assign', coach_api.coach_supplement_assign, name='api_v1_coach_supplement_assign'),
    path('api/v1/coach/subscriptions', coach_api.subscriptions, name='api_v1_coach_subscriptions'),
    path('api/v1/coach/connect/start', coach_api.coach_connect_start, name='api_v1_coach_connect_start'),
    path('api/v1/coach/connect/status', coach_api.coach_connect_status, name='api_v1_coach_connect_status'),
    path('api/v1/coach/resources', coach_api.resources, name='api_v1_coach_resources'),
    path('api/v1/coach/analytics', coach_api.analytics, name='api_v1_coach_analytics'),
    path('api/v1/coach/analytics/business', coach_api.analytics_business, name='api_v1_coach_analytics_business'),
    path('api/v1/coach/analytics/risk', coach_api.analytics_risk, name='api_v1_coach_analytics_risk'),
    path('api/v1/coach/analytics/client/<int:client_id>/risk', coach_api.analytics_client_risk, name='api_v1_coach_analytics_client_risk'),
    path('api/v1/coach/auto-messages', coach_api.auto_messages, name='api_v1_coach_auto_messages'),
    path('api/v1/coach/messageable-clients', coach_api.messageable_clients, name='api_v1_coach_messageable_clients'),
    path('api/v1/coach/conversations/start', coach_api.start_conversation, name='api_v1_coach_start_conversation'),
    path('api/v1/coach/conversations', coach_api.conversations, name='api_v1_coach_conversations'),
    path('api/v1/coach/conversations/<int:conversation_id>/messages', coach_api.messages, name='api_v1_coach_messages'),
    path('api/v1/coach/conversations/<int:conversation_id>/send', coach_api.send_message, name='api_v1_coach_send_message'),
    path('api/v1/coach/conversations/<int:conversation_id>/appointment', coach_api.request_appointment, name='api_v1_coach_request_appointment'),
    path('api/v1/coach/conversations/<int:conversation_id>/appointment/<int:appointment_id>/respond', coach_api.respond_appointment, name='api_v1_coach_respond_appointment'),
    path('api/v1/coach/profile', coach_api.profile, name='api_v1_coach_profile'),
    path('api/v1/coach/profile/photo', coach_api.profile_photo, name='api_v1_coach_profile_photo'),
    path('api/v1/coach/calendar-feed', coach_api.calendar_feed, name='api_v1_coach_calendar_feed'),
    path('api/v1/coach/billing-portal', coach_api.billing_portal, name='api_v1_coach_billing_portal'),
    path('api/v1/coach/clients/<int:client_id>/workout', coach_api.client_workout, name='api_v1_coach_client_workout'),
    path('api/v1/coach/clients/<int:client_id>/exercises/<int:workout_exercise_id>/trend',
         coach_api.client_exercise_trend, name='api_v1_coach_client_exercise_trend'),
    path('api/v1/coach/clients/<int:client_id>/sessions', coach_api.client_sessions, name='api_v1_coach_client_sessions'),
    path('api/v1/coach/sessions/<int:session_id>', coach_api.session_detail, name='api_v1_coach_session_detail'),
    path('api/v1/coach/clients/<int:client_id>/percorso', coach_api.client_percorso, name='api_v1_coach_client_percorso'),
    path('api/v1/coach/clients/<int:client_id>/percorso/phases', coach_api.phase_create, name='api_v1_coach_phase_create'),
    path('api/v1/coach/clients/<int:client_id>/percorso/phases/<int:phase_id>',
         coach_api.phase_detail, name='api_v1_coach_phase_detail'),
    path('api/v1/coach/chiron/chat/', coach_api.chiron_chat, name='api_v1_coach_chiron_chat'),
    path('api/v1/coach/chiron/chat/stream/', coach_api.chiron_chat_stream, name='api_v1_coach_chiron_chat_stream'),
    path('api/v1/coach/chiron/history/', coach_api.chiron_history, name='api_v1_coach_chiron_history'),
    path('api/v1/coach/chiron/clear/', coach_api.chiron_clear, name='api_v1_coach_chiron_clear'),
    path('api/v1/coach/chiron/azione/esegui/', coach_api.chiron_execute, name='api_v1_coach_chiron_execute'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
