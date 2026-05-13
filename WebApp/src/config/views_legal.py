"""Legal pages: Privacy Policy, Cookie Policy, Cookie Preferences manager."""
from django.shortcuts import render
from django.conf import settings


def _ctx(extra=None):
    ctx = {'consent_version': settings.CONSENT_VERSION}
    if extra:
        ctx.update(extra)
    return ctx


def privacy_view(request):
    return render(request, 'pages/legal/privacy.html', _ctx())


def cookie_view(request):
    return render(request, 'pages/legal/cookie.html', _ctx())


def cookie_preferences_view(request):
    return render(request, 'pages/legal/cookie_preferences.html', _ctx())
