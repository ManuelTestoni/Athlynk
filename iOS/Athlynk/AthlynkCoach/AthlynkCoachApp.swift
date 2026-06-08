//
//  AthlynkCoachApp.swift
//  Athlynk Coach — entry point for the coach / trainer / nutritionist app.
//  Shares the Athlynk design system + networking layer (see Shared/).
//

import SwiftUI

@main
struct AthlynkCoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            CoachRootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}

/// Root router for the coach app: splash → login → main shell, cross-faded.
/// Mirrors the athlete `ContentView` but routes into the coach tab shell.
struct CoachRootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            switch app.phase {
            case .splash: CoachSplashView()
            case .login:  CoachLoginView()
            case .app:    CoachMainTabView()
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: app.phase)
    }
}
