"""Aderenza nutrizionale per il recap CHIRON: % di kcal loggate rispetto al
target, split feriale/weekend. Nessun precedente da riusare — è logica di
dominio nuova, per questo vive qui e non in config/views_nutrition.py (che
resta solo layer HTTP). Totale per costruzione: mai un'eccezione, sempre un
dict con `available`/`reliable` espliciti."""

from datetime import date, timedelta

from domain.nutrition.models import NutritionAssignment, ClientMacroLogEntry

# Sotto questa soglia di giorni loggati nella finestra, il dato si mostra
# comunque ma è marcato come non affidabile (vedi §3 del piano recap).
MIN_RELIABLE_LOG_DAYS = 5

_WEEKDAY_CODES = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY']


def _day_target_kcal(plan, day):
    """Target kcal del piano per un giorno di calendario. None se non definito."""
    if plan.plan_kind == 'DAILY':
        return plan.daily_kcal or None
    diet_day = plan.days.filter(day_of_week=_WEEKDAY_CODES[day.weekday()]).first()
    return diet_day.target_kcal if diet_day else None


def compute_adherence(client, window_days=30, series_window_days=60):
    """Aderenza % (kcal loggati / kcal target) sugli ultimi `window_days`
    giorni chiusi (esclude oggi, ancora modificabile), split feriale/weekend.
    Include anche una serie settimanale su `series_window_days` (default più
    ampio dell'headline: serve più storico per un forecast, non solo per lo
    stato attuale — vedi domain.chiron.recap.forecast.forecast_nutrition_adherence).

    Ritorna sempre un dict; `available=False` se l'atleta non ha
    un'assegnazione MACRO attiva (nessun errore, solo niente da mostrare).
    """
    assignment = (
        NutritionAssignment.objects
        .filter(client=client, status='ACTIVE', nutrition_plan__plan_mode='MACRO')
        .select_related('nutrition_plan')
        .order_by('-assigned_at')
        .first()
    )
    if not assignment:
        return {
            'available': False, 'reliable': False, 'n_log_days': 0,
            'weekday_pct': None, 'weekend_pct': None, 'overall_pct': None,
            'window_days': window_days, 'weekly_pct_series': [],
        }

    plan = assignment.nutrition_plan
    today = date.today()
    fetch_start = today - timedelta(days=max(window_days, series_window_days))

    entries = (
        ClientMacroLogEntry.objects
        .filter(assignment=assignment, log_date__gte=fetch_start, log_date__lt=today)
        .select_related('food')
    )

    kcal_by_day = {}
    for entry in entries:
        kcal_by_day[entry.log_date] = kcal_by_day.get(entry.log_date, 0.0) + entry.kcal

    headline_start = today - timedelta(days=window_days)
    headline_days = {d: k for d, k in kcal_by_day.items() if d >= headline_start}
    n_log_days = len(headline_days)

    weekday_ratios, weekend_ratios = [], []
    for log_date, kcal in headline_days.items():
        target = _day_target_kcal(plan, log_date)
        if not target:
            continue
        ratio = kcal / target
        bucket = weekend_ratios if log_date.weekday() >= 5 else weekday_ratios
        bucket.append(ratio)

    def _avg_pct(ratios):
        return round(sum(ratios) / len(ratios) * 100, 1) if ratios else None

    # Serie settimanale (lunedì di ogni settimana -> % aggregata) su TUTTA la
    # finestra fetch — più ampia dell'headline, per dare al forecast più punti.
    weekly_logged, weekly_target = {}, {}
    for log_date, kcal in kcal_by_day.items():
        target = _day_target_kcal(plan, log_date)
        if not target:
            continue
        monday = log_date - timedelta(days=log_date.weekday())
        weekly_logged[monday] = weekly_logged.get(monday, 0) + kcal
        weekly_target[monday] = weekly_target.get(monday, 0) + target
    weekly_pct_series = [
        (monday, round(weekly_logged[monday] / weekly_target[monday] * 100, 1))
        for monday in sorted(weekly_logged) if weekly_target.get(monday)
    ]

    return {
        'available': True,
        'reliable': n_log_days >= MIN_RELIABLE_LOG_DAYS,
        'n_log_days': n_log_days,
        'window_days': window_days,
        'weekday_pct': _avg_pct(weekday_ratios),
        'weekend_pct': _avg_pct(weekend_ratios),
        'overall_pct': _avg_pct(weekday_ratios + weekend_ratios),
        'weekly_pct_series': weekly_pct_series,
    }
