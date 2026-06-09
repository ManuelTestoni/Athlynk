"""Train an XGBoost classifier for a target, with temporal validation and
honest metrics (PR-AUC, precision, recall, Brier), and register the artifact.

Bootstrap guard: when there are too few rows or only one class present, we still
produce a *bootstrap* model on the rule-based pseudo-label so the pipeline is
exercised — but it is flagged `is_bootstrap=True` and scoring treats it as
advisory. We never train on internal/test/mixed data (see ``dataset.load_dataset``).
"""

import hashlib
import logging
from datetime import datetime

from django.conf import settings
from django.utils import timezone

from . import FEATURE_COLUMNS
from .dataset import load_dataset, temporal_split

logger = logging.getLogger(__name__)

MIN_ROWS = 200          # below this, force bootstrap
MIN_POSITIVES = 20      # need enough positives for a real (non-bootstrap) model


def _require_libs():
    try:
        import numpy as np
        import xgboost as xgb
        from sklearn.metrics import (average_precision_score, brier_score_loss,
                                      precision_score, recall_score)
        import joblib  # noqa: F401
        return np, xgb, average_precision_score, brier_score_loss, precision_score, recall_score
    except ImportError as exc:
        raise RuntimeError(
            'ML deps missing (xgboost/scikit-learn/joblib). '
            'Install with: pip install -r requirements.txt'
        ) from exc


def _models_dir():
    d = getattr(settings, 'ANALYTICS_MODELS_DIR')
    d.mkdir(parents=True, exist_ok=True)
    return d


def _version_tag(target, n_rows):
    stamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    h = hashlib.sha1(f'{target}{stamp}{n_rows}'.encode()).hexdigest()[:8]
    return f'{target}-{stamp}-{h}'


def train(target, bootstrap=False, valid_fraction=0.2):
    """Train + register a model for ``target``. Returns the ModelVersion row."""
    np, xgb, avg_prec, brier, precision, recall = _require_libs()
    from ..models import ModelVersion

    if target == 'risk_class':
        bootstrap = True  # risk_class is always a rule-derived pseudo-label

    df, cols = load_dataset(target)
    n_rows = len(df)
    positives = int(df['label'].sum()) if n_rows else 0

    forced_bootstrap = bootstrap or n_rows < MIN_ROWS or positives < MIN_POSITIVES \
        or (n_rows and df['label'].nunique() < 2)

    if n_rows == 0:
        raise RuntimeError(
            f'No usable rows for target={target}. Run compute_daily_features first '
            f'(and accumulate history for real churn/renewal labels).'
        )

    train_df, valid_df = temporal_split(df, valid_fraction)
    if valid_df.empty or train_df.empty or train_df['label'].nunique() < 2:
        # Degenerate split (cold start) → train on everything, skip held-out metrics.
        train_df, valid_df = df, df.iloc[0:0]

    X_train = train_df[cols].to_numpy()
    y_train = train_df['label'].to_numpy()

    pos = max(int(y_train.sum()), 1)
    neg = max(int(len(y_train) - y_train.sum()), 1)
    scale_pos_weight = neg / pos  # counter class imbalance

    model = xgb.XGBClassifier(
        n_estimators=200, max_depth=4, learning_rate=0.05,
        subsample=0.9, colsample_bytree=0.9,
        scale_pos_weight=scale_pos_weight,
        objective='binary:logistic', eval_metric='aucpr',
        n_jobs=2, random_state=42,
    )
    model.fit(X_train, y_train)

    metrics = {'n_rows': n_rows, 'positives': positives, 'scale_pos_weight': round(scale_pos_weight, 3)}
    if not valid_df.empty and valid_df['label'].nunique() >= 2:
        X_val = valid_df[cols].to_numpy()
        y_val = valid_df['label'].to_numpy()
        proba = model.predict_proba(X_val)[:, 1]
        preds = (proba >= 0.5).astype(int)
        metrics.update({
            'pr_auc': round(float(avg_prec(y_val, proba)), 4),
            'precision': round(float(precision(y_val, preds, zero_division=0)), 4),
            'recall': round(float(recall(y_val, preds, zero_division=0)), 4),
            'brier': round(float(brier(y_val, proba)), 4),
            'n_valid': int(len(y_val)),
        })
    else:
        metrics['note'] = 'cold-start: no held-out validation set'

    # Feature importances (top contributors) for explainability.
    importances = dict(zip(cols, [round(float(v), 4) for v in model.feature_importances_]))
    metrics['top_features'] = dict(sorted(importances.items(), key=lambda kv: kv[1], reverse=True)[:8])

    version = _version_tag(target, n_rows)
    path = _models_dir() / f'{version}.json'
    model.save_model(str(path))

    # Activate this version, retire previous ones for the same target.
    ModelVersion.objects.filter(target=target, is_active=True).update(is_active=False)
    mv = ModelVersion.objects.create(
        target=target, version=version, path=str(path), metrics=metrics,
        n_train=int(len(train_df)), n_valid=int(metrics.get('n_valid', 0)),
        is_bootstrap=forced_bootstrap, is_active=True,
    )
    logger.info('Trained %s v=%s bootstrap=%s metrics=%s', target, version, forced_bootstrap, metrics)
    return mv
