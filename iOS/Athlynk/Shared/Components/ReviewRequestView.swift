//
//  ReviewRequestView.swift
//  Shown once after ChironTutorial (athlete) or CoachChironIntro (coach).
//  "Vota" fires SKStoreReview; after tap the "Salta" button fades in so
//  the user can't skip before seeing the native review dialog.
//

import SwiftUI
import StoreKit

struct ReviewRequestView: View {
    var onDone: () -> Void

    @Environment(\.requestReview) private var requestReview
    @AppStorage("athlynk.reviewDone") private var reviewDone = false
    @State private var showSkip = false
    @State private var entered = false
    @State private var burst = 0
    @State private var chironSpeak = 0

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.amber, Palette.magenta, Palette.bronze])

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    ParticleBurst(trigger: burst, colors: [Palette.bronze, Palette.amber, Palette.cyan])
                    ChironMascot(speak: chironSpeak, reduceMotion: false, size: 140)
                }
                .frame(height: 165)

                VStack(spacing: 16) {
                    Text("Ti piace Athlynk?")
                        .font(Typo.poster(42))
                        .foregroundStyle(Palette.textHi)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Bastano 10 secondi. La tua recensione aiuta altri atleti a scoprirci.")
                        .font(Typo.body(16))
                        .foregroundStyle(Palette.textMid)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)
                .padding(.top, 30)

                Spacer()

                VStack(spacing: 16) {
                    NeonButton(title: "★★★★★  Vota", icon: nil, color: Palette.bronze) {
                        reviewDone = true
                        burst += 1
                        chironSpeak += 1
                        Haptics.success()
                        requestReview()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            showSkip = true
                        }
                    }

                    if showSkip {
                        Button {
                            Haptics.tap()
                            onDone()
                        } label: {
                            Text("Salta")
                                .font(Typo.mono(12, .bold))
                                .tracking(1)
                                .foregroundStyle(Palette.textMid)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 50)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { entered = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { chironSpeak += 1 }
        }
    }
}
