# TrainElite → Athlynk

Athlynk is a coaching platform that connects athletes with their coaches. Everything —
the web console, the iOS apps, and the Android apps — runs on one shared brain: a Django
backend that speaks JSON. Build a feature once on the server and it shows up, consistent,
on every surface.

The three surfaces share one visual language too: a deep blue (`#1E3A5F`) with an azure
accent (`#5B89B6`) and a touch of gold (`#FFE066`), Bodoni Moda for headings and Inter for
text. The same palette lives in `WebApp/static/css/athlynk.css`, the iOS theme, and the
Flutter theme, so the apps look like siblings without extra effort.

## What's in the repo

- `WebApp/` — the Django backend and the web console for coaches and athletes: workouts,
  nutrition, progression tracking, check-ins, the Chiron AI assistant, and billing. This is
  also the single source of truth for the customizable dashboard the apps render.
- `Website/` — the marketing site, plus the code documentation at `Website/docs/`
  (published at athlynk.it/docs/).
- `iOS/Athlynk/` — the native SwiftUI apps (athlete + coach) in one Xcode project.
- `android/` — the Flutter apps (athlete + coach), one codebase with two entry points,
  mirroring the iOS apps.
- `graphify-out/` — a generated knowledge graph of the codebase.

## Stack

- Backend: Django, custom token auth, `/api/v1` for mobile.
- DB: Postgres via Supabase (session pooler), media on Supabase Storage (S3-compatible, private).
- Hosting: Railway (`start.sh` dispatches by `RAILWAY_SERVICE_NAME` — web service vs analytics cron).
- Frontend: Tailwind (local build), Alpine.js, Chart.js.
- ML: XGBoost churn prediction, PostHog analytics (optional, `domain.analytics` degrades to no-op without `POSTHOG_KEY`).
- Payments: Stripe (coach subscriptions + Athlynk platform purchases via redeem codes).

## Local dev

`DATABASE_URL` → sqlite for local (prod `.env` points at Supabase — don't run migrate against it by accident). See `WebApp/README.md`.
