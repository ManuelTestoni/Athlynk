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
    @State private var workoutsPath = NavigationPath()
    @State private var nutritionPath = NavigationPath()
    @State private var checksPath    = NavigationPath()
    @State private var altroPPath    = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tab)

            ZStack {
                page(.home)  { DashboardView(tab: $tab) }
                page(.train) { WorkoutsView(path: $workoutsPath) }
                page(.fuel)  { NutritionView(path: $nutritionPath) }
                page(.check) { ChecksView(path: $checksPath) }
                page(.altro) { AthleteMoreView(path: $altroPPath) }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            // Reserve the floating tab bar's footprint so the last bit of every
            // scroll view clears it instead of being hidden underneath.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }

            NeonTabBar(selection: $tab, onReselect: { reselectTab in
                Haptics.tap()
                switch reselectTab {
                case .train: workoutsPath = NavigationPath()
                case .fuel:  nutritionPath = NavigationPath()
                case .check: checksPath = NavigationPath()
                case .altro: altroPPath = NavigationPath()
                default: break
                }
            })
                .padding(.bottom, 6)
                .offset(y: app.tabBarHidden ? 160 : 0)
                .opacity(app.tabBarHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.tabBarHidden)
        }
    }

    /// Wraps a section as a paged tab. Identity is the stable tab tag — a paged
    /// TabView caches a page controller per tag, so the tagged child must keep a
    /// constant identity. Mutating it (the old `.id(nonce)` pop-to-root hack)
    /// invalidated the cached controller and crashed on non-adjacent switches.
    private func page<Content: View>(_ which: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == which ? 1 : 0)
            .allowsHitTesting(tab == which)
    }

    private var tabPalette: [Color] {
        let c = tab.color
        return [c, c.opacity(0.6), Palette.violet, Palette.cyan]
    }
}
