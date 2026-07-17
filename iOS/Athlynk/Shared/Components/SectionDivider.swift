//
//  SectionDivider.swift
//  A quiet hairline used between page sections — fades to transparent at
//  both ends instead of running edge to edge, so it reads as a pause rather
//  than a hard rule.
//

import SwiftUI

/// Soft-fade hairline divider. Use between page sections.
struct SectionDivider: View {
    var color: Color = Palette.bronze
    var height: CGFloat = 10
    var opacity: Double = 0.55

    var body: some View {
        LinearGradient(
            colors: [.clear, color.opacity(0.4), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

/// Uppercase mono eyebrow + optional serif title + optional InfoTip, the
/// standard section opener shared by both apps.
struct SectionHeader: View {
    var eyebrow: String
    var title: String? = nil
    var tip: String? = nil
    var accent: Color = Palette.bronze

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(eyebrow)
                    .font(Typo.mono(11, .semibold)).tracking(3)
                    .textCase(.uppercase).foregroundStyle(accent)
                if let tip { InfoTip(text: tip) }
                Spacer(minLength: 0)
            }
            if let title {
                Text(title)
                    .font(Typo.display(22)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Tooltip: a small ⓘ that opens a marble popover with a short explanation.
struct InfoTip: View {
    let text: String
    @State private var show = false

    var body: some View {
        Button {
            Haptics.tap()
            show = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textLow)
                .padding(4)                 // enlarge the tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Maggiori informazioni")
        .popover(isPresented: $show, arrowEdge: .top) {
            Text(text)
                .font(Typo.body(13))
                .foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Palette.void1)
        }
    }
}
