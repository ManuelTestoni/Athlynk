//
//  RingGauge.swift
//  Animated neon progress ring with a glowing leading dot.
//

import SwiftUI

struct RingGauge: View {
    var progress: Double            // 0...1 (can exceed → clamps visually)
    var color: Color = Palette.cyan
    var lineWidth: CGFloat = 12
    var label: String? = nil
    var value: String? = nil

    @State private var animated: Double = 0

    private var p: Double { min(max(animated, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.void2, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.45), color],
                                    center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Leading dot
            Circle()
                .fill(color)
                .frame(width: lineWidth * 1.2, height: lineWidth * 1.2)
                .offset(y: -ringRadius)
                .rotationEffect(.degrees(360 * p - 90))
                .opacity(p > 0.02 ? 1 : 0)

            VStack(spacing: 2) {
                if let value {
                    Text(value).font(Typo.poster(28)).foregroundStyle(Palette.textHi)
                }
                if let label {
                    Text(label).voltEyebrow()
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) { animated = progress } }
        .onChange(of: progress) { _, n in withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { animated = n } }
    }

    // Approx radius for the dot offset (ring sits inside a square frame).
    private var ringRadius: CGFloat { 44 }
}
