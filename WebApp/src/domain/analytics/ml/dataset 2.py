"""Build the flat training frame from the feature store.

Anti-contamination is enforced *here*, at the dataset boundary: internal/test
rows and non-production environments never enter the frame. pandas is imported
lazily so importing this module is cheap.
"""

from . import FEATURE_COLUMNS
from . import labels as labelmod


def _require_pandas():
    try:
        import pandas as pd  # noqa: F401
        return pd
    except ImportError as exc:
        raise RuntimeError(
            'pandas is required for the ML pipeline. Install analytics deps: '
            'pip install -r requirements.txt'
        ) from exc


def load_dataset(target, environment='production', exclude_flagged=True):
    """Return ``(df, feature_columns)`` where df has the feature columns plus a
    ``label`` and ``snapshot_date`` column. Rows with an unknown (None) label are
    dropped.
    """
    pd = _require_pandas()
    from ..models import DailyFeatureStore

    qs = DailyFeatureStore.objects.all()
    if environment:
        qs = qs.filter(environment=environment)
    if exclude_flagged:
        qs = qs.filter(is_internal_user=False, is_test_account=False)
    qs = qs.order_by('snapshot_date')

    records = []
    for row in qs.iterator():
        label = labelmod.label_for(target, row, row.snapshot_date)
        if label is None:
            continue
        rec = {col: getattr(row, col) for col in FEATURE_COLUMNS}
        rec['active_package_price'] = float(rec['active_package_price'] or 0)
        rec['label'] = int(label)
        rec['snapshot_date'] = row.snapshot_date
        records.append(rec)

    df = pd.DataFrame.from_records(records)
    if not df.empty:
        df[FEATURE_COLUMNS] = df[FEATURE_COLUMNS].astype('float64').fillna(0.0)
    return df, FEATURE_COLUMNS


def temporal_split(df, valid_fraction=0.2):
    """Split by time: earliest snapshots train, latest validate. Never random —
    a churn model judged on a random split leaks the future into training.
    """
    if df.empty:
        return df, df
    dates = sorted(df['snapshot_date'].unique())
    if len(dates) < 2:
        # Not enough distinct days to hold out by time → fall back to row order.
        cut = max(1, int(len(df) * (1 - valid_fraction)))
        return df.iloc[:cut], df.iloc[cut:]
    cut_idx = max(1, int(len(dates) * (1 - valid_fraction)))
    cutoff = dates[cut_idx]
    train = df[df['snapshot_date'] < cutoff]
    valid = df[df['snapshot_date'] >= cutoff]
    return train, valid
