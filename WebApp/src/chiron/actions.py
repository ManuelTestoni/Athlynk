"""Azioni eseguibili di CHIRON (Fase 2) — pattern propose → confirm → execute.

Sicurezza: il modello LLM NON muta MAI nulla. Propone soltanto (`build_proposal`).
La mutazione avviene server-side (`execute_action`) DOPO conferma esplicita del
coach, ri-validando l'intero scope (il descrittore che arriva dal client non è
mai fidato: client e check vengono ri-risolti vincolati al coach in sessione).

Azioni (review loop, niente progressioni):
- mark_check_reviewed: ultimo check COMPLETED dell'atleta → REVIEWED
- save_check_feedback: salva coach_feedback sull'ultimo check (+ REVIEWED)
- send_message: invia un messaggio in chat all'atleta (notifica MESSAGE)
I primi due notificano l'atleta (CHECK_REVIEWED).
"""

import logging

logger = logging.getLogger(__name__)

ACTION_TYPES = ("mark_check_reviewed", "save_check_feedback", "send_message")


def _latest_check(coach, client):
    from domain.checks.models import QuestionnaireResponse
    return (
        QuestionnaireResponse.objects
        .filter(coach=coach, client=client, status__in=["COMPLETED", "REVIEWED"])
        .order_by("-submitted_at").first()
    )


def build_proposal(coach, action_type, client_id, feedback=None, message=None):
    """Valida e risolve un'azione in un descrittore confermabile (NON muta nulla).

    Ritorna (proposal_dict, None) oppure (None, error_str).
    """
    from chiron.coach_tools import _client_in_scope, _full_name
    if action_type not in ACTION_TYPES:
        return None, f"Azione non valida. Ammesse: {', '.join(ACTION_TYPES)}."
    client = _client_in_scope(coach, client_id)
    if not client:
        return None, "Atleta non trovato tra i tuoi clienti."
    name = _full_name(client)

    # send_message non dipende da un check: gestita a parte.
    if action_type == "send_message":
        text = (message or "").strip()
        if not text:
            return None, "Manca il testo del messaggio da inviare."
        return {
            "action_type": action_type,
            "client_id": client.id,
            "message": text[:2000],
            "editable_field": "message",
            "title": f"Inviare il messaggio a {name}?",
            "description": (
                f"Il messaggio verrà inviato nella chat con {name}, che riceverà "
                f"una notifica. Puoi modificarlo prima di inviare."
            ),
        }, None

    check = _latest_check(coach, client)
    if not check:
        return None, f"{name} non ha check compilati su cui agire."
    date = check.submitted_at.strftime("%-d %b %Y") if check.submitted_at else ""

    if action_type == "mark_check_reviewed":
        if check.status == "REVIEWED":
            return None, f"L'ultimo check di {name} ({date}) è già revisionato."
        return {
            "action_type": action_type,
            "client_id": client.id,
            "response_id": check.id,
            "title": "Segnare il check come revisionato?",
            "description": (
                f"Ultimo check di {name} del {date} → stato «revisionato». "
                f"L'atleta riceverà una notifica."
            ),
        }, None

    # save_check_feedback
    text = (feedback or "").strip()
    if not text:
        return None, "Manca il testo del feedback da salvare."
    return {
        "action_type": action_type,
        "client_id": client.id,
        "response_id": check.id,
        "feedback": text[:4000],
        "editable_field": "feedback",
        "title": "Salvare il feedback sul check?",
        "description": (
            f"Verrà salvato come feedback sull'ultimo check di {name} ({date}) e il "
            f"check segnato come revisionato. L'atleta riceverà una notifica."
        ),
    }, None


def execute_action(coach, descriptor):
    """Esegue un'azione confermata ri-validando TUTTO lato server.

    Ritorna (ok: bool, message: str, action_link: dict | None).
    """
    from django.urls import reverse
    from domain.checks.models import QuestionnaireResponse
    from chiron.coach_tools import _client_in_scope, _full_name

    descriptor = descriptor or {}
    action_type = descriptor.get("action_type")
    if action_type not in ACTION_TYPES:
        return False, "Azione non valida.", None

    client = _client_in_scope(coach, descriptor.get("client_id"))
    if not client:
        return False, "Atleta non trovato tra i tuoi clienti.", None

    name = _full_name(client)

    # send_message: non tocca i check, scrive in chat tramite il canale ufficiale.
    if action_type == "send_message":
        from domain.chat.models import Conversation
        from domain.chat.services import _deliver
        text = (descriptor.get("message") or "").strip()
        if not text:
            return False, "Testo del messaggio mancante.", None
        try:
            _deliver(coach, client, text[:2000])
        except Exception:
            logger.exception("CHIRON: invio messaggio fallito")
            return False, "Invio del messaggio non riuscito.", None
        conv = Conversation.objects.filter(coach=coach, client=client).first()
        link = (
            {"label": f"Apri chat — {name}", "url": reverse("chat_detail", args=[conv.id])}
            if conv else None
        )
        return True, f"Messaggio inviato a {name}.", link

    # Il check viene ri-risolto per id MA vincolato a coach+client: il descrittore
    # del client non è mai fidato.
    try:
        check = QuestionnaireResponse.objects.get(
            id=descriptor.get("response_id"), coach=coach, client=client,
        )
    except QuestionnaireResponse.DoesNotExist:
        return False, "Check non trovato.", None

    link = {"label": f"Apri check — {name}", "url": reverse("check_detail", args=[check.id])}

    if action_type == "mark_check_reviewed":
        check.status = "REVIEWED"
        check.save(update_fields=["status", "updated_at"])
        _notify_reviewed(client, coach, check, link["url"])
        return True, f"Check di {name} segnato come revisionato.", link

    # save_check_feedback
    text = (descriptor.get("feedback") or "").strip()
    if not text:
        return False, "Testo del feedback mancante.", None
    check.coach_feedback = text[:4000]
    check.status = "REVIEWED"
    check.save(update_fields=["coach_feedback", "status", "updated_at"])
    _notify_reviewed(client, coach, check, link["url"])
    return True, f"Feedback salvato sul check di {name}.", link


def _notify_reviewed(client, coach, check, link_url):
    from domain.chat.models import Notification
    try:
        Notification.objects.create(
            target_user=client.user,
            notification_type="CHECK_REVIEWED",
            title="Check revisionato",
            body=f"{coach.first_name} {coach.last_name} ha revisionato il tuo check.",
            link_url=link_url,
        )
    except Exception:
        logger.exception("CHIRON: notifica CHECK_REVIEWED fallita")
