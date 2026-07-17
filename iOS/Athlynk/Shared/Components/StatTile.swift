//
//  StatTile.swift
//  Dashboard "big card" (KPI) and "small card" (quick action) building blocks.
//  Originally coach-only; promoted to Shared so the athlete dashboard can reuse
//  the same look for its own KPI/quick-nav row.
//

import SwiftUI

struct CoachStatTile: View {
    var value: String
    var label: String
    var icon: String
    var accent: Color
    var flag: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(accent)
                    Spacer()
                    if let flag {
                        Text(flag).font(Typo.mono(8, .black)).tracking(1)
                            .foregroundStyle(Palette.void0)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(accent))
                    }
                }
                Text(value)
                    .font(Typo.poster(38)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(label)
                    .font(Typo.mono(10, .semibold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Palette.textMid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .voltPanel()
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct CoachQuickAction: View {
    var icon: String
    var label: String
    var accent: Color
    /// Small "+" (or other) badge overlaid bottom-trailing on the icon —
    /// used for the dashboard's "add workout/nutrition" shortcuts.
    var badge: String? = nil
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 19, weight: .bold))
                    .foregroundStyle(accent)
                    .overlay(alignment: .bottomTrailing) {
                        if let badge {
                            Image(systemName: badge)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(Palette.void0)
                                .padding(3)
                                .background(Circle().fill(accent))
                                .offset(x: 8, y: 6)
                        }
                    }
                Text(label).font(Typo.mono(10, .semibold)).tracking(0.5)
                    .textCase(.uppercase).foregroundStyle(Palette.textHi)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.vertical, 12)
            .voltPanel(radius: 14)
        }
        .buttonStyle(PressableButtonStyle())
    }
}
