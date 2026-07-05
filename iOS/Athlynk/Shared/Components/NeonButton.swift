//
//  NeonButton.swift
//  Athlynk CTA: a pill button. Filled pours the accent (bronze/aegean) under
//  parchment text; ghost carries the accent as text + border + faint wash so it
//  still reads as a button, never as a label. Name kept from VOLT.
//

import SwiftUI

struct NeonButton: View {
    let title: String
    var icon: String?
    var color: Color = Palette.aegean
    var filled: Bool = true
    var loading: Bool = false
    /// Compact variant for inline CTAs (empty states, cards).
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                if loading {
                    ProgressView().tint(filled ? Palette.void0 : color)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                }
                Text(title)
                    .font(Typo.body(compact ? 14 : 16, .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(filled ? Palette.void0 : color)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 18 : 16)
            .padding(.vertical, compact ? 11 : 16)
            .background {
                if filled { color } else { color.opacity(0.07) }
            }
            .overlay {
                Capsule().strokeBorder(filled ? .clear : color.opacity(0.55), lineWidth: 1.2)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NeonPressStyle(filled: filled))
        .disabled(loading)
    }
}

/// Press feedback shared by every pill CTA: slight sink, shadow tightens,
/// filled buttons dim a touch — unmistakably "this is being pressed".
private struct NeonPressStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed && filled ? -0.05 : 0)
            .shadow(color: Color(hex: 0x14110D, alpha: filled ? 0.16 : 0.06),
                    radius: configuration.isPressed ? 4 : 12,
                    y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
