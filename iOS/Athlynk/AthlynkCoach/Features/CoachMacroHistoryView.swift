//
//  CoachMacroHistoryView.swift
//  Read-only view of what an athlete actually logged on their MACRO plan —
//  the coach's window onto the compiled meal history.
//  Backed by /api/v1/coach/clients/<id>/macro-history.
//

import SwiftUI

struct CoachClientMacroHistoryRoute: Hashable { let clientId: Int }

struct CoachMacroHistoryView: View {
    let clientId: Int

    @State private var days: [MacroHistoryDayDTO] = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false

    var body: some View {
        ScreenScroll {
            CoachSectionTitle(eyebrow: "Nutrizione", title: "Storico pasti", accent: Palette.lime)
            if loading {
                CoachPlanDetailSkeleton(accent: Palette.lime)
            } else if days.isEmpty {
                EmptyPanel(icon: "calendar", text: "L'atleta non ha ancora registrato pasti.")
            } else {
                ForEach(days) { day in dayCard(day) }
                if hasMore {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 8) {
                            if loadingMore { ProgressView().tint(Palette.lime) }
                            Text(loadingMore ? "Carico…" : "Carica altri giorni")
                                .font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14).voltPanel(radius: 12)
                    }
                    .disabled(loadingMore)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func dayCard(_ day: MacroHistoryDayDTO) -> some View {
        let over = day.consumed.kcal > max(day.target.kcal, 1)
        let accent = over ? Palette.amber : Palette.lime
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.dowShort).font(Typo.mono(11, .black)).tracking(1.5).foregroundStyle(accent)
                Text(prettyDate(day.date)).font(Typo.body(16, .bold)).foregroundStyle(Palette.textHi)
                Spacer()
                Text("\(Int(day.consumed.kcal))").font(Typo.mono(15, .bold)).foregroundStyle(accent)
                Text("/ \(Int(day.target.kcal)) kcal").font(Typo.mono(10, .bold)).foregroundStyle(Palette.textMid)
            }
            HStack(spacing: 16) {
                miniMacro("P", day.consumed.protein, Palette.cyan)
                miniMacro("C", day.consumed.carb, Palette.lime)
                miniMacro("G", day.consumed.fat, Palette.phase)
                Spacer()
            }
            if !day.entries.isEmpty {
                Divider().overlay(Palette.textLow.opacity(0.3))
                ForEach(day.entries) { e in
                    HStack {
                        Text(e.name).font(Typo.body(13)).foregroundStyle(Palette.textHi).lineLimit(1)
                        if !e.mealName.isEmpty {
                            Text(e.mealName).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                        }
                        Spacer(minLength: 6)
                        Text("\(Int(e.quantityG))g").font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                        Text("· \(Int(e.kcal)) kcal").font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }

    private func miniMacro(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(letter).font(Typo.mono(10, .black)).foregroundStyle(color)
            Text("\(Int(grams))g").font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
        }
    }

    private func load() async {
        loading = true
        if let r = try? await APIClient.shared.coachClientMacroHistory(clientId: clientId) {
            days = r.days; hasMore = r.hasMore
        }
        loading = false
    }

    private func loadMore() async {
        loadingMore = true
        if let r = try? await APIClient.shared.coachClientMacroHistory(clientId: clientId, offset: days.count) {
            days += r.days; hasMore = r.hasMore
        }
        loadingMore = false
    }

    private func prettyDate(_ iso: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: iso) else { return iso }
        let out = DateFormatter(); out.locale = Locale(identifier: "it_IT"); out.dateFormat = "d MMM yyyy"
        return out.string(from: d)
    }
}
