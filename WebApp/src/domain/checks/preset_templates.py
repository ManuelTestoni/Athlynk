"""
System preset templates for check-in questionnaires.

Each coach receives a personal clone of these presets the first time they
open `Gestisci Modelli`. Coaches can modify their copies; the `Ripristina`
action re-reads the original definition from this module.

Schema:
    PRESETS[key] = {
        'title':       str,
        'description': str,
        'steps':       [{'id': str, 'label': str, 'icon': str}, ...],
        'questions':   [{
            'id': str, 'step_id': str, 'type': str, 'label': str,
            'required': bool, 'report_visible': bool,
            # type-specific keys: 'unit', 'min', 'max', 'minLabel', 'maxLabel', 'options', 'placeholder'
        }, ...],
    }

Supported question types: antropometria, metrica, media, si_no, radio, checkbox, aperta, allegato.
The `antropometria` type bundles peso/circonferenze/pliche (see domain.checks.anthropometry);
its config keys are: 'weight' (bool), 'circumferences' (ordered stored-keys),
'skinfolds' (ordered keys).
"""

PRESETS = {
    # ──────────────────────────────────────────────────────────────────
    'completo_coach': {
        'title': 'Completo coach',
        'description': 'Check completo con antropometria, benessere, aderenza, note e foto progressi.',
        'steps': [
            {'id': 's_antrop',    'label': 'Antropometria', 'icon': 'ph-ruler'},
            {'id': 's_benessere', 'label': 'Benessere',     'icon': 'ph-smiley'},
            {'id': 's_note',      'label': 'Note',          'icon': 'ph-note-pencil'},
            {'id': 's_foto',      'label': 'Foto',          'icon': 'ph-camera'},
        ],
        'questions': [
            {'id': 'antropometria', 'step_id': 's_antrop', 'type': 'antropometria', 'label': 'Antropometria',
             'weight': True,
             'circumferences': ['chest', 'waist', 'gluteal', 'arm_relaxed_l', 'arm_relaxed_r', 'thigh_l', 'thigh_r'],
             'skinfolds': ['triceps', 'subscapular', 'suprailiac', 'abdominal'],
             'required': True, 'report_visible': True},
            {'id': 'benessere_umore',   'step_id': 's_benessere', 'type': 'media',   'label': 'Umore generale',        'min': 1, 'max': 5, 'minLabel': 'Pessimo',    'maxLabel': 'Eccellente', 'required': True,  'report_visible': True},
            {'id': 'benessere_sonno',   'step_id': 's_benessere', 'type': 'media',   'label': 'Qualità del sonno',     'min': 1, 'max': 5, 'minLabel': 'Pessima',    'maxLabel': 'Ottima',     'required': False, 'report_visible': True},
            {'id': 'benessere_dieta',   'step_id': 's_benessere', 'type': 'media',   'label': 'Aderenza alla dieta',   'min': 1, 'max': 5, 'minLabel': 'Non seguita','maxLabel': 'Perfetta',   'required': True,  'report_visible': True},
            {'id': 'benessere_workout', 'step_id': 's_benessere', 'type': 'media',   'label': 'Aderenza allenamento',  'min': 1, 'max': 5, 'minLabel': 'Non seguito','maxLabel': 'Perfetto',   'required': True,  'report_visible': True},
            {'id': 'note_infortuni',    'step_id': 's_note',      'type': 'aperta',  'label': 'Infortuni o dolori',    'placeholder': 'Eventuali dolori, tensioni o infortuni...',  'required': False, 'report_visible': True},
            {'id': 'note_limitazioni',  'step_id': 's_note',      'type': 'aperta',  'label': 'Limitazioni o adattamenti', 'placeholder': 'Hai saltato sessioni? Modificato esercizi?', 'required': False, 'report_visible': True},
            {'id': 'note_messaggio',    'step_id': 's_note',      'type': 'aperta',  'label': 'Messaggio al coach',    'placeholder': 'Tutto quello che vuoi condividere...', 'required': False, 'report_visible': False},
            {'id': 'foto_progressi',    'step_id': 's_foto',      'type': 'allegato','label': 'Foto progressi (frontale, laterale, posteriore)', 'required': False, 'report_visible': True},
        ],
    },

    # ──────────────────────────────────────────────────────────────────
    'rapido_atleta': {
        'title': 'Rapido atleta',
        'description': 'Check breve: peso, umore, sonno, aderenza. Per check-in settimanali veloci.',
        'steps': [
            {'id': 's_main', 'label': 'Check rapido', 'icon': 'ph-lightning'},
        ],
        'questions': [
            {'id': 'peso',     'step_id': 's_main', 'type': 'antropometria', 'label': 'Peso corporeo',
             'weight': True, 'circumferences': [], 'skinfolds': [],
             'required': True, 'report_visible': True},
            {'id': 'umore',    'step_id': 's_main', 'type': 'media',   'label': 'Umore',                'min': 1, 'max': 5, 'minLabel': 'Pessimo',   'maxLabel': 'Eccellente', 'required': True, 'report_visible': True},
            {'id': 'sonno',    'step_id': 's_main', 'type': 'media',   'label': 'Sonno',                'min': 1, 'max': 5, 'minLabel': 'Pessimo',   'maxLabel': 'Ottimo',     'required': True, 'report_visible': True},
            {'id': 'energia',  'step_id': 's_main', 'type': 'media',   'label': 'Livello di energia',   'min': 1, 'max': 5, 'minLabel': 'Esausto',   'maxLabel': 'Carico',     'required': False,'report_visible': True},
            {'id': 'dieta',    'step_id': 's_main', 'type': 'media',   'label': 'Aderenza dieta',       'min': 1, 'max': 5, 'minLabel': 'Non seguita','maxLabel': 'Perfetta',  'required': True, 'report_visible': True},
            {'id': 'workout',  'step_id': 's_main', 'type': 'media',   'label': 'Aderenza allenamento', 'min': 1, 'max': 5, 'minLabel': 'Non seguito','maxLabel': 'Perfetto',  'required': True, 'report_visible': True},
            {'id': 'note',     'step_id': 's_main', 'type': 'aperta',  'label': 'Note',                 'placeholder': 'Qualcosa da segnalare?', 'required': False, 'report_visible': False},
        ],
    },

    # ──────────────────────────────────────────────────────────────────
    'feedback_atleta': {
        'title': 'Feedback atleta',
        'description': 'Questionario di feedback sulla qualità del servizio e dell\'esperienza di coaching.',
        'steps': [
            {'id': 's_servizio',  'label': 'Servizio',   'icon': 'ph-star'},
            {'id': 's_programma', 'label': 'Programma',  'icon': 'ph-barbell'},
            {'id': 's_suggest',   'label': 'Suggerimenti','icon': 'ph-chat-circle-text'},
        ],
        'questions': [
            {'id': 'soddisfazione',     'step_id': 's_servizio',  'type': 'media',   'label': 'Soddisfazione generale',         'min': 1, 'max': 10, 'minLabel': 'Bassa', 'maxLabel': 'Alta', 'required': True, 'report_visible': True},
            {'id': 'comunicazione',     'step_id': 's_servizio',  'type': 'media',   'label': 'Comunicazione del coach',        'min': 1, 'max': 10, 'minLabel': 'Scarsa','maxLabel': 'Ottima','required': True,'report_visible': True},
            {'id': 'consiglieresti',    'step_id': 's_servizio',  'type': 'si_no',   'label': 'Consiglieresti il servizio?',                                                        'required': True, 'report_visible': True},
            {'id': 'difficolta',        'step_id': 's_programma', 'type': 'radio',   'label': 'Difficoltà percepita del programma', 'options': ['Troppo facile','Adeguata','Troppo difficile'], 'required': True, 'report_visible': True},
            {'id': 'risultati',         'step_id': 's_programma', 'type': 'media',   'label': 'Risultati ottenuti',             'min': 1, 'max': 10, 'minLabel': 'Nessuno','maxLabel': 'Eccellenti','required': True,'report_visible': True},
            {'id': 'aree_miglioramento','step_id': 's_programma', 'type': 'checkbox','label': 'Aree da migliorare',             'options': ['Programmazione','Comunicazione','Tempi di risposta','Materiale didattico','Frequenza check'], 'required': False,'report_visible': True},
            {'id': 'punto_forza',       'step_id': 's_suggest',   'type': 'aperta',  'label': 'Cosa apprezzi di più?',           'placeholder': 'Punti di forza...', 'required': False, 'report_visible': True},
            {'id': 'suggerimenti',      'step_id': 's_suggest',   'type': 'aperta',  'label': 'Suggerimenti per migliorare',     'placeholder': 'Cosa cambieresti?', 'required': False, 'report_visible': True},
        ],
    },

    # ──────────────────────────────────────────────────────────────────
    'nutrizione': {
        'title': 'Nutrizione',
        'description': 'Check nutrizionale: composizione corporea, abitudini alimentari, idratazione.',
        'steps': [
            {'id': 's_compos',    'label': 'Composizione', 'icon': 'ph-scales'},
            {'id': 's_abitudini', 'label': 'Abitudini',    'icon': 'ph-fork-knife'},
            {'id': 's_diario',    'label': 'Diario',       'icon': 'ph-notebook'},
        ],
        'questions': [
            {'id': 'antropometria',  'step_id': 's_compos',    'type': 'antropometria', 'label': 'Antropometria',
             'weight': True,
             'circumferences': ['waist', 'gluteal'],
             'skinfolds': ['abdominal'],
             'required': True, 'report_visible': True},
            {'id': 'aderenza_dieta', 'step_id': 's_abitudini', 'type': 'media',   'label': 'Aderenza al piano',       'min': 1, 'max': 10, 'minLabel': 'Nulla','maxLabel': 'Totale', 'required': True, 'report_visible': True},
            {'id': 'pasti_fuori',    'step_id': 's_abitudini', 'type': 'metrica', 'label': 'Pasti fuori casa',        'unit': 'n/sett', 'required': False, 'report_visible': True},
            {'id': 'sgarri',         'step_id': 's_abitudini', 'type': 'metrica', 'label': 'Sgarri programmati',      'unit': 'n/sett', 'required': False, 'report_visible': True},
            {'id': 'idratazione',    'step_id': 's_abitudini', 'type': 'metrica', 'label': 'Acqua assunta',           'unit': 'L/die', 'required': False, 'report_visible': True},
            {'id': 'fame',           'step_id': 's_abitudini', 'type': 'media',   'label': 'Senso di fame',           'min': 1, 'max': 5, 'minLabel': 'Mai','maxLabel': 'Costante', 'required': False, 'report_visible': True},
            {'id': 'digestione',     'step_id': 's_abitudini', 'type': 'radio',   'label': 'Digestione',               'options': ['Ottima','Buona','Discreta','Difficoltosa'], 'required': False, 'report_visible': True},
            {'id': 'integratori',    'step_id': 's_abitudini', 'type': 'checkbox','label': 'Integratori assunti',     'options': ['Proteine','Creatina','Multivitaminico','Omega 3','Vitamina D','Magnesio','Altro'], 'required': False, 'report_visible': True},
            {'id': 'diario',         'step_id': 's_diario',    'type': 'allegato','label': 'Diario alimentare (foto/PDF)', 'required': False, 'report_visible': True},
            {'id': 'note',           'step_id': 's_diario',    'type': 'aperta',  'label': 'Note al nutrizionista',   'placeholder': 'Difficoltà, dubbi, segnalazioni...', 'required': False, 'report_visible': False},
        ],
    },

    # ──────────────────────────────────────────────────────────────────
    # Coach-only: non viene mai assegnato all'atleta. Scopo: calcolo
    # fabbisogni energetici e di nutrienti (NCPT comparative standards).
    'calcolo_fabbisogni': {
        'title': 'Calcolo Fabbisogni',
        'description': 'Calcolo coach dei fabbisogni energetici e di macronutrienti (NCPT). Non viene assegnato all\'atleta.',
        'coach_only': True,
        'steps': [
            {'id': 's_dati_base',   'label': 'Dati Base',             'icon': 'ph-chart-bar'},
            {'id': 's_energetico',  'label': 'Fabbisogno Energetico', 'icon': 'ph-lightning'},
            {'id': 's_macro',       'label': 'Macronutrienti',        'icon': 'ph-scales'},
            {'id': 's_altri',       'label': 'Altri Fabbisogni',      'icon': 'ph-drop'},
            {'id': 's_note_op',     'label': 'Note Operative',        'icon': 'ph-note-pencil'},
        ],
        'questions': [
            # ── Dati Base ──────────────────────────────────────────
            {'id': 'altezza_cm',     'step_id': 's_dati_base', 'type': 'metrica', 'label': 'Altezza',           'unit': 'cm',   'required': True,  'report_visible': True},
            {'id': 'peso_kg',        'step_id': 's_dati_base', 'type': 'metrica', 'label': 'Peso corporeo',     'unit': 'kg',   'required': True,  'report_visible': True},
            {'id': 'eta_anni',       'step_id': 's_dati_base', 'type': 'metrica', 'label': 'Età',               'unit': 'anni', 'required': True,  'report_visible': True},
            {'id': 'sesso',          'step_id': 's_dati_base', 'type': 'radio',   'label': 'Sesso biologico',   'options': ['Maschio', 'Femmina'], 'required': True,  'report_visible': True},
            {'id': 'formula_mb',     'step_id': 's_dati_base', 'type': 'radio',   'label': 'Formula MB',        'options': ['Mifflin-St Jeor', 'Harris-Benedict', 'Cunningham', 'Altro'], 'required': True, 'report_visible': True},
            {'id': 'mb_stimata_kcal','step_id': 's_dati_base', 'type': 'metrica', 'label': 'MB stimata (auto-calcolata, modificabile)', 'unit': 'kcal', 'required': True, 'report_visible': True},
            {'id': 'pal_valore',     'step_id': 's_dati_base', 'type': 'metrica', 'label': 'LAF / PAL',         'unit': '×',    'required': True,  'report_visible': True},
            {'id': 'pal_descrizione','step_id': 's_dati_base', 'type': 'aperta',  'label': 'Descrizione livello di attività', 'placeholder': 'Es. Sedentario (1.2), Leggero (1.375), Moderato (1.55), Attivo (1.725)…', 'required': False, 'report_visible': True},
            # ── Fabbisogno Energetico ──────────────────────────────
            {'id': 'det_kcal',       'step_id': 's_energetico', 'type': 'metrica', 'label': 'DET — Fabbisogno energetico totale (MB × PAL, modificabile)', 'unit': 'kcal', 'required': True, 'report_visible': True},
            {'id': 'det_note',       'step_id': 's_energetico', 'type': 'aperta',  'label': 'Note DET', 'placeholder': 'Obiettivo calorico, modulazione secondo fasi, strategie…', 'required': False, 'report_visible': True},
            # ── Macronutrienti ─────────────────────────────────────
            {'id': 'proteine_gkg',      'step_id': 's_macro', 'type': 'metrica', 'label': 'Proteine — target',        'unit': 'g/kg', 'required': True,  'report_visible': True},
            {'id': 'proteine_g_totale', 'step_id': 's_macro', 'type': 'metrica', 'label': 'Proteine — intake totale (auto da kg, modificabile)', 'unit': 'g', 'required': True, 'report_visible': True},
            {'id': 'proteine_note',     'step_id': 's_macro', 'type': 'aperta',  'label': 'Note proteine', 'placeholder': 'Timing, distribuzione nei pasti, fonti preferite…', 'required': False, 'report_visible': True},
            {'id': 'carboidrati_gkg',      'step_id': 's_macro', 'type': 'metrica', 'label': 'Carboidrati — target',        'unit': 'g/kg', 'required': True,  'report_visible': True},
            {'id': 'carboidrati_g_totale', 'step_id': 's_macro', 'type': 'metrica', 'label': 'Carboidrati — intake totale (auto da kg, modificabile)', 'unit': 'g', 'required': True, 'report_visible': True},
            {'id': 'carboidrati_note',     'step_id': 's_macro', 'type': 'aperta',  'label': 'Note carboidrati', 'placeholder': 'Attorno all\'allenamento, fonti consigliate…', 'required': False, 'report_visible': True},
            {'id': 'lipidi_target',      'step_id': 's_macro', 'type': 'metrica', 'label': 'Lipidi — target',        'unit': 'g/kg o %kcal', 'required': True,  'report_visible': True},
            {'id': 'lipidi_g_totale',    'step_id': 's_macro', 'type': 'metrica', 'label': 'Lipidi — intake totale (auto da kg, modificabile)',   'unit': 'g', 'required': True, 'report_visible': True},
            {'id': 'lipidi_note',        'step_id': 's_macro', 'type': 'aperta',  'label': 'Note lipidi', 'placeholder': 'Tipologie di grassi, modulazione per fase…', 'required': False, 'report_visible': True},
            # ── Altri Fabbisogni ───────────────────────────────────
            {'id': 'fibra_gdie',         'step_id': 's_altri', 'type': 'metrica', 'label': 'Fabbisogno fibra',   'unit': 'g/die', 'required': False, 'report_visible': True},
            {'id': 'fibra_note',         'step_id': 's_altri', 'type': 'aperta',  'label': 'Note fibra', 'placeholder': 'Tolleranza, fonti consigliate…', 'required': False, 'report_visible': True},
            {'id': 'idrico_mldie',       'step_id': 's_altri', 'type': 'metrica', 'label': 'Fabbisogno idrico',  'unit': 'ml/die', 'required': False, 'report_visible': True},
            {'id': 'idrico_criterio',    'step_id': 's_altri', 'type': 'aperta',  'label': 'Criterio idrico', 'placeholder': 'ml/kg, ml/kcal, sintomi soggettivi…', 'required': False, 'report_visible': True},
            {'id': 'micronutrienti_critici', 'step_id': 's_altri', 'type': 'aperta', 'label': 'Micronutrienti critici da monitorare', 'placeholder': 'Ca, Fe, Vit D, Mg, Zn… in base a quadro clinico/sportivo', 'required': False, 'report_visible': True},
            # ── Note Operative ─────────────────────────────────────
            {'id': 'note_operative', 'step_id': 's_note_op', 'type': 'aperta', 'label': 'Sintesi punti chiave', 'placeholder': 'Vincoli, priorità, bandierine rosse, strategie iniziali, adattamenti programmati…', 'required': False, 'report_visible': True},
        ],
    },

    # ──────────────────────────────────────────────────────────────────
    'allenamento': {
        'title': 'Allenamento',
        'description': 'Check allenamento: aderenza, performance, recupero, dolori articolari.',
        'steps': [
            {'id': 's_aderenza',  'label': 'Aderenza',    'icon': 'ph-check-square'},
            {'id': 's_perf',      'label': 'Performance', 'icon': 'ph-chart-line-up'},
            {'id': 's_recupero',  'label': 'Recupero',    'icon': 'ph-moon'},
        ],
        'questions': [
            {'id': 'sessioni_fatte', 'step_id': 's_aderenza', 'type': 'metrica', 'label': 'Sessioni completate',     'unit': 'n', 'required': True, 'report_visible': True},
            {'id': 'sessioni_target','step_id': 's_aderenza', 'type': 'metrica', 'label': 'Sessioni programmate',    'unit': 'n', 'required': True, 'report_visible': True},
            {'id': 'aderenza_pct',   'step_id': 's_aderenza', 'type': 'media',   'label': 'Aderenza al programma',    'min': 1, 'max': 10, 'minLabel': 'Nulla', 'maxLabel': 'Totale', 'required': True, 'report_visible': True},
            {'id': 'esercizi_skip',  'step_id': 's_aderenza', 'type': 'aperta',  'label': 'Esercizi saltati o modificati', 'placeholder': 'Quali e perché?', 'required': False, 'report_visible': True},
            {'id': 'percezione_pr',  'step_id': 's_perf',     'type': 'si_no',   'label': 'Ottenuti PR questa settimana?', 'required': False, 'report_visible': True},
            {'id': 'rpe_medio',      'step_id': 's_perf',     'type': 'media',   'label': 'RPE medio sessioni',       'min': 1, 'max': 10, 'minLabel': '1', 'maxLabel': '10', 'required': True, 'report_visible': True},
            {'id': 'energia_palestra','step_id': 's_perf',    'type': 'media',   'label': 'Energia in palestra',      'min': 1, 'max': 5, 'minLabel': 'Esausto','maxLabel': 'Carico','required': True,'report_visible': True},
            {'id': 'note_perf',      'step_id': 's_perf',     'type': 'aperta',  'label': 'Note tecniche / esecuzione','placeholder': 'Cosa è andato bene/male?', 'required': False, 'report_visible': True},
            {'id': 'doms',           'step_id': 's_recupero', 'type': 'media',   'label': 'DOMS (indolenzimento)',    'min': 1, 'max': 5, 'minLabel': 'Nessuno','maxLabel': 'Severo','required': False,'report_visible': True},
            {'id': 'sonno_ore',      'step_id': 's_recupero', 'type': 'metrica', 'label': 'Ore di sonno medie',       'unit': 'h', 'required': False, 'report_visible': True},
            {'id': 'stress',         'step_id': 's_recupero', 'type': 'media',   'label': 'Stress percepito',         'min': 1, 'max': 5, 'minLabel': 'Basso','maxLabel': 'Alto','required': False,'report_visible': True},
            {'id': 'dolori',         'step_id': 's_recupero', 'type': 'checkbox','label': 'Dolori articolari',        'options': ['Spalle','Gomiti','Polsi','Schiena bassa','Ginocchia','Anche','Caviglie','Nessuno'], 'required': False, 'report_visible': True},
        ],
    },
}


def build_template_payload(preset_key: str) -> dict:
    """Return a dict suitable for QuestionnaireTemplate.objects.create defaults."""
    preset = PRESETS[preset_key]
    return {
        'title': preset['title'],
        'description': preset.get('description', ''),
        'questionnaire_type': 'preset_' + preset_key,
        'is_active': True,
        'preset_key': preset_key,
        'is_modified_preset': False,
        'steps_config': preset['steps'],
        'questions_config': preset['questions'],
    }
