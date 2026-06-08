//
//  Scaffold.swift
//  Shared screen scaffolding used by both apps: a common scroll container,
//  loading / empty panels, the Stitch "Monumental Stack" header, and status
//  badges. Re-skins every screen through the same primitives.
//

import SwiftUI

/// Shared scroll container giving every screen the same top inset + tab-bar clearance.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Lightweight inline state for a loadable screen section.
struct LoadingPanel: View {
    var text: String = "Carico…"
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Palette.cyan)
            Text(text).font(Typo.mono(13)).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct EmptyPanel: View {
    var icon: String
    var text: String
    var color: Color = Palette.textLow
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(Typo.body(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .voltPanel()
    }
}

/// Stitch "Monumental Stack" header: mono eyebrow + serif display title + body
/// subtitle, with an optional initials avatar pinned top-right (the wordmark/
/// account-icon row from the mockups).
struct ScreenHeader: View {
    @EnvironmentObject private var app: AppState
    var eyebrow: String
    var title: String
    var subtitle: String? = nil
    var initials: String? = nil
    var accent: Color = Palette.bronze

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(eyebrow)
                    .font(Typo.mono(11, .semibold)).tracking(3)
                    .textCase(.uppercase).foregroundStyle(accent)
                Spacer()
                if let initials {
                    AvatarView(url: app.avatarUrl, initials: initials, size: 40, initialsSize: 16)
                }
            }
            Text(title)
                .font(Typo.poster(46)).foregroundStyle(Palette.textHi)
                .lineLimit(2).minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(accent).frame(height: 1).opacity(0.5)   // bronze hairline rule
        }
    }
}

/// Small rectangular status pill (Stitch "ATTIVO" / "DA COMPILARE" badges).
struct StatusBadge: View {
    var text: String
    var color: Color = Palette.lime
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(Typo.mono(9, .black)).tracking(1).textCase(.uppercase)
            .foregroundStyle(filled ? Palette.void0 : color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background {
                if filled { Capsule().fill(color) }
                else { Capsule().stroke(color, lineWidth: 1) }
            }
    }
}
