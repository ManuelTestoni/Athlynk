//
//  OnboardingView.swift
//  Stitch "Onboarding Carousel": a 3-slide intro shown once on first launch
//  (gated by @AppStorage in ContentView). Static — no API.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0

    private struct Slide { let icon: String; let eyebrow: String; let title: String; let body: String; let color: Color }
    private let slides: [Slide] = [
        .init(icon: "building.columns.fill", eyebrow: "BENVENUTO",
              title: "Disciplina\ncome arte", body: "Athlynk porta il tuo coaching in un'esperienza essenziale e monumentale.", color: Palette.bronze),
        .init(icon: "dumbbell.fill", eyebrow: "ALLENATI",
              title: "Schede\nsempre con te", body: "Apri i tuoi programmi, avvia le sessioni e registra ogni serie in tempo reale.", color: Palette.magenta),
        .init(icon: "chart.xyaxis.line", eyebrow: "MONITORA",
              title: "Progressi\nmisurabili", body: "Peso, foto e check periodici: il tuo coach segue ogni passo del percorso.", color: Palette.cyan),
    ]

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.magenta, Palette.cyan, Palette.bronze])
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onDone() } label: {
                        Text("Salta").font(Typo.mono(12, .bold)).tracking(1).foregroundStyle(Palette.textMid)
                    }
                }
                .padding(.horizontal, 26).padding(.top, 16)

                TabView(selection: $page) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { i, s in
                        slideView(s).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dots
                    .padding(.bottom, 24)

                NeonButton(title: page == slides.count - 1 ? "Inizia" : "Avanti",
                           icon: page == slides.count - 1 ? "arrow.right" : nil,
                           color: slides[page].color) {
                    if page == slides.count - 1 { onDone() }
                    else { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { page += 1 } }
                }
                .padding(.horizontal, 26).padding(.bottom, 40)
            }
        }
    }

    private func slideView(_ s: Slide) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(s.color.opacity(0.16)).frame(width: 120, height: 120)
                Image(systemName: s.icon).font(.system(size: 52, weight: .black)).foregroundStyle(s.color)
                    .neonGlow(s.color, radius: 16)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(s.eyebrow).font(Typo.mono(11, .semibold)).tracking(3).foregroundStyle(s.color)
                Text(s.title).font(Typo.poster(48)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.body).font(Typo.body(16)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? slides[page].color : Palette.void2)
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
            }
        }
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.magenta, Palette.cyan])
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECUPERO").voltEyebrow()
                        Text("Password\ndimenticata").font(Typo.poster(44)).foregroundStyle(Palette.textHi)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Inserisci la tua email: se è registrata riceverai un link per reimpostare la password.")
                            .font(Typo.body(15)).foregroundStyle(Palette.textMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if sent {
                        Label("Se l'email è registrata, controlla la posta.", systemImage: "checkmark.seal.fill")
                            .font(Typo.body(14, .semibold)).foregroundStyle(Palette.lime)
                            .padding(16).voltPanel(Palette.lime.opacity(0.4))
                        NeonButton(title: "Torna al login", icon: "arrow.left", color: Palette.cyan, filled: false) {
                            dismiss()
                        }
                    } else {
                        VoltField(icon: "envelope.fill", placeholder: "Email", text: $email, accent: Palette.cyan)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        NeonButton(title: sending ? "Invio…" : "Invia link", icon: "paperplane.fill",
                                   color: Palette.cyan, loading: sending) {
                            Task { await send() }
                        }
                        .disabled(email.isEmpty)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 26)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func send() async {
        sending = true
        try? await APIClient.shared.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))
        Haptics.success()
        withAnimation(.spring) { sent = true }
        sending = false
    }
}
