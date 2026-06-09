#!/usr/bin/env bash
#
# Nightly analytics snapshot — wrapper for cron.
# Resolves paths from its own location so the crontab line stays machine-agnostic:
#   0 2 * * *  /abs/path/WebApp/src/scripts/run_daily_analytics.sh >> /tmp/athlynk_analytics.log 2>&1
#
# Computes the day's DailyFeatureStore -> RiskScoreDaily -> CoachBusinessMetricsDaily.
# Idempotent: re-running for the same day upserts (update_or_create).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"        # WebApp/src
ROOT_DIR="$(cd "$SRC_DIR/../.." && pwd)"        # repo root

PY="$ROOT_DIR/venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

cd "$SRC_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] run_daily_analytics start"
exec "$PY" manage.py run_daily_analytics "$@"
