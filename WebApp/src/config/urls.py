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
from django.views.generic import TemplateView

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', TemplateView.as_view(template_name='pages/dashboard.html'), name='dashboard'),
    
    # Nutrizione
    path('nutrizione/piani/', TemplateView.as_view(template_name='pages/nutrizione/piani_list.html'), name='nutrizione_piani'),
    path('nutrizione/anamnesi/', TemplateView.as_view(template_name='pages/nutrizione/anamnesi_create.html'), name='nutrizione_anamnesi'),
    path('nutrizione/integratori/', TemplateView.as_view(template_name='pages/nutrizione/integratori_list.html'), name='nutrizione_integratori'),
    
    # Allenamenti
    path('allenamenti/', TemplateView.as_view(template_name='pages/allenamenti/list.html'), name='allenamenti_list'),
    path('allenamenti/crea/', TemplateView.as_view(template_name='pages/allenamenti/create.html'), name='allenamenti_create'),
    path('allenamenti/dettaglio/', TemplateView.as_view(template_name='pages/allenamenti/detail.html'), name='allenamenti_detail'),
    
    # Agenda
    path('agenda/', TemplateView.as_view(template_name='pages/agenda/dashboard.html'), name='agenda_dashboard'),
    path('agenda/lista/', TemplateView.as_view(template_name='pages/agenda/list.html'), name='agenda_list'),
    path('agenda/dettaglio/', TemplateView.as_view(template_name='pages/agenda/detail.html'), name='agenda_detail'),
    
    # Abbonamenti
    path('abbonamenti/', TemplateView.as_view(template_name='pages/abbonamenti/dashboard.html'), name='abbonamenti_dashboard'),
    path('abbonamenti/dettaglio/', TemplateView.as_view(template_name='pages/abbonamenti/detail.html'), name='abbonamenti_detail'),
    path('abbonamenti/checkout/', TemplateView.as_view(template_name='pages/abbonamenti/checkout.html'), name='abbonamenti_checkout'),
    path('abbonamenti/checkout/success/', TemplateView.as_view(template_name='pages/abbonamenti/checkout_success.html'), name='abbonamenti_checkout_success'),
    
    # Check Progressi
    path('check/', TemplateView.as_view(template_name='pages/check/dashboard.html'), name='check_dashboard'),
    path('check/dettaglio/', TemplateView.as_view(template_name='pages/check/detail.html'), name='check_detail'),
    path('check/crea/', TemplateView.as_view(template_name='pages/check/create.html'), name='check_create'),
    
    # Impostazioni
    path('impostazioni/', TemplateView.as_view(template_name='pages/impostazioni/dashboard.html'), name='impostazioni_dashboard'),
]
