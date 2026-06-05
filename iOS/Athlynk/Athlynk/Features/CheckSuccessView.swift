//
//  CheckSuccessView.swift
//  Confirmation shown after a check is submitted to the coach. An animated
//  bronze/olive seal stamps in, a confetti burst fires, then the copy fades up.
//  The single bottom button pops back to the checks timeline.
//

import SwiftUI

struct CheckSuccessView: View {
    /// Title of the check that was just submitted (shown in the subtitle).
    let title: String
    /// Pop back to the checks list.
    var onClose: () -> Void

    @State private var sealIn = false
    @State private var checkIn = false
    @State private var textIn = false
    @State private var burst = 0

    private let accent = Palette.lime   // olive — success

    var body: some View {
        ZStack {
            VoltBackground()

            VStack(spacing: 30) {
                Spacer()
                seal
                copy
                Spacer()
            }
            .padding(.horizontal, 32)

            ParticleBurst(trigger: burst, colors: [accent, Palette.bronze, Palette.aegean])
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NeonButton(title: "Torna ai check", icon: "checkmark", color: accent) { onClose() }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 10)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { animateIn() }
    }

    // MARK: Seal

    private var seal: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.25), lineWidth: 2)
                .frame(width: 138, height: 138)
                .scaleEffect(sealIn ? 1 : 0.6).opacity(sealIn ? 1 : 0)
            Circle().fill(accent.opacity(0.12))
                .frame(width: 112, height: 112)
                .scaleEffect(sealIn ? 1 : 0.6)
            Circle().fill(accent)
                .frame(width: 90, height: 90)
                .neonGlow(accent, radius: 18)
                .scaleEffect(sealIn ? 1 : 0.35)
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(Palette.void0)
                .scaleEffect(checkIn ? 1 : 0.2)
                .opacity(checkIn ? 1 : 0)
        }
    }

    // MARK: Copy

    private var copy: some View {
        VStack(spacing: 12) {
            Text("FATTO").voltEyebrow()
            Text("Check compilato\ncon successo")
                .font(Typo.poster(34))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Text("“\(title)” è stato inviato al tuo coach.")
                .font(Typo.body(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textMid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(textIn ? 1 : 0)
        .offset(y: textIn ? 0 : 14)
    }

    // MARK: Animation

    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { sealIn = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.18)) { checkIn = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.32)) { textIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { burst += 1 }
    }
}
