//
//  AthlynkApp.swift
//  Athlynk — athlete app entry point. Shared APNs plumbing lives in
//  Shared/Core/PushBridge.swift (used by the coach app too).
//

import SwiftUI

@main
struct AthlynkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @StateObject private var confirmCenter = ConfirmCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .environmentObject(confirmCenter)
                .confirmDialogHost(confirmCenter)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}
