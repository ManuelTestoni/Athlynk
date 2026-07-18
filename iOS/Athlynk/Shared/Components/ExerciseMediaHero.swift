//
//  ExerciseMediaHero.swift
//  Shared "hero" media block for exercise detail screens/sheets — animated
//  gif, falling back to the static cover, falling back to a placeholder
//  icon, with an optional video play-button overlay. Extracted out of
//  ExerciseDetailView so ExerciseCatalogDetailSheet (coach + athlete picker
//  and list contexts) renders the exact same treatment, one implementation.
//

import SwiftUI

struct ExerciseMediaHero: View {
    var demoGifUrl: String?
    var coverImageUrl: String?
    var videoUrl: String?
    var accent: Color = Palette.textMid
    var height: CGFloat = 200
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Palette.void2, Palette.void1],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Palette.line, lineWidth: 1))

            if let gif = demoGifUrl, let url = URL(string: gif) {
                AnimatedWebPView(url: url)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if let cover = coverImageUrl, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(height: height)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }

            if let v = videoUrl, let url = URL(string: v) {
                Link(destination: url) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56)).foregroundStyle(accent)
                        .background(Circle().fill(Palette.void0).padding(8))
                        .neonGlow(accent, radius: 12)
                }
            }
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.system(size: height * 0.32, weight: .black)).foregroundStyle(accent.opacity(0.5))
    }
}
