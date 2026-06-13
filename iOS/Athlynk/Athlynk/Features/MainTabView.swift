//
//  MainTabView.swift
//  App shell: persistent neon background + custom tab bar over swapping screens.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: AppTab = .home
    /// Bumped when the active tab is re-tapped, changing the content identity so
    /// the tab's NavigationStack is rebuilt at its root (pop-to-root).
    @State private var resetNonce = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette).animation(.easeInOut(duration: 0.8), value: tab)

            Group {
                switch tab {
                case .home:  DashboardView(tab: $tab)
                case .train: WorkoutsView()
                case .fuel:  NutritionView()
                case .check: ChecksView()
                case .you:   ProfileView()
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 16)),
                removal: .opacity
            ))
            .id("\(tab.rawValue)-\(resetNonce)")

            NeonTabBar(selection: $tab, onReselect: { _ in
                withAnimation(.easeInOut(duration: 0.25)) { resetNonce &+= 1 }
            })
                .padding(.bottom, 6)
                .offset(y: app.tabBarHidden ? 160 : 0)
                .opacity(app.tabBarHidden ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.tabBarHidden)
        }
    }

    private var tabPalette: [Color] {
        let c = tab.color
        return [c, c.opacity(0.6), Palette.violet, Palette.cyan]
    }
}
