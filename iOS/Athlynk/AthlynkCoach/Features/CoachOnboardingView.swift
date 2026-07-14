//
//  CoachOnboardingView.swift
//  First-launch intro for coaches. Chiron walks through the 4 core coach features.
//  Shown once before login (gated by @AppStorage("athlynk.coach.onboarded")).
//

import SwiftUI

private struct CoachSlide {
    let icon: String?
    let eyebrow: String
    let title: String
    let body: String
    let color: Color
}

private let coachSlides: [CoachSlide] = [
    .init(icon: nil,
          eyebrow: "BENVENUTO, COACH",
          title: "Il tuo\nstudio digitale.",
          body: "Athlynk è lo spazio professionale dove gestisci atleti, piani e progressi in un'unica piattaforma.",
          color: Palette.bronze),
    .init(icon: "chart.bar.fill",
          eyebrow: "DASHBOARD",
          title: "Controllo\ncompleto",
          body: "Analytics, clienti attivi, check in sospeso e appuntamenti del giorno — tutto a colpo d'occhio.",
          color: Palette.cyan),
    .init(icon: "doc.richtext.fill",
          eyebrow: "PIANI",
          title: "Allena e\nnutri meglio",
          body: "Costruisci piani di allenamento e nutrizione personalizzati e assegnali in pochi tap.",
          color: Palette.magenta),
    .init(icon: "checkmark.circle.fill",
          eyebrow: "CHECK",
          title: "Monitora\ni progressi",
          body: "Questionari periodici, misure e foto: il feedback dei tuoi atleti sempre disponibile.",
          color: Palette.lime),
    .init(icon: "sparkles",
          eyebrow: "CHIRON AI",
          title: "Il tuo\nassistente IA",
          body: "Chiron risponde alle tue domande di coaching e propone azioni da eseguire con un tap.",
          color: Palette.amber),
    .init(icon: nil,
          eyebrow: "TUTTO PRONTO",
          title: "I tuoi atleti\nti aspettano.",
          body: "Accedi e inizia a guidare il loro percorso con Athlynk Coach.",
          color: Palette.bronze),
]

struct CoachOnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0
    @State private var burst = 0
    @State private var chironSpeak = 0

    private var isLast: Bool { page == coachSlides.count - 1 }
    private var current: CoachSlide { coachSlides[page] }

    var body: some View {
        ZStack {
            VoltBackground(palette: [current.color, Palette.amber, Palette.bronze, current.color])
                .animation(.easeInOut(duration: 0.6), value: page)

            VStack(spacing: 0) {
                topBar

                ZStack {
                    ParticleBurst(trigger: burst, colors: [current.color, Palette.amber, Palette.cyan])

                    TabView(selection: $page) {
                        ForEach(Array(coachSlides.enumerated()), id: \.offset) { i, s in
                            CoachSlideCard(slide: s,
                                          isHero: i == 0 || i == coachSlides.count - 1,
                                          chironSpeak: chironSpeak)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }

                NeonButton(
                    title: isLast ? "Accedi" : "Avanti",
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
                ForEach(0..<coachSlides.count, id: \.self) { i in
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

private struct CoachSlideCard: View {
    let slide: CoachSlide
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
