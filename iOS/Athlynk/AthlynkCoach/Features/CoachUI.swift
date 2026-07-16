//
//  CoachUI.swift
//  Small shared building blocks + date helpers for the coach screens. Built on
//  the shared Athlynk design primitives (Palette, Typo, voltPanel, AvatarView).
//

import SwiftUI

// MARK: - Date helpers

enum CoachDate {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
            ?? {
                let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"; return d.date(from: s)
            }()
    }

    static func time(_ s: String?) -> String {
        guard let d = parse(s) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    static func dayMonth(_ s: String?) -> String {
        guard let d = parse(s) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
        return f.string(from: d)
    }
    static func relative(_ s: String?) -> String {
        guard let d = parse(s) else { return "" }
        let rel = RelativeDateTimeFormatter(); rel.locale = Locale(identifier: "it_IT")
        rel.unitsStyle = .short
        return rel.localizedString(for: d, relativeTo: Date())
    }
    static func todayTitle() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date()).capitalized
    }
}

// MARK: - Section title (mono eyebrow + serif)

struct CoachSectionTitle: View {
    var eyebrow: String
    var title: String
    var accent: Color = Palette.bronze
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(Typo.mono(10, .semibold)).tracking(3)
                .textCase(.uppercase).foregroundStyle(accent)
            Text(title).font(Typo.display(24)).foregroundStyle(Palette.textHi)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Client avatar (uses uploaded photo when present)

struct CoachClientAvatar: View {
    var url: String?
    var initials: String
    var size: CGFloat = 46
    var body: some View {
        AvatarView(url: url, initials: initials, size: size, initialsSize: size * 0.38)
    }
}

// MARK: - Generic tappable list card

struct CoachListCard<Content: View>: View {
    var accent: Color = Palette.bronze
    var action: (() -> Void)? = nil
    /// Tappable cards show a trailing chevron so they read as navigable;
    /// pass false for tap actions that are not navigation (e.g. toggles).
    var chevron: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        if let action {
            Button { Haptics.tap(); action() } label: {
                HStack(spacing: 12) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                    if chevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.textLow)
                    }
                }
                .padding(16)
                .voltPanel()
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        } else { card }
    }

    private var card: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .voltPanel()
    }
}
