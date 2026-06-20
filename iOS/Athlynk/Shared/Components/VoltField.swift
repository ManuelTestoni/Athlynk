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

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)
            Group {
                if secure {
                    if isRevealed {
                        TextField("", text: $text, prompt: prompt)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("", text: $text, prompt: prompt)
                    }
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .font(Typo.body(16, .medium))
            .foregroundStyle(Palette.textHi)
            .tint(accent)
            if secure {
                Button(action: { isRevealed.toggle() }) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accent.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .voltPanel(accent.opacity(0.5), radius: 14)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Palette.textLow)
    }
}
