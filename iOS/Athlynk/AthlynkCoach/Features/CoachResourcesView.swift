//
//  CoachResourcesView.swift
//  "Libreria / Gestione Risorse (Coach)" — the coach's reusable content:
//  workout & nutrition plans, check templates and supplement sheets.
//

import SwiftUI

struct CoachResourcesView: View {
    @State private var sections: [CoachResourceSection] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Studio", title: "Risorse",
                         subtitle: "I tuoi modelli riutilizzabili", accent: Palette.violet)
            if loading && sections.isEmpty {
                ForEach(0..<4, id: \.self) { _ in SkelLinkRow(accent: Palette.violet) }
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                    section(s, accent: Palette.accent(i))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func section(_ s: CoachResourceSection, accent: Color) -> some View {
        let isOpen = expanded.contains(s.key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                if isOpen { expanded.remove(s.key) } else { expanded.insert(s.key) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: s.icon).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent).frame(width: 32)
                    Text(s.label).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                    Spacer()
                    Text("\(s.count)").font(Typo.mono(13, .bold)).foregroundStyle(accent)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textLow)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isOpen {
                if s.items.isEmpty {
                    Text("Vuoto").font(Typo.body(13)).foregroundStyle(Palette.textLow)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(s.items) { item in
                            HStack {
                                Circle().fill(accent.opacity(0.5)).frame(width: 6, height: 6)
                                Text(item.title).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                                    .lineLimit(1)
                                Spacer()
                                if let g = item.goal ?? item.planMode ?? item.type {
                                    Text(g).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        sections = (try? await APIClient.shared.coachResources()) ?? []
    }
}
