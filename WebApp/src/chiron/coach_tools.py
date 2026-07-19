"""Tool LangChain scoped al coach: danno a CHIRON conoscenza dell'app.

Principi:
- Il coach viene letto dal RunnableConfig (`configurable.coach_id`), MAI da un
  argomento del modello. Ogni query filtra per quel coach → impossibile leggere
  dati di altri coach.
- Tool read-only. Ritornano payload COMPATTI + link deterministici via
  `reverse()` (campo "actions"): CHIRON non inventa mai un URL.
- Import Django lazy nei corpi delle funzioni, per non rompere l'import del
  package (stesso ethos di chiron/tools.py).
"""

import json
import logging
from typing import Literal

from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

logger = logging.getLogger(__name__)

# Limiti anti token-burn.
MAX_LIST = 15
MAX_CANDIDATES = 6


# ---------------------------------------------------------------------------
# Helpers (scoping + serializzazione)
# ---------------------------------------------------------------------------

def _coach_from_config(config: RunnableConfig):
    """Estrae il CoachProfile dal config. None se assente/non valido."""
    cid = ((config or {}).get("configurable") or {}).get("coach_id")
    if not cid:
        return None
    from domain.accounts.models import CoachProfile
    return CoachProfile.objects.filter(id=cid).first()


def _coach_clients(coach):
    """QuerySet dei clienti con relazione ATTIVA con questo coach.

    Usa id__in (no join + distinct) così le annotate Count/Max non si gonfiano.
    """
    from domain.accounts.models import ClientProfile
    from domain.coaching.models import CoachingRelationship
    ids = (
        CoachingRelationship.objects
        .filter(coach=coach, status="ACTIVE")
        .values_list("client_id", flat=True)
    )
    return ClientProfile.objects.filter(id__in=ids)


def _client_in_scope(coach, client_id):
    """ClientProfile se appartiene al coach, altrimenti None."""
    return _coach_clients(coach).filter(id=client_id).first()


def _full_name(p) -> str:
    return f"{p.first_name} {p.last_name}".strip()


def _err(msg: str) -> str:
    return json.dumps({"ok": False, "error": msg}, ensure_ascii=False)


def _ok(payload: dict) -> str:
    out = dict(payload)
    out.setdefault("ok", True)
    return json.dumps(out, ensure_ascii=False)


def _short(v, n: int = 80) -> str:
    return str(v).replace("\n", " ").replace("\r", " ").strip()[:n]


def _trim_answers(answers, max_items: int = 12, max_chars: int = 600):
    """Riduce answers_json (dict o list) a una stringa compatta. None se vuoto."""
    if not answers:
        return None
    out: list[str] = []
    try:
        if isinstance(answers, dict):
            for k, v in list(answers.items())[:max_items]:
                out.append(f"{k}: {_short(v)}")
        elif isinstance(answers, list):
            for it in answers[:max_items]:
                if isinstance(it, dict):
                    q = it.get("question") or it.get("label") or it.get("id") or "?"
                    a = it.get("answer") or it.get("value") or it.get("response") or ""
                    out.append(f"{q}: {_short(a)}")
                else:
                    out.append(_short(it))
    except Exception:
        return None
    text = " | ".join(p for p in out if p.strip())
    return text[:max_chars] or None


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@tool("find_athlete")
def find_athlete(name: str, config: RunnableConfig) -> str:
    """Trova un atleta/cliente del coach dal nome (anche parziale) e ne ritorna il
    client_id. Chiamalo SEMPRE per primo quando l'utente cita un atleta per nome.
    Se restituisce più di un risultato, chiedi all'utente quale prima di procedere."""
    from django.db.models import Q
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    qs = _coach_clients(coach)
    for term in (name or "").split():
        qs = qs.filter(Q(first_name__icontains=term) | Q(last_name__icontains=term))
    rows = list(qs.order_by("first_name", "last_name")[:MAX_CANDIDATES])
    if not rows:
        return _ok({"matches": [], "note": "Nessun atleta trovato con questo nome."})
    return _ok({"matches": [
        {"client_id": c.id, "name": _full_name(c)}
        for c in rows
    ]})


@tool("app_action")
def app_action(
    action: Literal[
        "review_last_check", "open_check_history", "open_progress", "open_client",
    ],
    client_id: int,
    config: RunnableConfig,
) -> str:
    """Restituisce un link/azione cliccabile dell'app per un atleta. NON costruire
    MAI URL a mano: usa questo tool.
    - review_last_check: pagina di revisione dell'ultimo check compilato dall'atleta
    - open_check_history: storico check dell'atleta
    - open_progress: progressi/grafici dell'atleta
    - open_client: scheda cliente
    Richiede client_id (vedi find_athlete)."""
    from django.urls import reverse
    from domain.checks.models import QuestionnaireResponse
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    client = _client_in_scope(coach, client_id)
    if not client:
        return _err("Atleta non trovato tra i tuoi clienti.")
    name = _full_name(client)

    if action == "review_last_check":
        r = (
            QuestionnaireResponse.objects
            .filter(coach=coach, client=client, status__in=["COMPLETED", "REVIEWED"])
            .order_by("-submitted_at").first()
        )
        if not r:
            return _ok({"note": f"{name} non ha ancora check compilati.", "actions": []})
        date = r.submitted_at.strftime("%-d %b %Y") if r.submitted_at else ""
        state = "da revisionare" if r.status == "COMPLETED" else "già revisionato"
        return _ok({
            "note": f"Ultimo check di {name} del {date} ({state}).",
            "actions": [{
                "label": f"Revisiona check — {name} ({date})",
                "url": reverse("check_detail", args=[r.id]),
            }],
        })

    if action == "open_check_history":
        return _ok({
            "note": f"Storico check di {name}.",
            "actions": [{
                "label": f"Storico check — {name}",
                "url": reverse("check_client_history", args=[client.id]),
            }],
        })

    if action == "open_progress":
        return _ok({
            "note": f"Progressi di {name}.",
            "actions": [{
                "label": f"Progressi — {name}",
                "url": reverse("coach_client_progressi", args=[client.id]),
            }],
        })

    # open_client
    return _ok({
        "note": f"Scheda di {name}.",
        "actions": [{
            "label": f"Scheda cliente — {name}",
            "url": reverse("clienti_detail", args=[client.id]),
        }],
    })


@tool("athlete_snapshot")
def athlete_snapshot(client_id: int, config: RunnableConfig) -> str:
    """Riepilogo COMPATTO di un atleta: ultimo check, quanti check da revisionare,
    ultima sessione di allenamento, peso più recente. Usalo per domande tipo
    "come sta X" / "dammi un quadro di X". Richiede client_id (vedi find_athlete)."""
    from django.urls import reverse
    from domain.checks.models import QuestionnaireResponse
    from domain.workouts.models import WorkoutSession
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    client = _client_in_scope(coach, client_id)
    if not client:
        return _err("Atleta non trovato tra i tuoi clienti.")
    name = _full_name(client)

    last_check = (
        QuestionnaireResponse.objects
        .filter(coach=coach, client=client, status__in=["COMPLETED", "REVIEWED"])
        .order_by("-submitted_at").first()
    )
    to_review = QuestionnaireResponse.objects.filter(
        coach=coach, client=client, status="COMPLETED",
    ).count()
    last_session = (
        WorkoutSession.objects
        .filter(client=client, assignment__coach=coach)
        .order_by("-started_at").first()
    )

    weight = None
    if last_check and last_check.weight_kg is not None:
        weight = str(last_check.weight_kg)
    elif client.current_weight_kg is not None:
        weight = str(client.current_weight_kg)

    snap = {
        "name": name,
        "last_check": (
            last_check.submitted_at.strftime("%-d %b %Y")
            if last_check and last_check.submitted_at else None
        ),
        "last_check_weight_kg": weight,
        "checks_to_review": to_review,
        "last_workout_session": (
            last_session.started_at.strftime("%-d %b %Y") if last_session else None
        ),
    }
    actions = []
    if last_check:
        actions.append({
            "label": f"Revisiona ultimo check — {name}",
            "url": reverse("check_detail", args=[last_check.id]),
        })
    actions.append({
        "label": f"Progressi — {name}",
        "url": reverse("coach_client_progressi", args=[client.id]),
    })
    return _ok({"snapshot": snap, "actions": actions})


@tool("query_roster")
def query_roster(
    filter: Literal["checks_to_review", "no_check_yet", "inactive_14d"],
    config: RunnableConfig,
) -> str:
    """Interroga TUTTI gli atleti del coach.
    - checks_to_review: atleti con check compilati in attesa di revisione
    - no_check_yet: atleti senza alcun check compilato
    - inactive_14d: atleti senza sessioni di allenamento da oltre 14 giorni
    Usalo per panoramiche tipo "chi devo revisionare" / "chi è inattivo"."""
    from datetime import timedelta
    from django.utils import timezone
    from django.urls import reverse
    from django.db.models import Q, Count, Max
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    clients = _coach_clients(coach)
    items: list[dict] = []
    actions: list[dict] = []

    if filter == "checks_to_review":
        rows = (
            clients.annotate(n=Count(
                "questionnaire_responses",
                filter=Q(questionnaire_responses__coach=coach,
                         questionnaire_responses__status="COMPLETED"),
            )).filter(n__gt=0).order_by("-n")[:MAX_LIST]
        )
        for c in rows:
            items.append({"client_id": c.id, "name": _full_name(c),
                          "detail": f"{c.n} da revisionare"})
        actions.append({"label": "Apri dashboard check", "url": reverse("check_dashboard")})

    elif filter == "no_check_yet":
        rows = (
            clients.annotate(n=Count(
                "questionnaire_responses",
                filter=Q(questionnaire_responses__coach=coach),
            )).filter(n=0).order_by("first_name", "last_name")[:MAX_LIST]
        )
        for c in rows:
            items.append({"client_id": c.id, "name": _full_name(c), "detail": "nessun check"})

    else:  # inactive_14d
        cutoff = timezone.now() - timedelta(days=14)
        rows = (
            clients.annotate(last=Max(
                "workout_sessions__started_at",
                filter=Q(workout_sessions__assignment__coach=coach),
            )).filter(Q(last__lt=cutoff) | Q(last__isnull=True)).order_by("last")[:MAX_LIST]
        )
        for c in rows:
            last = c.last.strftime("%-d %b %Y") if c.last else "mai"
            items.append({"client_id": c.id, "name": _full_name(c),
                          "detail": f"ultima sessione: {last}"})

    payload = {"filter": filter, "count": len(items), "items": items}
    if actions:
        payload["actions"] = actions
    return _ok(payload)


@tool("summarize_check")
def summarize_check(client_id: int, config: RunnableConfig) -> str:
    """Restituisce i DATI dell'ultimo check compilato di un atleta (peso e variazione
    rispetto al precedente, limitazioni, infortuni, note, risposte principali ed
    eventuale feedback già scritto) per farne un riassunto o una bozza di feedback.
    Richiede client_id (vedi find_athlete). NON inventare valori non presenti."""
    from django.urls import reverse
    from domain.checks.models import QuestionnaireResponse
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    client = _client_in_scope(coach, client_id)
    if not client:
        return _err("Atleta non trovato tra i tuoi clienti.")
    name = _full_name(client)
    r = (
        QuestionnaireResponse.objects
        .filter(coach=coach, client=client, status__in=["COMPLETED", "REVIEWED"])
        .order_by("-submitted_at").first()
    )
    if not r:
        return _ok({"note": f"{name} non ha ancora check compilati.", "actions": []})

    prev = (
        QuestionnaireResponse.objects
        .filter(coach=coach, client=client, submitted_at__lt=r.submitted_at)
        .order_by("-submitted_at").first()
    )
    weight_delta = None
    if r.weight_kg is not None and prev and prev.weight_kg is not None:
        weight_delta = round(float(r.weight_kg) - float(prev.weight_kg), 1)

    data = {
        "name": name,
        "date": r.submitted_at.strftime("%-d %b %Y") if r.submitted_at else None,
        "status": "da revisionare" if r.status == "COMPLETED" else "revisionato",
        "weight_kg": str(r.weight_kg) if r.weight_kg is not None else None,
        "weight_delta_kg": weight_delta,
        "limitations": (r.limitations or "").strip()[:400] or None,
        "injuries": (r.injuries or "").strip()[:400] or None,
        "notes": (r.notes or "").strip()[:400] or None,
        "answers": _trim_answers(r.answers_json),
        "existing_feedback": (r.coach_feedback or "").strip()[:400] or None,
    }
    return _ok({
        "check": data,
        "actions": [{
            "label": f"Apri check — {name}",
            "url": reverse("check_detail", args=[r.id]),
        }],
    })


@tool("find_workout_plan")
def find_workout_plan(name: str, config: RunnableConfig) -> str:
    """Trova una SCHEDA di allenamento del coach dal titolo (anche parziale) e ne
    ritorna il plan_id. Chiamalo PRIMA di proporre `assign_workout_plan`.
    Se restituisce più risultati, chiedi all'utente quale prima di procedere."""
    from domain.workouts.models import WorkoutPlan
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    qs = WorkoutPlan.objects.filter(coach=coach)
    if (name or "").strip():
        qs = qs.filter(title__icontains=name.strip())
    rows = list(qs.order_by("-updated_at")[:MAX_CANDIDATES])
    if not rows:
        return _ok({"matches": [], "note": "Nessuna scheda trovata con questo nome."})
    return _ok({"matches": [{
        "plan_id": p.id,
        "title": p.title,
        "kind": "programmazione" if p.plan_kind == "PROGRAM" else "settimanale",
        "weeks": p.duration_weeks,
        "status": p.status,
    } for p in rows]})


@tool("find_nutrition_plan")
def find_nutrition_plan(name: str, config: RunnableConfig) -> str:
    """Trova un PIANO ALIMENTARE del coach dal titolo (anche parziale) e ne ritorna
    il plan_id. Chiamalo PRIMA di proporre `assign_nutrition_plan`.
    Se restituisce più risultati, chiedi all'utente quale prima di procedere."""
    from domain.nutrition.models import NutritionPlan
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    qs = NutritionPlan.objects.filter(coach=coach)
    if (name or "").strip():
        qs = qs.filter(title__icontains=name.strip())
    rows = list(qs.order_by("-updated_at")[:MAX_CANDIDATES])
    if not rows:
        return _ok({"matches": [], "note": "Nessun piano alimentare trovato con questo nome."})
    return _ok({"matches": [{
        "plan_id": p.id,
        "title": p.title,
        "mode": "macronutrienti" if p.plan_mode == "MACRO" else "alimenti",
        "kind": "settimanale" if p.plan_kind == "WEEKLY" else "giornaliero",
        "kcal": p.daily_kcal,
    } for p in rows]})


@tool("find_check_template")
def find_check_template(name: str, config: RunnableConfig) -> str:
    """Trova un TEMPLATE DI CHECK del coach dal titolo (anche parziale) e ne ritorna
    il template_id. Chiamalo PRIMA di proporre `assign_check`.
    Se restituisce più risultati, chiedi all'utente quale prima di procedere."""
    from domain.checks.models import QuestionnaireTemplate
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    qs = QuestionnaireTemplate.objects.filter(coach=coach, is_active=True)
    if (name or "").strip():
        qs = qs.filter(title__icontains=name.strip())
    rows = list(qs.order_by("-updated_at")[:MAX_CANDIDATES])
    if not rows:
        return _ok({"matches": [], "note": "Nessun check trovato con questo nome."})
    return _ok({"matches": [{
        "template_id": t.id,
        "title": t.title,
        "questions": len(t.questions_config or []),
    } for t in rows]})


@tool("propose_action")
def propose_action(
    action_type: Literal[
        "mark_check_reviewed", "save_check_feedback", "send_message",
        "assign_workout_plan", "assign_nutrition_plan", "assign_check",
        "schedule_appointment",
    ],
    client_id: int,
    config: RunnableConfig,
    feedback: str = "",
    message: str = "",
    plan_id: int = 0,
    template_id: int = 0,
    duration_value: int = 0,
    duration_unit: str = "",
    recurrence_type: str = "",
    weekly_day: int = -1,
    monthly_day: int = 0,
    duration_hours: int = 0,
    start_datetime: str = "",
    title: str = "",
    duration_minutes: int = 0,
) -> str:
    """Propone un'azione che MODIFICA i dati. NON viene eseguita: il coach la deve
    confermare con un click. Usala quando l'utente chiede di compiere un'azione.

    - mark_check_reviewed: segna l'ultimo check dell'atleta come revisionato
    - save_check_feedback: salva un feedback sull'ultimo check (scrivi il testo in
      `feedback`, basandoti su summarize_check)
    - send_message: invia un messaggio in chat all'atleta (testo esatto in `message`)
    - assign_workout_plan: assegna una scheda. Serve `plan_id` (vedi
      find_workout_plan); opzionali `duration_value` + `duration_unit` (WEEKS|MONTHS)
    - assign_nutrition_plan: assegna un piano alimentare. Serve `plan_id` (vedi
      find_nutrition_plan); opzionali `duration_value` + `duration_unit`
    - assign_check: assegna un check. Serve `template_id` (vedi find_check_template);
      opzionali `recurrence_type` (once|weekly|monthly|end_program), `weekly_day`
      (0=lunedì … 6=domenica), `monthly_day` (1-31), `duration_hours`
    - schedule_appointment: fissa un appuntamento. Serve `start_datetime` in ISO
      (es. "2026-03-12T18:00"); opzionali `title`, `duration_minutes`

    Richiede SEMPRE client_id (vedi find_athlete). Non indovinare mai un id: se non
    l'hai ottenuto da un tool di ricerca, cercalo prima."""
    from chiron.actions import build_proposal
    coach = _coach_from_config(config)
    if not coach:
        return _err("Contesto coach mancante.")
    proposal, error = build_proposal(
        coach, action_type, client_id,
        feedback=feedback or None,
        message=message or None,
        plan_id=plan_id or None,
        template_id=template_id or None,
        duration_value=duration_value or None,
        duration_unit=duration_unit or None,
        recurrence_type=recurrence_type or None,
        weekly_day=weekly_day if weekly_day >= 0 else None,
        monthly_day=monthly_day or None,
        duration_hours=duration_hours or None,
        start_datetime=start_datetime or None,
        title=title or None,
        duration_minutes=duration_minutes or None,
    )
    if error:
        return _err(error)
    # "confirm" viene raccolto dall'agente in pending_action; NON è un link diretto.
    return _ok({"confirm": proposal, "note": proposal["description"]})


def get_coach_tools() -> list:
    return [
        find_athlete, app_action, athlete_snapshot, query_roster, summarize_check,
        find_workout_plan, find_nutrition_plan, find_check_template,
        propose_action,
    ]
