//
//  Theme.swift
//  Athlynk — Greek-luxury design system (mirrors the web app: static/css/athlynk.css).
//
//  A refined, light aesthetic: parchment & marble surfaces, ink type, a bronze
//  imperial seal and Aegean teal as the two accents. Monumental serif display
//  (Didot ≈ Bodoni Moda), clean system body (≈ Inter), monospaced numerals
//  (≈ JetBrains Mono). Hard luxury, never neon.
//
//  Note: the type/modifier API names are kept from the previous "VOLT" theme so
//  every screen re-skins through these primitives without per-view rewrites.
//

import SwiftUI

enum Palette {
    // Surfaces (light, layered) — names kept for source compatibility.
    static let void0   = Color(hex: 0xF4EFE4)   // parchment — page background
    static let void1   = Color(hex: 0xECE5D6)   // marble — panel / card base
    static let void2   = Color(hex: 0xD8CFBA)   // stone — raised insets, track fills
    static let line    = Color(hex: 0x14110D, alpha: 0.14)   // hairline rule

    // Accents — all drawn from the Athlynk palette, dark enough to carry
    // parchment text when used as a fill. (Slot names kept from VOLT.)
    static let magenta = Color(hex: 0x8A6A3A)   // bronze — imperial seal / primary
    static let cyan    = Color(hex: 0x1C4A52)   // aegean — Poseidon teal
    static let lime    = Color(hex: 0x4A6B3A)   // olive — success
    static let violet  = Color(hex: 0x0E2F36)   // aegean deep
    static let amber   = Color(hex: 0x9C6F2E)   // deep gold
    static let phase   = Color(hex: 0x6E4A63)   // dusty plum — coach phases

    // Ink (text)
    static let textHi  = Color(hex: 0x14110D)   // ink
    static let textMid = Color(hex: 0x5B554A)   // ink-mute
    static let textLow = Color(hex: 0x8A8270)   // ink-line

    static let bronze  = magenta
    static let aegean  = cyan

    /// Rotating accent set used to colour cards / rings by index.
    static let accents: [Color] = [cyan, magenta, lime, violet, amber]
    static func accent(_ i: Int) -> Color { accents[((i % accents.count) + accents.count) % accents.count] }
}

enum Typo {
    /// Monumental serif (Didot ≈ Bodoni Moda) for the big display words/numerals.
    static func poster(_ size: CGFloat) -> Font {
        .custom("Didot", size: size)
    }
    /// Smaller serif headings.
    static func display(_ size: CGFloat) -> Font {
        .custom("Didot", size: size)
    }
    /// Monospaced HUD readouts (stats, timers, loads) ≈ JetBrains Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Clean body text ≈ Inter (system San Francisco).
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Surface + chrome modifiers

extension View {
    /// Soft luxury elevation. (Was a neon bloom — repurposed to a refined ink
    /// shadow so existing call sites read as gentle depth, not glow.)
    func neonGlow(_ color: Color, radius: CGFloat = 14, opacity: Double = 0.7) -> some View {
        self.shadow(color: Color(hex: 0x14110D, alpha: 0.12),
                    radius: max(radius * 0.55, 4), y: max(radius * 0.28, 2))
    }

    /// Athlynk surface: marble fill, ink hairline border, soft elevation.
    func voltPanel(_ tint: Color = Palette.line, radius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.void1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color(hex: 0x14110D, alpha: 0.10), radius: 18, x: 0, y: 10)
    }

    /// Uppercase bronze eyebrow label.
    func voltEyebrow() -> some View {
        self
            .font(Typo.mono(11, .semibold))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(Palette.bronze)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
