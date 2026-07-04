# TrainElite → Athlynk

Full-stack fitness coaching platform. Repo hold web app, marketing site, iOS apps, docs.

## Structure

- `WebApp/` — Django app (coach + athlete web dashboard). Nutrition, workouts, progression tracking, check-ins, Chiron AI assistant, Stripe billing.
- `Website/` — marketing site (static, `athlynk.com`).
- `iOS/Athlynk/` — SwiftUI apps: athlete app + Coach app (2nd target, shared Xcode project).
- `docs/` — codebase documentation site.
- `graphify-out/` — generated knowledge graph of codebase.

## Stack

- Backend: Django, custom token auth, `/api/v1` for mobile.
- DB: Postgres via Supabase (session pooler), media on Supabase Storage (S3-compatible, private).
- Hosting: Railway (`start.sh` dispatches by `RAILWAY_SERVICE_NAME` — web service vs analytics cron).
- Frontend: Tailwind (local build), Alpine.js, Chart.js.
- ML: XGBoost churn prediction, PostHog analytics (optional, `domain.analytics` degrades to no-op without `POSTHOG_KEY`).
- Payments: Stripe (coach subscriptions + Athlynk platform purchases via redeem codes).

## Local dev

`DATABASE_URL` → sqlite for local (prod `.env` points at Supabase — don't run migrate against it by accident). See `WebApp/README.md`.
