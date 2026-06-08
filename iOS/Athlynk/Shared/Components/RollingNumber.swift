//
//  RollingNumber.swift
//  A monospaced HUD readout that rolls when its value changes, plus a
//  count-up reveal when it first appears.
//

import SwiftUI

struct RollingNumber: View {
    let value: Int
    var size: CGFloat = 40
    var color: Color = Palette.textHi
    var suffix: String = ""

    @State private var shown: Int = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(shown)")
                .font(Typo.poster(size))
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(shown)))
            if !suffix.isEmpty {
                Text(suffix)
                    .font(Typo.mono(size * 0.42, .bold))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .onAppear { animate(to: value) }
        .onChange(of: value) { _, new in animate(to: new) }
    }

    private func animate(to target: Int) {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = target }
    }
}
