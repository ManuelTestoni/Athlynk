# iOS analytics & environment config

One-time Xcode wiring to activate PostHog + per-environment backend URLs. Until
this is done the app still builds and runs: `Analytics` is a no-op and
`AppConfig.apiBaseURL` falls back to `http://localhost:8000`.

## 1. Add the PostHog SDK (SPM)

Xcode ▸ **File ▸ Add Package Dependencies…** →
`https://github.com/PostHog/posthog-ios` → add the **PostHog** product to **both**
targets: `Athlynk` and `AthlynkCoach`.

`Shared/Core/Analytics.swift` is guarded by `#if canImport(PostHog)`, so it
starts emitting events automatically once the package is linked.

## 2. Wire the xcconfig files

1. Add `Config/Debug.xcconfig`, `Staging.xcconfig`, `Release.xcconfig` to the
   project (no target membership needed).
2. Project ▸ **Info ▸ Configurations**: set each configuration’s file to the
   matching xcconfig (duplicate Release → "Staging" if you want a staging config).

## 3. Expose the keys via Info.plist

In **each** target’s Info.plist add these rows (values are `$(KEY)` references so
they resolve from the active xcconfig):

| Key              | Value              |
|------------------|--------------------|
| `API_BASE_URL`   | `$(API_BASE_URL)`  |
| `POSTHOG_API_KEY`| `$(POSTHOG_API_KEY)`|
| `POSTHOG_HOST`   | `$(POSTHOG_HOST)`  |
| `ENVIRONMENT`    | `$(ENVIRONMENT)`   |

`AppConfig` reads these at runtime.

## 4. Fill in the keys

Put the project write keys into the xcconfig files. **Use a separate PostHog
project key per environment** (Debug/Staging/Production) so test traffic never
contaminates production analytics. Leave `POSTHOG_API_KEY` empty to keep
analytics off for a build.

## What’s instrumented

- `app_opened`, `coach_logged_in` — `AppState` (`bootstrap`/`login`); `reset()` on `logout`.
- `screen_viewed` — `CoachShell` tab changes.
- `client_list_viewed` — `CoachClientsView`.
- `checkin_opened` / `checkin_review_started` / `checkin_review_completed` — `CoachChecksView`.
- `message_sent` — `CoachMessagesView`.
- `plan_updated` — `CoachPlanCreateView`.

Event names mirror `WebApp/src/domain/analytics/events.py` — keep them in lockstep.
