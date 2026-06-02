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
                                  text: $password, secure: true, accent: Palette.magenta)
                            .focused($focus, equals: .password)
                    }
                    .revealUp(appear, index: 1)

                    if let err = app.loginError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Palette.magenta)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    NeonButton(title: "Accedi", icon: "bolt.fill",
                               color: Palette.cyan, loading: app.isAuthenticating) {
                        focus = nil
                        Task { await app.login(email: email, password: password) }
                    }
                    .revealUp(appear, index: 2)
                    .disabled(email.isEmpty || password.isEmpty)

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
    }
}

struct VoltField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var accent: Color = Palette.cyan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)
            Group {
                if secure { SecureField("", text: $text, prompt: prompt) }
                else { TextField("", text: $text, prompt: prompt) }
            }
            .font(Typo.body(16, .medium))
            .foregroundStyle(Palette.textHi)
            .tint(accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .voltPanel(accent.opacity(0.5), radius: 14)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Palette.textLow)
    }
}
