"""Azioni eseguibili di CHIRON — pattern propose → confirm → execute.

Sicurezza: il modello LLM NON muta MAI nulla. Propone soltanto (`build_proposal`).
La mutazione avviene server-side (`execute_action`) DOPO conferma esplicita del
coach, ri-validando l'intero scope: il descrittore che arriva dal client non è
mai fidato, quindi client, piani, template e check vengono ri-risolti vincolati
al coach in sessione. Un `plan_id` di un altro coach non è un errore da segnalare
al modello: è un tentativo di accesso che deve semplicemente fallire.

Azioni:
- mark_check_reviewed     ultimo check COMPLETED dell'atleta → REVIEWED
- save_check_feedback     salva coach_feedback sull'ultimo check (+ REVIEWED)
- send_message            invia un messaggio in chat all'atleta
- assign_workout_plan     assegna una scheda
- assign_nutrition_plan   assegna un piano alimentare
- assign_check            assegna un check (con ricorrenza)
- schedule_appointment    fissa un appuntamento in agenda

Le mutazioni vere stanno in `domain/coaching/assignment_services.py`, condivise
con il resto dell'app: CHIRON non è un percorso privilegiato.
"""

import logging
from datetime import datetime

logger = logging.getLogger(__name__)

ACTION_TYPES = (
    'mark_check_reviewed',
    'save_check_feedback',
    'send_message',
    'assign_workout_plan',
    'assign_nutrition_plan',
    'assign_check',
    'schedule_appointment',
)

_RECURRENCE_LABELS = {
    'once': 'Una volta sola',
    'weekly': 'Ogni settimana',
    'monthly': 'Ogni mese',
    'end_program': 'A fine programma',
}

_WEEKDAYS = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica']


def _latest_check(coach, client):
    from domain.checks.models import QuestionnaireResponse
    return (
        QuestionnaireResponse.objects
        .filter(coach=coach, client=client, status__in=["COMPLETED", "REVIEWED"])
        .order_by("-submitted_at").first()
    )


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _parse_dt(value):
    """Accetta ISO 8601 (con o senza secondi), com'è prodotto da <input datetime-local>."""
    if isinstance(value, datetime):
        return value
    text = (value or '').strip().replace('Z', '+00:00')
    if not text:
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Scope resolution — usato sia in propose sia in execute
# ---------------------------------------------------------------------------

def _workout_plan_in_scope(coach, plan_id):
    from domain.workouts.models import WorkoutPlan
    return WorkoutPlan.objects.filter(id=plan_id, coach=coach).first()


def _nutrition_plan_in_scope(coach, plan_id):
    from domain.nutrition.models import NutritionPlan
    return NutritionPlan.objects.filter(id=plan_id, coach=coach).first()


def _check_template_in_scope(coach, template_id):
    from domain.checks.models import QuestionnaireTemplate
    return QuestionnaireTemplate.objects.filter(id=template_id, coach=coach).first()


# ---------------------------------------------------------------------------
# Propose
# ---------------------------------------------------------------------------

def build_proposal(coach, action_type, client_id, **params):
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

    builder = _BUILDERS.get(action_type)
    return builder(coach, client, name, params)


def _build_send_message(coach, client, name, params):
    text = (params.get('message') or '').strip()
    if not text:
        return None, "Manca il testo del messaggio da inviare."
    return {
        'action_type': 'send_message',
        'client_id': client.id,
        'title': f'Inviare il messaggio a {name}?',
        'description': (
            f'Il messaggio verrà inviato nella chat con {name}, che riceverà una '
            f'notifica. Puoi modificarlo prima di inviare.'
        ),
        'payload': {'message': text[:2000]},
        'fields': [{
            'key': 'message', 'label': f'Messaggio per {name}',
            'type': 'textarea', 'value': text[:2000],
        }],
    }, None


def _build_mark_check_reviewed(coach, client, name, params):
    check = _latest_check(coach, client)
    if not check:
        return None, f"{name} non ha check compilati su cui agire."
    when = check.submitted_at.strftime('%-d %b %Y') if check.submitted_at else ''
    if check.status == 'REVIEWED':
        return None, f"L'ultimo check di {name} ({when}) è già revisionato."
    return {
        'action_type': 'mark_check_reviewed',
        'client_id': client.id,
        'title': 'Segnare il check come revisionato?',
        'description': (
            f'Ultimo check di {name} del {when} → stato «revisionato». '
            f'L\'atleta riceverà una notifica.'
        ),
        'payload': {'response_id': check.id},
        'fields': [],
    }, None


def _build_save_check_feedback(coach, client, name, params):
    check = _latest_check(coach, client)
    if not check:
        return None, f"{name} non ha check compilati su cui agire."
    when = check.submitted_at.strftime('%-d %b %Y') if check.submitted_at else ''
    text = (params.get('feedback') or '').strip()
    if not text:
        return None, "Manca il testo del feedback da salvare."
    return {
        'action_type': 'save_check_feedback',
        'client_id': client.id,
        'title': 'Salvare il feedback sul check?',
        'description': (
            f'Verrà salvato come feedback sull\'ultimo check di {name} ({when}) e il '
            f'check segnato come revisionato. L\'atleta riceverà una notifica.'
        ),
        'payload': {'response_id': check.id, 'feedback': text[:4000]},
        'fields': [{
            'key': 'feedback', 'label': f'Feedback per {name}',
            'type': 'textarea', 'value': text[:4000],
        }],
    }, None


def _duration_fields(value, unit):
    return [
        {'key': 'duration_value', 'label': 'Durata', 'type': 'number', 'value': value},
        {'key': 'duration_unit', 'label': 'Unità', 'type': 'select', 'value': unit,
         'options': [{'value': 'WEEKS', 'label': 'settimane'},
                     {'value': 'MONTHS', 'label': 'mesi'}]},
    ]


def _build_assign_workout_plan(coach, client, name, params):
    plan = _workout_plan_in_scope(coach, _int(params.get('plan_id')))
    if not plan:
        return None, "Scheda non trovata tra le tue. Cercala prima con `find_workout_plan`."
    if not plan.days.filter(exercises__isnull=False).exists():
        return None, f'La scheda «{plan.title}» non contiene esercizi: non è assegnabile.'

    value = _int(params.get('duration_value')) or plan.duration_weeks or 4
    unit = params.get('duration_unit') if params.get('duration_unit') in ('WEEKS', 'MONTHS') else 'WEEKS'
    kind = 'Programmazione' if plan.plan_kind == 'PROGRAM' else 'Scheda settimanale'
    return {
        'action_type': 'assign_workout_plan',
        'client_id': client.id,
        'title': f'Assegnare «{plan.title}» a {name}?',
        'description': (
            f'{kind}. Le altre schede attive di {name} verranno chiuse e l\'atleta '
            f'riceverà una notifica e una mail.'
        ),
        'payload': {'plan_id': plan.id, 'duration_value': value, 'duration_unit': unit},
        'fields': _duration_fields(value, unit),
    }, None


def _build_assign_nutrition_plan(coach, client, name, params):
    plan = _nutrition_plan_in_scope(coach, _int(params.get('plan_id')))
    if not plan:
        return None, "Piano alimentare non trovato tra i tuoi. Cercalo prima con `find_nutrition_plan`."

    value = _int(params.get('duration_value')) or 4
    unit = params.get('duration_unit') if params.get('duration_unit') in ('WEEKS', 'MONTHS') else 'WEEKS'
    mode = 'a macronutrienti' if plan.plan_mode == 'MACRO' else 'ad alimenti'
    return {
        'action_type': 'assign_nutrition_plan',
        'client_id': client.id,
        'title': f'Assegnare «{plan.title}» a {name}?',
        'description': (
            f'Piano {mode}. Gli altri piani alimentari attivi di {name} verranno '
            f'annullati e l\'atleta riceverà una notifica e una mail.'
        ),
        'payload': {'plan_id': plan.id, 'duration_value': value, 'duration_unit': unit},
        'fields': _duration_fields(value, unit),
    }, None


def _build_assign_check(coach, client, name, params):
    template = _check_template_in_scope(coach, _int(params.get('template_id')))
    if not template:
        return None, "Check non trovato tra i tuoi. Cercalo prima con `find_check_template`."

    recurrence = params.get('recurrence_type') or 'once'
    if recurrence not in _RECURRENCE_LABELS:
        recurrence = 'once'
    weekly_day = _int(params.get('weekly_day'))
    monthly_day = _int(params.get('monthly_day'))
    if recurrence == 'weekly' and weekly_day is None:
        return None, "Per una ricorrenza settimanale indica il giorno (0=lunedì … 6=domenica)."
    if recurrence == 'monthly' and monthly_day is None:
        return None, "Per una ricorrenza mensile indica il giorno del mese (1-31)."

    if recurrence == 'weekly':
        cadence = f'ogni {_WEEKDAYS[weekly_day % 7].lower()}'
    elif recurrence == 'monthly':
        cadence = f'il {monthly_day} di ogni mese'
    elif recurrence == 'end_program':
        cadence = 'a fine programma'
    else:
        cadence = 'una volta sola, subito'

    return {
        'action_type': 'assign_check',
        'client_id': client.id,
        'title': f'Assegnare il check «{template.title}» a {name}?',
        'description': (
            f'Verrà inviato {cadence}. Le domande vengono congelate ora, così '
            f'modifiche future al template non toccano questo check.'
        ),
        'payload': {
            'template_id': template.id, 'recurrence_type': recurrence,
            'weekly_day': weekly_day, 'monthly_day': monthly_day,
            'duration_hours': _int(params.get('duration_hours')) or 72,
        },
        'fields': [
            {'key': 'recurrence_type', 'label': 'Ricorrenza', 'type': 'select',
             'value': recurrence,
             'options': [{'value': k, 'label': v} for k, v in _RECURRENCE_LABELS.items()]},
            {'key': 'duration_hours', 'label': 'Ore per compilarlo', 'type': 'number',
             'value': _int(params.get('duration_hours')) or 72},
        ],
    }, None


def _build_schedule_appointment(coach, client, name, params):
    start = _parse_dt(params.get('start_datetime'))
    if not start:
        return None, ("Manca la data/ora dell'appuntamento, o il formato non è valido "
                      "(usa ISO, es. 2026-03-12T18:00).")
    title = (params.get('title') or '').strip() or f'Consulenza con {name}'
    duration = _int(params.get('duration_minutes')) or 60
    appointment_type = params.get('appointment_type') or 'consulenza'

    return {
        'action_type': 'schedule_appointment',
        'client_id': client.id,
        'title': f'Fissare «{title}» con {name}?',
        'description': (
            f'{start.strftime("%-d/%m/%Y alle %H:%M")}, {duration} minuti. '
            f'Finirà in agenda e {name} riceverà una notifica.'
        ),
        'payload': {
            'title': title[:200],
            'start_datetime': start.isoformat(),
            'duration_minutes': duration,
            'appointment_type': appointment_type,
            'description': (params.get('description') or '')[:1000],
        },
        'fields': [
            {'key': 'title', 'label': 'Titolo', 'type': 'text', 'value': title[:200]},
            {'key': 'start_datetime', 'label': 'Quando', 'type': 'datetime-local',
             'value': start.strftime('%Y-%m-%dT%H:%M')},
            {'key': 'duration_minutes', 'label': 'Durata (min)', 'type': 'number',
             'value': duration},
        ],
    }, None


_BUILDERS = {
    'send_message': _build_send_message,
    'mark_check_reviewed': _build_mark_check_reviewed,
    'save_check_feedback': _build_save_check_feedback,
    'assign_workout_plan': _build_assign_workout_plan,
    'assign_nutrition_plan': _build_assign_nutrition_plan,
    'assign_check': _build_assign_check,
    'schedule_appointment': _build_schedule_appointment,
}


# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

def execute_action(coach, descriptor):
    """Esegue un'azione confermata ri-validando TUTTO lato server.

    Ritorna (ok: bool, message: str, action_link: dict | None).
    """
    from django.urls import reverse
    from chiron.coach_tools import _client_in_scope, _full_name

    descriptor = descriptor or {}
    action_type = descriptor.get('action_type')
    if action_type not in ACTION_TYPES:
        return False, 'Azione non valida.', None

    client = _client_in_scope(coach, descriptor.get('client_id'))
    if not client:
        return False, 'Atleta non trovato tra i tuoi clienti.', None

    name = _full_name(client)
    # Il payload arriva dal browser: campi editabili inclusi. Ogni id viene
    # ri-risolto sotto lo scope del coach, mai fidato così com'è.
    payload = descriptor.get('payload') or {}

    try:
        return _EXECUTORS[action_type](coach, client, name, payload, reverse)
    except Exception:
        logger.exception('CHIRON: esecuzione azione %s fallita', action_type)
        return False, 'Azione non riuscita.', None


def _exec_send_message(coach, client, name, payload, reverse):
    from domain.chat.models import Conversation
    from domain.chat.services import _deliver
    text = (payload.get('message') or '').strip()
    if not text:
        return False, 'Testo del messaggio mancante.', None
    _deliver(coach, client, text[:2000])
    conv = Conversation.objects.filter(coach=coach, client=client).first()
    link = ({'label': f'Apri chat — {name}',
             'url': reverse('chat_detail', args=[conv.id])} if conv else None)
    return True, f'Messaggio inviato a {name}.', link


def _resolve_check(coach, client, payload):
    from domain.checks.models import QuestionnaireResponse
    return QuestionnaireResponse.objects.filter(
        id=payload.get('response_id'), coach=coach, client=client,
    ).first()


def _exec_mark_check_reviewed(coach, client, name, payload, reverse):
    check = _resolve_check(coach, client, payload)
    if not check:
        return False, 'Check non trovato.', None
    check.status = 'REVIEWED'
    check.save(update_fields=['status', 'updated_at'])
    link = {'label': f'Apri check — {name}',
            'url': reverse('check_detail', args=[check.id])}
    _notify_reviewed(client, coach, check, link['url'])
    return True, f'Check di {name} segnato come revisionato.', link


def _exec_save_check_feedback(coach, client, name, payload, reverse):
    check = _resolve_check(coach, client, payload)
    if not check:
        return False, 'Check non trovato.', None
    text = (payload.get('feedback') or '').strip()
    if not text:
        return False, 'Testo del feedback mancante.', None
    check.coach_feedback = text[:4000]
    check.status = 'REVIEWED'
    check.save(update_fields=['coach_feedback', 'status', 'updated_at'])
    link = {'label': f'Apri check — {name}',
            'url': reverse('check_detail', args=[check.id])}
    _notify_reviewed(client, coach, check, link['url'])
    return True, f'Feedback salvato sul check di {name}.', link


def _exec_assign_workout_plan(coach, client, name, payload, reverse):
    from domain.coaching.assignment_services import assign_workout_plan, AssignmentError
    plan = _workout_plan_in_scope(coach, _int(payload.get('plan_id')))
    if not plan:
        return False, 'Scheda non trovata.', None
    try:
        assign_workout_plan(
            coach, plan, client,
            duration_value=_int(payload.get('duration_value')) or 4,
            duration_unit=payload.get('duration_unit') or 'WEEKS',
        )
    except AssignmentError as exc:
        return False, str(exc), None
    return True, f'Scheda «{plan.title}» assegnata a {name}.', {
        'label': f'Apri scheda cliente — {name}',
        'url': reverse('clienti_detail', args=[client.id]),
    }


def _exec_assign_nutrition_plan(coach, client, name, payload, reverse):
    from domain.coaching.assignment_services import assign_nutrition_plan, AssignmentError
    plan = _nutrition_plan_in_scope(coach, _int(payload.get('plan_id')))
    if not plan:
        return False, 'Piano alimentare non trovato.', None
    try:
        assignment = assign_nutrition_plan(
            coach, plan, client,
            duration_value=_int(payload.get('duration_value')) or 4,
            duration_unit=payload.get('duration_unit') or 'WEEKS',
        )
    except AssignmentError as exc:
        return False, str(exc), None
    return True, f'Piano «{plan.title}» assegnato a {name}.', {
        'label': f'Apri piano — {name}',
        'url': f'/nutrizione/dettaglio/{assignment.id}/',
    }


def _exec_assign_check(coach, client, name, payload, reverse):
    from domain.coaching.assignment_services import assign_check, AssignmentError
    template = _check_template_in_scope(coach, _int(payload.get('template_id')))
    if not template:
        return False, 'Check non trovato.', None
    try:
        assign_check(
            coach, template, client,
            recurrence_type=payload.get('recurrence_type') or 'once',
            weekly_day=_int(payload.get('weekly_day')),
            monthly_day=_int(payload.get('monthly_day')),
            duration_hours=_int(payload.get('duration_hours')) or 72,
        )
    except AssignmentError as exc:
        return False, str(exc), None
    return True, f'Check «{template.title}» assegnato a {name}.', {
        'label': 'Apri dashboard check',
        'url': reverse('check_dashboard'),
    }


def _exec_schedule_appointment(coach, client, name, payload, reverse):
    from domain.coaching.assignment_services import create_appointment, AssignmentError
    start = _parse_dt(payload.get('start_datetime'))
    if not start:
        return False, "Data e ora dell'appuntamento mancanti o non valide.", None
    try:
        create_appointment(
            coach, client,
            title=payload.get('title') or f'Consulenza con {name}',
            start_datetime=start,
            appointment_type=payload.get('appointment_type') or 'consulenza',
            duration_minutes=_int(payload.get('duration_minutes')) or 60,
            description=payload.get('description') or '',
        )
    except AssignmentError as exc:
        return False, str(exc), None
    return True, (f'Appuntamento con {name} fissato per il '
                  f'{start.strftime("%-d/%m alle %H:%M")}.'), {
        'label': 'Apri agenda', 'url': reverse('agenda_dashboard'),
    }


_EXECUTORS = {
    'send_message': _exec_send_message,
    'mark_check_reviewed': _exec_mark_check_reviewed,
    'save_check_feedback': _exec_save_check_feedback,
    'assign_workout_plan': _exec_assign_workout_plan,
    'assign_nutrition_plan': _exec_assign_nutrition_plan,
    'assign_check': _exec_assign_check,
    'schedule_appointment': _exec_schedule_appointment,
}


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
