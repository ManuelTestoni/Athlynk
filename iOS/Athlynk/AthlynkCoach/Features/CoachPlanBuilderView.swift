//
//  CoachPlanBuilderView.swift
//  Full in-app builder for workout and nutrition plans — the mobile twin of the
//  web wizard, rethought for touch: day/meal cards, search sheets backed by the
//  exercise/food DB, steppers instead of spreadsheets, live macro totals.
//

import SwiftUI

// MARK: - Builder state models

/// One per-set override. Empty `setDetails` on an exercise = uniform prescription.
struct WBSetDraft: Identifiable {
    let id = UUID()
    var reps = ""                // string to allow ranges like "8-10"
    var loadValue: Double? = nil
    var loadUnit = "KG"
    var recoverySeconds: Int? = nil
    var rir: Int? = nil
    var rpe: Int? = nil
    var tempo = ""
}

struct WBExerciseDraft: Identifiable {
    let id = UUID()
    var pk: Int? = nil           // server WorkoutExercise id (edit round-trip)
    let exerciseId: Int
    let name: String
    let muscle: String
    var sets = 3
    var reps = 10
    var repRange = ""            // when set, wins over `reps`
    var recoverySeconds = 90
    var loadValue: Double? = nil
    var loadUnit = "KG"          // KG | PERCENT_1RM | BODYWEIGHT
    var rir: Int? = nil
    var rpe: Int? = nil
    var rpeRirType = "RPE"         // UI-only: "RPE" | "RIR"
    var tempo = ""
    var notes = ""
    var setDetails: [WBSetDraft] = []   // per-set overrides; empty = uniform

    var rpeRirValue: Int? {
        get { rpeRirType == "RPE" ? rpe : rir }
        set {
            if rpeRirType == "RPE" { rpe = newValue; rir = nil }
            else { rir = newValue; rpe = nil }
        }
    }

    /// Switches which field (RIR/RPE) is active, carrying this exercise's own
    /// value across so it isn't lost — never copies another exercise's value.
    mutating func applyRpeRirType(_ newType: String) {
        guard newType != rpeRirType else { return }
        if newType == "RPE" { rpe = rir; rir = nil } else { rir = rpe; rpe = nil }
        rpeRirType = newType
    }

    var summary: String {
        let r = repRange.isEmpty ? "\(reps)" : repRange
        var s = "\(sets)×\(r) · \(recoverySeconds)″"
        if let loadValue {
            let v = loadValue.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(loadValue))" : String(format: "%.1f", loadValue)
            s += loadUnit == "PERCENT_1RM" ? " · \(v)%" : " · \(v)kg"
        }
        if let rir { s += " · RIR \(rir)" }
        if let rpe { s += " · RPE \(rpe)" }
        return s
    }

    func blankSetRow() -> WBSetDraft {
        WBSetDraft(reps: repRange.isEmpty ? "\(reps)" : repRange,
                   loadValue: loadValue, loadUnit: loadUnit,
                   recoverySeconds: recoverySeconds, rir: rir, rpe: rpe, tempo: tempo)
    }

    /// Expand into `sets` per-set rows (prefilled from the base) or collapse to uniform.
    mutating func toggleSetDetails() {
        if setDetails.isEmpty {
            setDetails = (0..<max(1, sets)).map { _ in blankSetRow() }
        } else {
            setDetails = []
        }
    }

    /// Keep per-set rows aligned to the set count while expanded.
    mutating func syncSetDetails() {
        guard !setDetails.isEmpty else { return }
        let n = max(1, sets)
        while setDetails.count < n { setDetails.append(blankSetRow()) }
        if setDetails.count > n { setDetails.removeLast(setDetails.count - n) }
    }
}

struct WBDayDraft: Identifiable {
    let id = UUID()
    var pk: Int? = nil           // server WorkoutDay id (edit round-trip)
    var name: String
    var notes = ""
    var exercises: [WBExerciseDraft] = []
}

struct WBItemDraft: Identifiable {
    let id = UUID()
    let food: BuilderFood
    var grams: Double
    var notes = ""
    /// Substitutions built on the web, carried opaquely so a mobile save
    /// doesn't drop them.
    var substitutions: [[String: Any]] = []

    var kcal: Double { food.kcal * grams / 100 }
    var protein: Double { food.protein * grams / 100 }
    var carb: Double { food.carb * grams / 100 }
    var fat: Double { food.fat * grams / 100 }
}

struct WBMealDraft: Identifiable {
    let id = UUID()
    var name: String
    var time = ""
    var notes = ""
    var dayOfWeek: String? = nil // LUN…DOM, only for WEEKLY plans
    var items: [WBItemDraft] = []

    var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
}

// MARK: - Workout builder

struct WorkoutBuilderSection: View {
    @Binding var days: [WBDayDraft]
    let accent: Color

    @State private var pickingForDay: UUID?

    var body: some View {
        VStack(spacing: 14) {
            if days.isEmpty {
                emptyState
            }

            ForEach($days) { $day in
                WBDayCard(
                    day: $day,
                    accent: accent,
                    index: days.firstIndex(where: { $0.id == day.id }) ?? 0,
                    onAddExercise: { pickingForDay = day.id },
                    onDelete: { remove(day.id) },
                    onExerciseTypeChanged: { exId, newType in propagateRpeRirType(newType, excluding: exId) }
                )
            }

            Button {
                Haptics.tap()
                withAnimation(.snappy) {
                    days.append(WBDayDraft(name: "Giorno \(days.count + 1)"))
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text(days.isEmpty ? "Aggiungi il primo giorno" : "Aggiungi giorno")
                }
                .font(Typo.body(15, .semibold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: Binding(
            get: { pickingForDay != nil },
            set: { if !$0 { pickingForDay = nil } }
        )) {
            ExercisePickerSheet(accent: accent) { picked in
                guard let dayId = pickingForDay,
                      let idx = days.firstIndex(where: { $0.id == dayId }) else { return }
                Haptics.soft()
                withAnimation(.snappy) {
                    days[idx].exercises.append(WBExerciseDraft(
                        exerciseId: picked.id, name: picked.name,
                        muscle: picked.targetMuscleGroup ?? ""))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
            Text("Costruisci la scheda")
                .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Text("Aggiungi i giorni di allenamento, poi gli esercizi dal database con serie, ripetizioni e recupero.")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(18).voltPanel()
    }

    private func remove(_ id: UUID) {
        Haptics.warning()
        withAnimation(.snappy) { days.removeAll { $0.id == id } }
    }

    /// Only the RIR/RPE *type* propagates — each exercise keeps its own numeric value.
    private func propagateRpeRirType(_ newType: String, excluding exId: UUID) {
        for di in days.indices {
            for ei in days[di].exercises.indices {
                guard days[di].exercises[ei].id != exId else { continue }
                days[di].exercises[ei].applyRpeRirType(newType)
            }
        }
    }
}

private struct WBDayCard: View {
    @Binding var day: WBDayDraft
    let accent: Color
    let index: Int
    let onAddExercise: () -> Void
    let onDelete: () -> Void
    let onExerciseTypeChanged: (UUID, String) -> Void

    @EnvironmentObject private var confirmCenter: ConfirmCenter

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Text(String(format: "%02d", index + 1))
                    .font(Typo.mono(11, .semibold)).tracking(2).foregroundStyle(accent)
                TextField("", text: $day.name,
                          prompt: Text("Nome giorno").foregroundStyle(Palette.textLow))
                    .font(Typo.display(18)).foregroundStyle(Palette.textHi).tint(accent)
                Spacer(minLength: 4)
                Button {
                    Haptics.tap()
                    Task {
                        if await confirmCenter.confirm(.init(
                            title: "Eliminare il giorno?",
                            subtitle: "\"\(day.name)\" e tutti i suoi esercizi verranno rimossi.",
                            icon: "trash")) {
                            onDelete()
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.crimson.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)

            Rectangle().fill(Palette.line).frame(height: 1)

            // Exercises
            if day.exercises.isEmpty {
                Text("Nessun esercizio — aggiungine uno dal database.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ForEach($day.exercises) { $ex in
                    WBExerciseRow(ex: $ex, accent: accent,
                                  onDelete: { removeExercise(ex.id) },
                                  onMoveUp: { move(ex.id, by: -1) },
                                  onMoveDown: { move(ex.id, by: +1) },
                                  onTypeChanged: { newType in onExerciseTypeChanged(ex.id, newType) })
                    if ex.id != day.exercises.last?.id {
                        Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            Rectangle().fill(Palette.line).frame(height: 1)

            Button { Haptics.tap(); onAddExercise() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Aggiungi esercizio")
                }
                .font(Typo.body(13, .semibold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .voltPanel()
    }

    private func removeExercise(_ id: UUID) {
        Haptics.warning()
        withAnimation(.snappy) { day.exercises.removeAll { $0.id == id } }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = day.exercises.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard day.exercises.indices.contains(j) else { return }
        Haptics.tap()
        withAnimation(.snappy) { day.exercises.swapAt(i, j) }
    }
}

private struct WBExerciseRow: View {
    @Binding var ex: WBExerciseDraft
    let accent: Color
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onTypeChanged: (String) -> Void

    @EnvironmentObject private var confirmCenter: ConfirmCenter
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ex.name)
                            .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(ex.summary)
                                .font(Typo.mono(11, .semibold)).foregroundStyle(accent)
                            if !ex.muscle.isEmpty {
                                Text(ex.muscle.uppercased())
                                    .font(Typo.mono(9, .semibold)).tracking(1.5)
                                    .foregroundStyle(Palette.textLow)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textLow)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 12) {
                    // Row 1: SERIE, REPS, CARICO, UNITÀ
                    HStack(spacing: 8) {
                        WBStepper(label: "SERIE", value: $ex.sets, range: 1...12)
                        WBStepper(label: "REPS", value: $ex.reps, range: 1...50)
                            .opacity(ex.repRange.isEmpty ? 1 : 0.35)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("CARICO")
                                .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                            TextField("", value: $ex.loadValue, format: .number,
                                      prompt: Text("—").foregroundStyle(Palette.textLow))
                                .keyboardType(.decimalPad)
                                .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(accent)
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .voltPanel(radius: 10)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("UNITÀ")
                                .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                            Menu {
                                Button("kg") { ex.loadUnit = "KG" }
                                Button("% 1RM") { ex.loadUnit = "PERCENT_1RM" }
                                Button("BW") { ex.loadUnit = "BODYWEIGHT" }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(ex.loadUnit == "PERCENT_1RM" ? "%1RM"
                                         : ex.loadUnit == "BODYWEIGHT" ? "BW" : "kg")
                                        .font(Typo.body(13)).foregroundStyle(Palette.textHi)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Palette.textLow)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 11)
                                .voltPanel(radius: 10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Row 2: RECUPERO, RPE/RIR, TUT — three even, full-width columns.
                    // The note used to sit in a fixed 120pt side column that
                    // squeezed these fields on narrow phones; it's now its own
                    // full-width row below so every column stays symmetric.
                    HStack(alignment: .top, spacing: 8) {
                        WBStepper(label: "REC (SEC)", value: $ex.recoverySeconds,
                                  range: 0...600, step: 15)
                            .frame(maxWidth: .infinity)
                        // RPE/RIR — type as a compact dropdown (label slot), value
                        // typed directly (no +/- stepper). Matches the CARICO/TUT
                        // text-field cells so the row stays symmetric.
                        VStack(alignment: .leading, spacing: 5) {
                            Menu {
                                Button("RPE") { changeType("RPE") }
                                Button("RIR") { changeType("RIR") }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(ex.rpeRirType)
                                        .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 7, weight: .semibold)).foregroundStyle(Palette.textLow)
                                }
                            }
                            TextField("", value: Binding(get: { ex.rpeRirValue },
                                                         set: { ex.rpeRirValue = $0 }),
                                      format: .number,
                                      prompt: Text("—").foregroundStyle(Palette.textLow))
                                .keyboardType(.numberPad)
                                .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(accent)
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .voltPanel(radius: 10)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("TUT")
                                .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                            TextField("", text: $ex.tempo,
                                      prompt: Text("3-1-1").foregroundStyle(Palette.textLow))
                                .font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .voltPanel(radius: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // NOTE — full-width row.
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NOTE")
                            .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                        TextField("", text: $ex.notes,
                                  prompt: Text("Es. scapole addotte…").foregroundStyle(Palette.textLow),
                                  axis: .vertical)
                            .lineLimit(2...4)
                            .font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .voltPanel(radius: 10)
                    }
                    // Range reps (optional, below)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("RANGE REPS (OPZ.)")
                            .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                        TextField("", text: $ex.repRange,
                                  prompt: Text("Es. 8-12").foregroundStyle(Palette.textLow))
                            .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(accent)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .voltPanel(radius: 10)
                    }
                    // PER-SET — valori diversi per ogni serie
                    VStack(alignment: .leading, spacing: 8) {
                        Button { ex.toggleSetDetails() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: ex.setDetails.isEmpty ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                Text(ex.setDetails.isEmpty ? "Valori diversi per ogni serie"
                                                           : "Valori uguali per ogni serie")
                                    .font(Typo.mono(10, .semibold))
                            }
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                        if !ex.setDetails.isEmpty {
                            ForEach(ex.setDetails.indices, id: \.self) { i in
                                WBSetDetailRow(index: i, sd: $ex.setDetails[i],
                                               rpeRirType: ex.rpeRirType, accent: accent)
                            }
                        }
                    }
                    .onChange(of: ex.sets) { _, _ in ex.syncSetDetails() }
                    HStack {
                        Button { onMoveUp() } label: {
                            Image(systemName: "arrow.up").frame(width: 36, height: 30)
                        }
                        Button { onMoveDown() } label: {
                            Image(systemName: "arrow.down").frame(width: 36, height: 30)
                        }
                        Spacer()
                        Button {
                            Task {
                                if await confirmCenter.confirm(.init(
                                    title: "Eliminare l'esercizio?",
                                    subtitle: "\"\(ex.name)\" verrà rimosso dalla scheda.",
                                    icon: "trash")) {
                                    onDelete()
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Rimuovi")
                            }
                            .font(Typo.body(13, .semibold))
                            .foregroundStyle(Palette.crimson)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textMid)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func changeType(_ newType: String) {
        guard newType != ex.rpeRirType else { return }
        Haptics.tap()
        ex.applyRpeRirType(newType)
        onTypeChanged(newType)
    }
}

/// One editable per-set row: reps / load+unit on top, rest / RPE-RIR / tempo below.
private struct WBSetDetailRow: View {
    let index: Int
    @Binding var sd: WBSetDraft
    let rpeRirType: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("S\(index + 1)")
                    .font(Typo.mono(10, .bold)).foregroundStyle(accent)
                    .frame(width: 26, alignment: .leading)
                field("REPS") {
                    TextField("", text: $sd.reps, prompt: Text("8-10").foregroundStyle(Palette.textLow))
                        .font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                }
                field("CARICO") {
                    TextField("", value: $sd.loadValue, format: .number,
                              prompt: Text("—").foregroundStyle(Palette.textLow))
                        .keyboardType(.decimalPad).font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                }
                unitMenu
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 26)
                field("REC") {
                    TextField("", value: $sd.recoverySeconds, format: .number,
                              prompt: Text("—").foregroundStyle(Palette.textLow))
                        .keyboardType(.numberPad).font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                }
                field(rpeRirType) {
                    TextField("", value: rpeRirBinding, format: .number,
                              prompt: Text("—").foregroundStyle(Palette.textLow))
                        .keyboardType(.numberPad).font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                }
                field("TUT") {
                    TextField("", text: $sd.tempo, prompt: Text("3-1-1").foregroundStyle(Palette.textLow))
                        .font(Typo.body(13)).foregroundStyle(Palette.textHi).tint(accent)
                }
            }
        }
        .padding(8).voltPanel(radius: 10)
    }

    private var rpeRirBinding: Binding<Int?> {
        Binding(get: { rpeRirType == "RPE" ? sd.rpe : sd.rir },
                set: { if rpeRirType == "RPE" { sd.rpe = $0 } else { sd.rir = $0 } })
    }

    @ViewBuilder private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typo.mono(8, .semibold)).tracking(1).foregroundStyle(Palette.textMid)
            content().padding(.horizontal, 8).padding(.vertical, 7).voltPanel(radius: 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var unitMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("UNITÀ").font(Typo.mono(8, .semibold)).tracking(1).foregroundStyle(Palette.textMid)
            Menu {
                Button("kg") { sd.loadUnit = "KG" }
                Button("% 1RM") { sd.loadUnit = "PERCENT_1RM" }
                Button("BW") { sd.loadUnit = "BODYWEIGHT" }
            } label: {
                Text(sd.loadUnit == "PERCENT_1RM" ? "%1RM" : sd.loadUnit == "BODYWEIGHT" ? "BW" : "kg")
                    .font(Typo.body(12)).foregroundStyle(Palette.textHi)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8).padding(.vertical, 7).voltPanel(radius: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Nutrition builder

struct DietBuilderSection: View {
    @Binding var meals: [WBMealDraft]
    let accent: Color

    @State private var pickingForMeal: UUID?

    private var totals: (kcal: Double, p: Double, c: Double, f: Double) {
        meals.reduce((0.0, 0.0, 0.0, 0.0)) { acc, m in
            m.items.reduce(acc) { a, it in
                (a.0 + it.kcal, a.1 + it.protein, a.2 + it.carb, a.3 + it.fat)
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            totalsBar

            if meals.isEmpty {
                emptyState
            }

            ForEach($meals) { $meal in
                WBMealCard(meal: $meal, accent: accent,
                           onAddFood: { pickingForMeal = meal.id },
                           onDelete: { remove(meal.id) })
            }

            Button {
                Haptics.tap()
                withAnimation(.snappy) {
                    meals.append(WBMealDraft(name: defaultMealName))
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text(meals.isEmpty ? "Aggiungi il primo pasto" : "Aggiungi pasto")
                }
                .font(Typo.body(15, .semibold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: Binding(
            get: { pickingForMeal != nil },
            set: { if !$0 { pickingForMeal = nil } }
        )) {
            FoodPickerSheet(accent: accent) { food, grams in
                guard let mealId = pickingForMeal,
                      let idx = meals.firstIndex(where: { $0.id == mealId }) else { return }
                Haptics.soft()
                withAnimation(.snappy) {
                    meals[idx].items.append(WBItemDraft(food: food, grams: grams))
                }
            }
        }
    }

    private var defaultMealName: String {
        let presets = ["Colazione", "Spuntino", "Pranzo", "Merenda", "Cena"]
        return meals.count < presets.count ? presets[meals.count] : "Pasto \(meals.count + 1)"
    }

    private var totalsBar: some View {
        HStack(spacing: 0) {
            macroCell("KCAL", totals.kcal, Palette.textHi, bold: true)
            divider
            macroCell("PRO", totals.p, Palette.cyan)
            divider
            macroCell("CARB", totals.c, Palette.amber)
            divider
            macroCell("GRASSI", totals.f, Palette.crimson)
        }
        .padding(.vertical, 12)
        .voltPanel()
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(width: 1, height: 30)
    }

    private func macroCell(_ label: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(label).font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            Text(value.rounded().formatted(.number.grouping(.never)))
                .font(Typo.mono(bold ? 18 : 15, .bold)).foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.snappy, value: value.rounded())
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
            Text("Costruisci il piano")
                .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Text("Aggiungi i pasti e poi gli alimenti dal database con le grammature: i macro si calcolano da soli.")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(18).voltPanel()
    }

    private func remove(_ id: UUID) {
        Haptics.warning()
        withAnimation(.snappy) { meals.removeAll { $0.id == id } }
    }
}

private struct WBMealCard: View {
    @Binding var meal: WBMealDraft
    let accent: Color
    let onAddFood: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var confirmCenter: ConfirmCenter

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("", text: $meal.name,
                          prompt: Text("Nome pasto").foregroundStyle(Palette.textLow))
                    .font(Typo.display(18)).foregroundStyle(Palette.textHi).tint(accent)
                Spacer(minLength: 4)
                if meal.kcal > 0 {
                    Text("\(Int(meal.kcal.rounded())) kcal")
                        .font(Typo.mono(11, .semibold)).foregroundStyle(accent)
                }
                Button {
                    Haptics.tap()
                    Task {
                        if await confirmCenter.confirm(.init(
                            title: "Eliminare il pasto?",
                            subtitle: "\"\(meal.name)\" e tutti i suoi alimenti verranno rimossi.",
                            icon: "trash")) {
                            onDelete()
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.crimson.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)

            Rectangle().fill(Palette.line).frame(height: 1)

            if meal.items.isEmpty {
                Text("Nessun alimento — cercane uno nel database.")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ForEach($meal.items) { $item in
                    WBFoodRow(item: $item, accent: accent,
                              onDelete: { removeItem(item.id) })
                    if item.id != meal.items.last?.id {
                        Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            Rectangle().fill(Palette.line).frame(height: 1)

            Button { Haptics.tap(); onAddFood() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Aggiungi alimento")
                }
                .font(Typo.body(13, .semibold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .voltPanel()
    }

    private func removeItem(_ id: UUID) {
        Haptics.warning()
        withAnimation(.snappy) { meal.items.removeAll { $0.id == id } }
    }
}

private struct WBFoodRow: View {
    @Binding var item: WBItemDraft
    let accent: Color
    let onDelete: () -> Void

    @EnvironmentObject private var confirmCenter: ConfirmCenter
    @State private var showSubs = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.food.name)
                        .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                        .lineLimit(2)
                    if !item.substitutions.isEmpty {
                        Text("\(item.substitutions.count) alt")
                            .font(Typo.mono(9, .semibold)).foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                    }
                }
                Text("\(Int(item.kcal.rounded())) kcal · P \(fmt(item.protein)) · C \(fmt(item.carb)) · G \(fmt(item.fat))")
                    .font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
            }
            Spacer(minLength: 6)

            // substitutions
            Button { Haptics.tap(); showSubs = true } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(item.substitutions.isEmpty ? Palette.textLow : accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(item.substitutions.isEmpty ? Palette.void2 : accent.opacity(0.14)))
            }
            .buttonStyle(.plain)

            // grams stepper
            HStack(spacing: 0) {
                Button { bump(-10) } label: {
                    Image(systemName: "minus").frame(width: 28, height: 30)
                }
                Text("\(Int(item.grams))g")
                    .font(Typo.mono(12, .bold)).foregroundStyle(accent)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                Button { bump(10) } label: {
                    Image(systemName: "plus").frame(width: 28, height: 30)
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.textMid)
            .buttonStyle(.plain)
            .voltPanel(radius: 10)

            Button {
                Haptics.tap()
                Task {
                    if await confirmCenter.confirm(.init(
                        title: "Eliminare l'alimento?",
                        subtitle: "\"\(item.food.name)\" verrà rimosso dal pasto.",
                        icon: "trash")) {
                        onDelete()
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textLow)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .sheet(isPresented: $showSubs) {
            SubstitutionSheet(item: $item, accent: accent)
        }
    }

    private func bump(_ delta: Double) {
        Haptics.tap()
        withAnimation(.snappy) { item.grams = max(5, item.grams + delta) }
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
    }
}

// MARK: - Substitutions (iso-kcal / iso-prot / iso-carb), parity with web

private struct SubstitutionSheet: View {
    @Binding var item: WBItemDraft
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var mode = "ISOKCAL"
    @State private var query = ""
    @State private var results: [BuilderFood] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorText: String?

    private let modes = [("ISOKCAL", "iso-kcal"), ("ISOPROT", "iso-prot"), ("ISOCARB", "iso-carb")]

    enum Tab { case active, add }

    init(item: Binding<WBItemDraft>, accent: Color) {
        self._item = item
        self.accent = accent
        self._tab = State(initialValue: item.wrappedValue.substitutions.isEmpty ? .add : .active)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text("Attive (\(item.substitutions.count))").tag(Tab.active)
                    Text("Aggiungi").tag(Tab.add)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if tab == .active {
                    activeList
                } else {
                    addSearch
                }
            }
            .padding(.top, 8)
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Sostituzioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .onChange(of: query) { _, _ in scheduleSearch() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var activeList: some View {
        if item.substitutions.isEmpty {
            Spacer()
            Text("Nessuna sostituzione attiva. Passa a \"Aggiungi\" per proporne una.")
                .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(item.substitutions.enumerated()), id: \.offset) { idx, sub in
                        existingRow(sub, idx)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
    }

    private var addSearch: some View {
        VStack(spacing: 12) {
            // mode picker
            HStack(spacing: 8) {
                ForEach(modes, id: \.0) { key, label in
                    Button {
                        Haptics.tap(); mode = key
                    } label: {
                        Text(label)
                            .font(Typo.body(12, .semibold))
                            .foregroundStyle(mode == key ? Palette.void0 : Palette.textMid)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(mode == key ? accent : Palette.void2))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            VoltField(icon: "magnifyingglass", placeholder: "Cerca sostituto…",
                      text: $query, accent: accent)
                .padding(.horizontal, 16)

            if let errorText {
                Text(errorText).font(Typo.body(12)).foregroundStyle(Palette.crimson)
                    .padding(.horizontal, 16)
            }

            if loading && results.isEmpty {
                Spacer(); SwiftUI.ProgressView().tint(accent); Spacer()
            } else if results.isEmpty {
                Spacer()
                Text(query.isEmpty ? "Cerca un alimento da proporre come alternativa."
                                   : "Nessun alimento trovato.")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { food in
                            Button { add(food) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(food.name).font(Typo.body(14, .semibold))
                                            .foregroundStyle(Palette.textHi).multilineTextAlignment(.leading)
                                        Text("\(Int(food.kcal.rounded())) kcal · P \(Int(food.protein.rounded())) · C \(Int(food.carb.rounded())) · G \(Int(food.fat.rounded()))  /100g")
                                            .font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18, weight: .bold)).foregroundStyle(accent)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .voltPanel(radius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func existingRow(_ sub: [String: Any], _ idx: Int) -> some View {
        let name = sub["food_name"] as? String ?? "Alimento"
        let g = numd(sub["quantity_g"])
        let m = sub["mode"] as? String ?? ""
        HStack(spacing: 10) {
            Text(modeLabel(m)).font(Typo.mono(9, .bold)).foregroundStyle(accent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                Text("\(Int(g))g").font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
            }
            Spacer(minLength: 4)
            Button {
                Haptics.warning()
                withAnimation(.snappy) {
                    if idx < item.substitutions.count { item.substitutions.remove(at: idx) }
                }
            } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.crimson.opacity(0.8)).frame(width: 28, height: 28)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .voltPanel(radius: 12)
    }

    private func modeLabel(_ m: String) -> String {
        m == "ISOKCAL" ? "iso-kcal" : m == "ISOPROT" ? "iso-prot" : m == "ISOCARB" ? "iso-carb" : m
    }

    private func numd(_ v: Any?) -> Double {
        (v as? Double) ?? (v as? Int).map(Double.init) ?? 0
    }

    /// Mirrors the web computeSubGrams: keep the chosen macro constant.
    private func computeGrams(_ food: BuilderFood) -> Double? {
        let q = item.grams
        func round5(_ g: Double) -> Double { max(5, (g / 5).rounded() * 5) }
        switch mode {
        case "ISOKCAL":
            guard food.kcal > 0 else { return nil }
            return round5(item.food.kcal * q / 100 / food.kcal * 100)
        case "ISOPROT":
            guard food.protein > 0 else { return nil }
            return round5(item.food.protein * q / 100 / food.protein * 100)
        case "ISOCARB":
            guard food.carb > 0 else { return nil }
            return round5(item.food.carb * q / 100 / food.carb * 100)
        default: return nil
        }
    }

    private func add(_ food: BuilderFood) {
        guard let grams = computeGrams(food) else {
            errorText = "Sostituzione non applicabile: macro target a zero."
            return
        }
        errorText = nil
        Haptics.soft()
        withAnimation(.snappy) {
            item.substitutions.append([
                "food_id": food.id,
                "food_name": food.name,
                "mode": mode,
                "quantity_g": grams,
                "kcal_per_100g": food.kcal,
                "protein_per_100g": food.protein,
                "carb_per_100g": food.carb,
                "fat_per_100g": food.fat,
            ])
            tab = .active
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        loading = true; defer { loading = false }
        let resp = try? await APIClient.shared.coachSearchFoods(query: query)
        guard !Task.isCancelled else { return }
        results = resp?.results ?? []
    }
}

// MARK: - Shared stepper pills

private struct WBStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            HStack(spacing: 0) {
                Button { adjust(-step) } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity).frame(height: 34)
                }
                Text("\(value)")
                    .font(Typo.mono(15, .bold)).foregroundStyle(Palette.textHi)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                Button { adjust(step) } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity).frame(height: 34)
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


// MARK: - Exercise picker sheet

struct ExercisePickerSheet: View {
    let accent: Color
    let onPick: (BuilderExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BuilderExercise] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VoltField(icon: "magnifyingglass", placeholder: "Cerca esercizio…",
                          text: $query, accent: accent)
                    .padding(.horizontal, 16).padding(.top, 8)

                if loading && results.isEmpty {
                    Spacer(); SwiftUI.ProgressView().tint(accent); Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(query.isEmpty ? "Scrivi per cercare nel database esercizi."
                                       : "Nessun esercizio trovato.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { ex in
                                Button {
                                    onPick(ex)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(ex.name)
                                                .font(Typo.body(15, .semibold))
                                                .foregroundStyle(Palette.textHi)
                                                .multilineTextAlignment(.leading)
                                            HStack(spacing: 8) {
                                                if let m = ex.targetMuscleGroup, !m.isEmpty {
                                                    Text(m.uppercased())
                                                        .font(Typo.mono(9, .semibold)).tracking(1.5)
                                                        .foregroundStyle(accent)
                                                }
                                                if !ex.equipment.isEmpty {
                                                    Text(ex.equipment.map { $0.nameIt }.joined(separator: " · ").uppercased())
                                                        .font(Typo.mono(9, .semibold)).tracking(1.5)
                                                        .foregroundStyle(Palette.textLow)
                                                }
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(accent)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .voltPanel(radius: 13)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Database esercizi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .task { await search() }
        }
        .presentationDetents([.large])
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        loading = true; defer { loading = false }
        let found = (try? await APIClient.shared.coachSearchExercises(query: query)) ?? []
        guard !Task.isCancelled else { return }
        results = found
    }
}

// MARK: - Food picker sheet

struct FoodPickerSheet: View {
    let accent: Color
    let onPick: (BuilderFood, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BuilderFood] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selected: BuilderFood?
    @State private var grams: Double = 100
    @State private var filter = "all"        // all | cat | recent
    @State private var categories: [String] = []
    @State private var activeCat = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VoltField(icon: "magnifyingglass", placeholder: "Cerca alimento…",
                          text: $query, accent: accent)
                    .padding(.horizontal, 16).padding(.top, 8)

                // Filter chips: Tutti / Categorie / Recenti
                HStack(spacing: 8) {
                    ForEach([("all", "Tutti"), ("cat", "Categorie"), ("recent", "Recenti")], id: \.0) { key, label in
                        Button {
                            Haptics.tap()
                            filter = key; activeCat = ""; results = []
                            scheduleSearch(immediate: true)
                        } label: {
                            Text(label)
                                .font(Typo.body(12, .semibold))
                                .foregroundStyle(filter == key ? Palette.void0 : Palette.textMid)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(filter == key ? accent : Palette.void2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Back to categories (when a category is open)
                if filter == "cat" && !activeCat.isEmpty {
                    Button {
                        Haptics.tap()
                        activeCat = ""; results = []
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text(activeCat).font(Typo.body(13, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }

                if filter == "cat" && activeCat.isEmpty {
                    // Category list — one per row, alphabetical, filtered by search
                    if filteredCategories.isEmpty {
                        Spacer()
                        Text(categories.isEmpty ? "Caricamento categorie…" : "Nessuna categoria trovata.")
                            .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredCategories, id: \.self) { cat in
                                    categoryRow(cat)
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 24)
                        }
                    }
                } else if loading && results.isEmpty {
                    Spacer(); SwiftUI.ProgressView().tint(accent); Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(emptyText)
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { food in
                                foodRow(food)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Banca dati alimenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .task { if results.isEmpty { await search() } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func foodRow(_ food: BuilderFood) -> some View {
        let isSel = selected?.id == food.id
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) {
                    selected = isSel ? nil : food
                    grams = 100
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name)
                            .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                            .multilineTextAlignment(.leading)
                        Text("\(Int(food.kcal.rounded())) kcal · P \(Int(food.protein.rounded())) · C \(Int(food.carb.rounded())) · G \(Int(food.fat.rounded()))  /100g")
                            .font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isSel ? "chevron.up" : "plus.circle.fill")
                        .font(.system(size: isSel ? 13 : 20, weight: .bold))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSel {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200], id: \.self) { g in
                            Button {
                                Haptics.tap()
                                withAnimation(.snappy) { grams = Double(g) }
                            } label: {
                                Text("\(g)g")
                                    .font(Typo.mono(12, .bold))
                                    .foregroundStyle(grams == Double(g) ? Palette.void0 : Palette.textMid)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Capsule().fill(grams == Double(g) ? accent : Palette.void2))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        Button { Haptics.tap(); grams = max(5, grams - 10) } label: {
                            Image(systemName: "minus").frame(width: 38, height: 34)
                        }
                        Text("\(Int(grams))g")
                            .font(Typo.mono(15, .bold)).foregroundStyle(accent)
                            .frame(minWidth: 56)
                            .contentTransition(.numericText())
                        Button { Haptics.tap(); grams += 10 } label: {
                            Image(systemName: "plus").frame(width: 38, height: 34)
                        }
                        Spacer()
                        Button {
                            onPick(food, grams)
                            dismiss()
                        } label: {
                            Text("Aggiungi")
                                .font(Typo.body(14, .semibold)).foregroundStyle(Palette.void0)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(Capsule().fill(accent))
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textMid)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .voltPanel(isSel ? accent.opacity(0.5) : Palette.line, radius: 13)
    }

    private var filteredCategories: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? categories : categories.filter { $0.lowercased().contains(q) }
        return base.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func categoryRow(_ cat: String) -> some View {
        Button {
            Haptics.tap()
            activeCat = cat
            scheduleSearch(immediate: true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                Text(cat)
                    .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textMid)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voltPanel(Palette.line, radius: 13)
    }

    private var emptyText: String {
        if filter == "recent" { return "Nessun alimento recente." }
        if filter == "cat" && activeCat.isEmpty { return "Scegli una categoria." }
        return query.isEmpty ? "Cerca nella banca dati o scegli un filtro." : "Nessun alimento trovato."
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        // In Categorie mode we wait for a category to be chosen.
        if filter == "cat" && activeCat.isEmpty && categories.isEmpty {
            // first load → fetch categories
        } else if filter == "cat" && activeCat.isEmpty {
            results = []; return
        }
        loading = true; defer { loading = false }
        let resp = try? await APIClient.shared.coachSearchFoods(
            query: query,
            filter: filter == "recent" ? "recent" : nil,
            cat: filter == "cat" ? activeCat : nil,
            includeCats: filter == "cat" && categories.isEmpty)
        guard !Task.isCancelled else { return }
        if let cats = resp?.categories { categories = cats }
        // Don't dump foods under Categorie until a category is picked.
        if filter == "cat" && activeCat.isEmpty {
            results = []
        } else {
            results = resp?.results ?? []
        }
    }
}
