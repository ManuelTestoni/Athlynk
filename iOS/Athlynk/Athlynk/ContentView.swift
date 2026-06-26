//
//  ContentView.swift
//  Root router: splash → login → main app, cross-faded.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @AppStorage("athlynk.onboarded") private var onboarded = false

    var body: some View {
        ZStack {
            switch app.phase {
            case .splash: SplashView()
            case .login:
                if onboarded {
                    LoginView()
                } else {
                    OnboardingView { withAnimation(.spring) { onboarded = true } }
                }
            case .app: MainTabView()
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: app.phase)
        .fullScreenCover(isPresented: $app.needsTermsConsent) {
            TermsConsentView()
        }
        .fullScreenCover(isPresented: $app.showChiron) {
            ChironTutorialView(userName: app.greetingName) { app.finishChiron() }
        }
        .fullScreenCover(isPresented: $app.showReview) {
            ReviewRequestView { app.showReview = false }
        }
    }
}
