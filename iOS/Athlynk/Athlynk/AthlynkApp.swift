//
//  AthlynkApp.swift
//  Athlynk — athlete app entry point.
//

import SwiftUI
import Combine
import UIKit

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

/// Receives the APNs device token and forwards it to the backend. Fully inert
/// until the Push Notifications capability + APNs key are added to the target:
/// without an `aps-environment` entitlement iOS just calls didFailToRegister,
/// which we ignore.
final class AppDelegate: NSObject, UIApplicationDelegate {
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
}
