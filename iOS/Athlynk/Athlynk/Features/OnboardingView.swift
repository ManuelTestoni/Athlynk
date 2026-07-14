//
//  OnboardingView.swift
//  First-launch intro: Chiron welcomes the athlete and demos the 4 core features.
//  Shown once before login (gated by @AppStorage("athlynk.onboarded") in ContentView).
//

import SwiftUI

// MARK: - Data

private struct OnboardingSlide {
    let icon: String?
    let eyebrow: String
    let title: String
    let body: String
    let color: Color
}

private let onboardingSlides: [OnboardingSlide] = [
    .init(icon: nil,
          eyebrow: "BENVENUTO",
          title: "Allena.\nNutri.\nEvolvi.",
          body: "Athlynk connette atleti e coach in un'esperienza essenziale e monumentale.",
          color: Palette.bronze),
    .init(icon: "dumbbell.fill",
          eyebrow: "ALLENAMENTI",
          title: "Schede\nsempre con te",
          body: "Avvia le sessioni, registra ogni serie e monitora il tuo volume in tempo reale.",
          color: Palette.magenta),
    .init(icon: "leaf.fill",
          eyebrow: "NUTRIZIONE",
          title: "Mangia\ncon metodo",
          body: "Piani alimentari personalizzati e diario macro per ogni pasto della giornata.",
          color: Palette.lime),
    .init(icon: "chart.xyaxis.line",
          eyebrow: "PROGRESSI",
          title: "Misura ogni\ntraguardo",
          body: "Peso, misure corporee, foto e check periodici: ogni passo del tuo percorso registrato.",
          color: Palette.cyan),
    .init(icon: "sparkles",
          eyebrow: "CHIRON AI",
          title: "Il tuo\nassistente",
          body: "Chiron risponde alle tue domande su allenamento e nutrizione 24 ore su 24.",
          color: Palette.amber),
    .init(icon: nil,
          eyebrow: "TUTTO PRONTO",
          title: "Il tuo coach\nti aspetta.",
          body: "Accedi e inizia il tuo percorso con Athlynk.",
          color: Palette.bronze),
]

// MARK: - Main view

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    @State private var burst = 0
    @State private var chironSpeak = 0

    private var isLast: Bool { page == onboardingSlides.count - 1 }
    private var current: OnboardingSlide { onboardingSlides[page] }

    var body: some View {
        ZStack {
            VoltBackground(palette: [current.color, Palette.amber, Palette.bronze, current.color])
                .animation(.easeInOut(duration: 0.6), value: page)

            VStack(spacing: 0) {
                topBar

                ZStack {
                    ParticleBurst(trigger: burst, colors: [current.color, Palette.amber, Palette.cyan])

                    TabView(selection: $page) {
                        ForEach(Array(onboardingSlides.enumerated()), id: \.offset) { i, s in
                            OnboardingSlideCard(slide: s,
                                               isHero: i == 0 || i == onboardingSlides.count - 1,
                                               chironSpeak: chironSpeak)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }

                NeonButton(
                    title: isLast ? "Inizia" : "Avanti",
                    icon: isLast ? "arrow.right" : nil,
                    color: current.color
                ) {
                    if isLast {
                        onDone()
                    } else {
                        burst += 1
                        chironSpeak += 1
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { page += 1 }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 44)
                .animation(.easeInOut(duration: 0.25), value: page)
                .goldPulse(isLast)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<onboardingSlides.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= page ? current.color : Palette.void2)
                        .frame(width: i == page ? 22 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                }
            }
            Spacer()
            Button { onDone() } label: {
                Text("Salta")
                    .font(Typo.mono(12, .bold)).tracking(1)
                    .foregroundStyle(Palette.textMid)
            }
        }
        .padding(.horizontal, 26).padding(.top, 16)
    }
}

// MARK: - Individual slide card

private struct OnboardingSlideCard: View {
    let slide: OnboardingSlide
    let isHero: Bool
    let chironSpeak: Int

    @State private var appeared = false
    @State private var iconScale: CGFloat = 0.5
    @State private var iconRing = 0.0
    @State private var iconBob = false
    @State private var aura = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            HStack {
                Spacer()
                if isHero {
                    ChironMascot(speak: chironSpeak, reduceMotion: false, size: 160)
                } else {
                    iconView
                }
                Spacer()
            }
            .frame(height: 200)

            VStack(alignment: .leading, spacing: 14) {
                Text(slide.eyebrow)
                    .font(Typo.mono(11, .semibold)).tracking(3)
                    .foregroundStyle(slide.color)
                    .revealUp(appeared, index: 0)

                Text(slide.title)
                    .font(Typo.poster(46))
                    .foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                    .revealUp(appeared, index: 1)

                Text(slide.body)
                    .font(Typo.body(16))
                    .foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .revealUp(appeared, index: 2)
            }
            .padding(.top, 22)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .onAppear {
            appeared = false
            iconScale = 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                appeared = true
                withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.62)) { iconScale = 1 }
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { aura = true }
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { iconBob = true }
                withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) { iconRing = 360 }
            }
        }
        .onDisappear { appeared = false; iconScale = 0.5 }
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [slide.color.opacity(0.28), .clear],
                    center: .center, startRadius: 10, endRadius: 95))
                .frame(width: 200, height: 200)
                .scaleEffect(aura ? 1.15 : 0.92)
                .opacity(aura ? 1 : 0.6)

            Circle()
                .stroke(slide.color.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 11]))
                .frame(width: 152, height: 152)
                .rotationEffect(.degrees(iconRing))

            Circle()
                .fill(slide.color.opacity(0.16))
                .frame(width: 112, height: 112)

            Image(systemName: slide.icon ?? "sparkles")
                .font(.system(size: 50, weight: .black))
                .foregroundStyle(slide.color)
                .neonGlow(slide.color, radius: 14)
        }
        .scaleEffect(iconScale)
        .offset(y: iconBob ? -5 : 6)
    }
}

// MARK: - Forgot password (coexists in same file)

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
