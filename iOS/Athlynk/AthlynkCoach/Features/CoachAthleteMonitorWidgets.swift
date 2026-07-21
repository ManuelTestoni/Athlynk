//
//  CoachAthleteMonitorWidgets.swift
//  The "per atleta" dashboard widgets — parità con il web (athlete_body /
//  athlete_training / athlete_nutrition). Each carries its own athlete picker
//  over the coach's active athletes; the initial athlete comes from the
//  widget config (set when the coach pins an athlete on any surface). Charts
//  are native Swift Charts, fed by the existing coach client endpoints.
//

import SwiftUI
import Charts

// MARK: - Shared athlete picker

/// A compact menu that lets the coach switch the monitored athlete. Loads the
/// active-athlete list lazily and reports the chosen id back up.
private struct AthletePickerBar: View {
    let clients: [CoachClientRow]
    @Binding var selected: Int?

    private var currentName: String {
        clients.first { $0.id == selected }?.displayName ?? "Scegli atleta"
    }

    var body: some View {
        Menu {
            ForEach(clients) { c in
                Button(c.displayName) { selected = c.id }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textMid)
                Text(currentName)
                    .font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, 10).padding(.vertical, 7).voltPanel(radius: 10)
        }
    }
}

private enum AthleteMonitorLoader {
    /// Active athletes for every monitor widget's picker.
    static func activeClients() async -> [CoachClientRow] {
        guard let resp = try? await APIClient.shared.coachClients(limit: 200) else { return [] }
        // Keep only currently-active relationships when the flag is present.
        let active = resp.clients.filter { ($0.status ?? "ACTIVE").uppercased() == "ACTIVE" }
        return active.isEmpty ? resp.clients : active
    }
}

// MARK: - Composizione atleta (peso / circonferenze / pliche)

struct CoachAthleteBodyWidget: View {
    let config: DashboardWidgetConfigDTO?
    let size: String

    @State private var clients: [CoachClientRow] = []
    @State private var selected: Int?
    @State private var entries: [CoachProgressEntry] = []
    @State private var loading = true

    private struct WeightPoint: Identifiable { let id = UUID(); let label: String; let value: Double }

    private var weightPoints: [WeightPoint] {
        // entries arrive newest-first; take the latest 12 and plot oldest→newest.
        let recent = entries.prefix(12).reversed()
        return recent.compactMap { e -> WeightPoint? in
            guard let w = e.weightKg else { return nil }
            return WeightPoint(label: String((e.submittedAt ?? "").prefix(10).suffix(5)), value: w)
        }
    }

    private var latest: CoachProgressEntry? { entries.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CoachSectionTitle(eyebrow: "In evidenza", title: "Composizione atleta", accent: Palette.cyan)
                Spacer()
                AthletePickerBar(clients: clients, selected: $selected)
            }
            if loading {
                SwiftUI.ProgressView().tint(Palette.cyan).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if weightPoints.isEmpty {
                emptyState("scalemass", "Nessuna rilevazione di peso per questo atleta.")
            } else {
                Text("ANDAMENTO PESO").font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Chart(weightPoints) { p in
                    LineMark(x: .value("Data", p.label), y: .value("kg", p.value))
                        .foregroundStyle(Palette.cyan).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Data", p.label), y: .value("kg", p.value))
                        .foregroundStyle(Palette.cyan)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 130)

                if size == "L", let e = latest {
                    HStack(alignment: .top, spacing: 16) {
                        measureColumn("Circonferenze (cm)", e.measurements)
                        measureColumn("Pliche (mm)", e.skinfolds)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
        .task { await loadClients() }
        .task(id: selected) { await loadData() }
    }

    private func measureColumn(_ title: String, _ dict: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(Typo.mono(8, .semibold)).tracking(1).foregroundStyle(Palette.textLow)
            if dict.isEmpty {
                Text("—").font(Typo.body(12)).foregroundStyle(Palette.textLow)
            } else {
                ForEach(dict.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    HStack {
                        Text(k).font(Typo.body(11)).foregroundStyle(Palette.textMid)
                        Spacer()
                        Text(v).font(Typo.body(11, .semibold)).foregroundStyle(Palette.textHi)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadClients() async {
        clients = await AthleteMonitorLoader.activeClients()
        if selected == nil { selected = config?.clientId ?? clients.first?.id }
    }

    private func loadData() async {
        guard let id = selected else { loading = false; return }
        loading = true; defer { loading = false }
        entries = (try? await APIClient.shared.coachClientProgress(clientId: id)) ?? []
    }
}

// MARK: - Allenamento atleta (carico per esercizio)

struct CoachAthleteTrainingWidget: View {
    let config: DashboardWidgetConfigDTO?
    let size: String

    @State private var clients: [CoachClientRow] = []
    @State private var selected: Int?
    @State private var exercises: [(id: Int, name: String)] = []
    @State private var exerciseId: Int?
    @State private var trend: ExerciseTrendDTO?
    @State private var loading = true

    private struct LoadPoint: Identifiable { let id = UUID(); let label: String; let value: Double }

    private var points: [LoadPoint] {
        (trend?.sessions ?? []).compactMap { s in
            guard let v = s.topSet ?? s.weightedAvgLoad else { return nil }
            return LoadPoint(label: String((s.date ?? "").suffix(5)), value: v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CoachSectionTitle(eyebrow: "In evidenza", title: "Allenamento atleta", accent: Palette.lime)
                Spacer()
                AthletePickerBar(clients: clients, selected: $selected)
            }
            if !exercises.isEmpty {
                Menu {
                    ForEach(exercises, id: \.id) { ex in
                        Button(ex.name) { exerciseId = ex.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(exercises.first { $0.id == exerciseId }?.name ?? "Esercizio")
                            .font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.textLow)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7).voltPanel(radius: 10)
                }
            }
            if loading {
                SwiftUI.ProgressView().tint(Palette.lime).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if points.count < 2 {
                emptyState("dumbbell", "Nessun carico registrato per questo esercizio.")
            } else {
                Text("CARICO (TOP SET)").font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Chart(points) { p in
                    LineMark(x: .value("Data", p.label), y: .value("kg", p.value))
                        .foregroundStyle(Palette.lime).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Data", p.label), y: .value("kg", p.value))
                        .foregroundStyle(Palette.lime)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 130)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
        .task { await loadClients() }
        .task(id: selected) { await loadExercises() }
        .task(id: exerciseId) { await loadTrend() }
    }

    private func loadClients() async {
        clients = await AthleteMonitorLoader.activeClients()
        if selected == nil { selected = config?.clientId ?? clients.first?.id }
    }

    private func loadExercises() async {
        guard let id = selected else { loading = false; return }
        let workout = try? await APIClient.shared.coachClientWorkout(clientId: id)
        let flat = (workout?.days ?? []).flatMap { $0.exercises }
        var seen = Set<Int>(); var out: [(Int, String)] = []
        for ex in flat where !seen.contains(ex.id) { seen.insert(ex.id); out.append((ex.id, ex.name)) }
        exercises = out.map { (id: $0.0, name: $0.1) }
        exerciseId = exercises.first?.id
        if exercises.isEmpty { trend = nil; loading = false }
    }

    private func loadTrend() async {
        guard let cid = selected, let eid = exerciseId else { loading = false; return }
        loading = true; defer { loading = false }
        trend = try? await APIClient.shared.coachExerciseTrend(clientId: cid, workoutExerciseId: eid)
    }
}

// MARK: - Nutrizione atleta (resoconto macro)

struct CoachAthleteNutritionWidget: View {
    let config: DashboardWidgetConfigDTO?
    let size: String

    @State private var clients: [CoachClientRow] = []
    @State private var selected: Int?
    @State private var days: [MacroHistoryDayDTO] = []
    @State private var loading = true

    private struct KcalBar: Identifiable { let id = UUID(); let label: String; let kcal: Double }

    private var bars: [KcalBar] {
        days.suffix(8).map { KcalBar(label: $0.dowShort, kcal: $0.consumed.kcal) }
    }
    private var target: MacroMacrosDTO? { days.last?.target }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CoachSectionTitle(eyebrow: "In evidenza", title: "Nutrizione atleta", accent: Palette.amber)
                Spacer()
                AthletePickerBar(clients: clients, selected: $selected)
            }
            if loading {
                SwiftUI.ProgressView().tint(Palette.amber).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if bars.isEmpty {
                emptyState("fork.knife", "Nessun pasto registrato dall'atleta negli ultimi giorni.")
            } else {
                if let t = target {
                    HStack(spacing: 14) {
                        macroTile("kcal", t.kcal)
                        macroTile("Prot", t.protein)
                        macroTile("Carb", t.carb)
                        macroTile("Gras", t.fat)
                    }
                }
                Text("KCAL REGISTRATE · ULTIMI GIORNI").font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Chart(bars) { b in
                    BarMark(x: .value("Giorno", b.label), y: .value("kcal", b.kcal))
                        .foregroundStyle(Palette.amber).cornerRadius(4)
                    if let t = target {
                        RuleMark(y: .value("Target", t.kcal))
                            .foregroundStyle(Palette.textLow)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 130)

                if size == "L" {
                    ForEach(days.suffix(5).reversed()) { d in
                        HStack {
                            Text(d.dowShort).font(Typo.body(11)).foregroundStyle(Palette.textMid)
                            Spacer()
                            Text("\(Int(d.consumed.kcal)) kcal · \(Int(d.consumed.protein))g prot")
                                .font(Typo.body(11, .semibold)).foregroundStyle(Palette.textHi)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
        .task { await loadClients() }
        .task(id: selected) { await loadData() }
    }

    private func macroTile(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(value > 0 ? "\(Int(value))" : "—").font(Typo.display(18)).foregroundStyle(Palette.textHi)
            Text(label).font(Typo.mono(8, .semibold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadClients() async {
        clients = await AthleteMonitorLoader.activeClients()
        if selected == nil { selected = config?.clientId ?? clients.first?.id }
    }

    private func loadData() async {
        guard let id = selected else { loading = false; return }
        loading = true; defer { loading = false }
        days = (try? await APIClient.shared.coachClientMacroHistory(clientId: id))?.days ?? []
    }
}

// MARK: - Shared empty state

@ViewBuilder
private func emptyState(_ symbol: String, _ text: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.textLow)
        Text(text).font(Typo.body(12)).foregroundStyle(Palette.textMid).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 20)
}
