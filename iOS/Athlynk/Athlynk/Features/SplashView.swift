//
//  SplashView.swift
//  Cold-open: a charged wordmark that ignites, then hands off to bootstrap().
//

import SwiftUI
import Combine

struct SplashView: View {
    @EnvironmentObject var app: AppState
    @State private var charge: CGFloat = 0
    @State private var show = false
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.gold, Palette.violet, Palette.lime])

            VStack(spacing: 18) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.aegean, Palette.bronze],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .neonGlow(Palette.bronze, radius: 18)
                    .goldPulse(arrived)
                    .scaleEffect(show ? 1 : 0.4)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (show ? 0 : -25)))

                GlitchText(text: "ATHLYNK", size: 56)

                Text("DISCIPLINA · FORZA · GLORIA")
                    .font(Typo.mono(12, .bold))
                    .tracking(6)
                    .foregroundStyle(Palette.textMid)
                    .opacity(show ? 1 : 0)

                // Charging bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.void2)
                        Capsule()
                            .fill(Palette.bronze)
                            .frame(width: geo.size.width * charge)
                            .neonGlow(Palette.bronze, radius: 8)
                    }
                }
                .frame(width: 180, height: 6)
                .padding(.top, 8)

                if app.bootstrapRetryable {
                    Text("Connessione assente. Riprova.")
                        .font(Typo.mono(12, .bold))
                        .foregroundStyle(Palette.textMid)
                        .padding(.top, 12)
                    NeonButton(title: "Riprova", icon: "arrow.clockwise",
                               color: Palette.primary, compact: true) {
                        app.bootstrapRetryable = false
                        Task { await app.bootstrap() }
                    }
                }
            }
        }
        .task {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.6)) { show = true }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) { charge = 1 }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 1.2))
            arrived = true
            await app.bootstrap()
        }
    }
}
