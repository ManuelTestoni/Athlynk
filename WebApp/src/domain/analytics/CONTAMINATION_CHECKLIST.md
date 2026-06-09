# Anti-contamination checklist

The app is still in testing, so the #1 risk is poisoning analytics/ML with
internal and test traffic. PostHog filters only *hide* data in the UI — they do
**not** stop capture — so contamination must be prevented **at the source** and
again at every aggregation boundary. This is the standing checklist.

## Environments
- [ ] **Separate PostHog project per environment** (development / staging / production),
      each with its own `POSTHOG_KEY`. Never reuse the production key elsewhere.
- [ ] Every event/row also carries an `environment` super-property/column
      (`ANALYTICS_ENVIRONMENT` server-side, `ENVIRONMENT` in the iOS xcconfig) as a
      second line of defence.
- [ ] Local/dev: keep `POSTHOG_KEY` empty (the SDK no-ops) unless deliberately testing.

## Internal / test users
- [ ] Mark staff with `User.is_internal_user = True`, test accounts with
      `User.is_test_account = True`.
- [ ] Keep the env allowlists current: `TEST_ACCOUNT_EMAILS`, `INTERNAL_EMAIL_DOMAINS`.
- [ ] Both flags ride on every event as super-properties (web context processor +
      iOS identify) and on every `DailyFeatureStore` / `RiskScoreDaily` row.

## Feature store & KPIs
- [ ] `build_and_store` stamps `is_internal_user` / `is_test_account` / `environment`
      on each row (it does — see `services/features.py`).
- [ ] Production KPI dashboards filter `environment='production'` and exclude flagged rows.
- [ ] The web dashboard keeps test vs production cohorts separate (filter, never mix).

## ML pipeline
- [ ] `ml/dataset.load_dataset` excludes `is_internal_user` / `is_test_account` and
      filters `environment='production'` — verify this guard is intact before training.
- [ ] Temporal validation only (never a random split) so the future can't leak into training.
- [ ] Never train a non-bootstrap model on test/mixed/bootstrap rows; real churn/renewal
      labels only once enough clean history exists.
- [ ] `risk_probability_ml` stays advisory; the explainable rule score is the shown signal.

## Consent (web)
- [ ] PostHog only initialises with `analytics` cookie consent granted; otherwise
      `opt_out_capturing()` (see `templates/partials/posthog.html`).
- [ ] `reset()` fires on logout so a shared browser doesn't blend two people.

## Release gate
- [ ] Before any production model ships: confirm row counts, class balance, and that
      zero flagged/non-production rows entered the dataset.
