//
//  NeonTabBar.swift
//  Floating glass capsule with a morphing neon blob behind the active tab.
//

import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case home, train, fuel, check, altro
    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .train: return "dumbbell.fill"
        case .fuel: return "flame.fill"
        case .check: return "checkmark.seal.fill"
        case .altro: return "ellipsis"
        }
    }
    var title: String {
        switch self {
        case .home: return "Home"
        case .train: return "Allenamento"
        case .fuel: return "Nutrizione"
        case .check: return "Check"
        case .altro: return "Altro"
        }
    }
    var color: Color {
        switch self {
        case .home: return Palette.cyan
        case .train: return Palette.magenta
        case .fuel: return Palette.lime
        case .check: return Palette.violet
        case .altro: return Palette.amber
        }
    }
}

struct NeonTabBar: View {
    @Binding var selection: AppTab
    /// Fired when the already-active tab is tapped again (pop-to-root).
    var onReselect: (AppTab) -> Void = { _ in }
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
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
                            .font(Typo.mono(9, .bold))
                            .tracking(1)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(active ? Palette.void0 : Palette.textLow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if active {
                            Capsule()
                                .fill(tab.color)
                                .matchedGeometryEffect(id: "blob", in: ns)
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
