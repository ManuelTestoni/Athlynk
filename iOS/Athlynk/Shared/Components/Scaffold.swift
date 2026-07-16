//
//  Scaffold.swift
//  Shared screen scaffolding used by both apps: a common scroll container,
//  loading / empty panels, the Stitch "Monumental Stack" header, and status
//  badges. Re-skins every screen through the same primitives.
//

import SwiftUI

/// Shared layout constants used by both apps.
enum AppLayout {
    /// Bottom clearance reserved for the floating tab bar: home-indicator inset
    /// (~34) + bar height (~69) + its own bottom padding + a clearance gap.
    /// Single source of truth for `MainTabView`/`CoachShell`'s `safeAreaInset`
    /// AND for pushed screens that can't reliably inherit that inset (screens
    /// presented via `.sheet` get a fresh safe-area root; some raw `ScrollView`
    /// screens set their own `.ignoresSafeArea()` that can shadow it) — those
    /// screens reserve this same value directly instead of a smaller ad-hoc number.
    static let tabBarClearance: CGFloat = 120
}

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
            // Tab-bar clearance now comes from the shell's bottom safeAreaInset,
            // so this only needs a small trailing margin (avoids double padding).
            .padding(.bottom, 24)
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
    /// Optional call-to-action (e.g. "Creane uno ora" → open the builder). Shown
    /// only when both title and action are set.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(Typo.body(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textMid)
            if let actionTitle, let action {
                NeonButton(title: actionTitle,
                           color: color == Palette.textLow ? Palette.primary : color,
                           compact: true, action: action)
                    .padding(.top, 4)
            }
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

/// "Legale" card: opens the hosted legal documents in Safari. The documents
/// themselves live on the web (app.athlynk.it) — single source of truth, shared
/// by the athlete and coach apps; the app only links to them.
struct LegalLinks: View {
    var accent: Color = Palette.bronze

    private var base: String { AppConfig.apiBaseURL }
    // (title, SF Symbol, web path)
    private let docs: [(String, String, String)] = [
        ("Privacy & GDPR",            "lock.shield.fill",     "/privacy/"),
        ("Termini di servizio",       "doc.text.fill",        "/termini-di-servizio/"),
        ("Termini d'uso",             "doc.plaintext.fill",   "/termini-duso/"),
        ("Cookie",                    "circle.grid.2x2.fill", "/cookie/"),
        ("Trasparenza AI (AI Act)",   "sparkles",             "/ai-trasparenza/"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LEGALE").voltEyebrow()
            VStack(spacing: 0) {
                ForEach(Array(docs.enumerated()), id: \.offset) { i, d in
                    if i > 0 { Divider().background(Palette.line) }
                    if let u = URL(string: base + d.2) {
                        Link(destination: u) { row(d.0, d.1) }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4).voltPanel()
        }
    }

    private func row(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent).frame(width: 26)
            Text(title).font(Typo.body(14, .medium)).foregroundStyle(Palette.textHi)
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared settings building blocks (identical in athlete + coach)

/// One email-notification (or generic) toggle row. Both apps must use this so
/// the settings screens stay visually identical.
struct SettingsToggleRow: View {
    var label: String
    var desc: String
    @Binding var isOn: Bool
    /// Local mirror so the switch flips instantly; the source of truth catches
    /// up when the backing store (usually an API roundtrip) confirms.
    @State private var local: Bool

    init(label: String, desc: String, isOn: Binding<Bool>) {
        self.label = label; self.desc = desc; _isOn = isOn
        _local = State(initialValue: isOn.wrappedValue)
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { local },
            set: { v in local = v; isOn = v }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text(desc).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.control)
        .padding(16).voltPanel()
        .onChange(of: isOn) { _, v in local = v }
    }
}

/// Navigation row: icon + title/subtitle + chevron. The chevron is the
/// affordance — every tappable row that pushes or presents uses this.
struct NavListRow: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var accent: Color = Palette.primary
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    if let subtitle {
                        Text(subtitle).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(14).voltPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Hub grid tile ("Altro" sections in both apps): icon top-left, chevron
/// top-right as the tap affordance, title + subtitle below.
struct HubTile: View {
    var icon: String
    var title: String
    var subtitle: String
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textLow)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body(15, .bold)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(16).voltPanel()
        .contentShape(Rectangle())
    }
}

/// The shared logout + delete-account block. One look for both apps:
/// logout is a neutral ghost, delete is unmistakably destructive.
struct AccountActions: View {
    var onLogout: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            NeonButton(title: "Esci", icon: "rectangle.portrait.and.arrow.right",
                       color: Palette.control, filled: false, action: onLogout)
            NeonButton(title: "Elimina account", icon: "trash",
                       color: Palette.danger, filled: false, action: onDelete)
        }
        .padding(.top, 10)
    }
}

/// Shared destructive-action confirmation card (logout / delete / discard).
/// Presented as an overlay; both apps use this instead of ad-hoc dialogs.
struct ConfirmDialogCard: View {
    var icon: String
    var title: String
    var message: String
    var confirmTitle: String
    var accent: Color = Palette.danger
    var loading: Bool = false
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x14110D, alpha: 0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(accent)
                Text(title)
                    .font(Typo.display(22)).foregroundStyle(Palette.textHi)
                Text(message)
                    .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    NeonButton(title: confirmTitle, icon: icon, color: accent,
                               filled: true, loading: loading, action: onConfirm)
                    NeonButton(title: "Annulla", color: Palette.control,
                               filled: false, action: onCancel)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .voltPanel(accent.opacity(0.35))
            .padding(.horizontal, 28)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .zIndex(1)
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
