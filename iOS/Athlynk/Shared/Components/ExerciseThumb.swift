//
//  ExerciseThumb.swift
//  Small rounded exercise cover thumbnail, used identically in every list row
//  across both apps (builder picker, day view, session log, read-only scheda
//  detail) so a coach or athlete always recognizes an exercise at a glance —
//  mirrors the web builder's `.wbp-row-thumb`.
//

import SwiftUI

struct ExerciseThumb: View {
    var url: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Palette.void2)

            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    private var placeholderIcon: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Palette.textLow)
    }
}
