//
//  GlitchText.swift
//  Monumental serif headline (Didot ≈ Bodoni Moda), ink on parchment.
//  Name kept from the old neon theme; the RGB-split glitch is gone — this is
//  the refined Athlynk display word.
//

import SwiftUI

struct GlitchText: View {
    let text: String
    var size: CGFloat = 34
    var font: Font?

    var body: some View {
        Text(text)
            .font(font ?? Typo.poster(size))
            .foregroundStyle(Palette.textHi)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }
}
