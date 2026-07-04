"""Endpoint HTTP per l'assistente CHIRON."""

import json
import logging

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from pydantic import ValidationError

from chiron.actions import execute_action
from chiron.agent import run_chiron
from chiron.memory import build_context, reset as reset_memory
from chiron.schemas import ChatRequest
from domain.chiron.models import ChironMessage

from .session_utils import get_session_user, get_session_coach
from .services import ratelimit

logger = logging.getLogger(__name__)

# Paginazione history: pagina di default e tetto massimo per richiesta.
HISTORY_PAGE_DEFAULT = 10
HISTORY_PAGE_MAX = 50

# CHIRON invoca un LLM (+ web search): endpoint più costoso dell'app, throttle
# dedicato per utente oltre al backstop globale per-IP.
CHIRON_RATE_LIMIT = 30
CHIRON_RATE_WINDOW_SECONDS = 60
CHIRON_BLOCKED_MESSAGE = 'Troppe richieste a CHIRON. Riprova tra un minuto.'


def _role_from_coach(coach) -> str:
    """Mappa professional_type → user_role CHIRON."""
    mapping = {
        'COACH': 'coach',
        'ALLENATORE': 'allenatore',
        'NUTRIZIONISTA': 'nutrizionista',
    }
    return mapping.get(getattr(coach, 'professional_type', ''), 'utente')


@require_http_methods(["POST"])
def api_chiron_chat(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)

    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Solo i coach possono usare CHIRON in questa fase.'}, status=403)

    allowed, _ = ratelimit.hit('chiron_chat', str(user.id), CHIRON_RATE_LIMIT, CHIRON_RATE_WINDOW_SECONDS)
    if not allowed:
        return JsonResponse({'error': CHIRON_BLOCKED_MESSAGE}, status=429)

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

    # Contesto autorevole lato server: finestra recente + riassunto rotante.
    # build_context va chiamato PRIMA di persistere il nuovo messaggio utente.
    history, memory_summary = build_context(user)

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
            coach_id=coach.id,
            memory_summary=memory_summary,
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
        actions=[a.model_dump() for a in result.actions],
        used_web_search=result.used_web_search,
    )

    return JsonResponse({
        'response': result.response,
        'sources': [s.model_dump() for s in result.sources],
        'actions': [a.model_dump() for a in result.actions],
        'used_web_search': result.used_web_search,
        'pending_action': result.pending_action.model_dump() if result.pending_action else None,
    })


@require_http_methods(["POST"])
def api_chiron_action_execute(request):
    """Esegue un'azione proposta da CHIRON, DOPO conferma del coach.

    Il modello non muta mai i dati: qui il server ri-valida lo scope ed esegue.
    """
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)

    allowed, _ = ratelimit.hit('chiron_action', str(user.id), CHIRON_RATE_LIMIT, CHIRON_RATE_WINDOW_SECONDS)
    if not allowed:
        return JsonResponse({'error': CHIRON_BLOCKED_MESSAGE}, status=429)

    try:
        body = json.loads(request.body.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    try:
        ok, message, link = execute_action(coach, body or {})
    except Exception:
        logger.exception("CHIRON: errore in execute_action")
        return JsonResponse({'ok': False, 'message': 'Azione non riuscita.'}, status=500)

    if ok:
        # Registra l'esito come messaggio assistente: sopravvive al reload.
        ChironMessage.objects.create(
            user=user,
            role='assistant',
            content=f"✓ {message}",
            actions=[link] if link else [],
        )

    return JsonResponse(
        {'ok': ok, 'message': message, 'action': link},
        status=200 if ok else 400,
    )


@require_http_methods(["GET"])
def api_chiron_history(request):
    """Cronologia paginata (cursor su id). `?limit=10&before=<id>` per i più vecchi."""
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    if not get_session_coach(request):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    try:
        limit = int(request.GET.get('limit', HISTORY_PAGE_DEFAULT))
    except (ValueError, TypeError):
        limit = HISTORY_PAGE_DEFAULT
    limit = max(1, min(limit, HISTORY_PAGE_MAX))

    qs = ChironMessage.objects.filter(user=user)
    before = request.GET.get('before')
    if before:
        try:
            qs = qs.filter(id__lt=int(before))
        except (ValueError, TypeError):
            pass

    # Prende limit+1 per sapere se ci sono altri messaggi più vecchi.
    rows = list(qs.order_by('-id')[:limit + 1])
    has_more = len(rows) > limit
    rows = rows[:limit]
    rows.reverse()  # cronologico crescente per il rendering

    return JsonResponse({
        'messages': [
            {
                'id': r.id,
                'role': r.role,
                'content': r.content,
                'sources': r.sources or [],
                'actions': r.actions or [],
                'used_web_search': r.used_web_search,
                'created_at': r.created_at.isoformat(),
            }
            for r in rows
        ],
        'has_more': has_more,
    })


@require_http_methods(["POST"])
def api_chiron_clear(request):
    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    if not get_session_coach(request):
        return JsonResponse({'error': 'Forbidden'}, status=403)

    deleted, _ = ChironMessage.objects.filter(user=user).delete()
    reset_memory(user)
    return JsonResponse({'status': 'ok', 'deleted': deleted})
