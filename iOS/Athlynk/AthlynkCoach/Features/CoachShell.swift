//
//  CoachShell.swift
//  Athlynk Coach app shell: persistent luxury background + a custom tab bar over
//  swapping screens. Mirrors the athlete MainTabView but with coach destinations.
//

import SwiftUI

enum CoachTab: Int, CaseIterable, Identifiable {
    case home, allenamento, nutrizione, check, altro
    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .allenamento: return "dumbbell.fill"
        case .nutrizione:  return "flame.fill"
        case .check:       return "checkmark.seal.fill"
        case .altro:       return "ellipsis"
        }
    }
    var title: String {
        switch self {
        case .home:        return "Home"
        case .allenamento: return "Allenamento"
        case .nutrizione:  return "Nutrizione"
        case .check:       return "Check"
        case .altro:       return "Altro"
        }
    }
    var color: Color {
        switch self {
        case .home:        return Palette.bronze
        case .allenamento: return Palette.cyan
        case .nutrizione:  return Palette.lime
        case .check:       return Palette.violet
        case .altro:       return Palette.phase
        }
    }
}

struct CoachMainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: CoachTab = .home
    @State private var pendingMore: CoachRoute?
    @State private var allenamentoPath = NavigationPath()
    @State private var nutrizioneePath = NavigationPath()
    @State private var checkPath       = NavigationPath()
    @State private var altroPPath      = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tab)

            TabView(selection: $tab) {
                page(.home) { CoachDashboardView(tab: $tab, pendingMore: $pendingMore) }
                page(.allenamento) { CoachWorkoutsView(path: $allenamentoPath) }
                page(.nutrizione)  { CoachNutritionView(path: $nutrizioneePath) }
                page(.check)       { CoachChecksView(path: $checkPath) }
                page(.altro)       { CoachMoreView(path: $altroPPath, pending: $pendingMore) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            CoachTabBar(selection: $tab, onReselect: { reselectTab in
                Haptics.tap()
                switch reselectTab {
                case .allenamento: allenamentoPath = NavigationPath()
                case .nutrizione:  nutrizioneePath = NavigationPath()
                case .check:       checkPath = NavigationPath()
                case .altro:       altroPPath = NavigationPath()
                default: break
                }
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

    private func page<Content: View>(_ which: CoachTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .tag(which)
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
                            .lineLimit(1).minimumScaleFactor(0.6)
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
        // iOS 26 Liquid Glass: the bar refracts the content paging behind it.
        .glassEffect(.regular.tint(Palette.void1.opacity(0.28)).interactive(), in: .capsule)
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.40), .white.opacity(0.04), Palette.line.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .shadow(color: Color(hex: 0x14110D, alpha: 0.16), radius: 22, y: 12)
    }
}
