"""Endpoint HTTP per l'assistente CHIRON."""

import json
import logging

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from pydantic import ValidationError

from chiron.agent import run_chiron
from chiron.schemas import ChatRequest, HistoryMessage
from domain.chiron.models import ChironMessage

from .session_utils import get_session_user, get_session_coach

logger = logging.getLogger(__name__)

# Numero massimo di messaggi (user+assistant) usati come contesto per il modello.
HISTORY_WINDOW = 20
# Numero massimo di messaggi ritornati al frontend al reload.
HISTORY_PAGE = 50


def _role_from_coach(coach) -> str:
    """Mappa professional_type → user_role CHIRON."""
    mapping = {
        'COACH': 'coach',
        'ALLENATORE': 'allenatore',
        'NUTRIZIONISTA': 'nutrizionista',
    }
    return mapping.get(getattr(coach, 'professional_type', ''), 'utente')


def _load_history_from_db(user, limit: int = HISTORY_WINDOW) -> list[HistoryMessage]:
    """Carica gli ultimi N messaggi dal DB in ordine cronologico crescente."""
    rows = list(
        ChironMessage.objects
        .filter(user=user)
        .order_by('-created_at')[:limit]
    )
    rows.reverse()
    return [HistoryMessage(role=r.role, content=r.content) for r in rows]


@require_http_methods(["POST"])
def api_chiron_chat(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Solo i coach possono usare CHIRON in questa fase.'}, status=403)

    try:
        body = json.loads(request.body.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    # Forza il ruolo lato server dal CoachProfile: il client non può promuoversi.
    body['user_role'] = _role_from_coach(coach)

    try:
        payload = ChatRequest(**body)
    except ValidationError as exc:
        return JsonResponse({'error': 'Payload non valido', 'details': exc.errors()}, status=400)

    # Se il frontend non ha mandato history, ricostruiscila dal DB.
    history = payload.conversation_history or _load_history_from_db(user)

    # Persisti il messaggio utente PRIMA della chiamata al modello.
    ChironMessage.objects.create(
        user=user,
        role='user',
        content=payload.message,
    )

    try:
        result = run_chiron(
            message=payload.message,
            user_role=payload.user_role,
            history=history,
        )
    except Exception:
        logger.exception("CHIRON: errore in run_chiron")
        return JsonResponse(
            {'error': 'CHIRON non è raggiungibile in questo momento. Riprova tra poco.'},
            status=500,
        )

    # Persisti la risposta.
    ChironMessage.objects.create(
        user=user,
        role='assistant',
        content=result.response,
        sources=[s.model_dump() for s in result.sources],
        used_web_search=result.used_web_search,
    )

    return JsonResponse({
        'response': result.response,
        'sources': [s.model_dump() for s in result.sources],
        'used_web_search': result.used_web_search,
    })


@require_http_methods(["GET"])
def api_chiron_history(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    if not get_session_coach(request):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    rows = list(
        ChironMessage.objects
        .filter(user=user)
        .order_by('-created_at')[:HISTORY_PAGE]
    )
    rows.reverse()

    return JsonResponse({
        'messages': [
            {
                'role': r.role,
                'content': r.content,
                'sources': r.sources or [],
                'used_web_search': r.used_web_search,
                'created_at': r.created_at.isoformat(),
            }
            for r in rows
        ],
    })


@require_http_methods(["POST"])
def api_chiron_clear(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    if not get_session_coach(request):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    deleted, _ = ChironMessage.objects.filter(user=user).delete()
    return JsonResponse({'status': 'ok', 'deleted': deleted})
