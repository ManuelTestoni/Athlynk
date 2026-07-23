"""Endpoint HTTP per il recap atleta di CHIRON ("Genera recap atleta")."""

import json
import logging

from django.http import JsonResponse
from django.shortcuts import render, redirect, get_object_or_404
from django.views.decorators.http import require_http_methods

from domain.accounts.models import ClientProfile

from .session_utils import get_session_user, get_session_coach, coach_has_chiron_access, get_active_relationships
from .views_chiron import CHIRON_ADDON_MESSAGE
from .services import ratelimit

logger = logging.getLogger(__name__)

RECAP_RATE_LIMIT = 15
RECAP_RATE_WINDOW_SECONDS = 60
RECAP_BLOCKED_MESSAGE = 'Troppe richieste di recap. Riprova tra un minuto.'


def _coach_and_client(request, client_id):
    user = get_session_user(request)
    if not user:
        return None, None, JsonResponse({'error': 'Unauthorized'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return None, None, JsonResponse({'error': 'Forbidden'}, status=403)
    if not coach_has_chiron_access(coach):
        return None, None, JsonResponse({'error': CHIRON_ADDON_MESSAGE}, status=403)
    try:
        client = ClientProfile.objects.get(id=client_id)
    except ClientProfile.DoesNotExist:
        return None, None, JsonResponse({'error': 'not found'}, status=404)

    rels = get_active_relationships(client)
    is_coach_of_client = any(rel and rel.coach_id == coach.id for rel in rels.values())
    if not is_coach_of_client:
        return None, None, JsonResponse({'error': 'forbidden'}, status=403)
    return coach, client, None


def _build_or_error(coach, client, force_refresh):
    from domain.chiron.recap.builder import build_recap

    allowed, _ = ratelimit.hit('chiron_recap', str(coach.id), RECAP_RATE_LIMIT, RECAP_RATE_WINDOW_SECONDS)
    if not allowed:
        return None, JsonResponse({'error': RECAP_BLOCKED_MESSAGE}, status=429)
    try:
        payload = build_recap(coach, client, force_refresh=force_refresh)
    except Exception:
        logger.exception("CHIRON recap: errore in build_recap")
        return None, JsonResponse(
            {'error': 'Recap non generabile in questo momento. Riprova tra poco.'}, status=500,
        )
    return JsonResponse(payload.model_dump()), None


@require_http_methods(["GET"])
def api_chiron_recap(request, client_id):
    coach, client, err = _coach_and_client(request, client_id)
    if err:
        return err
    response, err = _build_or_error(coach, client, force_refresh=False)
    return err or response


@require_http_methods(["POST"])
def api_chiron_recap_regenerate(request, client_id):
    coach, client, err = _coach_and_client(request, client_id)
    if err:
        return err
    response, err = _build_or_error(coach, client, force_refresh=True)
    return err or response


@require_http_methods(["POST"])
def api_chiron_recap_insight_action(request, client_id):
    """Trasforma la raccomandazione di un insight in una PendingAction
    (send_message) tramite il pattern propose→confirm→execute già esistente
    in chiron/actions.py — mai un invio diretto. Il coach conferma/modifica il
    testo, poi lo stesso descriptor va a /api/chiron/azione/esegui/ (invariato)."""
    from domain.chiron.recap.insights import SUGGESTED_ACTION_MESSAGES
    from chiron.actions import build_proposal

    coach, client, err = _coach_and_client(request, client_id)
    if err:
        return err
    try:
        body = json.loads(request.body.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    code = body.get('insight_code')
    message = SUGGESTED_ACTION_MESSAGES.get(code)
    if not message:
        return JsonResponse({'error': 'Insight non riconosciuto.'}, status=400)

    proposal, error = build_proposal(coach, 'send_message', client.id, message=message)
    if error:
        return JsonResponse({'error': error}, status=400)
    return JsonResponse({'proposal': proposal})


@require_http_methods(["POST"])
def api_chiron_recap_insight_feedback(request, client_id):
    """V3 prep: registra 'utile/non utile' su un insight. Non calibra nulla
    ora — solo cattura, per una calibrazione futura quando c'è abbastanza
    segnale d'uso reale accumulato (vedi §V3 del piano)."""
    from domain.chiron.models import AthleteRecap, AthleteRecapFeedback

    coach, client, err = _coach_and_client(request, client_id)
    if err:
        return err
    try:
        body = json.loads(request.body.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    code = (body.get('insight_code') or '').strip()
    useful = body.get('useful')
    if not code or not isinstance(useful, bool):
        return JsonResponse({'error': 'insight_code e useful (bool) sono obbligatori.'}, status=400)

    latest_recap = AthleteRecap.objects.filter(coach=coach, client=client).first()
    AthleteRecapFeedback.objects.update_or_create(
        coach=coach, client=client, recap=latest_recap, insight_code=code,
        defaults={'useful': useful},
    )
    return JsonResponse({'ok': True})


@require_http_methods(["GET", "POST"])
def api_chiron_recap_settings(request):
    """V3 prep: legge/aggiorna le soglie di anomalia per-coach
    (CoachRecapSettings) usate dal motore insight — non è legato a un singolo
    atleta, per questo non passa da _coach_and_client. Solo le chiavi già
    note in DEFAULT_THRESHOLDS sono accettate: un coach non può iniettare
    chiavi arbitrarie nel motore regole."""
    from domain.chiron.models import CoachRecapSettings
    from domain.chiron.recap.insights import DEFAULT_THRESHOLDS

    user = get_session_user(request)
    if not user:
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    coach = get_session_coach(request)
    if not coach:
        return JsonResponse({'error': 'Forbidden'}, status=403)
    if not coach_has_chiron_access(coach):
        return JsonResponse({'error': CHIRON_ADDON_MESSAGE}, status=403)

    if request.method == 'GET':
        row = CoachRecapSettings.objects.filter(coach=coach).first()
        current = {**DEFAULT_THRESHOLDS, **(row.thresholds if row else {})}
        return JsonResponse({'defaults': DEFAULT_THRESHOLDS, 'thresholds': current})

    try:
        body = json.loads(request.body.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return JsonResponse({'error': 'Invalid JSON'}, status=400)

    cleaned = {}
    for key, value in (body.get('thresholds') or {}).items():
        if key not in DEFAULT_THRESHOLDS:
            continue  # ignora chiavi sconosciute, non un errore
        try:
            cleaned[key] = float(value)
        except (TypeError, ValueError):
            return JsonResponse({'error': f'Valore non valido per {key}.'}, status=400)

    CoachRecapSettings.objects.update_or_create(coach=coach, defaults={'thresholds': cleaned})
    return JsonResponse({'thresholds': {**DEFAULT_THRESHOLDS, **cleaned}})


@require_http_methods(["GET"])
def api_chiron_recap_history(request, client_id):
    """Elenco dei recap passati per questa coppia coach/atleta (storico
    append-only, V2). Solo metadati compatti — il dettaglio completo di un
    punto passato non è ancora esposto, non serve finché la UI mostra solo
    "cosa è cambiato rispetto all'ultimo"."""
    from domain.chiron.models import AthleteRecap

    coach, client, err = _coach_and_client(request, client_id)
    if err:
        return err

    rows = AthleteRecap.objects.filter(coach=coach, client=client)[:20]
    return JsonResponse({'history': [
        {
            'id': r.id,
            'generated_at': r.generated_at.isoformat(),
            'insight_count': len(r.facts_json.get('insights') or []),
            'forecast_direction': (r.facts_json.get('forecast') or {}).get('direction'),
            'narrative_snippet': (r.narrative_text or '')[:160],
        }
        for r in rows
    ]})


def coach_client_recap_view(request, client_id):
    """Pagina 'Genera recap atleta' — il JSON lo carica via fetch dagli
    endpoint sopra; qui solo il guscio + i dati non sensibili all'HTML."""
    user = get_session_user(request)
    if not user:
        return redirect('login')
    coach = get_session_coach(request)
    if not coach:
        return redirect('dashboard')
    if not coach_has_chiron_access(coach):
        return redirect('clienti_detail', client_id=client_id)

    client = get_object_or_404(ClientProfile, id=client_id)
    rels = get_active_relationships(client)
    if not any(rel and rel.coach_id == coach.id for rel in rels.values()):
        return redirect('clienti_list')

    return render(request, 'pages/clienti/recap.html', {'client': client})
