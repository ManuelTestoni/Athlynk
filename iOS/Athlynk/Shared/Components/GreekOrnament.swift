//
//  GreekOrnament.swift
//  Brand identity motifs from the website: the meander (greca) used as a
//  section divider, and a small laurel-adjacent seal mark. Ink on parchment,
//  always subtle — ornament, never decoration noise.
//

import SwiftUI

/// Meander (greek key) divider. Use between page sections in place of a
/// plain hairline when the section deserves ceremony.
struct GreekDivider: View {
    var color: Color = Palette.bronze
    var height: CGFloat = 10
    var opacity: Double = 0.55

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
            Meander(unit: height)
                .stroke(color, lineWidth: 1.1)
                .frame(width: height * 6, height: height)
            Rectangle().fill(color.opacity(0.35)).frame(height: 1)
        }
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

/// One run of greek-key units, drawn as a continuous stroke.
private struct Meander: Shape {
    var unit: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height / 2
        var x: CGFloat = 0
        var y: CGFloat = rect.maxY
        p.move(to: CGPoint(x: x, y: y))
        // Classic key: up, across, half-down, half-back, down, across — repeat.
        while x + 3 * h <= rect.width + 0.5 {
            y = rect.minY;     p.addLine(to: CGPoint(x: x, y: y))
            x += 2 * h;        p.addLine(to: CGPoint(x: x, y: y))
            y = rect.minY + h; p.addLine(to: CGPoint(x: x, y: y))
            x -= h;            p.addLine(to: CGPoint(x: x, y: y))
            y = rect.maxY;     p.addLine(to: CGPoint(x: x, y: y))
            x += 2 * h;        p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
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
