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
    /// Drives the StoreKit review prompt shown once after onboarding completes.
    @Published var showReview = false
    /// Drives the one-time coach profile setup wizard.
    @Published var showCoachChiron = false
    /// Slides the floating tab bar off-screen for immersive screens (e.g. chat,
    /// where it would otherwise cover the message composer).
    @Published var tabBarHidden = false
    /// True when the signed-in user still has to accept Terms + Privacy. Blocks
    /// the app behind a consent screen until they do.
    @Published var needsTermsConsent = false
    /// Set when `bootstrap()` fails for a reason other than an invalid token
    /// (offline, server hiccup) — the token is kept and the splash screen
    /// offers a retry instead of dropping the user back to the login form.
    @Published var bootstrapRetryable = false

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
            needsTermsConsent = me.user.needsTermsConsent
            showChiron = me.user.needsChironIntro
            if me.user.role.uppercased() == "COACH"
                && !UserDefaults.standard.bool(forKey: "athlynk.coach.chiron.done") {
                showCoachChiron = true
            }
            phase = .app
            Analytics.shared.configure()
            Analytics.shared.identify(userId: me.user.id, role: me.user.role, coachId: nil)
            Analytics.shared.capture(.appOpened)
            enablePushNotifications()
        } catch {
            // Only a genuine auth rejection means the token is stale — a
            // connectivity blip or server-side failure shouldn't log the user out.
            if case APIError.http(401, _) = error {
                api.token = nil
                Keychain.delete(tokenKey)
                phase = .login
            } else {
                bootstrapRetryable = true
            }
        }
    }

    func login(email: String, password: String, role: String) async {
        isAuthenticating = true
        loginError = nil
        defer { isAuthenticating = false }
        do {
            let res = try await api.login(email: email, password: password, role: role)
            api.token = res.token
            Keychain.set(res.token, for: tokenKey)
            user = res.user
            me = try? await api.me()
            avatarUrl = me?.profile?.imageUrl
            // Prefer the richer /me payload, but fall back to the login user.
            let identified = me?.user ?? res.user
            needsTermsConsent = identified.needsTermsConsent
            showChiron = identified.needsChironIntro
            if identified.role.uppercased() == "COACH"
                && !UserDefaults.standard.bool(forKey: "athlynk.coach.chiron.done") {
                showCoachChiron = true
            }
            Analytics.shared.configure()
            Analytics.shared.identify(userId: identified.id, role: identified.role, coachId: nil)
            if identified.role.uppercased() == "COACH" {
                Analytics.shared.capture(.coachLoggedIn)
            }
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { phase = .app }
            enablePushNotifications()
        } catch {
            Haptics.error()
            loginError = error.localizedDescription
        }
    }

    /// Record consent to Terms + Privacy and lift the gate. Returns false (gate
    /// stays up) if the request fails, so the view can show a retry message.
    @discardableResult
    func acceptTerms() async -> Bool {
        do {
            try await api.acceptTerms()
            needsTermsConsent = false
            return true
        } catch {
            Haptics.error()
            return false
        }
    }

    func logout() {
        AppDataCache.shared.invalidateAll()
        Analytics.shared.reset()
        api.token = nil
        Keychain.delete(tokenKey)
        user = nil
        me = nil
        avatarUrl = nil
        // Drop any open gate so the consent cover doesn't linger over the login.
        needsTermsConsent = false
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { phase = .login }
    }

    /// Dismiss the Chiron tutorial and persist that it has been seen.
    /// Triggers the review screen if the user hasn't rated yet.
    func finishChiron() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showChiron = false }
        Task { try? await api.completeTutorial() }
        let alreadyReviewed = UserDefaults.standard.bool(forKey: "athlynk.reviewDone")
        if !alreadyReviewed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { self.showReview = true }
            }
        }
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

/// Blocking consent gate shown when the signed-in user hasn't yet accepted the
/// Terms of Service + Privacy Policy. Shared by both the athlete and coach apps.
struct TermsConsentView: View {
    @EnvironmentObject var app: AppState
    @State private var working = false
    @State private var failed = false

    private let tos = URL(string: "https://app.athlynk.it/termini-di-servizio/")!
    private let privacy = URL(string: "https://app.athlynk.it/privacy/")!

    var body: some View {
        ZStack {
            Palette.void0.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(Palette.bronze)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Prima di iniziare").font(Typo.poster(32)).foregroundStyle(Palette.textHi)
                    Text("Per usare Athlynk devi accettare i nostri Termini di Servizio e la Privacy Policy.")
                        .font(Typo.body(15)).foregroundStyle(Palette.textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Link(destination: tos) { docRow("Termini di Servizio") }
                    Link(destination: privacy) { docRow("Privacy Policy") }
                }

                if failed {
                    Text("Non è stato possibile registrare il consenso. Controlla la connessione e riprova.")
                        .font(Typo.body(13)).foregroundStyle(Palette.crimson)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    working = true
                    failed = false
                    Task {
                        let ok = await app.acceptTerms()
                        working = false
                        failed = !ok
                    }
                } label: {
                    HStack {
                        Spacer()
                        if working { ProgressView().tint(Palette.void0) }
                        else { Text("Accetto e continuo").font(Typo.body(16, .bold)) }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.bronze))
                    .foregroundStyle(Palette.void0)
                }
                .disabled(working)

                Button { app.logout() } label: {
                    Text("Esci").font(Typo.body(14)).foregroundStyle(Palette.textLow)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 40)
        }
        .interactiveDismissDisabled(true)
    }

    private func docRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bronze)
            Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textLow)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.void1))
    }
}
