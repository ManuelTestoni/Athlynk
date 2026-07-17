//
//  CoachProgressionGridView.swift
//  Manual per-week progression editor — 1:1 with the web Step-3 grid.
//  Loads the server-computed day grid (forward-filled overrides), lets the coach
//  edit every week including week 1 (the server writes week-1 edits straight onto
//  the builder's base exercise fields, same as web), and shows a live weekly
//  chart (tonnage / volume / intensity). Edits persist immediately via the shared
//  `/progression/cell/` endpoint (the same one the web builder uses).
//

import SwiftUI
import Charts

struct CoachProgressionGridView: View {
    let planId: Int
    let days: [(id: Int, name: String)]
    let durationWeeks: Int
    let accent: Color

    @State private var dayIdx = 0
    @State private var exercises: [PGExercise] = []
    @State private var cells: [String: [String: [String: PGCell]]] = [:]
    @State private var loading = true
    @State private var editing: PGEditTarget?
    @State private var chartMetric: ProgMetric = .tonnage
    @StateObject private var flash = StatusFlash()

    private var weeks: [Int] { Array(1...max(1, durationWeeks)) }
    private var currentDayId: Int? { days.indices.contains(dayIdx) ? days[dayIdx].id : nil }

    var body: some View {
        VStack(spacing: 16) {
            header

            if days.count > 1 { daySelector }

            if loading {
                SwiftUI.ProgressView().tint(accent).padding(.vertical, 40)
            } else if exercises.isEmpty {
                Text("Nessun esercizio in questo giorno.")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                volumeChart
                ForEach(exercises) { ex in exerciseRow(ex) }
            }
        }
        .task(id: currentDayId) { await load() }
        .sheet(item: $editing) { target in
            PGCellEditor(target: target, accent: accent) { metric, value in
                await commit(target: target, metric: metric, value: value)
            }
        }
        .statusOverlay(flash)
    }

    // MARK: Header + day selector

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
            Text("Progressione su \(durationWeeks) settimane")
                .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Text("Modifica i valori per ogni settimana: si propagano alle settimane successive finché non li cambi di nuovo.")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(18).voltPanel()
    }

    private var daySelector: some View {
        Menu {
            ForEach(days.indices, id: \.self) { i in
                Button(days[i].name) { dayIdx = i }
            }
        } label: {
            HStack(spacing: 6) {
                Text(days.indices.contains(dayIdx) ? days[dayIdx].name : "Giorno")
                    .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11).voltPanel(radius: 12)
        }
    }

    // MARK: Volume chart

    private var volumeChart: some View {
        let points = weeks.map { w in (week: w, value: weeklyMetricValue(chartMetric, w)) }
        return VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $chartMetric) {
                ForEach(ProgMetric.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)

            Text(chartMetric.chartTitle)
                .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            Chart(points, id: \.week) { p in
                LineMark(x: .value("Sett.", p.week), y: .value(chartMetric.label, p.value))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Sett.", p.week), y: .value(chartMetric.label, p.value))
                    .foregroundStyle(accent)
            }
            .chartXAxis { AxisMarks(values: weeks) { v in
                AxisValueLabel { if let w = v.as(Int.self) { Text("S\(w)").font(Typo.mono(8)) } }
            } }
            .frame(height: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }

    // MARK: Exercise row (horizontal week cells)

    private func exerciseRow(_ ex: PGExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ex.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weeks, id: \.self) { w in weekCell(ex, w) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).voltPanel()
    }

    private func weekCell(_ ex: PGExercise, _ w: Int) -> some View {
        let rir = rpeRirMetric(ex)
        return Button {
            Haptics.tap()
            editing = PGEditTarget(exerciseId: ex.id, exerciseName: ex.name, week: w,
                                   rpeRirMetric: rir,
                                   serie: cellString(ex.id, w, "set_count"),
                                   reps: cellString(ex.id, w, "rep_range"),
                                   carico: cellString(ex.id, w, "load_value"),
                                   recupero: cellString(ex.id, w, "recovery_seconds"),
                                   intensita: cellString(ex.id, w, rir),
                                   tut: cellString(ex.id, w, "tempo"))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("S\(w)").font(Typo.mono(9, .bold)).foregroundStyle(accent)
                metricLine("Serie", cellString(ex.id, w, "set_count"), ex.id, w, "set_count")
                metricLine("Reps", cellString(ex.id, w, "rep_range"), ex.id, w, "rep_range")
                metricLine("Car.", cellString(ex.id, w, "load_value"), ex.id, w, "load_value")
                metricLine("Rec", cellString(ex.id, w, "recovery_seconds"), ex.id, w, "recovery_seconds")
                metricLine(rir == "rir" ? "RIR" : "RPE", cellString(ex.id, w, rir), ex.id, w, rir)
                metricLine("TUT", cellString(ex.id, w, "tempo"), ex.id, w, "tempo")
            }
            .frame(width: 96, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.void2))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func metricLine(_ label: String, _ value: String, _ exId: Int, _ w: Int, _ metric: String) -> some View {
        let isOverride = source(exId, w, metric) == "override"
        return HStack(spacing: 4) {
            Text(label).font(Typo.mono(8)).foregroundStyle(Palette.textLow).frame(width: 26, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(Typo.body(11, isOverride ? .semibold : .regular))
                .foregroundStyle(value.isEmpty ? Palette.textLow : (isOverride ? accent : Palette.textMid))
                .lineLimit(1)
        }
    }

    // MARK: Data access

    private func cell(_ exId: Int, _ w: Int, _ metric: String) -> PGCell? {
        cells["\(exId)"]?["\(w)"]?[metric]
    }
    private func cellString(_ exId: Int, _ w: Int, _ metric: String) -> String {
        cell(exId, w, metric)?.display ?? ""
    }
    private func source(_ exId: Int, _ w: Int, _ metric: String) -> String {
        cell(exId, w, metric)?.source ?? "base"
    }
    private func rpeRirMetric(_ ex: PGExercise) -> String {
        // Show RIR if the exercise's base uses it, else RPE (never both).
        if let v = ex.base["rir"], !(v is NSNull) { return "rir" }
        return "rpe"
    }

    /// Client-side only — same shape as the web builder's tonnage/volume/intensity
    /// switch, computed from the grid data already in memory (no extra network call).
    private func weeklyMetricValue(_ metric: ProgMetric, _ w: Int) -> Double {
        switch metric {
        case .tonnage:
            return exercises.reduce(0.0) { acc, ex in
                let sets = Double(cellString(ex.id, w, "set_count")) ?? 0
                let reps = Double(firstNumber(cellString(ex.id, w, "rep_range"))) ?? 0
                let load = Double(cellString(ex.id, w, "load_value")) ?? 0
                return acc + sets * reps * max(load, 1)
            }
        case .volume:
            return exercises.reduce(0.0) { acc, ex in
                let sets = Double(cellString(ex.id, w, "set_count")) ?? 0
                let reps = Double(firstNumber(cellString(ex.id, w, "rep_range"))) ?? 0
                return acc + sets * reps
            }
        case .intensity:
            // Reads each exercise's own effective value, RIR or RPE, whichever it uses.
            let values = exercises.compactMap { ex in Double(cellString(ex.id, w, rpeRirMetric(ex))) }
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
    }
    private func firstNumber(_ s: String) -> String {
        // "8-12" → "8"; "10" → "10".
        String(s.prefix { $0.isNumber })
    }

    // MARK: Load + commit

    private func load() async {
        guard let dayId = currentDayId else { loading = false; return }
        loading = exercises.isEmpty   // keep old grid on a refresh
        defer { loading = false }
        guard let grid = try? await APIClient.shared.coachProgressionGrid(planId: planId, dayId: dayId)
        else { return }
        exercises = (grid["exercises"] as? [[String: Any]] ?? []).compactMap { e in
            guard let id = e["id"] as? Int else { return nil }
            return PGExercise(id: id, name: e["name"] as? String ?? "Esercizio",
                              base: e["base"] as? [String: Any] ?? [:])
        }
        cells = parseCells(grid["cells"] as? [String: Any] ?? [:])
    }

    private func parseCells(_ raw: [String: Any]) -> [String: [String: [String: PGCell]]] {
        var out: [String: [String: [String: PGCell]]] = [:]
        for (exId, weeksAny) in raw {
            guard let weeksDict = weeksAny as? [String: Any] else { continue }
            var weekMap: [String: [String: PGCell]] = [:]
            for (week, metricsAny) in weeksDict {
                guard let metricsDict = metricsAny as? [String: Any] else { continue }
                var metricMap: [String: PGCell] = [:]
                for (metric, cellAny) in metricsDict {
                    guard let c = cellAny as? [String: Any] else { continue }
                    metricMap[metric] = PGCell(value: c["value"], source: c["source"] as? String ?? "base")
                }
                weekMap[week] = metricMap
            }
            out[exId] = weekMap
        }
        return out
    }

    private func commit(target: PGEditTarget, metric: String, value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let numeric = ["set_count", "load_value", "rpe", "rir", "recovery_seconds"]
        let payload: Any?
        if trimmed.isEmpty { payload = nil }
        else if numeric.contains(metric) { payload = Double(trimmed) ?? trimmed }
        else { payload = trimmed }
        do {
            _ = try await APIClient.shared.coachProgressionCell(
                planId: planId, exerciseId: target.exerciseId, week: target.week,
                metric: metric, value: payload, clear: payload == nil)
        } catch {
            flash.failure("Salvataggio non riuscito")
        }
        await load()
    }
}

// MARK: - Models

enum ProgMetric: String, CaseIterable, Identifiable {
    case tonnage, volume, intensity
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tonnage: return "Tonnellaggio"
        case .volume: return "Volume"
        case .intensity: return "Intensità"
        }
    }
    var chartTitle: String {
        switch self {
        case .tonnage: return "VOLUME SETTIMANALE (TONNELLAGGIO)"
        case .volume: return "VOLUME SETTIMANALE (SERIE × REPS)"
        case .intensity: return "INTENSITÀ MEDIA (RPE/RIR)"
        }
    }
}

struct PGExercise: Identifiable {
    let id: Int
    let name: String
    let base: [String: Any]
}

struct PGCell {
    let value: Any?
    let source: String
    var display: String {
        switch value {
        case let s as String: return s
        case let i as Int: return "\(i)"
        case let d as Double: return d == d.rounded() ? "\(Int(d))" : String(format: "%.2f", d)
        default: return ""
        }
    }
}

struct PGEditTarget: Identifiable {
    var id: String { "\(exerciseId)-\(week)" }
    let exerciseId: Int
    let exerciseName: String
    let week: Int
    let rpeRirMetric: String
    var serie: String
    var reps: String
    var carico: String
    var recupero: String
    var intensita: String
    var tut: String
}

// MARK: - Per-cell editor sheet (the 6 fields, direct entry)

private struct PGCellEditor: View {
    let target: PGEditTarget
    let accent: Color
    let onCommit: (_ metric: String, _ value: String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var serie: String
    @State private var reps: String
    @State private var carico: String
    @State private var recupero: String
    @State private var intensita: String
    @State private var tut: String
    @State private var saving = false

    init(target: PGEditTarget, accent: Color, onCommit: @escaping (_ metric: String, _ value: String) async -> Void) {
        self.target = target; self.accent = accent; self.onCommit = onCommit
        _serie = State(initialValue: target.serie)
        _reps = State(initialValue: target.reps)
        _carico = State(initialValue: target.carico)
        _recupero = State(initialValue: target.recupero)
        _intensita = State(initialValue: target.intensita)
        _tut = State(initialValue: target.tut)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        field("Serie", $serie, .numberPad)
                        field("Reps", $reps, .default)
                        field("Carico", $carico, .decimalPad)
                    }
                    HStack(spacing: 10) {
                        field("Rec (s)", $recupero, .numberPad)
                        field(target.rpeRirMetric == "rir" ? "RIR" : "RPE", $intensita, .decimalPad)
                        field("TUT", $tut, .default)
                    }
                    NeonButton(title: "Salva settimana \(target.week)", icon: "checkmark",
                               color: accent, loading: saving) { Task { await save() } }
                }
                .padding(20)
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("\(target.exerciseName) · S\(target.week)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Annulla") { dismiss() }.tint(Palette.textMid)
            } }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, _ kb: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(Typo.mono(9, .semibold)).tracking(1.5).foregroundStyle(Palette.textMid)
            TextField("—", text: text)
                .keyboardType(kb)
                .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(accent)
                .padding(.horizontal, 10).padding(.vertical, 10).voltPanel(radius: 10)
        }
        .frame(maxWidth: .infinity)
    }

    // Only push the metrics the coach actually changed.
    private func save() async {
        saving = true; defer { saving = false }
        if serie != target.serie { await onCommit("set_count", serie) }
        if reps != target.reps { await onCommit("rep_range", reps) }
        if carico != target.carico { await onCommit("load_value", carico) }
        if recupero != target.recupero { await onCommit("recovery_seconds", recupero) }
        if intensita != target.intensita { await onCommit(target.rpeRirMetric, intensita) }
        if tut != target.tut { await onCommit("tempo", tut) }
        dismiss()
    }
}
