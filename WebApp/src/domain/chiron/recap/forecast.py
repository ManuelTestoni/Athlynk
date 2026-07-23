"""Prediction layer del recap: regressione lineare, un metodo solo — niente
ARIMA/ML multivariato. Con 4-12 punti per atleta qualunque modello oltre una
retta farebbe overfitting ed è inspiegabile a un coach. Vedi §5 del piano.

V1 copriva solo il peso. V2 (qui) generalizza lo stesso fit a circonferenze e
aderenza nutrizionale settimanale — con soglie più severe, perché quei dati
sono più sparsi/rumorosi del peso: servono più punti prima di fidarsi di un
trend, e la "banda morta" (sotto la quale la direzione è 'stable') è tarata
sul rumore naturale di ciascuna metrica, non un valore unico copiato dal peso.
"""

from datetime import date as _date

from .schemas import RecapForecast

CAVEAT = (
    "Proiezione lineare ingenua sul trend recente, non un modello predittivo — "
    "assume che il trend continui invariato."
)

# Peso: il segnale più denso e universale — soglie originarie (V1).
WEIGHT_MIN_POINTS = 3
WEIGHT_HIGH_R2_MIN_N = 5
WEIGHT_DEAD_BAND = 0.3

# Circonferenze: si muovono più lente e si misurano meno spesso del peso —
# serve un punto in più prima di proiettare, e un rumore di misurazione
# tipico più ampio (mano/nastro) prima di chiamarlo un vero trend.
CIRCUMFERENCE_MIN_POINTS = 4
CIRCUMFERENCE_HIGH_R2_MIN_N = 6
CIRCUMFERENCE_DEAD_BAND = 0.5

# Aderenza nutrizionale settimanale: percentuale, non un'unità fisica — banda
# morta più larga (rumore settimana-su-settimana naturalmente alto) e più
# punti richiesti (una settimana sola non è un trend).
NUTRITION_MIN_POINTS = 4
NUTRITION_HIGH_R2_MIN_N = 6
NUTRITION_DEAD_BAND = 5.0


def _linreg(points):
    """points: [(x:int, y:float)]. Ritorna (slope, intercept, r2)."""
    n = len(points)
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    x_mean, y_mean = sum(xs) / n, sum(ys) / n
    ss_xx = sum((x - x_mean) ** 2 for x in xs)
    if ss_xx == 0:
        return 0.0, y_mean, 0.0
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / ss_xx
    intercept = y_mean - slope * x_mean
    ss_tot = sum((y - y_mean) ** 2 for y in ys)
    if ss_tot == 0:
        return slope, intercept, 1.0
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
    return slope, intercept, max(0.0, 1 - ss_res / ss_tot)


def _fit_forecast(series, metric, min_points, high_r2_min_n, dead_band):
    """Nucleo condiviso: fit lineare su una serie (data, valore) qualunque,
    usato per peso, circonferenze e aderenza nutrizionale settimanale."""
    points = sorted(series, key=lambda p: p[0])[-6:]
    if len(points) < min_points:
        return RecapForecast(metric=metric, available=False, caveat=CAVEAT)

    origin = points[0][0]
    xy = [((d - origin).days, v) for d, v in points]
    slope, intercept, r2 = _linreg(xy)

    if r2 < 0.3:
        confidence = 'low'
    elif r2 < 0.6:
        confidence = 'medium'
    else:
        confidence = 'high' if len(points) >= high_r2_min_n else 'medium'

    last_offset = xy[-1][0]
    proj_2w = slope * (last_offset + 14) + intercept
    proj_4w = slope * (last_offset + 28) + intercept
    change_2w = proj_2w - points[-1][1]

    if abs(change_2w) < dead_band:
        direction = 'stable'
    else:
        direction = 'up' if change_2w > 0 else 'down'

    return RecapForecast(
        metric=metric, available=True, direction=direction, confidence=confidence,
        projected_2w=round(proj_2w, 1), projected_4w=round(proj_4w, 1), caveat=CAVEAT,
    )


def forecast_weight(weight_series, today=None):
    """weight_series: [(date, value)] da aggregates_body.compute_body_comp."""
    return _fit_forecast(weight_series, 'weight_kg', WEIGHT_MIN_POINTS, WEIGHT_HIGH_R2_MIN_N, WEIGHT_DEAD_BAND)


def forecast_circumference(series, key, today=None):
    """series: [(date, value)] da body['circumferences'][key]['series']."""
    return _fit_forecast(series, f'circumference_{key}', CIRCUMFERENCE_MIN_POINTS,
                          CIRCUMFERENCE_HIGH_R2_MIN_N, CIRCUMFERENCE_DEAD_BAND)


def forecast_nutrition_adherence(weekly_pct_series, today=None):
    """weekly_pct_series: [(week_start_date, pct)] da
    domain.nutrition.adherence.compute_adherence()['weekly_pct_series']."""
    return _fit_forecast(weekly_pct_series, 'nutrition_adherence_pct', NUTRITION_MIN_POINTS,
                          NUTRITION_HIGH_R2_MIN_N, NUTRITION_DEAD_BAND)
