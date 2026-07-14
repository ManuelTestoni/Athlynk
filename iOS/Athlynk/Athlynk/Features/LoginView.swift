//
//  LoginView.swift
//

import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var appear = false
    @State private var showForgot = false
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Spacer(minLength: 60)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("BENVENUTO").voltEyebrow()
                        GlitchText(text: "ENTRA", size: 64)
                        Text("Accedi col tuo account Athlynk.")
                            .font(Typo.body(15))
                            .foregroundStyle(Palette.textMid)
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
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Palette.danger)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    NeonButton(title: "Accedi", icon: "arrow.right",
                               color: Palette.primary, loading: app.isAuthenticating) {
                        focus = nil
                        Task { await app.login(email: email, password: password, role: "CLIENT") }
                    }
                    .revealUp(appear, index: 2)
                    .goldPulse(appear)
                    .disabled(email.isEmpty || password.isEmpty)

                    Button { showForgot = true } label: {
                        Text("Password dimenticata?")
                            .font(Typo.mono(12, .semibold)).foregroundStyle(Palette.cyan)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .revealUp(appear, index: 3)

                    Text("Connesso a \(APIClient.shared.baseURL)")
                        .font(Typo.mono(10))
                        .foregroundStyle(Palette.textLow)
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
        .sheet(isPresented: $showForgot) {
            NavigationStack { ForgotPasswordView() }
        }
    }
}

// `VoltField` now lives in Shared/Components/VoltField.swift (used by both the
// athlete and coach login screens).
