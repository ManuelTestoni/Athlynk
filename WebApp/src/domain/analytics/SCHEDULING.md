# Scheduling the daily analytics job (production)

`run_daily_analytics` is a **batch snapshot**: it reads Postgres (the source of
truth, written continuously by the app) and computes the day's
`DailyFeatureStore → RiskScoreDaily → CoachBusinessMetricsDaily`. It does **not**
run itself — schedule it once per day on whatever hosts the Django app.

Wrapper (resolves its own paths, machine-agnostic):
`WebApp/src/scripts/run_daily_analytics.sh`

The command is idempotent (re-running a day upserts), so a missed run is harmless —
just runs the next day; trigger a manual catch-up with `--date YYYY-MM-DD` if needed.

## Pick the option matching your host

### A. VPS / own server (gunicorn + nginx) — system cron
Edit the app user's crontab (`crontab -e`):
```cron
0 2 * * *  /abs/path/TrainElite/WebApp/src/scripts/run_daily_analytics.sh >> /var/log/athlynk_analytics.log 2>&1
```
Runs nightly at 02:00. Ensure the user owns the venv + repo.

### B. PaaS scheduled jobs (command = `python manage.py run_daily_analytics`)
- **Render** → add a **Cron Job** service, schedule `0 2 * * *`, same env as the web service.
- **Railway** → a **Cron** service (or `railway.json` cron) with the command.
- **Heroku** → **Heroku Scheduler** add-on, daily, `python manage.py run_daily_analytics`.
- **Fly.io** → a scheduled machine / `[ [statics] ]`-style cron process.
- **PythonAnywhere** → **Tasks** tab → daily scheduled task with the full command.

### C. No always-on server — GitHub Actions (serverless cron)
A scheduled workflow runs the job from CI against the production DB. Needs
`DATABASE_URL` (+ any other prod env) as repo secrets. Sketch
`.github/workflows/daily-analytics.yml`:
```yaml
name: daily-analytics
on:
  schedule: [{ cron: '0 2 * * *' }]   # UTC
  workflow_dispatch: {}
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.13' }
      - run: pip install -r requirements.txt
      - run: python WebApp/src/manage.py run_daily_analytics
        working-directory: .
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          SECRET_KEY: ${{ secrets.SECRET_KEY }}
          ANALYTICS_ENVIRONMENT: production
```
Note: cron in GitHub Actions is **UTC** and best-effort (can be delayed under load).

## Weekly model retrain (later, optional)
Only once real churn history exists. Separate, slower cadence — **not** nightly
(see CONTAMINATION_CHECKLIST.md and the cold-start notes):
```cron
0 3 * * 1  /abs/path/.../run_daily_analytics.sh  # placeholder; swap for a train wrapper
```
Train with `python manage.py train_risk_model --target churn_30d` (no `--bootstrap`)
and promote only if PR-AUC / recall hold. Nightly scoring (`--ml-target auto`)
picks up the new active model automatically.
```
