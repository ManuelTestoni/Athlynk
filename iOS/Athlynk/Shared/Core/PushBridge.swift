//
//  PushBridge.swift
//  Shared APNs plumbing used by both the athlete and coach apps.
//
//  Turns incoming remote pushes into in-app refresh events and forwards the
//  device token to the backend. Fully inert until the Push Notifications
//  capability + APNs key are added to a target.
//

import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted when a remote push signals server-side data changed. The visible
    /// screen refetches only its slice (see `View.onRemoteChange`). userInfo
    /// carries the APNs `type` (WORKOUT_ASSIGNED, MESSAGE, …) so each screen
    /// reloads only for the changes it cares about — no wasted requests.
    static let athlynkRemoteChange = Notification.Name("athlynk.remoteChange")
}

/// Receives the APNs device token and forwards it to the backend, and turns
/// incoming pushes into local refresh events.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await APIClient.shared.registerDevice(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected before the push entitlement/key exist — no-op.
        #if DEBUG
        print("APNs registration unavailable: \(error.localizedDescription)")
        #endif
    }

    /// Background/foreground data push (content-available): refetch the changed
    /// slice without the user opening the app.
    nonisolated func application(_ application: UIApplication,
                                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let type = userInfo["type"] as? String ?? ""
        await broadcast(type: type)
        return .newData
    }

    /// Alert arriving while the app is foregrounded: still show it, and refresh.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        broadcast(type: notification.request.content.userInfo["type"] as? String ?? "")
        return [.banner, .sound, .badge]
    }

    /// User tapped the notification: refresh so the destination is up to date.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        broadcast(type: response.notification.request.content.userInfo["type"] as? String ?? "")
    }

    /// Posting drives SwiftUI `.onReceive` handlers, which mutate view state — so
    /// it MUST run on the main thread. The push callbacks are `nonisolated`, so
    /// posting from them directly would deliver `.onReceive` off-main → SwiftUI
    /// state mutated off the main actor → AttributeGraph corruption (main-thread
    /// hang / watchdog kill). Hop to the main actor first.
    @MainActor
    private func broadcast(type: String) {
        NotificationCenter.default.post(name: .athlynkRemoteChange, object: nil,
                                        userInfo: ["type": type])
    }
}

extension View {
    /// Reload when a push signals a relevant change. `types` empty = react to any
    /// change; otherwise only when the push `type` is in the set.
    func onRemoteChange(_ types: Set<String> = [], perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .athlynkRemoteChange)) { note in
            let type = note.userInfo?["type"] as? String ?? ""
            if types.isEmpty || types.contains(type) { action() }
        }
    }
}
