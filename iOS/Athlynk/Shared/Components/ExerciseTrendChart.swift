//
//  ExerciseTrendChart.swift
//  Per-exercise trend over completed sessions (volume / top set / weighted avg),
//  matching the website's exercise_trend feature. Self-loading card shared by the
//  athlete (ExerciseDetailView) and the coach (per-athlete drill-down). The caller
//  supplies the loader so the same UI works against either token scope.
//

import SwiftUI

enum TrendMetric: String, CaseIterable, Identifiable {
    case topSet, volume, avg
    var id: String { rawValue }
    var label: String {
        switch self {
        case .topSet: return "Top set"
        case .volume: return "Volume"
        case .avg:    return "Media pond."
        }
    }
}

struct ExerciseTrendCard: View {
    let load: () async throws -> ExerciseTrendDTO
    var accent: Color = Palette.magenta

    @State private var data: ExerciseTrendDTO?
    @State private var loading = true
    @State private var metric: TrendMetric = .topSet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 14, weight: .black))
                    .foregroundStyle(accent)
                Text("ANDAMENTO").voltEyebrow()
                InfoTip(text: "Top set: carico massimo della sessione. Volume: somma di reps × carico. Media pond.: carico medio pesato sulle ripetizioni. Tieni premuto sul grafico per vedere i valori punto per punto.")
            }

            if loading {
                ProgressView().tint(accent).frame(maxWidth: .infinity, minHeight: 120)
            } else if let d = data, d.hasData, !chronoSessions.isEmpty {
                metricPicker
                chart(d)
                sessionList
            } else {
                ChartEmpty(icon: "chart.xyaxis.line",
                           text: "Nessuna sessione registrata.\nL'andamento apparirà dopo i primi allenamenti.")
                    .frame(minHeight: 120)
            }
        }
        .padding(18).voltPanel(accent.opacity(0.35))
        .task { await reload() }
    }

    private var chronoSessions: [TrendSessionDTO] { data?.sessions ?? [] }

    private var unit: String {
        switch metric {
        case .volume: return ""
        default: return (data?.exercise.loadUnit ?? "KG").lowercased() == "kg" ? "kg" : (data?.exercise.loadUnit ?? "")
        }
    }

    private func metricValue(_ s: TrendSessionDTO) -> Double? {
        switch metric {
        case .topSet: return s.topSet
        case .volume: return s.volume
        case .avg:    return s.weightedAvgLoad
        }
    }

    private var metricPicker: some View {
        Picker("", selection: $metric) {
            ForEach(TrendMetric.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
    }

    private func chart(_ d: ExerciseTrendDTO) -> some View {
        let values = chronoSessions.compactMap(metricValue)
        return VStack(alignment: .leading, spacing: 10) {
            if values.count >= 2 {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(fmt(values.last ?? 0)).font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                        if !unit.isEmpty {
                            Text(unit).font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                        }
                    }
                    Spacer()
                    DeltaPill(delta: (values.last ?? 0) - (values.first ?? 0),
                              unit: unit, goodWhenDown: false)
                }
                TrendLine(values: values, color: accent,
                          labels: chronoSessions.compactMap { metricValue($0) != nil ? dateShort($0.date) : nil })
                    .frame(height: 140)
                HStack {
                    Text(dateShort(chronoSessions.first?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                    Spacer()
                    Text("\(chronoSessions.count) sessioni").font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                    Spacer()
                    Text(dateShort(chronoSessions.last?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
            } else {
                ChartEmpty(icon: "chart.xyaxis.line",
                           text: "Servono almeno 2 sessioni\ncon questa metrica.")
                    .frame(height: 120)
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ULTIME SESSIONI").font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            ForEach(chronoSessions.reversed().prefix(6).map { $0 }) { s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dateMedium(s.date)).font(Typo.mono(10, .bold)).foregroundStyle(Palette.textMid)
                        Spacer()
                        if let top = s.topSet {
                            Text("Top \(fmt(top))\(unitSuffix(s))").font(Typo.mono(10, .bold))
                                .foregroundStyle(accent)
                        }
                    }
                    if !s.sets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(s.sets) { set in setChip(set, session: s) }
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
            }
        }
    }

    private func setChip(_ set: TrendSetDTO, session s: TrendSessionDTO) -> some View {
        let reps = set.reps.map { "\($0)" } ?? "—"
        let load = set.load.map { fmt($0) } ?? "—"
        return Text("\(reps)×\(load)")
            .font(Typo.mono(10, .semibold))
            .foregroundStyle((set.isExtra ?? false) ? Palette.amber : Palette.textHi)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Palette.void1))
            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    private func unitSuffix(_ s: TrendSessionDTO) -> String {
        let u = (s.loadUnit ?? data?.exercise.loadUnit ?? "").lowercased()
        return u == "kg" ? " kg" : ""
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    @MainActor private func reload() async {
        loading = true
        data = try? await load()
        loading = false
    }
}

// MARK: - Date helpers (file-private)

private func parseISODate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(iso.prefix(10)))
}
private func dateShort(_ iso: String?) -> String {
    guard let d = parseISODate(iso) else { return "—" }
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
    return f.string(from: d)
}
private func dateMedium(_ iso: String?) -> String {
    guard let d = parseISODate(iso) else { return "—" }
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}
