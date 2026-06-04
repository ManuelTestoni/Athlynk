//
//  AppState.swift
//  Auth + session lifecycle for the whole app.
//

import SwiftUI
import Combine
import UIKit
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    enum Phase { case splash, login, app }

    @Published var phase: Phase = .splash
    @Published var user: AuthUser?
    @Published var me: MeResponse?
    /// The athlete's profile-photo URL, surfaced app-wide for header avatars.
    @Published var avatarUrl: String?
    @Published var loginError: String?
    @Published var isAuthenticating = false
    /// Drives the one-time Chiron mascot tutorial (clients, first login only).
    @Published var showChiron = false

    private let tokenKey = "athlynk.api.token"
    private let api = APIClient.shared

    init() {
        api.token = Keychain.get(tokenKey)
    }

    /// Decide where to send the user after the splash animation.
    func bootstrap() async {
        guard api.token != nil else { phase = .login; return }
        do {
            let me = try await api.me()
            self.me = me
            self.user = me.user
            self.avatarUrl = me.profile?.imageUrl
            showChiron = me.user.needsChironIntro
            phase = .app
            enablePushNotifications()
        } catch {
            // Token stale / server down → back to login.
            api.token = nil
            Keychain.delete(tokenKey)
            phase = .login
        }
    }

    func login(email: String, password: String) async {
        isAuthenticating = true
        loginError = nil
        defer { isAuthenticating = false }
        do {
            let res = try await api.login(email: email, password: password)
            api.token = res.token
            Keychain.set(res.token, for: tokenKey)
            user = res.user
            me = try? await api.me()
            avatarUrl = me?.profile?.imageUrl
            // Prefer the richer /me payload, but fall back to the login user.
            showChiron = (me?.user ?? res.user).needsChironIntro
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { phase = .app }
            enablePushNotifications()
        } catch {
            Haptics.error()
            loginError = error.localizedDescription
        }
    }

    func logout() {
        api.token = nil
        Keychain.delete(tokenKey)
        user = nil
        me = nil
        avatarUrl = nil
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .login }
    }

    /// Dismiss the Chiron tutorial and persist that it has been seen.
    func finishChiron() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showChiron = false }
        Task { try? await api.completeTutorial() }
    }

    /// Deactivate the account server-side, then drop the local session.
    func deleteAccount() async {
        try? await api.deleteAccount()
        logout()
    }

    /// Ask for notification permission, then register for remote (APNs) push.
    /// Safe before the push entitlement exists: registration simply fails and is
    /// ignored by the AppDelegate, so nothing breaks until the key is added.
    func enablePushNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    var greetingName: String {
        let n = user?.firstName ?? ""
        return n.isEmpty ? "Atleta" : n
    }
}
