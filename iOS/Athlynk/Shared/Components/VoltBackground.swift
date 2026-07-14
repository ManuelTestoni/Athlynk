//
//  VoltBackground.swift
//  The stage: a white/marble field washed with drifting royal-blue + gold
//  radial tints — mirrors the web app's body background. Calm, premium,
//  never busy. Drop behind any screen.
//

import SwiftUI

struct VoltBackground: View {
    /// Tint pair for the ambient wash. Falls back to brand blue + gold.
    var palette: [Color] = []
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var a: Color { palette.first ?? Palette.bronze }
    private var b: Color { palette.count > 1 ? palette[1] : Palette.gold }

    var body: some View {
        ZStack {
            Palette.void0.ignoresSafeArea()

            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    wash(drift: t)
                }
            } else {
                wash(drift: 0)
            }

            // Whisper of paper grain.
            Grain().opacity(0.025).ignoresSafeArea().blendMode(.multiply)
        }
    }

    /// Slow figure-eight drift of the tint pools — ambient, never distracting.
    private func wash(drift t: TimeInterval) -> some View {
        let dx = sin(t * 0.12) * 0.09
        let dy = cos(t * 0.09) * 0.07

        return ZStack {
            // Marble light pooling from the top.
            RadialGradient(
                colors: [Color.white.opacity(0.55), .clear],
                center: UnitPoint(x: 0.6 + dx, y: -0.1 + dy),
                startRadius: 0, endRadius: 520
            )
            .ignoresSafeArea()

            // Royal-blue warmth, lower-left.
            RadialGradient(
                colors: [a.opacity(0.07), .clear],
                center: UnitPoint(x: 0 - dx, y: 1 - dy),
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            // Second tint, upper-right.
            RadialGradient(
                colors: [b.opacity(0.055), .clear],
                center: UnitPoint(x: 1 + dy, y: 0.25 - dx),
                startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            // Restrained gold glimmer, upper-left corner — never a fill, just a whisper.
            RadialGradient(
                colors: [Palette.gold.opacity(0.045), .clear],
                center: UnitPoint(x: 0.12 + dy * 0.6, y: 0.1 + dx * 0.6),
                startRadius: 0, endRadius: 260
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
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
