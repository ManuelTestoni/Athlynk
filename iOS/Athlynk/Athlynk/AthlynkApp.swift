//
//  AthlynkApp.swift
//  Athlynk — athlete app entry point.
//

import SwiftUI
import Combine
import UIKit
import UserNotifications

@main
struct AthlynkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}

extension Notification.Name {
    /// Posted when a remote push signals server-side data changed. The visible
    /// screen refetches only its slice (see `View.onRemoteChange`). userInfo
    /// carries the APNs `type` (WORKOUT_ASSIGNED, MESSAGE, …) so each screen
    /// reloads only for the changes it cares about — no wasted requests.
    static let athlynkRemoteChange = Notification.Name("athlynk.remoteChange")
}

/// Receives the APNs device token and forwards it to the backend, and turns
/// incoming pushes into local refresh events. Fully inert until the Push
/// Notifications capability + APNs key are added to the target: without an
/// `aps-environment` entitlement iOS just calls didFailToRegister, which we
/// ignore.
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
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        broadcast(userInfo)
        return .newData
    }

    /// Alert arriving while the app is foregrounded: still show it, and refresh.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        broadcast(notification.request.content.userInfo)
        return [.banner, .sound, .badge]
    }

    /// User tapped the notification: refresh so the destination is up to date.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        broadcast(response.notification.request.content.userInfo)
    }

    private func broadcast(_ userInfo: [AnyHashable: Any]) {
        let type = userInfo["type"] as? String ?? ""
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
