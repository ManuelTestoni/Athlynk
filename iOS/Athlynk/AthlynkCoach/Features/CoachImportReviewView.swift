//
//  CoachImportReviewView.swift
//  Chiron import review — full parity with the web review step:
//   • per-item match badge colored by confidence, unresolved counter
//   • tap a row to remap it via the builder's ExercisePickerSheet/FoodPickerSheet
//   • create a custom exercise inline (same endpoint as the web drawer)
//   • plan shape controls (workout: WEEKLY/PROGRAM + weeks; nutrition:
//     FOOD/MACRO × DAILY/WEEKLY with editable macro targets)
//   • save gate: workout blocked while unresolved > 0 (server refuses too)
//
//  The extraction JSON stays the wire format: rows keep their original payload
//  dict and edits are written back into it, so confirm echoes exactly what the
//  backend produced plus the coach's corrections.
//

import SwiftUI
import Combine

// MARK: - Review model

final class ImportReviewModel: ObservableObject {
    let kind: CoachPlanKind
    private var original: [String: Any]

    // Workout
    @Published var sessions: [RevSession] = []
    @Published var planKind = "WEEKLY"
    @Published var durationWeeks = 1

    // Nutrition
    @Published var days: [RevDay] = []
    @Published var dietMode = "FOOD"          // FOOD | MACRO
    @Published var dietKind = "DAILY"         // DAILY | WEEKLY
    @Published var planKcal = ""
    @Published var planProt = ""
    @Published var planCarb = ""
    @Published var planFat = ""

    struct RevExercise: Identifiable {
        let id = UUID()
        var payload: [String: Any]

        var rawName: String { (payload["raw_name"] as? String) ?? "Esercizio" }
        var matchedId: Int? { payload["matched_exercise_id"] as? Int }
        var matchedName: String? { payload["matched_exercise_name"] as? String }
        var confidence: String { (payload["match_confidence"] as? String) ?? "none" }
        var isUncertain: Bool { (payload["uncertain"] as? Bool) ?? false }
        var weekCount: Int {
            ((payload["week_values"] as? [[String: Any]]) ?? [])
                .compactMap { $0["week"] as? Int }.max() ?? 0
        }
        var hasSetDetails: Bool {
            !(((payload["set_details"] as? [[String: Any]]) ?? []).isEmpty)
        }
        var paramsLine: String {
            var bits: [String] = []
            let sets = payload["sets"] as? Int
            let reps = (payload["reps"] as? Int).map(String.init) ?? (payload["reps"] as? String)
            if let sets { bits.append("\(sets)×\(reps ?? "?")") }
            else if let reps { bits.append(reps) }
            if let load = payload["load"] as? Double {
                let unit = (payload["load_type"] as? String) == "percentage_1rm"
                    ? "%" : ((payload["load_unit"] as? String) ?? "kg")
                bits.append(load.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(load))\(unit)" : "\(load)\(unit)")
            }
            if let rpe = payload["rpe"] as? Double { bits.append("RPE \(Int(rpe))") }
            if let rir = payload["rir"] as? Int { bits.append("RIR \(rir)") }
            if let rest = payload["rest_seconds"] as? Int { bits.append("rec \(rest)s") }
            return bits.joined(separator: " · ")
        }

        mutating func remap(to ex: BuilderExercise) {
            payload["matched_exercise_id"] = ex.id
            payload["matched_exercise_name"] = ex.name
            payload["matched_primary_muscle"] = ex.targetMuscleGroup ?? ""
            payload["matched_equipment"] = ex.equipment.map { $0.nameIt }.joined(separator: ", ")
            payload["match_confidence"] = "manual"
            payload["match_method"] = "manual"
            payload["uncertain"] = false
        }
    }

    struct RevBlock: Identifiable {
        let id = UUID()
        var payload: [String: Any]
        var exercises: [RevExercise]
        var blockType: String { (payload["block_type"] as? String) ?? "straight" }
    }

    struct RevSession: Identifiable {
        let id = UUID()
        var payload: [String: Any]
        var blocks: [RevBlock]
        var label: String {
            let l = (payload["day_label"] as? String) ?? ""
            return l.isEmpty ? "Sessione" : l
        }
    }

    struct RevFood: Identifiable {
        let id = UUID()
        var payload: [String: Any]
        var name: String { (payload["name"] as? String) ?? "Alimento" }
        var foodId: Int? { payload["food_id"] as? Int }
        var isUncertain: Bool { (payload["uncertain"] as? Bool) ?? false }
        var quantityLabel: String {
            let qty = (payload["quantity"] as? Double) ?? Double(payload["quantity"] as? Int ?? 0)
            let unit = (payload["unit"] as? String) ?? "g"
            return qty > 0 ? "\(Int(qty)) \(unit)" : ""
        }
        mutating func remap(to food: BuilderFood, grams: Double) {
            payload["food_id"] = food.id
            payload["name"] = food.name
            if grams > 0 { payload["quantity"] = grams; payload["unit"] = "g" }
            payload["uncertain"] = false
        }
    }

    struct RevMeal: Identifiable {
        let id = UUID()
        var payload: [String: Any]
        var foods: [RevFood]
        var label: String {
            let labels = ["BREAKFAST": "Colazione", "MORNING_SNACK": "Spuntino mattutino",
                          "LUNCH": "Pranzo", "AFTERNOON_SNACK": "Spuntino pomeridiano",
                          "DINNER": "Cena"]
            return labels[(payload["meal_type"] as? String) ?? ""] ?? "Pasto"
        }
    }

    struct RevDay: Identifiable {
        let id = UUID()
        var payload: [String: Any]
        var meals: [RevMeal]
        var targetKcal: String
        var targetProt: String
        var targetCarb: String
        var targetFat: String
        var label: String {
            let labels = ["MONDAY": "Lunedì", "TUESDAY": "Martedì", "WEDNESDAY": "Mercoledì",
                          "THURSDAY": "Giovedì", "FRIDAY": "Venerdì", "SATURDAY": "Sabato",
                          "SUNDAY": "Domenica"]
            return labels[(payload["day_of_week"] as? String) ?? ""] ?? "Giorno"
        }
    }

    init(kind: CoachPlanKind, extracted: [String: Any]) {
        self.kind = kind
        self.original = extracted
        if kind == .workout {
            sessions = ((extracted["sessions"] as? [[String: Any]]) ?? []).map { s in
                RevSession(payload: s, blocks: ((s["blocks"] as? [[String: Any]]) ?? []).map { b in
                    RevBlock(payload: b,
                             exercises: ((b["exercises"] as? [[String: Any]]) ?? []).map { RevExercise(payload: $0) })
                })
            }
            let dw = (extracted["duration_weeks"] as? Int) ?? 0
            let maxWv = sessions.flatMap { $0.blocks }.flatMap { $0.exercises }.map { $0.weekCount }.max() ?? 0
            let weeks = max(dw, maxWv)
            if weeks >= 2 { planKind = "PROGRAM"; durationWeeks = min(52, weeks) }
        } else {
            days = ((extracted["days"] as? [[String: Any]]) ?? []).map { d in
                RevDay(payload: d,
                       meals: ((d["meals"] as? [[String: Any]]) ?? []).map { m in
                           RevMeal(payload: m,
                                   foods: ((m["foods"] as? [[String: Any]]) ?? []).map { RevFood(payload: $0) })
                       },
                       targetKcal: Self.numString(d["target_kcal"]),
                       targetProt: Self.numString(d["target_protein_g"]),
                       targetCarb: Self.numString(d["target_carb_g"]),
                       targetFat: Self.numString(d["target_fat_g"]))
            }
            dietMode = (extracted["plan_mode"] as? String) == "MACRO" ? "MACRO" : "FOOD"
            dietKind = (extracted["plan_kind"] as? String) ?? (days.count > 1 ? "WEEKLY" : "DAILY")
            planKcal = Self.numString(extracted["daily_kcal"] ?? extracted["total_calories_daily"])
            planProt = Self.numString(extracted["protein_target_g"])
            planCarb = Self.numString(extracted["carb_target_g"])
            planFat = Self.numString(extracted["fat_target_g"])
        }
    }

    private static func numString(_ v: Any?) -> String {
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(Int(d)) }
        return ""
    }

    var unresolvedCount: Int {
        sessions.flatMap { $0.blocks }.flatMap { $0.exercises }.filter { $0.matchedId == nil }.count
    }
    var mediumCount: Int {
        sessions.flatMap { $0.blocks }.flatMap { $0.exercises }
            .filter { $0.matchedId != nil && ($0.confidence == "medium" || $0.isUncertain) }.count
    }
    var exerciseCount: Int { sessions.flatMap { $0.blocks }.flatMap { $0.exercises }.count }
    var unlinkedFoodCount: Int {
        days.flatMap { $0.meals }.flatMap { $0.foods }.filter { $0.foodId == nil }.count
    }

    // MARK: Confirm payload reconstruction

    func buildWorkoutJson() -> [String: Any] {
        var out = original
        out["sessions"] = sessions.map { s -> [String: Any] in
            var sp = s.payload
            sp["blocks"] = s.blocks.map { b -> [String: Any] in
                var bp = b.payload
                bp["exercises"] = b.exercises.map { $0.payload }
                return bp
            }
            return sp
        }
        return out
    }

    func buildDietJson() -> [String: Any] {
        func intOrNil(_ s: String) -> Any { Int(s.trimmingCharacters(in: .whitespaces)) ?? NSNull() }
        var out = original
        out["plan_mode"] = dietMode
        out["plan_kind"] = dietKind
        out["daily_kcal"] = intOrNil(planKcal)
        out["protein_target_g"] = intOrNil(planProt)
        out["carb_target_g"] = intOrNil(planCarb)
        out["fat_target_g"] = intOrNil(planFat)
        out["days"] = days.map { d -> [String: Any] in
            var dp = d.payload
            dp["target_kcal"] = intOrNil(d.targetKcal)
            dp["target_protein_g"] = intOrNil(d.targetProt)
            dp["target_carb_g"] = intOrNil(d.targetCarb)
            dp["target_fat_g"] = intOrNil(d.targetFat)
            dp["meals"] = dietMode == "MACRO" ? [] : d.meals.map { m -> [String: Any] in
                var mp = m.payload
                mp["foods"] = m.foods.map { $0.payload }
                return mp
            }
            return dp
        }
        return out
    }
}

// MARK: - Review view

struct CoachImportReviewView: View {
    let kind: CoachPlanKind
    @Binding var title: String
    var onSaved: () -> Void

    @StateObject private var model: ImportReviewModel
    @ObservedObject var flash: StatusFlash
    @State private var busy = false

    // Remap targets (index paths into the model)
    @State private var remapExercise: (s: Int, b: Int, e: Int)?
    @State private var showExercisePicker = false
    @State private var remapFood: (d: Int, m: Int, f: Int)?
    @State private var showFoodPicker = false
    @State private var customFor: (s: Int, b: Int, e: Int)?
    @State private var showCustomSheet = false

    private var accent: Color { kind.accent }

    init(kind: CoachPlanKind, extracted: [String: Any], title: Binding<String>,
         flash: StatusFlash, onSaved: @escaping () -> Void) {
        self.kind = kind
        self._title = title
        self.flash = flash
        self.onSaved = onSaved
        self._model = StateObject(wrappedValue: ImportReviewModel(kind: kind, extracted: extracted))
    }

    var body: some View {
        VStack(spacing: 14) {
            statusBanner
            if kind == .workout {
                workoutShapeControls
                workoutSessions
            } else {
                nutritionShapeControls
                if model.dietMode == "MACRO" { macroTargets } else { nutritionDays }
            }
            saveButton
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet(accent: accent) { picked in
                if let path = remapExercise {
                    model.sessions[path.s].blocks[path.b].exercises[path.e].remap(to: picked)
                    model.objectWillChange.send()
                }
            }
        }
        .sheet(isPresented: $showFoodPicker) {
            FoodPickerSheet(accent: accent) { picked, grams in
                if let path = remapFood {
                    model.days[path.d].meals[path.m].foods[path.f].remap(to: picked, grams: grams)
                    model.objectWillChange.send()
                }
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomExerciseSheet(accent: accent, prefillName: customPrefillName) { id, name in
                if let path = customFor {
                    var ex = model.sessions[path.s].blocks[path.b].exercises[path.e]
                    ex.payload["matched_exercise_id"] = id
                    ex.payload["matched_exercise_name"] = name
                    ex.payload["match_confidence"] = "manual"
                    ex.payload["match_method"] = "manual"
                    ex.payload["uncertain"] = false
                    model.sessions[path.s].blocks[path.b].exercises[path.e] = ex
                    model.objectWillChange.send()
                }
            }
        }
    }

    private var customPrefillName: String {
        guard let p = customFor else { return "" }
        return model.sessions[p.s].blocks[p.b].exercises[p.e].rawName
    }

    // MARK: Status banner

    @ViewBuilder
    private var statusBanner: some View {
        if kind == .workout {
            if model.unresolvedCount > 0 {
                banner(icon: "exclamationmark.triangle.fill", color: Palette.danger,
                       text: "\(model.unresolvedCount) eserciz\(model.unresolvedCount == 1 ? "io" : "i") non collegat\(model.unresolvedCount == 1 ? "o" : "i") al database. Tocca la riga per collegarlo o crealo.")
            } else if model.mediumCount > 0 {
                banner(icon: "info.circle.fill", color: Palette.amber,
                       text: "Tutti collegati; \(model.mediumCount) da verificare (evidenziati).")
            } else {
                banner(icon: "checkmark.circle.fill", color: Palette.success,
                       text: "Tutti gli esercizi sono collegati al database.")
            }
        } else if model.dietMode == "FOOD", model.unlinkedFoodCount > 0 {
            banner(icon: "info.circle.fill", color: Palette.amber,
                   text: "\(model.unlinkedFoodCount) aliment\(model.unlinkedFoodCount == 1 ? "o" : "i") non collegat\(model.unlinkedFoodCount == 1 ? "o" : "i") al DB: verranno salvati come testo. Tocca per collegarli.")
        }
    }

    private func banner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).voltPanel(radius: 12)
    }

    // MARK: Workout

    private var workoutShapeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIPO DI SCHEDA").font(Typo.mono(10, .semibold)).tracking(2)
                .foregroundStyle(Palette.textMid)
            Picker("", selection: $model.planKind) {
                Text("Settimanale").tag("WEEKLY")
                Text("Programmazione").tag("PROGRAM")
            }
            .pickerStyle(.segmented)
            if model.planKind == "PROGRAM" {
                Stepper(value: $model.durationWeeks, in: 2...52) {
                    Text("\(model.durationWeeks) settimane")
                        .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                }
                .tint(accent)
            }
        }
        .padding(14).voltPanel()
    }

    private var workoutSessions: some View {
        VStack(spacing: 12) {
            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { sIdx, session in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.label)
                        .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    ForEach(Array(session.blocks.enumerated()), id: \.element.id) { bIdx, block in
                        VStack(alignment: .leading, spacing: 6) {
                            if block.blockType != "straight" {
                                Text(block.blockType.uppercased())
                                    .font(Typo.mono(9, .semibold)).tracking(1.5)
                                    .foregroundStyle(accent)
                            }
                            ForEach(Array(block.exercises.enumerated()), id: \.element.id) { eIdx, ex in
                                exerciseRow(ex, path: (sIdx, bIdx, eIdx))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).voltPanel()
            }
        }
    }

    private func exerciseRow(_ ex: ImportReviewModel.RevExercise,
                             path: (s: Int, b: Int, e: Int)) -> some View {
        Button {
            Haptics.tap()
            remapExercise = path
            showExercisePicker = true
        } label: {
            HStack(spacing: 10) {
                Circle().fill(confidenceColor(ex)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.rawName)
                        .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let matched = ex.matchedName {
                            Text("→ \(matched)").font(Typo.body(11)).foregroundStyle(Palette.textMid)
                                .lineLimit(1)
                        } else {
                            Text("Nessuna corrispondenza — tocca per collegare")
                                .font(Typo.body(11)).foregroundStyle(Palette.danger)
                        }
                    }
                    HStack(spacing: 8) {
                        if !ex.paramsLine.isEmpty {
                            Text(ex.paramsLine).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                        }
                        if ex.weekCount >= 2 {
                            Text("W1–W\(ex.weekCount)")
                                .font(Typo.mono(9, .semibold)).tracking(1)
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(accent.opacity(0.14)))
                        }
                        if ex.hasSetDetails {
                            Text("SET VAR").font(Typo.mono(9, .semibold)).tracking(1)
                                .foregroundStyle(accent)
                        }
                    }
                }
                Spacer(minLength: 4)
                if ex.matchedId == nil {
                    Button {
                        Haptics.tap()
                        customFor = path
                        showCustomSheet = true
                    } label: {
                        Text("Crea").font(Typo.body(12, .semibold)).foregroundStyle(accent)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().stroke(accent.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.void2.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ex.matchedId == nil ? Palette.danger.opacity(0.5)
                        : (ex.confidence == "medium" || ex.isUncertain ? Palette.amber.opacity(0.5) : .clear),
                        lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func confidenceColor(_ ex: ImportReviewModel.RevExercise) -> Color {
        if ex.matchedId == nil { return Palette.danger }
        switch ex.confidence {
        case "exact", "high", "manual": return Palette.success
        case "medium": return Palette.amber
        default: return Palette.amber
        }
    }

    // MARK: Nutrition

    private var nutritionShapeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIPO DI PIANO").font(Typo.mono(10, .semibold)).tracking(2)
                .foregroundStyle(Palette.textMid)
            Picker("", selection: $model.dietMode) {
                Text("Alimenti").tag("FOOD")
                Text("Macro").tag("MACRO")
            }
            .pickerStyle(.segmented)
            Picker("", selection: $model.dietKind) {
                Text("Giornaliero").tag("DAILY")
                Text("Settimanale").tag("WEEKLY")
            }
            .pickerStyle(.segmented)
            if model.dietMode == "MACRO" {
                Text("Solo target kcal/macro: gli alimenti estratti non verranno importati.")
                    .font(Typo.body(11)).foregroundStyle(Palette.textLow)
            }
        }
        .padding(14).voltPanel()
    }

    private var macroTargets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.dietKind == "WEEKLY" ? "TARGET PER GIORNO" : "TARGET GIORNALIERI")
                .font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            if model.dietKind == "WEEKLY" && !model.days.isEmpty {
                ForEach($model.days) { $day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(day.label).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                        macroFieldRow(kcal: $day.targetKcal, prot: $day.targetProt,
                                      carb: $day.targetCarb, fat: $day.targetFat)
                    }
                    .padding(.bottom, 4)
                }
            } else {
                macroFieldRow(kcal: $model.planKcal, prot: $model.planProt,
                              carb: $model.planCarb, fat: $model.planFat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).voltPanel()
    }

    private func macroFieldRow(kcal: Binding<String>, prot: Binding<String>,
                               carb: Binding<String>, fat: Binding<String>) -> some View {
        HStack(spacing: 8) {
            macroField("Kcal", kcal)
            macroField("Prot", prot)
            macroField("Carb", carb)
            macroField("Grassi", fat)
        }
    }

    private func macroField(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(Typo.mono(8, .semibold)).tracking(1)
                .foregroundStyle(Palette.textLow)
            TextField("—", text: value)
                .keyboardType(.numberPad)
                .font(Typo.mono(14, .semibold)).foregroundStyle(Palette.textHi)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.void2))
        }
    }

    private var nutritionDays: some View {
        VStack(spacing: 12) {
            ForEach(Array(model.days.enumerated()), id: \.element.id) { dIdx, day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.label).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    ForEach(Array(day.meals.enumerated()), id: \.element.id) { mIdx, meal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.label.uppercased())
                                .font(Typo.mono(9, .semibold)).tracking(1.5)
                                .foregroundStyle(accent)
                            ForEach(Array(meal.foods.enumerated()), id: \.element.id) { fIdx, food in
                                foodRow(food, path: (dIdx, mIdx, fIdx))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).voltPanel()
            }
        }
    }

    private func foodRow(_ food: ImportReviewModel.RevFood,
                         path: (d: Int, m: Int, f: Int)) -> some View {
        Button {
            Haptics.tap()
            remapFood = path
            showFoodPicker = true
        } label: {
            HStack(spacing: 10) {
                Circle().fill(food.foodId == nil ? Palette.amber : Palette.success)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if !food.quantityLabel.isEmpty {
                            Text(food.quantityLabel).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                        }
                        Text(food.foodId == nil ? "testo libero — tocca per collegare al DB" : "DB")
                            .font(Typo.mono(9, .semibold)).tracking(1)
                            .foregroundStyle(food.foodId == nil ? Palette.amber : accent)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.void2.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(food.foodId == nil ? Palette.amber.opacity(0.4) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private var saveGateBlocked: Bool { kind == .workout && model.unresolvedCount > 0 }

    private var saveButton: some View {
        NeonButton(title: saveGateBlocked ? "Collega tutti gli esercizi per salvare" : "Salva e apri nel builder",
                   icon: "tray.and.arrow.down.fill",
                   color: saveGateBlocked ? Palette.textLow : accent,
                   loading: busy) {
            guard !saveGateBlocked else { return }
            Task { await save() }
        }
        .disabled(saveGateBlocked)
        .opacity(saveGateBlocked ? 0.6 : 1)
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            if kind == .workout {
                try await APIClient.shared.coachConfirmWorkout(
                    workoutJson: model.buildWorkoutJson(), title: title,
                    planKind: model.planKind,
                    durationWeeks: model.planKind == "PROGRAM" ? model.durationWeeks : 1)
            } else {
                try await APIClient.shared.coachConfirmDiet(
                    dietJson: model.buildDietJson(), title: title,
                    planKind: model.dietKind, planMode: model.dietMode)
            }
            flash.success("Bozza salvata")
            try? await Task.sleep(for: .seconds(1.0))
            onSaved()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}

// MARK: - Custom exercise sheet (minimal form: name + primary muscles)

struct CustomExerciseSheet: View {
    let accent: Color
    let prefillName: String
    var onCreated: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscles: [(id: Int, name: String)] = []
    @State private var selected: Set<Int> = []
    @State private var busy = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOME").font(Typo.mono(10, .semibold)).tracking(2)
                            .foregroundStyle(Palette.textMid)
                        TextField("Es. Panca piana manubri", text: $name)
                            .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(accent)
                            .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MUSCOLI PRIMARI").font(Typo.mono(10, .semibold)).tracking(2)
                            .foregroundStyle(Palette.textMid)
                        FlowChips(items: muscles, selected: $selected, accent: accent)
                    }
                    if let errorMsg {
                        Text(errorMsg).font(Typo.body(12)).foregroundStyle(Palette.danger)
                    }
                    NeonButton(title: "Crea esercizio", icon: "plus.circle.fill",
                               color: accent, loading: busy) {
                        Task { await create() }
                    }
                }
                .padding(20)
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Esercizio personalizzato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Annulla") { dismiss() }.tint(Palette.textMid)
            } }
            .task {
                name = prefillName
                let raw = (try? await APIClient.shared.coachMuscleGroups()) ?? []
                muscles = raw.compactMap { m in
                    guard let id = m["id"] as? Int, let n = m["name"] as? String else { return nil }
                    return (id, n)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func create() async {
        errorMsg = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { errorMsg = "Nome: minimo 3 caratteri."; return }
        guard !selected.isEmpty else { errorMsg = "Seleziona almeno un muscolo primario."; return }
        busy = true; defer { busy = false }
        do {
            let res = try await APIClient.shared.coachCreateCustomExercise(
                name: trimmed, primaryMuscleIds: Array(selected))
            guard let id = res["id"] as? Int else {
                errorMsg = (res["error"] as? String) ?? "Errore di salvataggio."
                return
            }
            onCreated(id, (res["name"] as? String) ?? trimmed)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

/// Wrapping chip multi-select for the muscle taxonomy.
private struct FlowChips: View {
    let items: [(id: Int, name: String)]
    @Binding var selected: Set<Int>
    let accent: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.id) { item in
                Button {
                    Haptics.tap()
                    if selected.contains(item.id) { selected.remove(item.id) }
                    else { selected.insert(item.id) }
                } label: {
                    Text(item.name)
                        .font(Typo.body(12, .semibold))
                        .foregroundStyle(selected.contains(item.id) ? Palette.void0 : Palette.textMid)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(selected.contains(item.id) ? accent : Palette.void2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
