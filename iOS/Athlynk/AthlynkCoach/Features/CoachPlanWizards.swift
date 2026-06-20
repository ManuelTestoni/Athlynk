//
//  CoachPlanWizards.swift
//  Full mobile twins of the web creation wizards.
//
//  Workout: the same phases as /allenamenti/wizard/ — 1) details + kind
//  ("Scheda settimanale" | "Programmazione"), 2) days/exercises, 3) progression
//  (PROGRAM only, the common rule families), 4) finalize (template / assign).
//  Writes go through the web save/finalize endpoints, so web and mobile share
//  one code path.
//
//  Nutrition: the same phases as /nutrizione/piani/crea/ — 1) mode
//  ("Alimenti" | "Macronutrienti") + kind ("Giornaliero" | "Settimanale"),
//  2) meals/foods or macro targets (per-day for weekly), 3) save + assign.
//

import SwiftUI

// MARK: - Shared bits

let wzWeekdays = ["LUN", "MAR", "MER", "GIO", "VEN", "SAB", "DOM"]
let wzWeekdayNames: [String: String] = [
    "LUN": "Lunedì", "MAR": "Martedì", "MER": "Mercoledì", "GIO": "Giovedì",
    "VEN": "Venerdì", "SAB": "Sabato", "DOM": "Domenica",
]

private struct WZStepBar: View {
    let steps: [String]
    let current: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(i <= current ? accent : Palette.void2)
                        .frame(height: 4)
                    Text(label.uppercased())
                        .font(Typo.mono(8, .semibold)).tracking(1)
                        .foregroundStyle(i == current ? accent : Palette.textLow)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WZField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var accent: Color = Palette.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textLow))
                .font(Typo.body(16)).foregroundStyle(Palette.textHi).tint(accent)
                .keyboardType(keyboard)
                .padding(.horizontal, 14).padding(.vertical, 13).voltPanel(radius: 12)
        }
    }
}

/// Big selectable card used by the kind/mode choice steps.
private struct WZChoiceCard: View {
    let icon: String
    let title: String
    let caption: String
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(selected ? accent : Palette.textMid)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typo.body(16, .semibold))
                        .foregroundStyle(Palette.textHi)
                    Text(caption).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? accent : Palette.textLow)
            }
            .padding(16)
            .voltPanel(selected ? accent.opacity(0.6) : Palette.line)
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
func wzBackLink(_ action: @escaping () -> Void) -> some View {
    Button {
        Haptics.tap(); action()
    } label: {
        HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Indietro") }
            .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textMid)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .buttonStyle(.plain)
}

private struct WZNavButtons: View {
    let canBack: Bool
    let nextTitle: String
    let nextEnabled: Bool
    let accent: Color
    var loading = false
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if canBack {
                Button {
                    Haptics.tap(); onBack()
                } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Indietro") }
                        .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textMid)
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .voltPanel(radius: 14)
                }
                .buttonStyle(.plain)
            }
            NeonButton(title: nextTitle, icon: "chevron.right", color: accent, loading: loading) {
                onNext()
            }
            .disabled(!nextEnabled)
            .opacity(nextEnabled ? 1 : 0.4)
        }
    }
}

// MARK: - Workout progression drafts

enum WBProgressionType: String, CaseIterable, Identifiable {
    case loadLinear, volSets, volReps, intRpe, intRir, denRest
    var id: String { rawValue }

    var label: String {
        switch self {
        case .loadLinear: return "Carico lineare (+kg)"
        case .volSets:    return "Progressione serie"
        case .volReps:    return "Progressione reps"
        case .intRpe:     return "RPE progressivo"
        case .intRir:     return "RIR progressivo"
        case .denRest:    return "Riduzione recupero"
        }
    }

    var family: String {
        switch self {
        case .loadLinear: return "LOAD"
        case .volSets, .volReps: return "VOLUME"
        case .intRpe, .intRir: return "INTENSITY"
        case .denRest: return "DENSITY"
        }
    }

    var subtype: String {
        switch self {
        case .loadLinear: return "LOAD_LINEAR"
        case .volSets:    return "VOL_SETS"
        case .volReps:    return "VOL_REPS"
        case .intRpe:     return "INT_RPE"
        case .intRir:     return "INT_RIR"
        case .denRest:    return "DEN_REST"
        }
    }

    var metric: String {
        switch self {
        case .loadLinear: return "load"
        case .volSets:    return "sets"
        case .volReps:    return "reps"
        case .intRpe:     return "rpe"
        case .intRir:     return "rir"
        case .denRest:    return "rest"
        }
    }

    static func from(subtype: String) -> WBProgressionType? {
        allCases.first { $0.subtype == subtype }
    }
}

struct WBRuleDraft: Identifiable {
    let id = UUID()
    var serverId: Int? = nil
    var exerciseRef: UUID
    var type: WBProgressionType = .loadLinear
    var everyNWeeks = 1
    // Type-specific parameters (only the ones for `type` are sent).
    var loadDelta = 2.5
    var setsStep = 1
    var repMin = 8
    var repMax = 12
    var repStep = 1
    var rpeStart = 7.0
    var rpeDelta = 0.5
    var rirStart = 3
    var rirDelta = -1
    var restDelta = -15
    var restMin = 60

    var parameters: [String: Any] {
        switch type {
        case .loadLinear: return ["delta": loadDelta, "every_n_weeks": everyNWeeks]
        case .volSets:    return ["step": setsStep, "every_n_weeks": everyNWeeks]
        case .volReps:    return ["min": repMin, "max": repMax, "step": repStep,
                                  "every_n_weeks": everyNWeeks]
        case .intRpe:     return ["start": rpeStart, "delta": rpeDelta,
                                  "every_n_weeks": everyNWeeks]
        case .intRir:     return ["start": rirStart, "delta": rirDelta,
                                  "every_n_weeks": everyNWeeks]
        case .denRest:    return ["delta_seconds": restDelta, "min_seconds": restMin,
                                  "every_n_weeks": everyNWeeks]
        }
    }

    var summary: String {
        switch type {
        case .loadLinear: return String(format: "+%.1f kg ogni %d sett.", loadDelta, everyNWeeks)
        case .volSets:    return "+\(setsStep) serie ogni \(everyNWeeks) sett."
        case .volReps:    return "\(repMin)→\(repMax) reps, +\(repStep)/\(everyNWeeks) sett."
        case .intRpe:     return String(format: "RPE da %.1f, %+.1f/%d sett.", rpeStart, rpeDelta, everyNWeeks)
        case .intRir:     return "RIR da \(rirStart), \(rirDelta > 0 ? "+" : "")\(rirDelta)/\(everyNWeeks) sett."
        case .denRest:    return "\(restDelta)s recupero/\(everyNWeeks) sett. (min \(restMin)s)"
        }
    }

    static func from(dict: [String: Any], exerciseRef: UUID) -> WBRuleDraft? {
        guard let subtype = dict["subtype"] as? String,
              let type = WBProgressionType.from(subtype: subtype) else { return nil }
        var d = WBRuleDraft(exerciseRef: exerciseRef, type: type)
        d.serverId = dict["id"] as? Int
        let p = dict["parameters"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double? {
            (p[k] as? Double) ?? (p[k] as? Int).map(Double.init) ?? (p[k] as? String).flatMap(Double.init)
        }
        d.everyNWeeks = Int(num("every_n_weeks") ?? 1)
        switch type {
        case .loadLinear: d.loadDelta = num("delta") ?? 2.5
        case .volSets:    d.setsStep = Int(num("step") ?? 1)
        case .volReps:
            d.repMin = Int(num("min") ?? 8); d.repMax = Int(num("max") ?? 12)
            d.repStep = Int(num("step") ?? 1)
        case .intRpe:     d.rpeStart = num("start") ?? 7; d.rpeDelta = num("delta") ?? 0.5
        case .intRir:     d.rirStart = Int(num("start") ?? 3); d.rirDelta = Int(num("delta") ?? -1)
        case .denRest:    d.restDelta = Int(num("delta_seconds") ?? -15); d.restMin = Int(num("min_seconds") ?? 60)
        }
        return d
    }
}

// MARK: - Workout wizard

struct CoachWorkoutWizardView: View {
    var planId: Int? = nil               // non-nil = edit existing plan
    var onSaved: () -> Void = {}
    var embedded = false                 // true when hosted by CoachPlanCreateView

    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var step = 0
    @State private var kind = "WEEKLY"   // WEEKLY | PROGRAM
    @State private var title = ""
    @State private var goal = ""
    @State private var level = ""
    @State private var frequency = 3
    @State private var durationWeeks = 8
    @State private var days: [WBDayDraft] = []
    @State private var rules: [WBRuleDraft] = []
    // Web-authored progression data carried opaquely so a mobile save keeps it.
    @State private var opaqueWeeks: [[String: Any]] = []
    @State private var opaqueRules: [[String: Any]] = []
    @State private var opaqueOverrides: [[String: Any]] = []

    @State private var savedPlanId: Int?
    @State private var clients: [CoachAssignableClient] = []
    @State private var selectedClients: Set<Int> = []
    @State private var assignWeeks = 8
    @State private var overwrite = true

    @State private var busy = false
    @State private var loadingPlan = false

    private let accent = Palette.cyan

    private var steps: [String] {
        kind == "PROGRAM"
            ? ["Dettagli", "Struttura", "Progressione", "Finalizza"]
            : ["Dettagli", "Struttura", "Finalizza"]
    }
    private var finalizeIndex: Int { steps.count - 1 }
    private var progressionIndex: Int? { kind == "PROGRAM" ? 2 : nil }

    var body: some View {
        Group {
            if embedded { content } else {
                NavigationStack {
                    content
                        .navigationTitle(planId == nil ? "Nuova scheda" : "Modifica scheda")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarLeading) {
                            Button("Chiudi") { dismiss() }.tint(Palette.textMid)
                        } }
                }
            }
        }
        .statusOverlay(flash)
        .task { await loadIfEditing() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                WZStepBar(steps: steps, current: step, accent: accent)

                if loadingPlan {
                    SwiftUI.ProgressView().tint(accent).padding(.vertical, 60)
                } else {
                    switch step {
                    case 0: detailsStep
                    case 1: structureStep
                    case let s where s == progressionIndex: progressionStep
                    default: finalizeStep
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.void0.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 1 — details + kind

    private var detailsStep: some View {
        VStack(spacing: 14) {
            WZChoiceCard(icon: "calendar", title: "Scheda settimanale",
                         caption: "Struttura fissa che si ripete ogni settimana.",
                         selected: kind == "WEEKLY", accent: accent) { kind = "WEEKLY" }
            WZChoiceCard(icon: "chart.line.uptrend.xyaxis", title: "Programmazione",
                         caption: "Piano multi-settimana con progressioni su carichi, volume e intensità.",
                         selected: kind == "PROGRAM", accent: accent) { kind = "PROGRAM" }

            WZField(label: "Titolo", text: $title, placeholder: "Es. Upper/Lower 4x", accent: accent)
            WZField(label: "Obiettivo (opz.)", text: $goal, placeholder: "Es. Ipertrofia", accent: accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("LIVELLO (OPZ.)").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                HStack(spacing: 8) {
                    ForEach(["Principiante", "Intermedio", "Avanzato"], id: \.self) { l in
                        Button {
                            Haptics.tap()
                            level = (level == l) ? "" : l
                        } label: {
                            Text(l)
                                .font(Typo.body(13, .semibold))
                                .foregroundStyle(level == l ? Palette.void0 : Palette.textMid)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(Capsule().fill(level == l ? accent : Palette.void2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                WZIntStepper(label: "FREQUENZA / SETT.", value: $frequency, range: 1...6)
                if kind == "PROGRAM" {
                    WZIntStepper(label: "DURATA (SETT.)", value: $durationWeeks, range: 1...52)
                }
            }

            WZNavButtons(canBack: false, nextTitle: "Continua",
                         nextEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty,
                         accent: accent, onBack: {}) { advance() }
        }
    }

    // MARK: Step 2 — days + exercises

    private var structureStep: some View {
        VStack(spacing: 14) {
            WorkoutBuilderSection(days: $days, accent: accent)
            WZNavButtons(canBack: true, nextTitle: "Continua",
                         nextEnabled: days.contains { !$0.exercises.isEmpty },
                         accent: accent, onBack: { back() }) { advance() }
        }
    }

    // MARK: Step 3 — progression (PROGRAM only)

    private var allExercises: [(day: WBDayDraft, exercise: WBExerciseDraft)] {
        days.flatMap { d in d.exercises.map { (d, $0) } }
    }

    private var progressionStep: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
                Text("Progressione su \(durationWeeks) settimane")
                    .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text("Aggiungi una regola di progressione agli esercizi: il motore calcola i valori di ogni settimana.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(18).voltPanel()

            ForEach(allExercises, id: \.exercise.id) { pair in
                exerciseRulesCard(pair.day, pair.exercise)
            }

            if !opaqueRules.isEmpty {
                Text("\(opaqueRules.count) progressioni avanzate create dal web verranno mantenute.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            WZNavButtons(canBack: true, nextTitle: "Continua", nextEnabled: true,
                         accent: accent, onBack: { back() }) { advance() }
        }
    }

    private func exerciseRulesCard(_ day: WBDayDraft, _ ex: WBExerciseDraft) -> some View {
        let exRules = rules.filter { $0.exerciseRef == ex.id }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    Text(day.name.uppercased())
                        .font(Typo.mono(9, .semibold)).tracking(1.5).foregroundStyle(Palette.textLow)
                }
                Spacer()
                Menu {
                    ForEach(WBProgressionType.allCases) { t in
                        Button(t.label) {
                            Haptics.soft()
                            withAnimation(.snappy) {
                                rules.append(WBRuleDraft(exerciseRef: ex.id, type: t))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                        Text("Regola")
                    }
                    .font(Typo.body(13, .semibold)).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            ForEach($rules) { $rule in
                if rule.exerciseRef == ex.id {
                    Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1).padding(.leading, 16)
                    WZRuleRow(rule: $rule, accent: accent) {
                        Haptics.warning()
                        withAnimation(.snappy) { rules.removeAll { $0.id == rule.id } }
                    }
                }
            }

            if exRules.isEmpty {
                Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1).padding(.leading, 16)
                Text("Nessuna progressione: valori costanti ogni settimana.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .voltPanel()
    }

    // MARK: Step 4 — finalize

    private var finalizeStep: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RIEPILOGO").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Text(title).font(Typo.display(22)).foregroundStyle(Palette.textHi)
                HStack(spacing: 8) {
                    chip(kind == "PROGRAM" ? "Programmazione" : "Scheda settimanale")
                    chip("\(days.count) giorni")
                    chip("\(days.reduce(0) { $0 + $1.exercises.count }) esercizi")
                    if kind == "PROGRAM" { chip("\(durationWeeks) sett.") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()

            CoachSectionTitle(eyebrow: "Assegna", title: "Atleti", accent: accent)
            if clients.isEmpty {
                Text("Nessun atleta attivo da assegnare. Puoi salvare la scheda come bozza o template.")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
            } else {
                ForEach(clients) { c in clientRow(c) }
                if !selectedClients.isEmpty {
                    WZIntStepper(label: "DURATA ASSEGNAZIONE (SETT.)", value: $assignWeeks, range: 1...52)
                    Toggle(isOn: $overwrite) {
                        Text("Chiudi le schede attive degli atleti selezionati")
                            .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    }
                    .tint(accent)
                    .padding(.horizontal, 16).padding(.vertical, 12).voltPanel()
                }
            }

            if !selectedClients.isEmpty {
                NeonButton(title: "Assegna a \(selectedClients.count) atlet\(selectedClients.count == 1 ? "a" : "i")",
                           icon: "paperplane.fill", color: accent, loading: busy) {
                    Task { await saveAndFinalize(action: "assign") }
                }
            }
            NeonButton(title: "Salva come template", icon: "square.on.square",
                       color: Palette.bronze, loading: busy) {
                Task { await saveAndFinalize(action: "template") }
            }
            Button {
                Task { await saveAndFinalize(action: nil) }
            } label: {
                Text("Salva come bozza")
                    .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textMid)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .voltPanel(radius: 14)
            }
            .buttonStyle(.plain)

            wzBackLink { back() }
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(Typo.mono(10, .semibold)).tracking(1).foregroundStyle(accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
    }

    private func clientRow(_ c: CoachAssignableClient) -> some View {
        let isSel = selectedClients.contains(c.id)
        return Button {
            Haptics.tap()
            withAnimation(.snappy) {
                if isSel { selectedClients.remove(c.id) } else { selectedClients.insert(c.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isSel ? accent : Palette.textLow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    if let a = c.activeAssignment {
                        Text("Scheda attiva: \(a.planTitle)")
                            .font(Typo.body(12)).foregroundStyle(Palette.amber)
                    }
                }
                Spacer()
            }
            .padding(14)
            .voltPanel(isSel ? accent.opacity(0.5) : Palette.line)
        }
        .buttonStyle(.plain)
    }

    // MARK: Navigation + actions

    private func advance() {
        Haptics.tap()
        withAnimation(.snappy) { step = min(step + 1, finalizeIndex) }
        if step == finalizeIndex {
            assignWeeks = kind == "PROGRAM" ? durationWeeks : assignWeeks
            Task {
                clients = (try? await APIClient.shared.coachAssignableClients(excludePlanId: savedPlanId ?? planId)) ?? []
            }
        }
    }

    private func back() {
        withAnimation(.snappy) { step = max(step - 1, 0) }
    }

    private func loadIfEditing() async {
        guard let planId, savedPlanId == nil else { return }
        loadingPlan = true; defer { loadingPlan = false }
        do {
            let plan = try await APIClient.shared.coachWorkoutBuilder(planId: planId)
            apply(builder: plan)
            savedPlanId = planId
            step = 1
        } catch {
            flash.failure("Impossibile caricare la scheda")
        }
    }

    private func apply(builder plan: [String: Any]) {
        title = plan["title"] as? String ?? ""
        goal = plan["goal"] as? String ?? ""
        level = plan["level"] as? String ?? ""
        kind = (plan["plan_kind"] as? String ?? "WEEKLY").uppercased() == "PROGRAM" ? "PROGRAM" : "WEEKLY"
        frequency = plan["frequency_per_week"] as? Int ?? 3
        durationWeeks = plan["duration_weeks"] as? Int ?? 8

        var pkToRef: [Int: UUID] = [:]
        days = (plan["days"] as? [[String: Any]] ?? []).map { d in
            var day = WBDayDraft(pk: d["pk"] as? Int, name: d["name"] as? String ?? "Giorno")
            day.exercises = (d["exercises"] as? [[String: Any]] ?? []).compactMap { e in
                guard let exId = e["exercise_id"] as? Int else { return nil }
                var ex = WBExerciseDraft(pk: e["pk"] as? Int, exerciseId: exId,
                                         name: e["exercise_name"] as? String ?? "Esercizio",
                                         muscle: e["target_muscle_group"] as? String ?? "")
                ex.sets = e["sets"] as? Int ?? 3
                let reps = "\(e["reps"] ?? "10")"
                if let n = Int(reps) { ex.reps = n; ex.repRange = "" } else { ex.repRange = reps }
                ex.recoverySeconds = e["recovery_seconds"] as? Int ?? 90
                ex.loadValue = (e["load_value"] as? Double) ?? (e["load_value"] as? Int).map(Double.init)
                ex.loadUnit = e["load_unit"] as? String ?? "KG"
                if ex.loadUnit.isEmpty { ex.loadUnit = "KG" }
                ex.rir = e["rir"] as? Int
                ex.rpe = e["rpe"] as? Int
                ex.tempo = e["tempo"] as? String ?? ""
                ex.notes = (e["coach_notes"] as? String) ?? (e["notes"] as? String) ?? ""
                if let pk = ex.pk { pkToRef[pk] = ex.id }
                return ex
            }
            return day
        }

        let prog = plan["progression"] as? [String: Any] ?? [:]
        opaqueWeeks = prog["weeks"] as? [[String: Any]] ?? []
        opaqueOverrides = prog["overrides"] as? [[String: Any]] ?? []
        rules = []
        opaqueRules = []
        for r in prog["rules"] as? [[String: Any]] ?? [] {
            if let exPk = r["workout_exercise_id"] as? Int, let ref = pkToRef[exPk],
               let draft = WBRuleDraft.from(dict: r, exerciseRef: ref) {
                rules.append(draft)
            } else {
                opaqueRules.append(r)
            }
        }
    }

    private func buildPayload(lastStep: Int) -> [String: Any] {
        var payload: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "goal": goal, "level": level, "plan_kind": kind,
            "frequency_per_week": frequency,
            "duration_weeks": kind == "PROGRAM" ? durationWeeks : 1,
            "last_step": lastStep,
        ]
        payload["days"] = days.map { day -> [String: Any] in
            var d: [String: Any] = ["name": day.name, "local_id": "loc-\(day.id.uuidString)"]
            if let pk = day.pk { d["pk"] = pk }
            d["exercises"] = day.exercises.map { ex -> [String: Any] in
                var e: [String: Any] = [
                    "local_id": ex.id.uuidString,
                    "exercise_id": ex.exerciseId,
                    "sets": ex.sets,
                    "reps": ex.repRange.isEmpty ? "\(ex.reps)" : ex.repRange,
                    "recovery_seconds": ex.recoverySeconds,
                ]
                if let pk = ex.pk { e["pk"] = pk }
                if let load = ex.loadValue { e["load_value"] = load; e["load_unit"] = ex.loadUnit }
                if let rir = ex.rir { e["rir"] = rir }
                if let rpe = ex.rpe { e["rpe"] = rpe }
                if !ex.tempo.isEmpty { e["tempo"] = ex.tempo }
                if !ex.notes.isEmpty { e["coach_notes"] = ex.notes }
                return e
            }
            return d
        }
        // Progression: full diff server-side, so always include the opaque
        // web-authored entries alongside the mobile-edited rules.
        var ruleDicts = opaqueRules
        for (i, rule) in rules.enumerated() {
            var r: [String: Any] = [
                "family": rule.type.family,
                "subtype": rule.type.subtype,
                "target_metric": rule.type.metric,
                "application_mode": "FIXED_INCREMENT",
                "start_week": 1,
                "parameters": rule.parameters,
                "stackable": true,
                "order_index": i,
            ]
            if let sid = rule.serverId { r["id"] = sid }
            if let exDraft = days.flatMap(\.exercises).first(where: { $0.id == rule.exerciseRef }) {
                if let pk = exDraft.pk { r["workout_exercise_id"] = pk }
                else { r["workout_exercise_local_id"] = exDraft.id.uuidString }
            }
            ruleDicts.append(r)
        }
        payload["progression"] = [
            "weeks": opaqueWeeks,
            "rules": ruleDicts,
            "overrides": opaqueOverrides,
        ]
        return payload
    }

    private func saveAndFinalize(action: String?) async {
        busy = true; defer { busy = false }
        do {
            let saved = try await APIClient.shared.coachSaveWorkoutPlan(
                planId: savedPlanId ?? planId,
                payload: buildPayload(lastStep: 4))
            guard let pid = saved["id"] as? Int else {
                flash.failure("Salvataggio non riuscito"); return
            }
            savedPlanId = pid

            if let action {
                var body: [String: Any] = ["action": action]
                if action == "assign" {
                    body["client_ids"] = Array(selectedClients)
                    body["weeks"] = assignWeeks
                    body["overwrite"] = overwrite
                }
                try await APIClient.shared.coachFinalizeWorkoutPlan(planId: pid, payload: body)
            }
            Analytics.shared.capture(.planUpdated, ["kind": "workout"])
            flash.success(action == "assign" ? "Scheda assegnata"
                          : action == "template" ? "Template salvato" : "Bozza salvata")
            try? await Task.sleep(for: .seconds(1.1))
            onSaved()
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}

/// Labeled int stepper used by the wizard detail steps.
private struct WZIntStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            HStack(spacing: 0) {
                Button { adjust(-1) } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity).frame(height: 36)
                }
                Text("\(value)")
                    .font(Typo.mono(16, .bold)).foregroundStyle(Palette.textHi)
                    .frame(minWidth: 46)
                    .contentTransition(.numericText())
                Button { adjust(1) } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity).frame(height: 36)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.textMid)
            .buttonStyle(.plain)
            .voltPanel(radius: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func adjust(_ d: Int) {
        let nv = min(max(value + d, range.lowerBound), range.upperBound)
        guard nv != value else { return }
        Haptics.tap()
        withAnimation(.snappy) { value = nv }
    }
}

/// One progression rule row with inline parameter editors.
private struct WZRuleRow: View {
    @Binding var rule: WBRuleDraft
    let accent: Color
    let onDelete: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.type.label)
                            .font(Typo.body(13, .semibold)).foregroundStyle(accent)
                        Text(rule.summary)
                            .font(Typo.mono(10)).foregroundStyle(Palette.textMid)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textLow)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 10) {
                    switch rule.type {
                    case .loadLinear:
                        WZDoubleStepper(label: "DELTA KG", value: $rule.loadDelta, step: 0.5, range: 0.5...20)
                    case .volSets:
                        WZRuleIntStepper(label: "SERIE +", value: $rule.setsStep, range: 1...4)
                    case .volReps:
                        HStack(spacing: 10) {
                            WZRuleIntStepper(label: "DA", value: $rule.repMin, range: 1...30)
                            WZRuleIntStepper(label: "A", value: $rule.repMax, range: 1...50)
                            WZRuleIntStepper(label: "STEP", value: $rule.repStep, range: 1...5)
                        }
                    case .intRpe:
                        HStack(spacing: 10) {
                            WZDoubleStepper(label: "RPE INIZIALE", value: $rule.rpeStart, step: 0.5, range: 5...10)
                            WZDoubleStepper(label: "DELTA", value: $rule.rpeDelta, step: 0.5, range: -2...2)
                        }
                    case .intRir:
                        HStack(spacing: 10) {
                            WZRuleIntStepper(label: "RIR INIZIALE", value: $rule.rirStart, range: 0...6)
                            WZRuleIntStepper(label: "DELTA", value: $rule.rirDelta, range: -3...3)
                        }
                    case .denRest:
                        HStack(spacing: 10) {
                            WZRuleIntStepper(label: "DELTA SEC", value: $rule.restDelta, range: -60...0, step: 5)
                            WZRuleIntStepper(label: "MIN SEC", value: $rule.restMin, range: 15...180, step: 15)
                        }
                    }
                    HStack {
                        WZRuleIntStepper(label: "OGNI N SETT.", value: $rule.everyNWeeks, range: 1...8)
                        Spacer()
                        Button { onDelete() } label: {
                            HStack(spacing: 5) { Image(systemName: "trash"); Text("Rimuovi") }
                                .font(Typo.body(13, .semibold)).foregroundStyle(Palette.crimson)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct WZRuleIntStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.mono(8, .semibold)).tracking(1.5).foregroundStyle(Palette.textMid)
            HStack(spacing: 0) {
                Button { adjust(-step) } label: { Image(systemName: "minus").frame(width: 26, height: 28) }
                Text("\(value)")
                    .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                    .frame(minWidth: 34)
                    .contentTransition(.numericText())
                Button { adjust(step) } label: { Image(systemName: "plus").frame(width: 26, height: 28) }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.textMid)
            .buttonStyle(.plain)
            .voltPanel(radius: 9)
        }
    }

    private func adjust(_ d: Int) {
        let nv = min(max(value + d, range.lowerBound), range.upperBound)
        guard nv != value else { return }
        Haptics.tap()
        withAnimation(.snappy) { value = nv }
    }
}

private struct WZDoubleStepper: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.mono(8, .semibold)).tracking(1.5).foregroundStyle(Palette.textMid)
            HStack(spacing: 0) {
                Button { adjust(-step) } label: { Image(systemName: "minus").frame(width: 26, height: 28) }
                Text(value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value))
                    .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                    .frame(minWidth: 40)
                    .contentTransition(.numericText())
                Button { adjust(step) } label: { Image(systemName: "plus").frame(width: 26, height: 28) }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.textMid)
            .buttonStyle(.plain)
            .voltPanel(radius: 9)
        }
    }

    private func adjust(_ d: Double) {
        let nv = min(max(value + d, range.lowerBound), range.upperBound)
        guard nv != value else { return }
        Haptics.tap()
        withAnimation(.snappy) { value = nv }
    }
}

// MARK: - Nutrition wizard

struct WZDayTargetDraft: Identifiable {
    let day: String              // LUN…DOM
    var kcal = ""
    var protein = ""
    var carb = ""
    var fat = ""
    var id: String { day }

    var isEmpty: Bool { kcal.isEmpty && protein.isEmpty && carb.isEmpty && fat.isEmpty }
}

struct CoachNutritionWizardView: View {
    var planId: Int? = nil               // non-nil = edit existing plan
    var onSaved: () -> Void = {}
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var step = 0
    @State private var mode = "FOOD"     // FOOD | MACRO
    @State private var kind = "DAILY"    // DAILY | WEEKLY
    @State private var title = ""
    @State private var planDescription = ""

    // FOOD content
    @State private var meals: [WBMealDraft] = []
    @State private var selectedDay = "LUN"

    // MACRO content
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carb = ""
    @State private var fat = ""
    @State private var dayTargets: [WZDayTargetDraft] = wzWeekdays.map { WZDayTargetDraft(day: $0) }

    @State private var savedPlanId: Int?
    @State private var clients: [CoachAssignableClient] = []
    @State private var selectedClients: Set<Int> = []

    @State private var busy = false
    @State private var loadingPlan = false
    @State private var fabbisogni: CoachFabbisogniDTO? = nil

    private let accent = Palette.lime
    private let steps = ["Tipo", "Contenuto", "Finalizza"]

    var body: some View {
        Group {
            if embedded { content } else {
                NavigationStack {
                    content
                        .navigationTitle(planId == nil ? "Nuovo piano" : "Modifica piano")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarLeading) {
                            Button("Chiudi") { dismiss() }.tint(Palette.textMid)
                        } }
                }
            }
        }
        .statusOverlay(flash)
        .task { await loadIfEditing() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                WZStepBar(steps: steps, current: step, accent: accent)

                if loadingPlan {
                    SwiftUI.ProgressView().tint(accent).padding(.vertical, 60)
                } else {
                    switch step {
                    case 0: typeStep
                    case 1: contentStep
                    default: finalizeStep
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.void0.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Step 1 — mode + kind

    private var typeStep: some View {
        VStack(spacing: 14) {
            WZField(label: "Titolo", text: $title,
                    placeholder: "Es. Definizione 2200 kcal", accent: accent)

            CoachSectionTitle(eyebrow: "Tipo di piano", title: "Cosa prescrivi?", accent: accent)
            WZChoiceCard(icon: "fork.knife", title: "Alimenti",
                         caption: "Pasti e alimenti dal database: la dieta classica.",
                         selected: mode == "FOOD", accent: accent) { setMode("FOOD") }
            WZChoiceCard(icon: "chart.pie.fill", title: "Macronutrienti",
                         caption: "Solo target di kcal e macro: l'atleta registra ciò che mangia.",
                         selected: mode == "MACRO", accent: accent) { setMode("MACRO") }

            CoachSectionTitle(eyebrow: "Struttura", title: "Su quale arco?", accent: accent)
            WZChoiceCard(icon: "sun.max.fill", title: "Giornaliero",
                         caption: "Un singolo giorno valido tutti i giorni.",
                         selected: kind == "DAILY", accent: accent) { setKind("DAILY") }
            WZChoiceCard(icon: "calendar", title: "Settimanale",
                         caption: "Contenuti diversi per ogni giorno della settimana.",
                         selected: kind == "WEEKLY", accent: accent) { setKind("WEEKLY") }

            if planId != nil {
                Text("Tipo e struttura non sono modificabili dopo la creazione.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            WZNavButtons(canBack: false, nextTitle: "Continua",
                         nextEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty,
                         accent: accent, onBack: {}) {
                Haptics.tap()
                withAnimation(.snappy) { step = 1 }
            }
        }
    }

    private func setMode(_ m: String) { if planId == nil { mode = m } }
    private func setKind(_ k: String) { if planId == nil { kind = k } }

    // MARK: Step 2 — content

    @ViewBuilder
    private var contentStep: some View {
        VStack(spacing: 14) {
            if mode == "FOOD" {
                if kind == "WEEKLY" { weekdayTabs }
                DietBuilderSection(meals: visibleMealsBinding, accent: accent)
            } else if kind == "DAILY" {
                macroTargetsDaily
            } else {
                macroTargetsWeekly
            }

            WZNavButtons(canBack: true, nextTitle: "Continua",
                         nextEnabled: contentValid,
                         accent: accent, onBack: { withAnimation(.snappy) { step = 0 } }) {
                Haptics.tap()
                withAnimation(.snappy) { step = 2 }
                Task { clients = (try? await APIClient.shared.coachAssignableClients()) ?? [] }
            }
        }
    }

    private var contentValid: Bool {
        if mode == "FOOD" { return meals.contains { !$0.items.isEmpty } }
        if kind == "DAILY" { return [kcal, protein, carb, fat].contains { Int($0) != nil } }
        return dayTargets.contains { !$0.isEmpty }
    }

    private var weekdayTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wzWeekdays, id: \.self) { d in
                    let count = meals.filter { $0.dayOfWeek == d }.count
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) { selectedDay = d }
                    } label: {
                        VStack(spacing: 2) {
                            Text(d).font(Typo.mono(12, .bold))
                            if count > 0 {
                                Text("\(count)").font(Typo.mono(9, .semibold))
                                    .foregroundStyle(selectedDay == d ? Palette.void0.opacity(0.7) : Palette.textLow)
                            }
                        }
                        .foregroundStyle(selectedDay == d ? Palette.void0 : Palette.textMid)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selectedDay == d ? accent : Palette.void2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// For WEEKLY plans the meal builder edits only the selected day's meals;
    /// new meals are tagged with that day.
    private var visibleMealsBinding: Binding<[WBMealDraft]> {
        guard kind == "WEEKLY" else { return $meals }
        return Binding(
            get: { meals.filter { $0.dayOfWeek == selectedDay } },
            set: { newValue in
                var tagged = newValue
                for i in tagged.indices where tagged[i].dayOfWeek == nil {
                    tagged[i].dayOfWeek = selectedDay
                }
                meals = meals.filter { $0.dayOfWeek != selectedDay } + tagged
            }
        )
    }

    private var macroTargetsDaily: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
                Text("Target giornalieri")
                    .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text("L'atleta vedrà questi obiettivi e registrerà gli alimenti consumati.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(18).voltPanel()

            HStack(spacing: 10) {
                WZField(label: "Kcal", text: $kcal, placeholder: "2200", keyboard: .numberPad, accent: accent)
                WZField(label: "Proteine (g)", text: $protein, placeholder: "160", keyboard: .numberPad, accent: accent)
            }
            HStack(spacing: 10) {
                WZField(label: "Carboidrati (g)", text: $carb, placeholder: "250", keyboard: .numberPad, accent: accent)
                WZField(label: "Grassi (g)", text: $fat, placeholder: "60", keyboard: .numberPad, accent: accent)
            }
        }
    }

    private var macroTargetsWeekly: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
                Text("Target per giorno")
                    .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text("Compila solo i giorni che vuoi prescrivere: gli altri restano liberi.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(18).voltPanel()

            ForEach($dayTargets) { $dt in
                VStack(alignment: .leading, spacing: 10) {
                    Text(wzWeekdayNames[dt.day] ?? dt.day)
                        .font(Typo.body(15, .semibold))
                        .foregroundStyle(dt.isEmpty ? Palette.textMid : accent)
                    HStack(spacing: 8) {
                        miniField("KCAL", $dt.kcal)
                        miniField("PRO", $dt.protein)
                        miniField("CARB", $dt.carb)
                        miniField("GRASSI", $dt.fat)
                    }
                }
                .padding(14).voltPanel()
            }
        }
    }

    private func miniField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.mono(8, .semibold)).tracking(1.5).foregroundStyle(Palette.textMid)
            TextField("", text: text, prompt: Text("—").foregroundStyle(Palette.textLow))
                .keyboardType(.numberPad)
                .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi).tint(accent)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .voltPanel(radius: 9)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Step 3 — finalize

    private var finalizeStep: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RIEPILOGO").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Text(title).font(Typo.display(22)).foregroundStyle(Palette.textHi)
                HStack(spacing: 8) {
                    chip(mode == "MACRO" ? "Macronutrienti" : "Alimenti")
                    chip(kind == "WEEKLY" ? "Settimanale" : "Giornaliero")
                    if mode == "FOOD" { chip("\(meals.count) pasti") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()

            CoachSectionTitle(eyebrow: "Assegna (opzionale)", title: "Atleti", accent: accent)
            if clients.isEmpty {
                Text("Nessun atleta attivo: il piano resterà nella tua libreria.")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
            } else {
                ForEach(clients) { c in clientRow(c) }
            }

            if mode == "MACRO", let fab = fabbisogni, fab.fresh, let d = fab.data {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "calculator").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("Calcolo Fabbisogni recente").font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                    }
                    HStack(spacing: 12) {
                        if let v = d.detKcal      { fabPill("Kcal", "\(v)",  Palette.bronze) }
                        if let v = d.proteineG    { fabPill("Pro",  "\(v)g", Palette.cyan)   }
                        if let v = d.carboidratiG { fabPill("Carb", "\(v)g", Palette.lime)   }
                        if let v = d.lipidiG      { fabPill("Fat",  "\(v)g", Palette.magenta) }
                    }
                    Button {
                        if let v = d.detKcal      { kcal    = "\(v)" }
                        if let v = d.proteineG    { protein = "\(v)" }
                        if let v = d.carboidratiG { carb    = "\(v)" }
                        if let v = d.lipidiG      { fat     = "\(v)" }
                        withAnimation(.snappy) { step = 1 }
                    } label: {
                        Label("Applica target e rivedi", systemImage: "arrow.uturn.left")
                            .font(Typo.body(12, .semibold)).foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14).voltPanel(accent.opacity(0.25))
            }

            NeonButton(title: selectedClients.isEmpty
                           ? "Salva piano"
                           : "Salva e assegna a \(selectedClients.count)",
                       icon: "tray.and.arrow.down.fill", color: accent, loading: busy) {
                Task { await save() }
            }

            wzBackLink { withAnimation(.snappy) { step = 1 } }
        }
    }

    private func fabPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Typo.mono(13, .bold)).foregroundStyle(color)
            Text(label).font(Typo.mono(9, .semibold)).foregroundStyle(Palette.textMid)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .voltPanel(color.opacity(0.15))
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(Typo.mono(10, .semibold)).tracking(1).foregroundStyle(accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
    }

    private func clientRow(_ c: CoachAssignableClient) -> some View {
        let isSel = selectedClients.contains(c.id)
        return Button {
            Haptics.tap()
            withAnimation(.snappy) {
                if isSel { selectedClients.remove(c.id) } else { selectedClients.insert(c.id) }
            }
            if mode == "MACRO" && !isSel {
                Task { fabbisogni = try? await APIClient.shared.coachClientFabbisogni(clientId: c.id) }
            } else if selectedClients.count != 1 {
                fabbisogni = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isSel ? accent : Palette.textLow)
                Text(c.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Spacer()
            }
            .padding(14)
            .voltPanel(isSel ? accent.opacity(0.5) : Palette.line)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load + save

    private func loadIfEditing() async {
        guard let planId, savedPlanId == nil else { return }
        loadingPlan = true; defer { loadingPlan = false }
        do {
            let plan = try await APIClient.shared.coachNutritionBuilder(planId: planId)
            apply(builder: plan)
            savedPlanId = planId
            step = 1
        } catch {
            flash.failure("Impossibile caricare il piano")
        }
    }

    private func apply(builder plan: [String: Any]) {
        title = plan["title"] as? String ?? ""
        planDescription = plan["description"] as? String ?? ""
        mode = (plan["plan_mode"] as? String ?? "FOOD").uppercased() == "MACRO" ? "MACRO" : "FOOD"
        kind = (plan["plan_kind"] as? String ?? "DAILY").uppercased() == "WEEKLY" ? "WEEKLY" : "DAILY"

        func intText(_ v: Any?) -> String { (v as? Int).map(String.init) ?? "" }
        kcal = intText(plan["daily_kcal"])
        protein = intText(plan["protein_target_g"])
        carb = intText(plan["carb_target_g"])
        fat = intText(plan["fat_target_g"])

        meals = (plan["meals"] as? [[String: Any]] ?? []).map { m in
            var meal = WBMealDraft(name: m["name"] as? String ?? "Pasto")
            meal.time = m["time_of_day"] as? String ?? ""
            meal.notes = m["notes"] as? String ?? ""
            meal.dayOfWeek = m["day_of_week"] as? String
            meal.items = (m["items"] as? [[String: Any]] ?? []).compactMap { i in
                guard let fid = i["food_id"] as? Int else { return nil }
                func num(_ k: String) -> Double {
                    (i[k] as? Double) ?? (i[k] as? Int).map(Double.init) ?? 0
                }
                let food = BuilderFood(id: fid,
                                       name: i["food_name"] as? String ?? "Alimento",
                                       category: nil,
                                       kcal: num("kcal_per_100g"),
                                       protein: num("protein_per_100g"),
                                       carb: num("carb_per_100g"),
                                       fat: num("fat_per_100g"))
                var item = WBItemDraft(food: food, grams: num("quantity_g"))
                item.notes = i["notes"] as? String ?? ""
                item.substitutions = i["substitutions"] as? [[String: Any]] ?? []
                return item
            }
            return meal
        }

        if let targets = plan["day_targets"] as? [[String: Any]] {
            func intText(_ v: Any?) -> String { (v as? Int).map(String.init) ?? "" }
            dayTargets = wzWeekdays.map { day in
                var dt = WZDayTargetDraft(day: day)
                if let t = targets.first(where: { ($0["day_of_week"] as? String) == day }) {
                    dt.kcal = intText(t["kcal"]); dt.protein = intText(t["protein"])
                    dt.carb = intText(t["carb"]); dt.fat = intText(t["fat"])
                }
                return dt
            }
        }
    }

    private func buildPayload() -> [String: Any] {
        var p: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespaces),
            "plan_kind": kind,
            "plan_mode": mode,
        ]
        if !planDescription.isEmpty { p["description"] = planDescription }

        if mode == "MACRO" {
            if kind == "DAILY" {
                if let v = Int(kcal) { p["daily_kcal"] = v }
                if let v = Int(protein) { p["protein_target_g"] = v }
                if let v = Int(carb) { p["carb_target_g"] = v }
                if let v = Int(fat) { p["fat_target_g"] = v }
            } else {
                p["day_targets"] = dayTargets.filter { !$0.isEmpty }.map { dt -> [String: Any] in
                    var t: [String: Any] = ["day_of_week": dt.day]
                    if let v = Int(dt.kcal) { t["kcal"] = v }
                    if let v = Int(dt.protein) { t["protein"] = v }
                    if let v = Int(dt.carb) { t["carb"] = v }
                    if let v = Int(dt.fat) { t["fat"] = v }
                    return t
                }
            }
            p["meals"] = []
            return p
        }

        p["meals"] = meals.map { meal -> [String: Any] in
            var m: [String: Any] = ["name": meal.name]
            if !meal.time.isEmpty { m["time_of_day"] = meal.time }
            if !meal.notes.isEmpty { m["notes"] = meal.notes }
            if kind == "WEEKLY", let d = meal.dayOfWeek { m["day_of_week"] = d }
            m["items"] = meal.items.map { item -> [String: Any] in
                var i: [String: Any] = ["food_id": item.food.id, "quantity_g": item.grams]
                if !item.notes.isEmpty { i["notes"] = item.notes }
                if !item.substitutions.isEmpty { i["substitutions"] = item.substitutions }
                return i
            }
            return m
        }
        return p
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            let pid = try await APIClient.shared.coachSaveNutritionPlan(
                planId: savedPlanId ?? planId, payload: buildPayload())
            guard pid > 0 else { flash.failure("Salvataggio non riuscito"); return }
            savedPlanId = pid

            for clientId in selectedClients {
                try await APIClient.shared.coachAssignNutrition(planId: pid, clientId: clientId)
            }
            Analytics.shared.capture(.planUpdated, ["kind": "nutrition"])
            flash.success(selectedClients.isEmpty ? "Piano salvato" : "Piano assegnato")
            try? await Task.sleep(for: .seconds(1.1))
            onSaved()
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
