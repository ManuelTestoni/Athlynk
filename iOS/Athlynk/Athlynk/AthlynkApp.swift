//
//  AthlynkApp.swift
//  Athlynk — athlete app entry point.
//

import SwiftUI
import Combine

@main
struct AthlynkApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}
