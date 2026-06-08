//
//  PressableCard.swift
//  Springy press feedback for tappable panels.
//

import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension View {
    /// Staggered slide-up + fade reveal driven by `appear`.
    func revealUp(_ appear: Bool, index: Int) -> some View {
        self
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 26)
            .blur(radius: appear ? 0 : 6)
            .animation(.spring(response: 0.6, dampingFraction: 0.82)
                .delay(Double(index) * 0.07), value: appear)
    }
}
