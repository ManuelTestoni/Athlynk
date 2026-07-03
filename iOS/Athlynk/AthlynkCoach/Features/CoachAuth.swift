//
//  CoachAuth.swift
//  Splash + login for Athlynk Coach. Reuses the shared AppState auth flow
//  (the same /api/v1/auth/login endpoint serves coaches and athletes).
//

import SwiftUI

struct CoachSplashView: View {
    @EnvironmentObject var app: AppState
    @State private var charge: CGFloat = 0
    @State private var show = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.cyan, Palette.violet, Palette.amber])

            VStack(spacing: 18) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [Palette.bronze, Palette.amber],
                                                    startPoint: .top, endPoint: .bottom))
                    .neonGlow(Palette.bronze, radius: 18)
                    .scaleEffect(show ? 1 : 0.4)
                    .rotationEffect(.degrees(show ? 0 : -25))

                GlitchText(text: "ATHLYNK", size: 52)
                Text("COACH")
                    .font(Typo.mono(15, .black)).tracking(14)
                    .foregroundStyle(Palette.bronze)
                    .opacity(show ? 1 : 0)

                Text("GUIDA · METODO · RISULTATO")
                    .font(Typo.mono(11, .bold)).tracking(5)
                    .foregroundStyle(Palette.textMid)
                    .opacity(show ? 1 : 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.void2)
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.bronze, Palette.amber],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * charge)
                            .neonGlow(Palette.bronze, radius: 8)
                    }
                }
                .frame(width: 180, height: 6).padding(.top, 8)

                if app.bootstrapRetryable {
                    Text("Connessione assente. Riprova.")
                        .font(Typo.mono(12, .bold))
                        .foregroundStyle(Palette.textMid)
                        .padding(.top, 12)
                    Button {
                        app.bootstrapRetryable = false
                        Task { await app.bootstrap() }
                    } label: {
                        Text("RIPROVA")
                            .font(Typo.mono(13, .bold))
                            .tracking(2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Palette.bronze))
                    }
                }
            }
        }
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { show = true }
            withAnimation(.easeInOut(duration: 1.1)) { charge = 1 }
            try? await Task.sleep(for: .seconds(1.2))
            await app.bootstrap()
        }
    }
}

struct CoachLoginView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var appear = false
    @State private var resetSent = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.violet, Palette.cyan, Palette.bronze])

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Spacer(minLength: 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AREA PROFESSIONISTI").voltEyebrow()
                        GlitchText(text: "STUDIO", size: 60)
                        Text("Accedi al tuo studio Athlynk Coach.")
                            .font(Typo.body(15)).foregroundStyle(Palette.textMid)
                    }
                    .revealUp(appear, index: 0)

                    VStack(spacing: 14) {
                        VoltField(icon: "envelope.fill", placeholder: "Email",
                                  text: $email, accent: Palette.cyan)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .focused($focus, equals: .email)
                        VoltField(icon: "lock.fill", placeholder: "Password",
                                  text: $password, secure: true, accent: Palette.bronze)
                            .focused($focus, equals: .password)
                    }
                    .revealUp(appear, index: 1)

                    if let err = app.loginError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(Typo.body(13, .semibold)).foregroundStyle(Palette.bronze)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    NeonButton(title: "Accedi", icon: "key.fill",
                               color: Palette.bronze, loading: app.isAuthenticating) {
                        focus = nil
                        Task { await app.login(email: email, password: password, role: "COACH") }
                    }
                    .revealUp(appear, index: 2)
                    .disabled(email.isEmpty || password.isEmpty)

                    Button {
                        guard !email.isEmpty else { return }
                        Task { try? await APIClient.shared.forgotPassword(email: email); resetSent = true }
                    } label: {
                        Text(resetSent ? "Email inviata, controlla la posta" : "Password dimenticata?")
                            .font(Typo.mono(12, .semibold)).foregroundStyle(Palette.cyan)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .revealUp(appear, index: 3)

                    Text("Connesso a \(APIClient.shared.baseURL)")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .revealUp(appear, index: 3)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 26)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { appear = true }
        .animation(.spring, value: app.loginError)
        .animation(.spring, value: resetSent)
    }
}
