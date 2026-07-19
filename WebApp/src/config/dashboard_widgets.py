"""Customizable dashboard: widget registry, role defaults, layout validation.

Single source of truth for the WordPress-style dashboard on BOTH surfaces:
the web grid (GridStack, 12 columns) and the iOS apps (ordered list). The
canonical layout lives in ``User.dashboard_layout`` (JSONField):

    {"version": 1,
     "widgets": [{"id": "wg_x1", "type": "recent_clients",
                  "x": 0, "y": 0, "size": "M", "config": {}}]}

Contract:
- Array order == canonical cross-platform order (web saves sorted by (y, x)).
- ``x``/``y`` are web-grid hints; iOS ignores them and renders array order.
- ``size`` is one of the registry-allowed labels (S/M/L); the registry maps
  it to grid (w, h) so clients can never store arbitrary dimensions.
- One instance per widget type (v1); ``id`` future-proofs multi-instance.

Every write goes through ``validate_and_save_layout`` which is the ONLY
invalidation path for both web and mobile endpoints — this is what prevents
the historical cross-surface stale-cache bug.
"""

import re

from django.core.cache import cache

from .services import cachekeys

SCHEMA_VERSION = 1
MAX_WIDGETS = 20
_ID_RE = re.compile(r'^[a-zA-Z0-9_-]{1,32}$')

# Grid geometry per size label: {label: (w, h)} in 12-column GridStack units.
# Each widget lists the labels it supports; 'default_size' must be one of them.
WIDGET_REGISTRY = {
    # --- COACH ---------------------------------------------------------------
    'recent_clients': {
        'title': 'Atleti recenti',
        'desc': 'Gli ultimi atleti registrati nel tuo studio.',
        'icon': 'ph-users',
        'sf_symbol': 'person.2',
        'roles': {'COACH'},
        'sizes': {'M': (8, 4), 'L': (12, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'subscription_plans': {
        'title': 'Piani attivi',
        'desc': 'I tuoi piani di abbonamento in vendita.',
        'icon': 'ph-credit-card',
        'sf_symbol': 'creditcard',
        'roles': {'COACH'},
        'sizes': {'S': (4, 4), 'M': (6, 4)},
        'default_size': 'S',
        'mobile_size': 'full',
    },
    'pinned_athletes': {
        'title': 'Atleti in evidenza',
        'desc': 'Tieni sotto controllo gli atleti che scegli tu.',
        'icon': 'ph-push-pin',
        'sf_symbol': 'pin',
        'roles': {'COACH'},
        'sizes': {'M': (6, 4), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
        'config_schema': {'client_ids': {'type': 'int_list', 'max_len': 6}},
    },
    'agenda_today': {
        'title': 'Agenda di oggi',
        'desc': 'Gli appuntamenti in programma per oggi.',
        'icon': 'ph-calendar-check',
        'sf_symbol': 'calendar',
        'roles': {'COACH'},
        'sizes': {'S': (4, 4), 'M': (6, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'pending_checks': {
        'title': 'Check da rivedere',
        'desc': 'I check inviati dagli atleti in attesa di revisione.',
        'icon': 'ph-clipboard-text',
        'sf_symbol': 'checklist',
        'roles': {'COACH'},
        'sizes': {'S': (4, 4), 'M': (6, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'activity_feed': {
        'title': 'Attività recente',
        'desc': 'Le ultime novità dai tuoi atleti.',
        'icon': 'ph-pulse',
        'sf_symbol': 'waveform.path.ecg',
        'roles': {'COACH'},
        'sizes': {'M': (6, 5), 'L': (12, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'unread_messages': {
        'title': 'Messaggi non letti',
        'desc': 'Quante conversazioni aspettano una risposta.',
        'icon': 'ph-chat-circle-text',
        'sf_symbol': 'bubble.left',
        'roles': {'COACH'},
        'sizes': {'S': (3, 2), 'M': (4, 2)},
        'default_size': 'S',
        'mobile_size': 'half',
    },
    'business_kpis': {
        'title': 'KPI business',
        'desc': 'Ricavi mensili, rinnovi e churn a colpo d\'occhio.',
        'icon': 'ph-chart-line-up',
        'sf_symbol': 'chart.line.uptrend.xyaxis',
        'roles': {'COACH'},
        'sizes': {'M': (6, 3), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'churn_risk': {
        'title': 'Rischio abbandono',
        'desc': 'Gli atleti a rischio secondo il modello predittivo.',
        'icon': 'ph-warning-diamond',
        'sf_symbol': 'exclamationmark.triangle',
        'roles': {'COACH'},
        'sizes': {'M': (6, 4), 'L': (12, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'revenue_chart': {
        'title': 'Andamento ricavi',
        'desc': 'La curva dei ricavi degli ultimi mesi.',
        'icon': 'ph-trend-up',
        'sf_symbol': 'chart.xyaxis.line',
        'roles': {'COACH'},
        'sizes': {'M': (6, 4), 'L': (12, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'checks_volume_chart': {
        'title': 'Volume check',
        'desc': 'Check ricevuti nelle ultime 8 settimane.',
        'icon': 'ph-chart-bar',
        'sf_symbol': 'chart.bar',
        'roles': {'COACH'},
        'sizes': {'M': (6, 3), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'quick_actions': {
        'title': 'Azioni rapide',
        'desc': 'Scorciatoie per le operazioni più frequenti.',
        'icon': 'ph-lightning',
        'sf_symbol': 'bolt',
        'roles': {'COACH', 'CLIENT'},
        'sizes': {'M': (12, 2)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    # --- CLIENT --------------------------------------------------------------
    'weight_trend': {
        'title': 'Andamento peso',
        'desc': 'Le tue ultime rilevazioni di peso.',
        'icon': 'ph-scales',
        'sf_symbol': 'scalemass',
        'roles': {'CLIENT'},
        'sizes': {'M': (6, 3), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'training_loads': {
        'title': 'Carichi principali',
        'desc': 'La progressione dei tuoi esercizi chiave.',
        'icon': 'ph-barbell',
        'sf_symbol': 'dumbbell',
        'roles': {'CLIENT'},
        'sizes': {'M': (6, 3), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'weekly_volume': {
        'title': 'Volume settimanale',
        'desc': 'Quanto ti sei allenato settimana per settimana.',
        'icon': 'ph-chart-bar',
        'sf_symbol': 'chart.bar',
        'roles': {'CLIENT'},
        'sizes': {'M': (6, 3), 'L': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'next_workout': {
        'title': 'Sessione di oggi',
        'desc': 'Il prossimo allenamento in programma.',
        'icon': 'ph-barbell',
        'sf_symbol': 'figure.strengthtraining.traditional',
        'roles': {'CLIENT'},
        'sizes': {'S': (4, 3), 'M': (6, 3)},
        'default_size': 'M',
        'mobile_size': 'half',
    },
    'next_meal': {
        'title': 'Prossimo pasto',
        'desc': 'Cosa prevede il tuo piano alimentare adesso.',
        'icon': 'ph-fork-knife',
        'sf_symbol': 'fork.knife',
        'roles': {'CLIENT'},
        'sizes': {'S': (4, 3), 'M': (6, 3)},
        'default_size': 'M',
        'mobile_size': 'half',
    },
    'coach_message': {
        'title': 'Dal tuo coach',
        'desc': 'L\'ultimo messaggio ricevuto dal tuo coach.',
        'icon': 'ph-chat-circle-text',
        'sf_symbol': 'bubble.left',
        'roles': {'CLIENT'},
        'sizes': {'S': (4, 2), 'M': (6, 2)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'journey_timeline': {
        'title': 'Percorso',
        'desc': 'Le tappe del tuo percorso con il coach.',
        'icon': 'ph-path',
        'sf_symbol': 'point.topleft.down.curvedto.point.bottomright.up',
        'roles': {'CLIENT'},
        'sizes': {'M': (6, 4), 'L': (12, 4)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'checks_due': {
        'title': 'Check da compilare',
        'desc': 'I check assegnati che aspettano la tua compilazione.',
        'icon': 'ph-clipboard-text',
        'sf_symbol': 'checklist',
        'roles': {'CLIENT'},
        'sizes': {'S': (4, 3), 'M': (6, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
    'nav_shortcuts': {
        'title': 'Scorciatoie',
        'desc': 'Accesso rapido ad allenamento, nutrizione e check.',
        'icon': 'ph-squares-four',
        'sf_symbol': 'square.grid.2x2',
        'roles': {'CLIENT'},
        'sizes': {'M': (12, 3)},
        'default_size': 'M',
        'mobile_size': 'full',
    },
}

# Role defaults are the union of what each surface's old static dashboard
# showed (web sections + iOS cards), since one canonical layout now feeds
# both. Array order is the iOS rendering order.
DEFAULT_LAYOUT_COACH = {
    'version': SCHEMA_VERSION,
    'widgets': [
        {'id': 'wg_default_quick', 'type': 'quick_actions',
         'x': 0, 'y': 0, 'size': 'M', 'config': {}},
        {'id': 'wg_default_agenda', 'type': 'agenda_today',
         'x': 0, 'y': 2, 'size': 'M', 'config': {}},
        {'id': 'wg_default_activity', 'type': 'activity_feed',
         'x': 6, 'y': 2, 'size': 'M', 'config': {}},
        {'id': 'wg_default_recent', 'type': 'recent_clients',
         'x': 0, 'y': 7, 'size': 'M', 'config': {}},
        {'id': 'wg_default_plans', 'type': 'subscription_plans',
         'x': 8, 'y': 7, 'size': 'S', 'config': {}},
    ],
}

DEFAULT_LAYOUT_CLIENT = {
    'version': SCHEMA_VERSION,
    'widgets': [
        {'id': 'wg_default_quick', 'type': 'quick_actions',
         'x': 0, 'y': 0, 'size': 'M', 'config': {}},
        {'id': 'wg_default_workout', 'type': 'next_workout',
         'x': 0, 'y': 2, 'size': 'M', 'config': {}},
        {'id': 'wg_default_meal', 'type': 'next_meal',
         'x': 6, 'y': 2, 'size': 'M', 'config': {}},
        {'id': 'wg_default_msg', 'type': 'coach_message',
         'x': 0, 'y': 5, 'size': 'M', 'config': {}},
        {'id': 'wg_default_weight', 'type': 'weight_trend',
         'x': 6, 'y': 5, 'size': 'M', 'config': {}},
        {'id': 'wg_default_loads', 'type': 'training_loads',
         'x': 0, 'y': 8, 'size': 'M', 'config': {}},
        {'id': 'wg_default_volume', 'type': 'weekly_volume',
         'x': 6, 'y': 8, 'size': 'M', 'config': {}},
        {'id': 'wg_default_nav', 'type': 'nav_shortcuts',
         'x': 0, 'y': 11, 'size': 'M', 'config': {}},
    ],
}


class LayoutValidationError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def _default_for(role):
    return DEFAULT_LAYOUT_COACH if role == 'COACH' else DEFAULT_LAYOUT_CLIENT


def widget_dims(widget_type, size):
    """(w, h) for a type+size label, falling back to the type's default size."""
    entry = WIDGET_REGISTRY[widget_type]
    if size not in entry['sizes']:
        size = entry['default_size']
    w, h = entry['sizes'][size]
    return size, w, h


def get_layout(user):
    """Saved layout or role default. Defensively strips widget types the
    role can't use (catalog may shrink between releases). Cached 30s with
    event invalidation on every write."""
    key = cachekeys.dashboard_layout(user.id)
    cached = cache.get(key)
    if cached is not None:
        return cached

    raw = user.dashboard_layout or {}
    if not raw.get('widgets'):
        layout = _default_for(user.role)
    else:
        widgets = [
            w for w in raw['widgets']
            if w.get('type') in WIDGET_REGISTRY
            and user.role in WIDGET_REGISTRY[w['type']]['roles']
        ]
        layout = {'version': SCHEMA_VERSION, 'widgets': widgets}
        if not widgets:
            layout = _default_for(user.role)

    cache.set(key, layout, 30)
    return layout


def _sanitize_config(user, widget_type, config):
    """Whitelist config keys per type; scope-check values (e.g. pinned
    client_ids must belong to the coach's ACTIVE relationships)."""
    schema = WIDGET_REGISTRY[widget_type].get('config_schema')
    if not schema or not isinstance(config, dict):
        return {}
    clean = {}
    for key, rule in schema.items():
        val = config.get(key)
        if rule['type'] == 'int_list' and isinstance(val, list):
            ids = [v for v in val if isinstance(v, int)][:rule['max_len']]
            if key == 'client_ids' and ids:
                from domain.coaching.models import CoachingRelationship
                coach = getattr(user, 'coach_profile', None)
                if coach is None:
                    ids = []
                else:
                    linked = set(
                        CoachingRelationship.objects
                        .filter(coach=coach, client_id__in=ids, status='ACTIVE')
                        .values_list('client_id', flat=True)
                    )
                    ids = [i for i in ids if i in linked]
            if ids:
                clean[key] = ids
    return clean


def validate_and_save_layout(user, payload):
    """Full-replace write. Raises LayoutValidationError on bad input.
    Returns the normalized layout that was saved."""
    if not isinstance(payload, dict):
        raise LayoutValidationError('Payload non valido.')
    version = payload.get('version')
    if version != SCHEMA_VERSION:
        # 409 so an outdated app build never clobbers a newer schema.
        raise LayoutValidationError('Versione layout non supportata.', status=409)

    widgets_in = payload.get('widgets')
    if not isinstance(widgets_in, list):
        raise LayoutValidationError('Campo widgets mancante.')
    if len(widgets_in) > MAX_WIDGETS:
        raise LayoutValidationError('Troppi widget.')

    seen_types = set()
    clean = []
    for w in widgets_in:
        if not isinstance(w, dict):
            raise LayoutValidationError('Widget non valido.')
        wtype = w.get('type')
        if wtype not in WIDGET_REGISTRY:
            raise LayoutValidationError(f'Widget sconosciuto: {wtype}')
        if user.role not in WIDGET_REGISTRY[wtype]['roles']:
            raise LayoutValidationError(f'Widget non disponibile per il tuo ruolo: {wtype}')
        if wtype in seen_types:
            continue  # v1: one instance per type, extra copies dropped
        seen_types.add(wtype)

        wid = w.get('id')
        if not isinstance(wid, str) or not _ID_RE.match(wid):
            wid = f'wg_{wtype}'
        size, _, _ = widget_dims(wtype, w.get('size'))
        x = w.get('x');  y = w.get('y')
        x = x if isinstance(x, int) and 0 <= x <= 11 else 0
        y = y if isinstance(y, int) and y >= 0 else 0
        clean.append({
            'id': wid, 'type': wtype, 'x': x, 'y': y, 'size': size,
            'config': _sanitize_config(user, wtype, w.get('config')),
        })

    clean.sort(key=lambda w: (w['y'], w['x']))
    layout = {'version': SCHEMA_VERSION, 'widgets': clean}

    user.dashboard_layout = layout
    user.save(update_fields=['dashboard_layout', 'updated_at'])
    cachekeys.invalidate_dashboard_layout(user.id)
    return layout


def reset_layout(user):
    """DELETE → back to the role default."""
    user.dashboard_layout = {}
    user.save(update_fields=['dashboard_layout', 'updated_at'])
    cachekeys.invalidate_dashboard_layout(user.id)
    return _default_for(user.role)


def catalog_for(user):
    """Role-filtered widget catalog for the web palette and the iOS edit
    sheet. Sizes exposed as label → [w, h] so clients render pickers from
    server truth."""
    out = []
    for wtype, entry in WIDGET_REGISTRY.items():
        if user.role not in entry['roles']:
            continue
        out.append({
            'type': wtype,
            'title': entry['title'],
            'desc': entry['desc'],
            'icon': entry['icon'],
            'sf_symbol': entry['sf_symbol'],
            'sizes': {label: list(dims) for label, dims in entry['sizes'].items()},
            'default_size': entry['default_size'],
            'mobile_size': entry['mobile_size'],
        })
    return out
