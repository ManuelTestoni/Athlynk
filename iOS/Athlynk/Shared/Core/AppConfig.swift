//
//  AppConfig.swift
//  Per-build configuration read from Info.plist (injected via xcconfig).
//
//  Keys (add to each target's Info.plist, values supplied by the matching
//  xcconfig — see Debug.xcconfig / Staging.xcconfig / Release.xcconfig):
//    API_BASE_URL      e.g. http://localhost:8000  |  https://api.athlynk.app
//    POSTHOG_API_KEY   PostHog project write key (empty -> analytics off)
//    POSTHOG_HOST      https://eu.i.posthog.com
//    ENVIRONMENT       development | staging | production
//
//  Everything has a safe default so the app builds and runs before any of this
//  is wired (analytics simply stays off and the base URL falls back to local).
//

import Foundation

enum AppConfig {
    private static func string(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = v.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Backend base URL. Falls back to the local dev server.
    static var apiBaseURL: String {
        string("API_BASE_URL") ?? "https://athlynk-production.up.railway.app"
    }

    /// PostHog project key; empty/absent disables analytics entirely.
    static var posthogKey: String? { string("POSTHOG_API_KEY") }

    static var posthogHost: String { string("POSTHOG_HOST") ?? "https://eu.i.posthog.com" }

    /// development | staging | production (tags every analytics event).
    static var environment: String { string("ENVIRONMENT") ?? "development" }

    /// Short app version string for the `app_version` super-property.
    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }
}
