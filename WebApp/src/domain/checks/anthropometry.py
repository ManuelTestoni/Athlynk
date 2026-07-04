"""
Catalogo antropometrico ISAK — single source of truth condivisa fra backend e
template per il tipo di domanda `antropometria`.

Una domanda `antropometria` raggruppa in modo ordinato tre sezioni:
    - peso corporeo  → QuestionnaireResponse.weight_kg
    - circonferenze  → QuestionnaireResponse.body_circumferences (dict)
    - pliche         → QuestionnaireResponse.skinfolds (dict)

Le circonferenze degli arti (`is_limb=True`) si compilano per lato: le chiavi
memorizzate sono suffissate `_l` (sinistra) / `_r` (destra). Le pliche sono
sempre un valore singolo (mai lati).

Ogni misura porta due metadati numerici, condivisi fra validazione input e
grafici:
    - `range` (lo, hi): intervallo plausibile per un adulto; valori fuori da qui
      vengono rifiutati in compilazione (web + app). cm per circonferenze, mm
      per pliche, kg per il peso.
    - `pad`: semi-ampiezza (± attorno a min/max dei dati) usata per impostare
      l'asse Y dei grafici di andamento, così la linea non parte da zero ed è
      leggibile. Tarata sulla parte anatomica (es. polso ±2 cm, vita ±6 cm).
"""

# ──────────────────────────────────────────────────────────────────────────
# Catalogo (ordine = ordine di presentazione)
# ──────────────────────────────────────────────────────────────────────────

# Peso corporeo (kg): intervallo plausibile + padding asse Y dei grafici.
WEIGHT_RANGE = (20.0, 400.0)
WEIGHT_PAD = 10.0

CIRCUMFERENCES = [
    {'key': 'head',        'it': 'Testa',                      'en': 'Head girth',                  'isak': 'Massima circonferenza del capo, sopra glabella e occipite.',          'position': 'Testa; fascia orizzontale, perpendicolare all’asse longitudinale.',           'is_limb': False, 'range': (40.0, 65.0),  'pad': 3.0},
    {'key': 'neck',        'it': 'Collo',                      'en': 'Neck girth',                  'isak': 'Minima circonferenza del collo, sotto la laringe.',                   'position': 'Collo; fascia orizzontale, perpendicolare all’asse longitudinale.',           'is_limb': False, 'range': (25.0, 60.0),  'pad': 3.0},
    {'key': 'chest',       'it': 'Torace',                     'en': 'Chest girth',                 'isak': 'Circonferenza toracica al livello di riferimento ISAK.',              'position': 'Torace; fascia orizzontale, perpendicolare all’asse longitudinale.',          'is_limb': False, 'range': (55.0, 170.0), 'pad': 6.0},
    {'key': 'arm_relaxed', 'it': 'Braccio rilassato',          'en': 'Arm girth, relaxed',          'isak': 'Massima circonferenza del braccio rilassato.',                        'position': 'Braccio; fascia orizzontale, perpendicolare all’asse longitudinale.',         'is_limb': True,  'range': (15.0, 60.0),  'pad': 4.0},
    {'key': 'arm_flexed',  'it': 'Braccio flesso e contratto', 'en': 'Arm girth, flexed and tensed','isak': 'Massima circonferenza del braccio in flessione.',                     'position': 'Braccio; fascia orizzontale, perpendicolare all’asse longitudinale.',         'is_limb': True,  'range': (15.0, 65.0),  'pad': 4.0},
    {'key': 'forearm',     'it': 'Avambraccio',                'en': 'Forearm girth',               'isak': 'Massima circonferenza dell’avambraccio.',                             'position': 'Avambraccio; fascia orizzontale, perpendicolare all’asse longitudinale.',     'is_limb': True,  'range': (12.0, 50.0),  'pad': 3.0},
    {'key': 'wrist',       'it': 'Polso',                      'en': 'Wrist girth',                 'isak': 'Minima circonferenza sopra i processi stiloidei.',                    'position': 'Polso; fascia orizzontale, perpendicolare all’asse longitudinale.',           'is_limb': True,  'range': (10.0, 25.0),  'pad': 2.0},
    {'key': 'waist',       'it': 'Vita',                       'en': 'Waist girth',                 'isak': 'Minima circonferenza del tronco tra coste e cresta iliaca.',          'position': 'Addome/torace inferiore; fascia orizzontale.',                                 'is_limb': False, 'range': (45.0, 200.0), 'pad': 6.0},
    {'key': 'gluteal',     'it': 'Gluteo / Fianchi',           'en': 'Gluteal girth',               'isak': 'Massima circonferenza di glutei e anche.',                            'position': 'Bacino; fascia orizzontale, perpendicolare all’asse longitudinale.',          'is_limb': False, 'range': (55.0, 190.0), 'pad': 6.0},
    {'key': 'thigh',       'it': 'Coscia',                     'en': 'Thigh girth',                 'isak': 'Massima circonferenza della coscia.',                                 'position': 'Coscia; fascia orizzontale, perpendicolare all’asse longitudinale.',          'is_limb': True,  'range': (25.0, 100.0), 'pad': 5.0},
    {'key': 'calf',        'it': 'Polpaccio',                  'en': 'Calf girth',                  'isak': 'Massima circonferenza del polpaccio.',                                'position': 'Gamba; fascia orizzontale, perpendicolare all’asse longitudinale.',           'is_limb': True,  'range': (20.0, 65.0),  'pad': 4.0},
    {'key': 'ankle',       'it': 'Caviglia',                   'en': 'Ankle girth',                 'isak': 'Minima circonferenza sopra i malleoli.',                              'position': 'Caviglia; fascia orizzontale, perpendicolare all’asse longitudinale.',        'is_limb': True,  'range': (15.0, 40.0),  'pad': 2.0},
]

# Pliche (mm): intervallo plausibile uniforme + padding asse Y.
SKIN_RANGE = (1.0, 80.0)
SKIN_PAD = 5.0

SKINFOLDS = [
    {'key': 'biceps',      'it': 'Bicipitale',       'en': 'Biceps skinfold',      'isak': 'Faccia anteriore del braccio, sul punto medio tra acromion e radiale.',            'position': 'Braccio superiore; verticale.',          'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'triceps',     'it': 'Tricipitale',      'en': 'Triceps skinfold',     'isak': 'Faccia posteriore del braccio, sul punto medio tra acromion e radiale.',           'position': 'Braccio superiore; verticale.',          'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'subscapular', 'it': 'Sottoscapolare',   'en': 'Subscapular skinfold', 'isak': 'Sotto l’angolo inferiore della scapola.',                                          'position': 'Regione scapolare; diagonale discendente.','range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'supraspinale','it': 'Sopraspinale',     'en': 'Supraspinale skinfold','isak': 'Sopra la cresta iliaca, lungo la linea verso la spina iliaca antero-superiore.',    'position': 'Fianchi/anca; diagonale discendente.',   'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'suprailiac',  'it': 'Soprailiaca',      'en': 'Suprailiac skinfold',  'isak': 'Sopra la cresta iliaca, in prossimità della linea ascellare anteriore.',           'position': 'Fianco; diagonale ascendente.',          'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'abdominal',   'it': 'Addominale',       'en': 'Abdominal skinfold',   'isak': 'A circa 2 cm a destra dell’ombelico.',                                             'position': 'Addome; verticale.',                     'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'front_thigh', 'it': 'Coscia anteriore', 'en': 'Front thigh skinfold', 'isak': 'Faccia anteriore della coscia, nel punto medio del segmento.',                      'position': 'Coscia; verticale.',                     'range': SKIN_RANGE, 'pad': SKIN_PAD},
    {'key': 'medial_calf', 'it': 'Polpaccio mediale','en': 'Medial calf skinfold', 'isak': 'Faccia mediale del polpaccio, nel punto di massimo sviluppo del gastrocnemio.',      'position': 'Gamba; verticale.',                      'range': SKIN_RANGE, 'pad': SKIN_PAD},
]

_CIRC_BY_KEY = {c['key']: c for c in CIRCUMFERENCES}
_SKIN_BY_KEY = {s['key']: s for s in SKINFOLDS}

# Ordine canonico delle chiavi *memorizzate* (con lati per gli arti).
CIRC_STORED_ORDER = []
for _c in CIRCUMFERENCES:
    if _c['is_limb']:
        CIRC_STORED_ORDER += [str(_c['key']) + '_l', str(_c['key']) + '_r']
    else:
        CIRC_STORED_ORDER.append(str(_c['key']))
SKIN_STORED_ORDER = [s['key'] for s in SKINFOLDS]

# ──────────────────────────────────────────────────────────────────────────
# Mappe legacy (vecchio vocabolario → nuove chiavi ISAK). None = scartata.
# Usate dalla data-migration 0009.
# ──────────────────────────────────────────────────────────────────────────

LEGACY_CIRC_MAP = {
    'shoulders':   None,          # nessun equivalente ISAK → scartata
    'chest':       'chest',
    'waist':       'waist',
    'hips':        'gluteal',
    'thigh_right': 'thigh_r',
    'arm_right':   'arm_relaxed_r',
}

LEGACY_SKIN_MAP = {
    'chest':   None,              # nessun equivalente ISAK → scartata
    'abdomen': 'abdominal',
    'thigh':   'front_thigh',
    'tricep':  'triceps',
}

# Etichette IT per chiavi legacy non ancora migrate (solo per render storico).
_LEGACY_CIRC_LABELS = {
    'shoulders': 'Spalle', 'hips': 'Fianchi',
    'thigh_right': 'Coscia DX', 'arm_right': 'Braccio DX',
}
_LEGACY_SKIN_LABELS = {
    'abdomen': 'Addome', 'thigh': 'Coscia', 'tricep': 'Tricipite', 'chest': 'Petto',
}


def _split_side(stored_key):
    """('arm_relaxed_r') → ('arm_relaxed', ' DX'); ('waist') → ('waist', '')."""
    if stored_key.endswith('_r'):
        return stored_key[:-2], ' DX'
    if stored_key.endswith('_l'):
        return stored_key[:-2], ' SX'
    return stored_key, ''


def circ_label(stored_key):
    base, side = _split_side(stored_key)
    item = _CIRC_BY_KEY.get(base)
    if item:
        return item['it'] + side
    return _LEGACY_CIRC_LABELS.get(stored_key, stored_key)


def skin_label(stored_key):
    item = _SKIN_BY_KEY.get(stored_key)
    if item:
        return item['it']
    return _LEGACY_SKIN_LABELS.get(stored_key, stored_key)


def circ_range(stored_key):
    """Intervallo plausibile (lo, hi) in cm per una chiave circonferenza
    memorizzata (lato incluso). None se chiave sconosciuta (es. legacy)."""
    base, _ = _split_side(stored_key)
    item = _CIRC_BY_KEY.get(base)
    return item['range'] if item else None


def circ_pad(stored_key):
    base, _ = _split_side(stored_key)
    item = _CIRC_BY_KEY.get(base)
    return item['pad'] if item else 5.0


def skin_range(key):
    item = _SKIN_BY_KEY.get(key)
    return item['range'] if item else SKIN_RANGE


def skin_pad(key):
    item = _SKIN_BY_KEY.get(key)
    return item['pad'] if item else SKIN_PAD


def circ_side_keys(key):
    """Chiavi memorizzate per una circonferenza: [_l,_r] se arto, altrimenti [key]."""
    item = _CIRC_BY_KEY.get(key)
    if item and item['is_limb']:
        return [key + '_l', key + '_r']
    return [key]


def order_circ_keys(keys):
    """Ordina un insieme di chiavi circ secondo CIRC_STORED_ORDER (legacy in coda)."""
    idx = {k: i for i, k in enumerate(CIRC_STORED_ORDER)}
    return sorted(keys, key=lambda k: idx.get(k, 10_000))


def order_skin_keys(keys):
    idx = {k: i for i, k in enumerate(SKIN_STORED_ORDER)}
    return sorted(keys, key=lambda k: idx.get(k, 10_000))


def catalog_json():
    """Dict serializzabile per i template (builder + filler)."""
    return {
        'circumferences': CIRCUMFERENCES,
        'skinfolds': SKINFOLDS,
        'weight': {'range': WEIGHT_RANGE, 'pad': WEIGHT_PAD},
    }


def measurement_options():
    """Opzioni piatte (chiave+label) per i picker di misurazione singola, web e
    mobile. Le circonferenze degli arti espongono i due lati come voci separate,
    coerenti con le chiavi memorizzate (_l / _r)."""
    circ = []
    for c in CIRCUMFERENCES:
        if c['is_limb']:
            circ.append({'key': c['key'] + '_r', 'label': c['it'] + ' (DX)'})
            circ.append({'key': c['key'] + '_l', 'label': c['it'] + ' (SX)'})
        else:
            circ.append({'key': c['key'], 'label': c['it']})
    skin = [{'key': s['key'], 'label': s['it']} for s in SKINFOLDS]
    return {
        'weight': {'unit': 'kg', 'range': list(WEIGHT_RANGE)},
        'circumferences': circ,
        'skinfolds': skin,
    }
