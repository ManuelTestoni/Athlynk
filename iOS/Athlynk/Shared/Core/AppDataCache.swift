//
//  AppDataCache.swift
//  @MainActor in-memory cache with configurable TTL. Shared by both apps.
//  Keys are plain strings (e.g. "dashboard.workouts", "coach.dashboard").
//  Cleared on logout so a subsequent login sees fresh data.
//

import Foundation

@MainActor
final class AppDataCache {
    static let shared = AppDataCache()

    /// How long a cached entry is considered fresh. Default: 5 minutes.
    var staleDuration: TimeInterval = 300

    private struct Entry { let data: Any; let at: Date }
    private var store: [String: Entry] = [:]

    func get<T>(_ key: String) -> T? {
        guard let e = store[key], Date().timeIntervalSince(e.at) < staleDuration else { return nil }
        return e.data as? T
    }

    func set<T>(_ key: String, _ value: T) {
        store[key] = Entry(data: value, at: Date())
    }

    func invalidate(_ key: String) { store.removeValue(forKey: key) }
    func invalidateAll() { store.removeAll() }
}
