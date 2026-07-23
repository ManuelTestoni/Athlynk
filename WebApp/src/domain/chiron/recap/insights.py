"""Motore insight deterministico per il recap CHIRON.

Stessa struttura di domain/analytics/services/rules_engine.py (reason_code +
dizionario di label), con un livello in più: interpretazione +
raccomandazione, non solo un peso numerico. observation/interpretation/
recommendation sono SEMPRE stringhe template da questi dizionari — mai testo
libero generato al volo, nemmeno qui. Il layer LLM (narrative.py) riformula
questi insight già calcolati, non ne genera di nuovi.

Se una regola non ha abbastanza dati (soglie in aggregates_*), l'insight non
viene generato affatto — niente interpretazioni a bassa confidenza travestite
da fatto.
"""

from .schemas import RecapInsight, Evidence

# V3 prep: soglie di anomalia regolabili per coach (domain.chiron.models.
# CoachRecapSettings.thresholds), invece di costanti fisse uguali per tutti.
# Un coach senza override usa questi default — nessuna migrazione dati
# necessaria, solo le chiavi presenti sovrascrivono.
DEFAULT_THRESHOLDS = {
    'plateau_change_pct': -5.0,           # calo % oltre il quale scatta plateau_load
    'nutrition_weekend_gap_points': 20.0,  # punti percentuali feriale-vs-weekend
    'overreaching_rpe_delta': 0.7,          # delta RPE 2w-vs-prev-2w
    'recomposition_weight_stable_kg': 0.5,  # |delta peso| sotto cui è "stabile"
    'recomposition_waist_drop_cm': -1.0,    # delta vita sotto cui è "in calo"
}

_INTERPRETATIONS = {
    'recomposition_signal':
        'Il peso è stabile ma la circonferenza vita è in calo: probabile ricomposizione corporea favorevole.',
    'plateau_load':
        'Il volume di allenamento è in calo nelle ultime settimane rispetto alle precedenti: possibile plateau o riduzione di stimolo.',
    'nutrition_adherence_weekend_drop':
        "L'aderenza nutrizionale è nettamente più bassa nel weekend rispetto ai giorni feriali.",
    'exercise_dropped':
        'Uno o più esercizi programmati risultano sistematicamente assenti dallo storico sessioni.',
    'exercise_substituted_often':
        'Uno o più esercizi vengono sostituiti di frequente rispetto al programma.',
    'result_despite_low_adherence':
        "Il peso è in calo nonostante un'aderenza training registrata bassa — possibile compenso non tracciato.",
    'overreaching_signal':
        'RPE percepito in salita nelle ultime settimane: possibile accumulo di fatica.',
    'low_logging_coverage':
        "Pochi giorni di log nutrizionale nella finestra osservata: il dato di aderenza potrebbe non riflettere il comportamento reale.",
}

_RECOMMENDATIONS = {
    'recomposition_signal': 'Mantenere la direzione attuale del programma.',
    'plateau_load': 'Valutare una variazione di stimolo (carico, volume o esercizio) nel prossimo blocco.',
    'nutrition_adherence_weekend_drop': "Discutere con l'atleta strategie per il weekend (pasti flessibili, planning anticipato).",
    'exercise_dropped': "Verificare con l'atleta il motivo (fastidio, tempo, gradimento) e valutare una sostituzione stabile in scheda.",
    'exercise_substituted_often': "Considerare di aggiornare la scheda con l'esercizio effettivamente svolto, se la sostituzione è sistematica.",
    'result_despite_low_adherence': "Approfondire con l'atleta cosa sta realmente accadendo prima di modificare il piano.",
    'overreaching_signal': 'Valutare uno scarico o una settimana di recupero nel prossimo blocco.',
    'low_logging_coverage': 'Incoraggiare un log più regolare prima di trarre conclusioni sull\'aderenza.',
}

# Bozza di messaggio in chat suggerita per ogni insight — usata dall'azione
# "Suggerisci azione" sulla recap card (§V2 del piano: propose/confirm
# esistente in chiron/actions.py, mai un invio diretto). Template
# deterministico, non generato dall'LLM: il coach lo legge/modifica prima di
# confermare, quindi non serve passare dalla guardia anti-allucinazione.
SUGGESTED_ACTION_MESSAGES = {
    'recomposition_signal': 'Bel lavoro! Il peso è stabile ma la circonferenza vita è in calo: siamo sulla strada giusta, continuiamo così.',
    'plateau_load': 'Ho notato che nelle ultime settimane il volume di allenamento è calato. Come ti senti? Ne parliamo per capire se serve una variazione nel prossimo blocco?',
    'nutrition_adherence_weekend_drop': "Ho notato che nel weekend l'aderenza al piano nutrizionale tende a calare rispetto ai giorni feriali. Vuoi che troviamo insieme una strategia più semplice da seguire anche sabato e domenica?",
    'exercise_dropped': "Ho notato che un esercizio programmato manca da un po' dal tuo storico allenamenti. C'è un motivo particolare (fastidio, tempo, altro)? Fammi sapere così aggiorniamo la scheda se serve.",
    'exercise_substituted_often': 'Ho notato che stai spesso sostituendo un esercizio in scheda con un altro. Se preferisci la variante che stai usando, aggiorniamo la scheda così resta coerente con quello che fai davvero.',
    'result_despite_low_adherence': "I tuoi dati recenti mostrano un risultato positivo nonostante un'aderenza al programma registrata bassa. Mi racconti cosa stai facendo di diverso? Mi aiuta a capire come supportarti meglio.",
    'overreaching_signal': 'Ho notato un RPE percepito in aumento nelle ultime settimane. Come ti senti a livello di recupero? Valutiamo insieme se inserire uno scarico.',
    'low_logging_coverage': 'Ho visto pochi giorni di log nutrizionale di recente. Va tutto bene? Anche un log parziale mi aiuta a seguirti meglio.',
}


def _make(code, domain, observation, confidence, evidence):
    return RecapInsight(
        code=code, domain=domain, observation=observation,
        interpretation=_INTERPRETATIONS[code],
        recommendation=_RECOMMENDATIONS.get(code),
        confidence=confidence, evidence=evidence,
    )


# --- regole per-dominio ------------------------------------------------------

def _rule_plateau_load(training, t):
    """V2: segnale di carico preciso sull'esercizio più allenato (top_set per
    sessione), non solo il proxy di volume totale — vedi
    aggregates_training.compute_top_exercise_load_trend."""
    top = training.get('top_exercise_load') or {}
    if not top.get('available'):
        return None
    sessions = top['sessions']
    if len(sessions) < 6:
        return None
    values = [s['top_set'] for s in sessions[-6:]]
    recent, prior = values[-3:], values[:3]
    prior_avg = sum(prior) / 3
    if prior_avg == 0:
        return None
    recent_avg = sum(recent) / 3
    change_pct = (recent_avg - prior_avg) / prior_avg * 100
    if change_pct > t['plateau_change_pct']:
        return None
    name = top['name']
    observation = (f"Carico su {name} in calo del {abs(round(change_pct))}% nelle ultime 3 "
                   f"sessioni rispetto alle 3 precedenti.")
    return _make('plateau_load', 'training', observation, 'medium',
                 Evidence(metric='top_set_load', window='3sess_vs_prev_3sess',
                          current_value=round(recent_avg, 1), previous_value=round(prior_avg, 1),
                          extra={'exercise': name}))


def _rule_plateau_volume(training, t):
    """Fallback: proxy di volume totale quando non c'è ancora un esercizio
    con abbastanza sessioni per un segnale di carico preciso (_rule_plateau_load)."""
    volume = training.get('volume') or {}
    weeks = volume.get('weeks') or []
    series = volume.get('series') or {}
    if len(weeks) < 6 or not series:
        return None
    totals = [sum(series[m][i] for m in series) for i in range(len(weeks))]
    recent, prior = totals[-3:], totals[-6:-3]
    if not prior or sum(prior) == 0:
        return None
    recent_avg, prior_avg = sum(recent) / 3, sum(prior) / 3
    change_pct = (recent_avg - prior_avg) / prior_avg * 100
    if change_pct > t['plateau_change_pct']:
        return None
    observation = f"Volume di allenamento in calo del {abs(round(change_pct))}% nelle ultime 3 settimane rispetto alle 3 precedenti."
    return _make('plateau_load', 'training', observation, 'medium',
                 Evidence(metric='volume_total', window='3w_vs_prev_3w',
                          current_value=round(recent_avg, 1), previous_value=round(prior_avg, 1)))


def _rule_plateau(training, t):
    # Preferisci il segnale di carico (più preciso); il volume resta il
    # fallback finché non c'è abbastanza storico sull'esercizio principale.
    return _rule_plateau_load(training, t) or _rule_plateau_volume(training, t)


def _rule_nutrition_weekend(nutrition, t):
    if not nutrition.get('available') or not nutrition.get('reliable'):
        return None
    weekday_pct, weekend_pct = nutrition.get('weekday_pct'), nutrition.get('weekend_pct')
    if weekday_pct is None or weekend_pct is None:
        return None
    gap = weekday_pct - weekend_pct
    if gap < t['nutrition_weekend_gap_points']:
        return None
    observation = f"Aderenza feriale {weekday_pct:.0f}% vs weekend {weekend_pct:.0f}% (gap {gap:.0f} punti) su {nutrition['window_days']} giorni."
    return _make('nutrition_adherence_weekend_drop', 'nutrition', observation, 'medium',
                 Evidence(metric='nutrition_adherence_pct', window=f"{nutrition['window_days']}d",
                          current_value=weekday_pct, previous_value=weekend_pct,
                          extra={'n_log_days': nutrition['n_log_days']}))


def _rule_low_logging(nutrition):
    if not nutrition.get('available') or nutrition.get('reliable'):
        return None
    observation = f"Solo {nutrition['n_log_days']} giorni loggati negli ultimi {nutrition['window_days']}."
    return _make('low_logging_coverage', 'nutrition', observation, 'low',
                 Evidence(metric='n_log_days', window=f"{nutrition['window_days']}d",
                          current_value=nutrition['n_log_days']))


def _rule_exercise_dropped(compliance):
    dropped = (compliance or {}).get('dropped') or []
    if not dropped:
        return None
    names = ', '.join(e['exercise_name'] for e in dropped[:3])
    n = compliance['sessions_considered']
    observation = f"{names} assente/i in {dropped[0]['count']} delle ultime {n} sessioni corrispondenti."
    return _make('exercise_dropped', 'training', observation, 'high',
                 Evidence(metric='exercise_dropped', window=f'last_{n}_sessions', extra={'exercises': dropped}))


def _rule_exercise_substituted(compliance):
    substituted = (compliance or {}).get('substituted') or []
    if not substituted:
        return None
    names = ', '.join(e['exercise_name'] for e in substituted[:3])
    n = compliance['sessions_considered']
    observation = f"{names} sostituito/i in {substituted[0]['count']} delle ultime {n} sessioni corrispondenti."
    return _make('exercise_substituted_often', 'training', observation, 'high',
                 Evidence(metric='exercise_substituted', window=f'last_{n}_sessions', extra={'exercises': substituted}))


# --- regole cross-dominio ----------------------------------------------------

def _rule_recomposition(body, training, t):
    weight = body.get('weight', {})
    waist = (body.get('circumferences') or {}).get('waist')
    if not weight.get('reliable') or not waist or not waist.get('reliable'):
        return None
    if weight.get('delta') is None or waist.get('delta') is None:
        return None
    if not (abs(weight['delta']) < t['recomposition_weight_stable_kg']
            and waist['delta'] < t['recomposition_waist_drop_cm']):
        return None
    observation = f"Peso stabile (Δ{weight['delta']:+.1f}kg), vita in calo (Δ{waist['delta']:+.1f}cm)."
    return _make('recomposition_signal', 'cross', observation, 'medium',
                 Evidence(metric='weight_vs_waist', window='30d_vs_prev', current_value=weight['current_avg'],
                          previous_value=weight['previous_avg'], extra={'waist_delta': waist['delta']}))


def _rule_result_despite_low_adherence(body, training):
    weight = body.get('weight', {})
    adherence = (training or {}).get('adherence') or {}
    if not weight.get('reliable') or weight.get('delta') is None or adherence.get('overall_pct') is None:
        return None
    if not (weight['delta'] < -1.0 and adherence['overall_pct'] < 60):
        return None
    observation = f"Peso in calo (Δ{weight['delta']:+.1f}kg) con aderenza training al {adherence['overall_pct']:.0f}%."
    return _make('result_despite_low_adherence', 'cross', observation, 'medium',
                 Evidence(metric='weight_vs_training_adherence', window='30d_vs_prev / 12w',
                          current_value=weight['delta'], extra={'adherence_pct': adherence['overall_pct']}))


def _rule_overreaching(training, t):
    rpe_series = ((training or {}).get('rpe') or {}).get('series') or []
    if len(rpe_series) < 4:
        return None
    recent = [w['avg_rpe'] for w in rpe_series[-2:]]
    prior = [w['avg_rpe'] for w in rpe_series[-4:-2]]
    recent_avg, prior_avg = sum(recent) / len(recent), sum(prior) / len(prior)
    if (recent_avg - prior_avg) < t['overreaching_rpe_delta']:
        return None

    # Il self-report sonno è SOLO un qualificatore testuale — mai un input
    # numerico di confidence/forecast (§3/§5 del piano: resta soggettivo).
    sleep = (training or {}).get('sleep_signal') or {}
    sleep_note = ''
    if sleep.get('available') and sleep.get('trend') == 'declining':
        sleep_note = ', in coincidenza con una qualità del sonno auto-riportata in calo'

    observation = (f"RPE medio in salita ({prior_avg:.1f} → {recent_avg:.1f}) nelle ultime "
                   f"settimane rispetto alle precedenti{sleep_note}.")
    return _make('overreaching_signal', 'cross', observation, 'medium',
                 Evidence(metric='rpe_trend', window='2w_vs_prev_2w',
                          current_value=round(recent_avg, 1), previous_value=round(prior_avg, 1),
                          extra={'sleep_trend': sleep.get('trend')} if sleep.get('available') else {}))


def generate_insights(body, nutrition, training, thresholds=None):
    """body/nutrition/training: dict dagli aggregates_*. training può essere
    {} se il coach non ha accesso al dominio (gating nel builder).
    thresholds: override parziale di DEFAULT_THRESHOLDS (V3 prep, da
    CoachRecapSettings) — solo le chiavi presenti sovrascrivono i default."""
    t = {**DEFAULT_THRESHOLDS, **(thresholds or {})}
    candidates = [
        _rule_plateau(training, t),
        _rule_nutrition_weekend(nutrition, t),
        _rule_low_logging(nutrition),
        _rule_exercise_dropped(training.get('exercise_compliance')),
        _rule_exercise_substituted(training.get('exercise_compliance')),
        _rule_recomposition(body, training, t),
        _rule_result_despite_low_adherence(body, training),
        _rule_overreaching(training, t),
    ]
    return [c for c in candidates if c is not None]
