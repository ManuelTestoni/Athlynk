//
//  Theme.swift
//  Athlynk — Greek-luxury design system (mirrors the web app: static/css/athlynk.css).
//
//  Royal Blue + restrained Gold on white/marble surfaces, navy ink type.
//  Monumental serif display (Didot ≈ Bodoni Moda), clean system body
//  (≈ Inter), monospaced numerals (≈ JetBrains Mono). Hard luxury, never neon.
//
//  Note: the type/modifier API names are kept from the previous "VOLT" theme so
//  every screen re-skins through these primitives without per-view rewrites.
//

import SwiftUI
import UIKit

enum Palette {
    // Surfaces (light, layered) — names kept for source compatibility.
    static let void0   = Color(hex: 0xFFFFFF)   // parchment — page background
    static let void1   = Color(hex: 0xF4F6F9)   // marble — panel / card base
    static let void2   = Color(hex: 0xE8ECF2)   // stone — raised insets, track fills
    static let line    = Color(hex: 0x0B1D3A, alpha: 0.12)   // hairline rule

    // Accents — all drawn from the Athlynk palette, dark enough to carry
    // white text when used as a fill. (Slot names kept from VOLT.)
    static let magenta = Color(hex: 0x1E3A5F)   // royal blue — primary
    static let cyan    = Color(hex: 0x5B89B6)   // royal blue, light — control
    static let lime    = Color(hex: 0x3F7A5E)   // success
    static let violet  = Color(hex: 0x132A47)   // royal blue, deep
    static let amber   = Color(hex: 0xB8860B)   // gold — text-safe (headlines, icons)
    static let phase   = Color(hex: 0x5C4A6B)   // muted plum — coach phases
    static let crimson = Color(hex: 0xA23B3B)   // error / destructive

    // Ink (text)
    static let textHi  = Color(hex: 0x0B1D3A)   // ink
    static let textMid = Color(hex: 0x4B5D75)   // ink-mute
    static let textLow = Color(hex: 0x7C8CA3)   // ink-line

    static let bronze  = magenta
    static let aegean  = cyan

    // Premium gold — glows/highlights only, never a solid text/fill colour
    // (mirrors the web's restraint: --al-highlight-premium).
    static let gold     = Color(hex: 0xFFE066)
    static let goldText = Color(hex: 0x9C7A1F)

    // Semantic roles — use these instead of raw slots so intent survives reskins.
    static let danger  = crimson    // destructive actions, errors
    static let success = lime
    static let primary = bronze     // royal blue — primary CTA / brand accent
    static let control = cyan       // interactive controls (toggles, pickers, links)

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

// MARK: - Motion & spacing tokens

/// Signature animations — every screen uses these two curves so the whole app
/// moves as one. `snappy` for feedback (presses, toggles, chips), `luxe` for
/// content (cards, layout shifts, reveals).
enum Motion {
    static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.70)
    static let luxe   = Animation.spring(response: 0.55, dampingFraction: 0.85)
    /// Delay step for staggered entrances (used by `.revealUp`).
    static let staggerStep: Double = 0.07

    /// Big page-enter reveal (mirrors the web's --al-d-page, 0.52s).
    static let pageEnter = Animation.spring(response: 0.52, dampingFraction: 0.86)
    /// Gold-glow micro-interaction: 320ms entrance + 900ms decay (mirrors the
    /// web's "just added" pulse — the clearest translatable wow motif).
    static let glowIn    = Animation.easeOut(duration: 0.32)
    static let glowDecay = Animation.easeOut(duration: 0.9)
}

/// Spacing scale — page and card rhythm shared by every screen.
enum Space {
    static let screenH: CGFloat = 22   // horizontal page padding
    static let section: CGFloat = 22   // between page sections
    static let card: CGFloat    = 16   // card internal padding
    static let element: CGFloat = 12   // between elements inside a card
}

// MARK: - Surface + chrome modifiers

extension View {
    /// Soft luxury elevation. (Was a neon bloom — repurposed to a refined ink
    /// shadow so existing call sites read as gentle depth, not glow.)
    func neonGlow(_ color: Color, radius: CGFloat = 14, opacity: Double = 0.7) -> some View {
        self.shadow(color: Color(hex: 0x0B1D3A, alpha: 0.12),
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
            .shadow(color: Color(hex: 0x0B1D3A, alpha: 0.10), radius: 18, x: 0, y: 10)
    }

    /// Uppercase gold eyebrow label.
    func voltEyebrow() -> some View {
        self
            .font(Typo.mono(11, .semibold))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(Palette.goldText)
    }

    /// One-shot premium gold pulse: 320ms glow-in, 900ms decay. Fires whenever
    /// `trigger` changes (or immediately if `trigger` starts `true`). The
    /// mobile translation of the web's "just added" gold micro-interaction —
    /// reserved for real moments (arrival, success, primary CTA reveal).
    func goldPulse(_ trigger: Bool) -> some View {
        modifier(GoldPulseModifier(trigger: trigger))
    }
}

private struct GoldPulseModifier: ViewModifier {
    let trigger: Bool
    @State private var glow: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .shadow(color: Palette.gold.opacity(glow * 0.9), radius: 18 * glow, y: 0)
            .onChange(of: trigger) { _, new in if new { fire() } }
            .onAppear { if trigger { fire() } }
    }

    private func fire() {
        guard !reduceMotion else { return }
        withAnimation(Motion.glowIn) { glow = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(Motion.glowDecay) { glow = 0 }
        }
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

    /// "#RRGGBB" -> Color, or nil if malformed. Mirrors the web brand-color
    /// hex format (session_utils._HEX_RE).
    init?(hexString: String) {
        guard hexString.hasPrefix("#"), hexString.count == 7,
              let value = UInt32(hexString.dropFirst(), radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// Color -> "#RRGGBB" for round-tripping through the brand-color API.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
