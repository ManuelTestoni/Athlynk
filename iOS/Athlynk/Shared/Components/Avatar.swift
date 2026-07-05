//
//  Avatar.swift
//  The athlete's own avatar: the uploaded profile photo when present, else the
//  bronze→gold seal with initials. One primitive so every header reads the same.
//

import SwiftUI

struct AvatarView: View {
    var url: String?
    var initials: String
    var size: CGFloat = 40
    /// Initials point size; defaults to a ratio of the circle.
    var initialsSize: CGFloat? = nil
    var glow: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.bronze)

            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: initialsText
                    }
                }
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .neonGlow(Palette.amber, radius: glow)
    }

    private var initialsText: some View {
        Text(initials.isEmpty ? "A" : initials)
            .font(Typo.poster(initialsSize ?? size * 0.4))
            .foregroundStyle(Palette.void0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
