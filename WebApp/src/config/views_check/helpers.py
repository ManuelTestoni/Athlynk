"""Helper condivisi del dominio check: misure antropometriche,
sezioni di render, delta e prefill."""

from django.shortcuts import render, redirect
from django.http import JsonResponse, HttpResponse
from django.core.paginator import Paginator
from django.utils import timezone
from django.db.models import Q, Count, OuterRef, Subquery
from django.core.files.storage import default_storage
from django.utils.dateparse import parse_datetime
from django.core.mail import send_mail
from django.conf import settings
import json
from datetime import timedelta, datetime, time

from domain.checks.models import QuestionnaireTemplate, QuestionnaireResponse, ProgressPhoto, AssignedCheck, AssignedCheckInstance, QuestionAttachment, CheckFolder
from domain.checks.preset_templates import PRESETS, build_template_payload
from domain.checks.anthropometry import (
    circ_label, skin_label, order_circ_keys, order_skin_keys, catalog_json,
    circ_pad, skin_pad, WEIGHT_PAD, WEIGHT_RANGE, circ_range, skin_range,
)
from domain.coaching.models import CoachingRelationship
from domain.accounts.models import ClientProfile
from domain.chat.models import Notification
from ..services.images import to_webp, is_image

try:
    from domain.calendar.models import Appointment
except ImportError:
    from domain.appointments.models import Appointment  # type: ignore[no-redef]

from ..session_utils import get_session_user, get_session_coach, get_session_client, get_active_relationship



RESERVED_FIELD_MAP = {
    'peso_corporeo':    ('weight_kg', None),
    'circ_spalle':      ('body_circumferences', 'shoulders'),
    'circ_petto':       ('body_circumferences', 'chest'),
    'circ_vita':        ('body_circumferences', 'waist'),
    'circ_fianchi':     ('body_circumferences', 'hips'),
    'circ_coscia':      ('body_circumferences', 'thigh_right'),
    'circ_braccio':     ('body_circumferences', 'arm_right'),
    'pl_petto':         ('skinfolds', 'chest'),
    'pl_addome':        ('skinfolds', 'abdomen'),
    'pl_coscia':        ('skinfolds', 'thigh'),
    'pl_tricipite':     ('skinfolds', 'tricep'),
    'note_messaggio':   ('notes', None),
    'note_infortuni':   ('injuries', None),
    'note_limitazioni': ('limitations', None),
}


def _get_q_value(q_id, resp):
    if not resp:
        return None
    if q_id in RESERVED_FIELD_MAP:
        field, key = RESERVED_FIELD_MAP[q_id]
        val = getattr(resp, field, None)
        if key:
            if not isinstance(val, dict):
                return None
            v = val.get(key)
            return v if v not in ('', None) else None
        return val if val not in ('', None) else None
    aj = resp.answers_json or {}
    v = aj.get(q_id)
    return v if v not in ('', None) else None


def _to_float(val):
    try:
        v = float(val or 0)
        return v or None
    except (ValueError, TypeError):
        return None


# Chiavi answers_json gestite dallo strumento «Calcolo Fabbisogni».
FB_TOOL_KEYS = [
    'altezza_cm', 'peso_kg', 'eta_anni', 'sesso', 'formula_mb', 'mb_stimata_kcal',
    'pal_valore', 'pal_descrizione', 'det_kcal', 'det_adjust_kcal', 'det_finale_kcal',
    'det_note', 'proteine_gkg', 'proteine_g_totale', 'proteine_note',
    'carboidrati_gkg', 'carboidrati_g_totale', 'carboidrati_note',
    'lipidi_target', 'lipidi_g_totale', 'lipidi_note',
    'fibra_gdie', 'fibra_note', 'idrico_mldie', 'idrico_criterio',
    'micronutrienti_critici', 'note_operative',
]

_FB_MACRO_DEFS = [
    ('Proteine',    'proteine_gkg',    'proteine_g_totale',    'proteine_note',    4),
    ('Carboidrati', 'carboidrati_gkg', 'carboidrati_g_totale', 'carboidrati_note', 4),
    ('Lipidi',      'lipidi_target',   'lipidi_g_totale',      'lipidi_note',      9),
]


def _fabbisogni_summary(q, response):
    """Riepilogo leggibile dello strumento «Calcolo Fabbisogni» da answers_json.
    Ritorna None se non ci sono dati significativi da mostrare."""
    aj = (response.answers_json or {}) if response else {}

    def g(k):
        v = aj.get(k)
        return v if v not in (None, '') else None

    def gi(k):
        v = _to_float(aj.get(k))
        return int(round(v)) if v else None

    det_base = gi('det_kcal')
    try:
        det_adj = int(round(float(aj.get('det_adjust_kcal') or 0)))
    except (TypeError, ValueError):
        det_adj = 0
    det_finale = gi('det_finale_kcal') or ((det_base + det_adj) if det_base else None)

    macros = []
    for label, gkg_k, g_k, note_k, factor in _FB_MACRO_DEFS:
        grams = gi(g_k)
        if grams or g(gkg_k) or g(note_k):
            macros.append({
                'label': label, 'gkg': g(gkg_k), 'g': grams,
                'kcal': int(round(grams * factor)) if grams else None,
                'note': g(note_k),
            })

    fb = {
        'altezza': g('altezza_cm'), 'peso': g('peso_kg'), 'eta': g('eta_anni'), 'sesso': g('sesso'),
        'formula': g('formula_mb'), 'mb': gi('mb_stimata_kcal'),
        'pal': g('pal_valore'), 'pal_desc': g('pal_descrizione'),
        'det_base': det_base, 'det_adjust': det_adj, 'det_finale': det_finale, 'det_note': g('det_note'),
        'macros': macros,
        'fibra': g('fibra_gdie'), 'fibra_note': g('fibra_note'),
        'idrico': g('idrico_mldie'), 'idrico_note': g('idrico_criterio'),
        'micro': g('micronutrienti_critici'), 'note_op': g('note_operative'),
    }
    has_data = bool(macros) or any(v for k, v in fb.items() if k != 'det_adjust' and v)
    if not has_data:
        return None
    return {'id': q.get('id'), 'type': 'strumento_fabbisogni',
            'label': q.get('label', 'Calcolo Fabbisogni'), 'fb': fb}


def build_measurements(raw_answers, questions_config, parse_fn):
    """Build (weight_kg, body_circumferences, skinfolds) from submitted answers.

    Template-driven: handles both legacy `metrica` antropometric questions (via
    RESERVED_FIELD_MAP) and the composite `antropometria` type. `parse_fn`
    normalizes a single metric value to its stored string form.
    """
    weight_kg = None
    circ, skin = {}, {}
    for q in (questions_config or []):
        qid = q.get('id')
        qtype = q.get('type')
        if qtype == 'antropometria':
            if q.get('weight'):
                w = _to_float(raw_answers.get('peso_corporeo'))
                if w:
                    weight_kg = w
            for key in q.get('circumferences') or []:
                circ[key] = parse_fn(raw_answers.get('circ::' + key))
            for key in q.get('skinfolds') or []:
                skin[key] = parse_fn(raw_answers.get('pl::' + key))
        elif qtype == 'metrica' and qid in RESERVED_FIELD_MAP:
            field, sub = RESERVED_FIELD_MAP[qid]
            val = raw_answers.get(qid)
            if field == 'weight_kg':
                w = _to_float(val)
                if w:
                    weight_kg = w
            elif field == 'body_circumferences':
                circ[sub] = parse_fn(val)
            elif field == 'skinfolds':
                skin[sub] = parse_fn(val)
    return weight_kg, circ, skin


def _measure_row(label, unit, val, prev):
    delta = None
    try:
        if prev not in (None, ''):
            delta = round(float(val) - float(prev), 1)
    except (ValueError, TypeError):
        delta = None
    return {'type': 'metrica', 'label': label, 'unit': unit,
            'value': val, 'previous': prev, 'delta': delta}


def _antropometria_rows(q, response, prev_response):
    """Expand a composite `antropometria` question into ordered metrica-style
    rows (weight → circonferenze → pliche) so detail.html renders them as usual."""
    rows = []
    if q.get('weight'):
        val = response.weight_kg
        if val not in (None, ''):
            prev = prev_response.weight_kg if prev_response else None
            rows.append({**_measure_row('Peso corporeo', 'kg', val, prev), 'id': 'peso_corporeo'})
    curr_c = response.body_circumferences or {}
    prev_c = (prev_response.body_circumferences or {}) if prev_response else {}
    q_circ = q.get('circumferences') or []
    done = set()
    for key in q_circ:
        if key in done:
            continue
        # Arto con entrambi i lati nella domanda → riga doppia (DX | SX).
        if key[-2:] in ('_l', '_r'):
            base = key[:-2]
            rkey, lkey = base + '_r', base + '_l'
            if rkey in q_circ and lkey in q_circ:
                done.update((rkey, lkey))
                rv, lv = curr_c.get(rkey), curr_c.get(lkey)
                has_r, has_l = rv not in (None, ''), lv not in (None, '')
                if has_r and has_l:
                    r = _measure_row('', 'cm', rv, prev_c.get(rkey)); r['tag'] = 'DX'
                    l = _measure_row('', 'cm', lv, prev_c.get(lkey)); l['tag'] = 'SX'
                    rows.append({'type': 'metrica_pair', 'id': 'circ::' + base,
                                 'label': circ_label(base), 'unit': 'cm', 'sides': [r, l]})
                    continue
                # un solo lato compilato → riga singola per quel lato
                side = rkey if has_r else lkey
                if has_r or has_l:
                    rows.append({**_measure_row(circ_label(side), 'cm', curr_c.get(side), prev_c.get(side)), 'id': 'circ::' + side})
                continue
        val = curr_c.get(key)
        if val in (None, ''):
            continue
        rows.append({**_measure_row(circ_label(key), 'cm', val, prev_c.get(key)), 'id': 'circ::' + key})
    curr_s = response.skinfolds or {}
    prev_s = (prev_response.skinfolds or {}) if prev_response else {}
    for key in q.get('skinfolds') or []:
        val = curr_s.get(key)
        if val in (None, ''):
            continue
        rows.append({**_measure_row(skin_label(key), 'mm', val, prev_s.get(key)), 'id': 'pl::' + key})
    return rows


def _collect_measurement_keys(responses):
    present_circ, present_skin = set(), set()
    for r in responses:
        for k, v in (r['body_circumferences'] or {}).items():
            if v not in (None, ''):
                present_circ.add(k)
        for k, v in (r['skinfolds'] or {}).items():
            if v not in (None, ''):
                present_skin.add(k)
    return order_circ_keys(present_circ), order_skin_keys(present_skin)


def _build_chart_data(target_client):
    """Time-series chart data, dynamic over the measurements actually stored
    for the athlete (ordered per ISAK catalog; legacy keys kept in tail)."""
    responses = list(
        QuestionnaireResponse.objects.filter(client=target_client)
        .order_by('submitted_at')
        .values('submitted_at', 'weight_kg', 'body_circumferences', 'skinfolds')
    )
    circ_keys, skin_keys = _collect_measurement_keys(responses)
    labels, dates, weight = [], [], []
    chart_circ = {k: [] for k in circ_keys}
    chart_skin = {k: [] for k in skin_keys}
    for r in responses:
        labels.append(r['submitted_at'].strftime('%d/%m/%Y'))
        dates.append(r['submitted_at'].strftime('%Y-%m-%d'))
        weight.append(float(r['weight_kg']) if r['weight_kg'] else None)
        circ = r['body_circumferences'] or {}
        for k in circ_keys:
            v = circ.get(k)
            chart_circ[k].append(float(v) if v else None)
        skin = r['skinfolds'] or {}
        for k in skin_keys:
            v = skin.get(k)
            chart_skin[k].append(float(v) if v else None)
    return {
        'labels': labels,
        # ISO dates (YYYY-MM-DD) — used by check_progress.js to aggregate the
        # raw per-check series into weekly means and homologous month-weeks.
        'dates': dates,
        'weight': weight,
        'circumferences': chart_circ,
        'skinfolds': chart_skin,
        'circ_keys': circ_keys,
        'skin_keys': skin_keys,
        'circ_labels': {k: circ_label(k) for k in circ_keys},
        'skin_labels': {k: skin_label(k) for k in skin_keys},
        # Semi-ampiezza asse Y per ogni metrica (grafici: niente partenza da 0).
        'weight_pad': WEIGHT_PAD,
        'circ_pad': {k: circ_pad(k) for k in circ_keys},
        'skin_pad': {k: skin_pad(k) for k in skin_keys},
    }


def _response_config(response):
    """(questions, steps) per il render di una risposta: preferisce lo snapshot
    salvato alla compilazione, fallback alla config live del template."""
    template = response.questionnaire_template
    questions = response.questions_snapshot
    if questions is None:
        questions = (template.questions_config or []) if template else []
    steps = response.steps_snapshot
    if not steps:
        steps = (template.steps_config or []) if template else []
    return list(questions or []), list(steps or [])


def _build_check_sections(questions, steps, response, prev_response, attachments_by_q):
    if not steps:
        steps = [{'id': '__solo', 'label': 'Check', 'icon': 'ph-clipboard-text'}]

    fallback_sid = steps[0].get('id')
    sections = []
    for step in steps:
        sid = step.get('id')
        step_qs = [q for q in questions if (q.get('step_id') or fallback_sid) == sid]
        rendered = []
        for q in step_qs:
            q_id = q.get('id')
            q_type = q.get('type', 'aperta')

            if q_type == 'allegato':
                files = attachments_by_q.get(q_id, [])
                if not files:
                    continue
                rendered.append({
                    'id': q_id, 'type': 'allegato',
                    'label': q.get('label', 'Allegato'),
                    'files': files,
                })
                continue

            if q_type == 'antropometria':
                rendered.extend(_antropometria_rows(q, response, prev_response))
                continue

            if q_type == 'strumento_fabbisogni':
                summary = _fabbisogni_summary(q, response)
                if summary:
                    rendered.append(summary)
                continue

            val = _get_q_value(q_id, response)
            if val in (None, '') or val == []:
                continue
            # checkbox: lista di opzioni → stringa leggibile (il template
            # altrimenti stamperebbe la repr Python della lista)
            if isinstance(val, list):
                val = ', '.join(str(v) for v in val)

            prev_val = _get_q_value(q_id, prev_response)
            if isinstance(prev_val, list):
                prev_val = ', '.join(str(v) for v in prev_val)
            delta = None
            if q_type in ('metrica', 'range', 'media'):
                try:
                    if prev_val not in (None, ''):
                        delta = round(float(val) - float(prev_val), 1)
                except (ValueError, TypeError):
                    delta = None

            rendered.append({
                'id': q_id,
                'type': q_type,
                'label': q.get('label', q_id),
                'unit': q.get('unit'),
                'value': val,
                'previous': prev_val,
                'delta': delta,
                'options': q.get('options'),
                'min': q.get('min'),
                'max': q.get('max'),
                'min_label': q.get('minLabel'),
                'max_label': q.get('maxLabel'),
                'range_min': q.get('rangeMin'),
                'range_max': q.get('rangeMax'),
            })

        if rendered:
            sections.append({
                'id': sid,
                'label': step.get('label', 'Sezione'),
                'icon': step.get('icon') or 'ph-list',
                'questions': rendered,
            })
    return sections


def _has_allegato_questions(questions):
    return any(q.get('type') == 'allegato' for q in (questions or []))


def _dict_deltas(curr, prev):
    curr = curr or {}
    prev = prev or {}
    out = {}
    for key in curr:
        try:
            if curr.get(key) and prev.get(key):
                out[key] = round(float(curr[key]) - float(prev[key]), 1)
            else:
                out[key] = None
        except (ValueError, TypeError):
            out[key] = None
    return out


def _compute_deltas(current_response, prev_response):
    weight_delta = None
    if prev_response and current_response.weight_kg and prev_response.weight_kg:
        weight_delta = float(current_response.weight_kg) - float(prev_response.weight_kg)

    prev_circ = prev_response.body_circumferences if prev_response else None
    prev_sf = prev_response.skinfolds if prev_response else None
    circ_deltas = _dict_deltas(current_response.body_circumferences, prev_circ)
    skinfold_deltas = _dict_deltas(current_response.skinfolds, prev_sf)
    return weight_delta, circ_deltas, skinfold_deltas


_BENESSERE_ALIASES = {
    'benessere_umore':   'mood',
    'benessere_dieta':   'diet_adherence',
    'benessere_workout': 'workout_adherence',
}


_NOTE_FIELD_MAP = {
    'note_messaggio':   'notes',
    'note_infortuni':   'injuries',
    'note_limitazioni': 'limitations',
}


def _build_prefill(response):
    """Reverse a stored response back into raw_answers form (keyed as the
    builder expects) so the coach edit form renders pre-filled. Walks the
    template's questions_config — the source of truth for what's rendered.
    Attachments are not re-editable here, so `allegato` is skipped."""
    questions_cfg, _ = _response_config(response)
    aj = response.answers_json or {}
    circ = response.body_circumferences or {}
    skin = response.skinfolds or {}
    prefill = {}
    for q in questions_cfg:
        qid = q.get('id')
        qtype = q.get('type')
        if qtype == 'antropometria':
            if q.get('weight') and response.weight_kg not in (None, ''):
                prefill['peso_corporeo'] = float(response.weight_kg)
            for key in q.get('circumferences') or []:
                v = circ.get(key)
                if v not in (None, ''):
                    prefill['circ::' + key] = v
            for key in q.get('skinfolds') or []:
                v = skin.get(key)
                if v not in (None, ''):
                    prefill['pl::' + key] = v
            continue
        if qtype == 'allegato':
            continue
        if qtype == 'strumento_fabbisogni':
            # Lo strumento salva chiavi piatte in answers_json: ricaricale tutte
            # così la ricompilazione coach riparte dai valori salvati.
            for k in FB_TOOL_KEYS:
                v = aj.get(k)
                if v not in (None, ''):
                    prefill[k] = v
            continue
        if qid in _BENESSERE_ALIASES:
            v = aj.get(qid, aj.get(_BENESSERE_ALIASES[qid]))
        elif qid in _NOTE_FIELD_MAP:
            v = getattr(response, _NOTE_FIELD_MAP[qid], None)
        elif qid in RESERVED_FIELD_MAP:
            v = _get_q_value(qid, response)
        else:
            v = aj.get(qid)
        if v not in (None, ''):
            prefill[qid] = v
    return prefill


# ---------------------------------------------------------------------------
# Misurazione singola ("pesata/circonferenza/plica del giorno X")
# ---------------------------------------------------------------------------
# Una misura singola viene salvata come una QuestionnaireResponse "leggera" sotto
# un template sintetico per-coach, così compare automaticamente nel grafico di
# andamento, negli eventi de "Il mio percorso" e nello storico check, senza nuovi
# percorsi di lettura. Snapshot single-metric → il dettaglio la renderizza come
# un normale check antropometrico con la sola voce compilata.

QUICK_MEASUREMENT_TYPE = 'quick_measurement'
QUICK_MEASUREMENT_TITLE = 'Misurazione rapida'


def quick_measurement_template(coach):
    """Template sintetico (uno per coach) che ancora le misurazioni singole."""
    template, _ = QuestionnaireTemplate.objects.get_or_create(
        coach=coach,
        questionnaire_type=QUICK_MEASUREMENT_TYPE,
        defaults={
            'title': QUICK_MEASUREMENT_TITLE,
            'description': 'Misurazioni singole inserite manualmente.',
            'questions_config': [],
            'steps_config': [],
            'is_active': True,
        },
    )
    return template


class QuickMeasurementError(ValueError):
    """Input non valido per una misurazione singola (messaggio mostrabile)."""


def create_quick_measurement(coach, client, mtype, key, value, day):
    """Crea una QuestionnaireResponse per una singola misura del giorno `day`.

    mtype: 'weight' | 'circumference' | 'skinfold'
    key:   chiave ISAK memorizzata (ignorata per 'weight')
    value: numero (kg / cm / mm)
    day:   datetime.date della misurazione

    Solleva QuickMeasurementError per input fuori range o chiave ignota.
    """
    try:
        val = float(value)
    except (TypeError, ValueError):
        raise QuickMeasurementError('Valore non valido.')
    if val <= 0:
        raise QuickMeasurementError('Inserisci un valore maggiore di zero.')

    if day is None:
        raise QuickMeasurementError('Data mancante.')
    if day > timezone.localdate():
        raise QuickMeasurementError('La data non può essere nel futuro.')

    weight_kg = None
    body_circumferences = {}
    skinfolds = {}
    snapshot_q = {'id': 'antropometria', 'type': 'antropometria', 'label': 'Misura',
                  'step_id': '__solo', 'weight': False, 'circumferences': [], 'skinfolds': []}

    if mtype == 'weight':
        lo, hi = WEIGHT_RANGE
        if not (lo <= val <= hi):
            raise QuickMeasurementError(f'Il peso deve essere tra {lo:g} e {hi:g} kg.')
        weight_kg = round(val, 1)
        snapshot_q['weight'] = True
    elif mtype == 'circumference':
        rng = circ_range(key)
        if rng is None:
            raise QuickMeasurementError('Circonferenza sconosciuta.')
        lo, hi = rng
        if not (lo <= val <= hi):
            raise QuickMeasurementError(f'{circ_label(key)} deve essere tra {lo:g} e {hi:g} cm.')
        body_circumferences[key] = str(round(val, 1))
        snapshot_q['circumferences'] = [key]
    elif mtype == 'skinfold':
        rng = skin_range(key)
        lo, hi = rng
        if not (lo <= val <= hi):
            raise QuickMeasurementError(f'{skin_label(key)} deve essere tra {lo:g} e {hi:g} mm.')
        skinfolds[key] = str(round(val, 1))
        snapshot_q['skinfolds'] = [key]
    else:
        raise QuickMeasurementError('Tipo di misura non valido.')

    # Mezzogiorno locale per ancorare la serie temporale del grafico al giorno X.
    naive = datetime.combine(day, time(12, 0))
    submitted_at = timezone.make_aware(naive) if settings.USE_TZ else naive

    return QuestionnaireResponse.objects.create(
        questionnaire_template=quick_measurement_template(coach),
        client=client,
        coach=coach,
        submitted_at=submitted_at,
        status='REVIEWED',
        weight_kg=weight_kg,
        body_circumferences=body_circumferences,
        skinfolds=skinfolds,
        answers_json={},
        questions_snapshot=[snapshot_q],
        steps_snapshot=[{'id': '__solo', 'label': QUICK_MEASUREMENT_TITLE, 'icon': 'ph-ruler'}],
    )
