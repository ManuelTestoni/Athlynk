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
    @StateObject private var confirmCenter = ConfirmCenter()

    var body: some Scene {
        WindowGroup {
            CoachRootView()
                .environmentObject(app)
                .environmentObject(confirmCenter)
                .confirmDialogHost(confirmCenter)
                .preferredColorScheme(.light)
                .statusBarHidden(false)
        }
    }
}

/// Root router for the coach app: splash → login → main shell, cross-faded.
/// Mirrors the athlete `ContentView` but routes into the coach tab shell.
struct CoachRootView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("athlynk.coach.onboarded") private var coachOnboarded = false

    var body: some View {
        ZStack {
            switch app.phase {
            case .splash: CoachSplashView()
            case .login:
                if coachOnboarded {
                    CoachLoginView()
                } else {
                    CoachOnboardingView { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { coachOnboarded = true } }
                }
            case .app: CoachMainTabView()
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: app.phase)
        .fullScreenCover(isPresented: $app.needsTermsConsent) {
            TermsConsentView().environmentObject(app)
        }
        .fullScreenCover(isPresented: $app.showCoachChiron) {
            CoachChironIntroView {
                UserDefaults.standard.set(true, forKey: "athlynk.coach.chiron.done")
                app.showCoachChiron = false
                guard !UserDefaults.standard.bool(forKey: "athlynk.reviewDone") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { app.showReview = true }
            }
        }
        .fullScreenCover(isPresented: $app.showReview) {
            ReviewRequestView { app.showReview = false }
        }
    }
}
