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

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.cyan, Palette.violet, Palette.lime])

            VStack(spacing: 18) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 58, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.aegean, Palette.bronze],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .neonGlow(Palette.bronze, radius: 18)
                    .scaleEffect(show ? 1 : 0.4)
                    .rotationEffect(.degrees(show ? 0 : -25))

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
                            .fill(LinearGradient(colors: [Palette.cyan, Palette.magenta],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * charge)
                            .neonGlow(Palette.magenta, radius: 8)
                    }
                }
                .frame(width: 180, height: 6)
                .padding(.top, 8)

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
                            .background(Capsule().fill(Palette.magenta))
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
