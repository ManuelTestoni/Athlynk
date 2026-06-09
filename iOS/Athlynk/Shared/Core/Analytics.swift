//
//  Analytics.swift
//  Thin PostHog wrapper. Mirrors the server event contract
//  (WebApp/src/domain/analytics/events.py) so the iOS, web and server streams
//  share one schema.
//
//  Guarded by `#if canImport(PostHog)` so the project BUILDS AND RUNS before the
//  PostHog SPM package is added — every call is a no-op until both the package
//  is linked and a POSTHOG_API_KEY is present. To activate:
//    1. Xcode ▸ File ▸ Add Packages… ▸ https://github.com/PostHog/posthog-ios
//       (add to both the Athlynk and AthlynkCoach targets).
//    2. Put POSTHOG_API_KEY / POSTHOG_HOST / ENVIRONMENT in the target Info.plist
//       (values from the xcconfig).
//

import Foundation

#if canImport(PostHog)
import PostHog
#endif

/// Event names — keep in lockstep with `events.py` (`Ev`) on the backend.
enum AnalyticsEvent: String {
    case appOpened = "app_opened"
    case screenViewed = "screen_viewed"
    case coachLoggedIn = "coach_logged_in"
    case clientListViewed = "client_list_viewed"
    case checkinOpened = "checkin_opened"
    case checkinReviewStarted = "checkin_review_started"
    case checkinReviewCompleted = "checkin_review_completed"
    case messageSent = "message_sent"
    case planUpdated = "plan_updated"
    case taskCreated = "task_created"
    case taskCompleted = "task_completed"
}

@MainActor
final class Analytics {
    static let shared = Analytics()

    static let eventVersion = "1.0"

    private var started = false

    /// Initialise the SDK once, if a key is configured. Safe to call repeatedly.
    func configure() {
        guard !started, let key = AppConfig.posthogKey, !key.isEmpty else { return }
        started = true
        #if canImport(PostHog)
        let cfg = PostHogConfig(apiKey: key, host: AppConfig.posthogHost)
        cfg.captureApplicationLifecycleEvents = false  // we send app_opened ourselves
        cfg.captureScreenViews = false                 // we send screen_viewed ourselves
        PostHogSDK.shared.setup(cfg)
        PostHogSDK.shared.register(baseSuperProperties())
        #endif
    }

    /// Properties attached to every event (the global schema).
    private func baseSuperProperties() -> [String: Any] {
        [
            "event_version": Analytics.eventVersion,
            "environment": AppConfig.environment,
            "platform": "ios",
            "app_version": AppConfig.appVersion,
        ]
    }

    /// Tie events to a user after login. `role`/`coachId` become super-properties.
    func identify(userId: Int, role: String, coachId: Int?) {
        configure()
        #if canImport(PostHog)
        guard started else { return }
        var props: [String: Any] = ["role": role]
        if let coachId { props["coach_id"] = coachId }
        PostHogSDK.shared.register(props)
        PostHogSDK.shared.identify("user:\(userId)", userProperties: props)
        #endif
    }

    func capture(_ event: AnalyticsEvent, _ properties: [String: Any] = [:]) {
        #if canImport(PostHog)
        guard started else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
        #endif
    }

    /// Convenience for navigation tracking.
    func screen(_ name: String) {
        capture(.screenViewed, ["screen": name])
    }

    /// Clear the identified person on logout / account switch.
    func reset() {
        #if canImport(PostHog)
        guard started else { return }
        PostHogSDK.shared.reset()
        #endif
    }
}
