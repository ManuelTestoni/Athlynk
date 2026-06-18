//
//  MainTabView.swift
//  App shell: persistent neon background + a Liquid-Glass tab bar over a paged,
//  swipeable section stack. Dragging horizontally moves between sections; the
//  floating glass bar stays in sync.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: AppTab = .home
    /// Bumped when the active tab is re-tapped, changing the content identity so
    /// the tab's NavigationStack is rebuilt at its root (pop-to-root).
    @State private var resetNonce = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tab)

            TabView(selection: $tab) {
                page(.home) { DashboardView(tab: $tab) }
                page(.train) { WorkoutsView() }
                page(.fuel) { NutritionView() }
                page(.check) { ChecksView() }
                page(.altro) { AthleteMoreView() }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)

            NeonTabBar(selection: $tab, onReselect: { _ in
                withAnimation(.easeInOut(duration: 0.25)) { resetNonce &+= 1 }
            })
                .padding(.bottom, 6)
                .offset(y: app.tabBarHidden ? 160 : 0)
                .opacity(app.tabBarHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.tabBarHidden)
        }
    }

    /// Wraps a section as a paged tab. `resetNonce` rebuilds the page at its root
    /// when its tab is re-tapped (pop-to-root).
    private func page<Content: View>(_ which: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .id("\(which.rawValue)-\(resetNonce)")
            .tag(which)
    }

    private var tabPalette: [Color] {
        let c = tab.color
        return [c, c.opacity(0.6), Palette.violet, Palette.cyan]
    }
}
