//
//  AppState.swift
//  Auth + session lifecycle for the whole app.
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase { case splash, login, app }

    @Published var phase: Phase = .splash
    @Published var user: AuthUser?
    @Published var me: MeResponse?
    @Published var loginError: String?
    @Published var isAuthenticating = false

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
            phase = .app
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
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { phase = .app }
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
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .login }
    }

    var greetingName: String {
        let n = user?.firstName ?? ""
        return n.isEmpty ? "Atleta" : n
    }
}
