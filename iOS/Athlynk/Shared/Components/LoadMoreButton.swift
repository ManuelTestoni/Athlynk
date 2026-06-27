//
//  LoadMoreButton.swift
//  Shared "Carica ancora" pagination button — uniform style across both apps.
//

import SwiftUI

struct LoadMoreButton: View {
    let loading: Bool
    var accent: Color = Palette.cyan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(accent) }
                Text(loading ? "Caricamento…" : "Carica ancora")
                    .font(Typo.mono(11, .bold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }
}
