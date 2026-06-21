from django.shortcuts import render
from django.http import JsonResponse


def _is_api(request):
    return request.path.startswith('/api/')


def bad_request(request, exception=None):
    if _is_api(request):
        return JsonResponse({'error': 'Richiesta non valida'}, status=400)
    return render(request, '400.html', status=400)


def forbidden(request, exception=None):
    if _is_api(request):
        return JsonResponse({'error': 'Accesso negato'}, status=403)
    return render(request, '403.html', status=403)


def not_found(request, exception=None):
    if _is_api(request):
        return JsonResponse({'error': 'Risorsa non trovata'}, status=404)
    return render(request, '404.html', status=404)


def server_error(request):
    if _is_api(request):
        return JsonResponse({'error': 'Errore interno del server'}, status=500)
    return render(request, '500.html', status=500)
