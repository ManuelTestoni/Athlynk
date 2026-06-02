//
//  ContentView.swift
//  Root router: splash → login → main app, cross-faded.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            switch app.phase {
            case .splash: SplashView()
            case .login:  LoginView()
            case .app:    MainTabView()
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: app.phase)
    }
}
