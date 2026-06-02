//
//  ParticleBurst.swift
//  A one-shot neon confetti burst, fired by bumping `trigger`.
//

import SwiftUI

struct ParticleBurst: View {
    var trigger: Int
    var colors: [Color] = Palette.accents

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let color: Color
        let spin: Double
    }

    @State private var particles: [Particle] = []
    @State private var fire = false

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                RoundedRectangle(cornerRadius: 1)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 1.8)
                    .neonGlow(p.color, radius: 5)
                    .rotationEffect(.degrees(fire ? p.spin : 0))
                    .offset(
                        x: fire ? cos(p.angle) * p.distance : 0,
                        y: fire ? sin(p.angle) * p.distance : 0
                    )
                    .opacity(fire ? 0 : 1)
                    .scaleEffect(fire ? 0.4 : 1)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        particles = (0..<26).map { _ in
            Particle(
                angle: .random(in: 0...(2 * .pi)),
                distance: .random(in: 80...190),
                size: .random(in: 5...11),
                color: colors.randomElement() ?? Palette.cyan,
                spin: .random(in: -260...260)
            )
        }
        fire = false
        Haptics.success()
        withAnimation(.easeOut(duration: 0.9)) { fire = true }
    }
}
