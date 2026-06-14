"""Quota giornaliera di import AI per coach.

CHIRON estrae schede (diete) e allenamenti dai file caricati: ogni estrazione è
una chiamata AI costosa. Per contenere i costi ogni coach ha un tetto giornaliero
per dominio. Import Excel e PDF dello stesso dominio condividono il contatore.

Backend: il rate limiter cache-based (services.ratelimit) con finestra 24h. Il
bucket è allineato al giorno UTC, quindi il contatore si azzera a mezzanotte UTC.
"""

from django.http import JsonResponse

from . import ratelimit

DAILY_LIMIT = 5
_WINDOW_SECONDS = 24 * 60 * 60

# Ogni dominio: (prefisso cache del contatore, etichetta per il messaggio utente).
DIET = ('chiron_import_diet', 'schede')
WORKOUT = ('chiron_import_workout', 'allenamenti')


def consume(coach, kind) -> tuple[bool, int]:
    """Registra un tentativo di import e dice se è consentito.

    `kind` è DIET o WORKOUT. Ritorna (allowed, remaining): allowed=False quando il
    coach ha già esaurito il tetto giornaliero per quel dominio.
    """
    prefix, _label = kind
    return ratelimit.hit(prefix, f'coach:{coach.id}', DAILY_LIMIT, _WINDOW_SECONDS)


def limit_response(kind) -> JsonResponse:
    """Risposta 429 con messaggio in italiano per il dominio dato."""
    _prefix, label = kind
    return JsonResponse({
        'error': 'quota_exceeded',
        'detail': (
            f'Hai raggiunto il limite di {DAILY_LIMIT} import di {label} al giorno. '
            f'Riprova domani.'
        ),
    }, status=429)
