//
//  NeonButton.swift
//  Athlynk CTA: a pill button. Filled pours the accent (bronze/aegean) under
//  parchment text; ghost is an ink-hairline outline. Name kept from VOLT.
//

import SwiftUI

struct NeonButton: View {
    let title: String
    var icon: String?
    var color: Color = Palette.aegean
    var filled: Bool = true
    var loading: Bool = false
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().tint(filled ? Palette.void0 : color)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(Typo.body(16, .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(filled ? Palette.void0 : Palette.textHi)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                if filled { color }
            }
            .overlay {
                Capsule().stroke(filled ? .clear : Palette.line, lineWidth: 1)
            }
            .clipShape(Capsule())
            .shadow(color: Color(hex: 0x14110D, alpha: filled ? 0.16 : 0.06),
                    radius: pressed ? 4 : 12, y: pressed ? 2 : 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .disabled(loading)
    }
}
