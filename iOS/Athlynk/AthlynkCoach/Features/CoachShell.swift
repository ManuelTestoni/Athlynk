//
//  CoachShell.swift
//  Athlynk Coach app shell: persistent luxury background + a custom tab bar over
//  swapping screens. Mirrors the athlete MainTabView but with coach destinations.
//

import SwiftUI

enum CoachTab: Int, CaseIterable, Identifiable {
    case dashboard, clienti, agenda, chat, altro
    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .clienti:   return "person.2.fill"
        case .agenda:    return "calendar"
        case .chat:      return "bubble.left.fill"
        case .altro:     return "ellipsis"
        }
    }
    var title: String {
        switch self {
        case .dashboard: return "Hub"
        case .clienti:   return "Atleti"
        case .agenda:    return "Agenda"
        case .chat:      return "Chat"
        case .altro:     return "Altro"
        }
    }
    var color: Color {
        switch self {
        case .dashboard: return Palette.bronze
        case .clienti:   return Palette.cyan
        case .agenda:    return Palette.amber
        case .chat:      return Palette.violet
        case .altro:     return Palette.phase
        }
    }
}

struct CoachMainTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: CoachTab = .dashboard
    /// Bumped when the active tab is re-tapped, changing the content identity so
    /// the tab's NavigationStack is rebuilt at its root (pop-to-root).
    @State private var resetNonce = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette).animation(.easeInOut(duration: 0.8), value: tab)

            Group {
                switch tab {
                case .dashboard: CoachDashboardView(tab: $tab)
                case .clienti:   CoachClientsView()
                case .agenda:    CoachAgendaView()
                case .chat:      CoachMessagesView()
                case .altro:     CoachMoreView()
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 16)),
                removal: .opacity
            ))
            .id("\(tab.rawValue)-\(resetNonce)")

            CoachTabBar(selection: $tab, onReselect: { _ in
                withAnimation(.easeInOut(duration: 0.25)) { resetNonce &+= 1 }
            })
                .padding(.bottom, 6)
                .offset(y: app.tabBarHidden ? 160 : 0)
                .opacity(app.tabBarHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.tabBarHidden)
        }
        .task { Analytics.shared.screen("coach_\(tab.title.lowercased())") }
        .onChange(of: tab) { _, newTab in
            Analytics.shared.screen("coach_\(newTab.title.lowercased())")
        }
    }

    private var tabPalette: [Color] {
        let c = tab.color
        return [c, c.opacity(0.6), Palette.violet, Palette.cyan]
    }
}

struct CoachTabBar: View {
    @Binding var selection: CoachTab
    /// Fired when the already-active tab is tapped again (pop-to-root).
    var onReselect: (CoachTab) -> Void = { _ in }
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CoachTab.allCases) { tab in
                let active = tab == selection
                Button {
                    Haptics.tap()
                    if active {
                        onReselect(tab)
                    } else {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { selection = tab }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .bold))
                            .symbolEffect(.bounce, value: active)
                            .frame(height: 22)
                        Text(tab.title)
                            .font(Typo.mono(9, .bold)).tracking(1).textCase(.uppercase)
                    }
                    .foregroundStyle(active ? Palette.void0 : Palette.textLow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if active {
                            Capsule().fill(tab.color)
                                .matchedGeometryEffect(id: "coachblob", in: ns)
                                .neonGlow(tab.color, radius: 14)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(Palette.void1.opacity(0.85))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .shadow(color: Color(hex: 0x14110D, alpha: 0.16), radius: 22, y: 12)
    }
}
