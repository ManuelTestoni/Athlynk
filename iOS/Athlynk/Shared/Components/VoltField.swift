//
//  VoltField.swift
//  Shared bottom-accent text field used by both apps' auth + edit screens.
//

import SwiftUI

struct VoltField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var accent: Color = Palette.cyan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)
            Group {
                if secure { SecureField("", text: $text, prompt: prompt) }
                else { TextField("", text: $text, prompt: prompt) }
            }
            .font(Typo.body(16, .medium))
            .foregroundStyle(Palette.textHi)
            .tint(accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .voltPanel(accent.opacity(0.5), radius: 14)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Palette.textLow)
    }
}
