//
//  GlitchText.swift
//  Monumental serif headline (Didot ≈ Bodoni Moda), ink on parchment.
//  Name kept from the old neon theme; the RGB-split glitch is gone — this is
//  the refined Athlynk display word. Settles in with a gold-lit reveal.
//

import SwiftUI

struct GlitchText: View {
    let text: String
    var size: CGFloat = 34
    var font: Font?

    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font ?? Typo.poster(size))
            .foregroundStyle(Palette.textHi)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: Palette.gold.opacity(settled ? 0 : 0.5), radius: settled ? 0 : 10)
            .opacity(reduceMotion ? 1 : (settled ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (settled ? 0 : 10))
            .onAppear {
                guard !reduceMotion else { return }
                settled = false
                withAnimation(Motion.pageEnter.delay(0.05)) { settled = true }
            }
    }
}
