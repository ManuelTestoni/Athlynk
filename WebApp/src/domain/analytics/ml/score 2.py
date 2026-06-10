"""Batch scoring: load the active model for a target and write
``risk_probability_ml`` onto the day's RiskScoreDaily rows.

Advisory by design — the rule-based score is always the shown signal; the ML
probability augments it. A bootstrap model still scores, but its provenance is
recorded via ``model_version`` so the dashboard can label it.
"""

import logging

from . import FEATURE_COLUMNS

logger = logging.getLogger(__name__)


def _load_active_model(target):
    """Return ``(booster, version)`` for the active model, or ``(None, None)``."""
    from ..models import ModelVersion
    mv = ModelVersion.objects.filter(target=target, is_active=True).first()
    if mv is None:
        return None, None
    try:
        import xgboost as xgb
        model = xgb.XGBClassifier()
        model.load_model(mv.path)
        return model, mv.version
    except Exception as exc:
        logger.warning('Could not load model %s: %s', getattr(mv, 'version', '?'), exc)
        return None, None


def score_day(snapshot_date, target='churn_30d'):
    """Fill ``risk_probability_ml`` for every feature row on ``snapshot_date``.

    Returns the number of rows scored (0 when no model is active).
    """
    model, version = _load_active_model(target)
    if model is None:
        return 0

    import numpy as np
    from ..models import DailyFeatureStore, RiskScoreDaily

    rows = list(DailyFeatureStore.objects.filter(snapshot_date=snapshot_date))
    if not rows:
        return 0

    X = np.array([[float(getattr(r, c) or 0) for c in FEATURE_COLUMNS] for r in rows], dtype='float64')
    proba = model.predict_proba(X)[:, 1]

    scored = 0
    for row, p in zip(rows, proba):
        updated = RiskScoreDaily.objects.filter(
            client_id=row.client_id, snapshot_date=snapshot_date,
        ).update(risk_probability_ml=float(p), model_version=version)
        scored += updated
    logger.info('Scored %s rows with %s (%s)', scored, target, version)
    return scored
