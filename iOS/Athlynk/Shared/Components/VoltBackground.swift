//
//  VoltBackground.swift
//  The stage: a parchment field washed with faint marble light and the softest
//  bronze/aegean radial tints — mirrors the web app's body background. Calm,
//  premium, never busy. Drop behind any screen.
//

import SwiftUI

struct VoltBackground: View {
    /// Kept for source compatibility with the old neon API; unused.
    var palette: [Color] = []
    var animated: Bool = true

    var body: some View {
        ZStack {
            Palette.void0.ignoresSafeArea()

            // Marble light pooling from the top.
            RadialGradient(
                colors: [Color.white.opacity(0.55), .clear],
                center: UnitPoint(x: 0.6, y: -0.1),
                startRadius: 0, endRadius: 520
            )
            .ignoresSafeArea()

            // Faint bronze warmth, lower-left.
            RadialGradient(
                colors: [Palette.bronze.opacity(0.06), .clear],
                center: UnitPoint(x: 0, y: 1),
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            // Faint aegean cool, upper-right.
            RadialGradient(
                colors: [Palette.aegean.opacity(0.05), .clear],
                center: UnitPoint(x: 1, y: 0.25),
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            // Whisper of paper grain.
            Grain().opacity(0.025).ignoresSafeArea().blendMode(.multiply)
        }
    }
}

/// Static paper grain, drawn once from a seeded pattern (cheap, no per-frame cost).
private struct Grain: View {
    private let dots: [(CGPoint, CGFloat, Double)] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<1100).map { _ in
            (CGPoint(x: .random(in: 0...1, using: &rng), y: .random(in: 0...1, using: &rng)),
             CGFloat.random(in: 0.5...1.2, using: &rng),
             Double.random(in: 0.2...0.7, using: &rng))
        }
    }()

    var body: some View {
        Canvas { ctx, size in
            for (p, r, o) in dots {
                let rect = CGRect(x: p.x * size.width, y: p.y * size.height, width: r, height: r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Palette.textHi.opacity(o)))
            }
        }
    }
}
