//
//  MacroHistoryView.swift
//  Past days of the MACRO food diary. Each day is editable: tap opens the
//  diary for that date (add/remove foods) via MacroLogView(logDate:).
//  Backed by /api/v1/nutrition/assignments/<id>/macro-history.
//

import SwiftUI

struct MacroHistoryView: View {
    let assignmentId: Int
    let planTitle: String

    @State private var days: [MacroHistoryDayDTO] = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if loading {
                        MacroLogSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.lime)
                    } else if days.isEmpty {
                        EmptyPanel(icon: "calendar", text: "Nessun giorno registrato.\nInizia dal diario di oggi.",
                                   color: Palette.lime)
                    } else {
                        ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                            NavigationLink {
                                MacroLogView(assignmentId: assignmentId, planTitle: planTitle, logDate: day.date)
                            } label: { dayCard(day) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(true, index: i)
                        }
                        if hasMore {
                            Button { Task { await loadMore() } } label: {
                                HStack(spacing: 8) {
                                    if loadingMore { ProgressView().tint(Palette.lime) }
                                    Text(loadingMore ? "Carico…" : "Carica altri giorni")
                                        .font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.lime.opacity(0.12)))
                            }
                            .disabled(loadingMore)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 44)
            }
        }
        .navigationTitle("Storico pasti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Palette.lime)
        .task { await load() }
    }

    private func dayCard(_ day: MacroHistoryDayDTO) -> some View {
        let target = max(day.target.kcal, 1)
        let over = day.consumed.kcal > target
        let accent = over ? Palette.amber : Palette.lime
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.dowShort).font(Typo.mono(11, .black)).tracking(1.5).foregroundStyle(accent)
                Text(prettyDate(day.date)).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Spacer()
                Text("\(Int(day.consumed.kcal))").font(Typo.mono(17, .bold)).foregroundStyle(accent)
                Text("/ \(Int(day.target.kcal)) kcal").font(Typo.mono(10, .bold)).foregroundStyle(Palette.textMid)
            }
            HStack(spacing: 16) {
                miniMacro("P", day.consumed.protein, Palette.magenta)
                miniMacro("C", day.consumed.carb, Palette.cyan)
                miniMacro("G", day.consumed.fat, Palette.amber)
                Spacer()
                Text("\(day.entries.count) alimenti").font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .black))
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
        .padding(16).voltPanel(accent.opacity(0.3))
    }

    private func miniMacro(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(letter).font(Typo.mono(10, .black)).foregroundStyle(color)
            Text("\(Int(grams))g").font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
        }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let r = try await APIClient.shared.macroHistory(assignment: assignmentId)
            days = r.days; hasMore = r.hasMore
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        loadingMore = true
        do {
            let r = try await APIClient.shared.macroHistory(assignment: assignmentId, offset: days.count)
            days += r.days; hasMore = r.hasMore
        } catch { /* keep what we have */ }
        loadingMore = false
    }

    private func prettyDate(_ iso: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: iso) else { return iso }
        let out = DateFormatter(); out.locale = Locale(identifier: "it_IT"); out.dateFormat = "d MMM yyyy"
        return out.string(from: d)
    }
}
