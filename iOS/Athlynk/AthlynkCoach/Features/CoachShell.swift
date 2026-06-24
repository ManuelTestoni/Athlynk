//
//  CoachShell.swift
//  Athlynk Coach app shell: persistent luxury background + a custom tab bar over
//  swapping screens. Mirrors the athlete MainTabView but with coach destinations.
//

import SwiftUI
import Combine

// MARK: - Deep-link routing (Chiron "section" links → native screens)

/// A native destination Chiron can ask the app to open. Parsed from the web
/// path (`reverse()`) the backend emits; falls back to the section when no
/// per-id native screen exists (e.g. progressi → client detail).
enum CoachDeepLink: Equatable {
    case client(Int)
    case check(Int)
    case checkDashboard

    static func parse(_ url: String) -> CoachDeepLink? {
        // Backend emits relative paths (Django reverse), e.g. "/clienti/5/".
        // Take the path only; tolerate an absolute URL just in case.
        let path = URLComponents(string: url)?.path ?? url
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        func int(_ i: Int) -> Int? { i < parts.count ? Int(parts[i]) : nil }
        switch first {
        case "clienti":                              // /clienti/<id>/ , /clienti/<id>/progressi/
            if let id = int(1) { return .client(id) }
        case "check":
            if parts.count == 1 { return .checkDashboard }            // /check/
            if parts[1] == "cliente", let id = int(2) { return .client(id) } // /check/cliente/<id>/
            if let id = Int(parts[1]) { return .check(id) }           // /check/<id>/
        default: break
        }
        return nil
    }
}

@MainActor
final class CoachRouter: ObservableObject {
    /// Set by a deep-link tap; CoachShell observes and consumes it.
    @Published var deepLink: CoachDeepLink?
    func open(_ url: String) { if let dl = CoachDeepLink.parse(url) { deepLink = dl } }
}

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
    @State private var allenamentoPath = NavigationPath()
    @State private var nutrizioneePath = NavigationPath()
    @State private var checkPath       = NavigationPath()
    @State private var altroPPath      = NavigationPath()
    @State private var showChiron      = false
    @StateObject private var router    = CoachRouter()

    var body: some View {
        ZStack(alignment: .bottom) {
            VoltBackground(palette: tabPalette)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: tab)

            // ZStack instead of TabView(.page): avoids iOS 26 UINavigationBar assertion
            // that fires when multiple NavigationStacks are alive in UIPageViewController.
            // All views stay alive (state preserved); only one is visible + interactive.
            ZStack {
                page(.home) { CoachDashboardView(tab: $tab) }
                page(.allenamento) { CoachWorkoutsView(path: $allenamentoPath) }
                page(.nutrizione)  { CoachNutritionView(path: $nutrizioneePath) }
                page(.check)       { CoachChecksView(path: $checkPath) }
                page(.altro)       { CoachMoreView(path: $altroPPath) }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            // Reserve the floating tab bar's footprint so the last bit of every
            // scroll view clears it instead of being hidden underneath.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }

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

            // Chiron floating button — always visible, bottom-right above tab bar
            ChironFAB(show: $showChiron)
                .padding(.trailing, 20)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: app.tabBarHidden ? 80 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.tabBarHidden)
        }
        .sheet(isPresented: $showChiron) {
            NavigationStack { CoachChironView() }
                .environmentObject(router)
        }
        .task { Analytics.shared.screen("coach_\(tab.title.lowercased())") }
        .onChange(of: tab) { _, newTab in
            Analytics.shared.screen("coach_\(newTab.title.lowercased())")
        }
        .onChange(of: router.deepLink) { _, dl in
            guard let dl else { return }
            showChiron = false
            applyDeepLink(dl)
            router.deepLink = nil
        }
    }

    /// Route a Chiron link to the matching native screen, falling back to the
    /// relevant section when no per-id screen exists.
    private func applyDeepLink(_ dl: CoachDeepLink) {
        switch dl {
        case .client(let id):
            var p = NavigationPath()
            p.append(CoachRoute.clients)   // More tab → clients list → detail
            p.append(id)                   // Int → CoachClientDetailView(clientId:)
            altroPPath = p
            tab = .altro
        case .check(let id):
            var p = NavigationPath()
            p.append(CheckRoute(id: id))
            checkPath = p
            tab = .check
        case .checkDashboard:
            checkPath = NavigationPath()
            tab = .check
        }
    }

    private func page<Content: View>(_ which: CoachTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == which ? 1 : 0)
            .allowsHitTesting(tab == which)
    }

    private var tabPalette: [Color] {
        let c = tab.color
        return [c, c.opacity(0.6), Palette.violet, Palette.cyan]
    }
}

// MARK: - Chiron Floating Action Button

struct ChironFAB: View {
    @Binding var show: Bool

    var body: some View {
        Button { Haptics.tap(); show = true } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Palette.bronze, Palette.amber],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .neonGlow(Palette.bronze, radius: 16)
                    .shadow(color: Palette.bronze.opacity(0.45), radius: 12, y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apri Chiron AI")
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
