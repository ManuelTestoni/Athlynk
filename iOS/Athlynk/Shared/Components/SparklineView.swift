//
//  SparklineView.swift
//  Minimal line sparkline drawn with native shapes (no chart dependency) —
//  used by the dashboard's weight-trend widget; reusable for any short series.
//

import SwiftUI

struct SparklineView: View {
    let values: [Double]
    var accent: Color = Palette.cyan

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                // Soft fill under the line
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.12))

                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = pts.last {
                    Circle().fill(accent)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2,
              let minV = values.min(), let maxV = values.max() else { return [] }
        let span = max(maxV - minV, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        // 4pt vertical inset so the stroke and end dot never clip.
        let usable = size.height - 8
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: 4 + usable * CGFloat(1 - (v - minV) / span))
        }
    }
}
