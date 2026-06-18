//
//  CoachPlanDetailViews.swift
//  Read-only detail of a workout / nutrition plan — the full structure (days,
//  exercises / meals, items, macros) the coach taps into from the library.
//

import SwiftUI

// MARK: - Route

enum CoachPlanRoute: Hashable {
    case workout(Int)
    case nutrition(Int)
}

// MARK: - Workout detail

struct CoachWorkoutDetailView: View {
    let planId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var plan: CoachWorkoutDetailDTO?
    @State private var loading = true
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        ScreenScroll {
            if let p = plan {
                header(title: p.title,
                       subtitle: [p.goal, p.level].compactMap { $0 }.joined(separator: " · "),
                       chips: [p.planKind == "PROGRAM" ? "Programmazione" : "Settimanale",
                               p.durationWeeks.map { "\($0) sett." },
                               p.frequencyPerWeek.map { "\($0)x/sett" }].compactMap { $0 },
                       accent: Palette.cyan)
                if let d = p.description, !d.isEmpty { noteCard(d) }
                if p.days.isEmpty {
                    EmptyPanel(icon: "dumbbell", text: "Nessun giorno in questa scheda.")
                } else {
                    ForEach(p.days) { day in dayCard(day) }
                }
            } else if loading {
                CoachPlanDetailSkeleton(accent: Palette.cyan)
            } else {
                EmptyPanel(icon: "exclamationmark.triangle", text: "Scheda non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { editing = true } label: { Label("Modifica", systemImage: "pencil") }
                Button { Task { await duplicatePlan() } } label: { Label("Duplica", systemImage: "doc.on.doc") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Elimina", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").tint(Palette.cyan)
            }
            .disabled(plan == nil || deleting)
        } }
        .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) {
            CoachWorkoutWizardView(planId: planId)
        }
        .confirmationDialog("Eliminare questa scheda?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina scheda", role: .destructive) { Task { await deletePlan() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verrà rimossa anche dagli atleti a cui è assegnata.")
        }
        .task { await load() }
    }

    private func load() async {
        plan = try? await APIClient.shared.coachWorkoutDetail(planId: planId)
        loading = false
    }

    private func deletePlan() async {
        deleting = true; defer { deleting = false }
        do {
            try await APIClient.shared.coachDeleteWorkoutPlan(planId: planId)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    private func duplicatePlan() async {
        deleting = true; defer { deleting = false }
        do {
            _ = try await APIClient.shared.coachDuplicateWorkoutPlan(planId: planId)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    private func dayCard(_ day: CoachWorkoutDayDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.name).font(Typo.body(16, .bold)).foregroundStyle(Palette.textHi)
                Spacer()
                if let f = day.focus, !f.isEmpty {
                    Text(f.uppercased()).font(Typo.mono(9, .semibold)).tracking(1)
                        .foregroundStyle(Palette.cyan)
                }
            }
            ForEach(day.exercises) { ex in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Palette.cyan.opacity(0.5)).frame(width: 6, height: 6).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                        if !ex.prescription.isEmpty {
                            Text(ex.prescription).font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                        }
                    }
                    Spacer()
                }
            }
            if let n = day.notes, !n.isEmpty {
                Text(n).font(Typo.body(12)).foregroundStyle(Palette.textLow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }
}

// MARK: - Nutrition detail

struct CoachNutritionDetailView: View {
    let planId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var plan: CoachNutritionDetailDTO?
    @State private var loading = true
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        ScreenScroll {
            if let p = plan {
                header(title: p.title,
                       subtitle: [p.planMode == "MACRO" ? "Macronutrienti" : "Alimenti",
                                  p.planKind == "WEEKLY" ? "Settimanale" : "Giornaliero"]
                           .joined(separator: " · "),
                       chips: [p.dailyKcal.map { "\($0) kcal" }].compactMap { $0 },
                       accent: Palette.lime)
                if p.planMode == "MACRO" {
                    macroTargetsSection(p)
                } else {
                    macroBar(p.totals)
                }
                if let d = p.description, !d.isEmpty { noteCard(d) }
                if p.planMode == "MACRO" {
                    EmptyView()
                } else if p.meals.isEmpty {
                    EmptyPanel(icon: "fork.knife", text: "Nessun pasto in questo piano.")
                } else if p.planKind == "WEEKLY" {
                    weeklyMeals(p.meals)
                } else {
                    ForEach(p.meals) { meal in mealCard(meal) }
                }
            } else if loading {
                CoachPlanDetailSkeleton(accent: Palette.lime)
            } else {
                EmptyPanel(icon: "exclamationmark.triangle", text: "Piano non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { editing = true } label: { Label("Modifica", systemImage: "pencil") }
                Button { Task { await duplicatePlan() } } label: { Label("Duplica", systemImage: "doc.on.doc") }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Elimina", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").tint(Palette.lime)
            }
            .disabled(plan == nil || deleting)
        } }
        .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) {
            CoachNutritionWizardView(planId: planId)
        }
        .confirmationDialog("Eliminare questo piano?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina piano", role: .destructive) { Task { await deletePlan() } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Verrà rimosso anche dagli atleti a cui è assegnato.")
        }
        .task { await load() }
    }

    private func load() async {
        plan = try? await APIClient.shared.coachNutritionDetail(planId: planId)
        loading = false
    }

    private func deletePlan() async {
        deleting = true; defer { deleting = false }
        do {
            try await APIClient.shared.coachDeleteNutritionPlan(planId: planId)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    private func duplicatePlan() async {
        deleting = true; defer { deleting = false }
        do {
            _ = try await APIClient.shared.coachDuplicateNutritionPlan(planId: planId)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    /// WEEKLY FOOD plans: meals grouped per weekday in fixed LUN→DOM order.
    private func weeklyMeals(_ meals: [CoachMealDTO]) -> some View {
        let order = ["LUN", "MAR", "MER", "GIO", "VEN", "SAB", "DOM"]
        let names = ["LUN": "Lunedì", "MAR": "Martedì", "MER": "Mercoledì", "GIO": "Giovedì",
                     "VEN": "Venerdì", "SAB": "Sabato", "DOM": "Domenica"]
        let grouped = Dictionary(grouping: meals) { $0.dayOfWeek ?? "" }
        return ForEach(order.filter { grouped[$0] != nil }, id: \.self) { day in
            VStack(alignment: .leading, spacing: 10) {
                Text((names[day] ?? day).uppercased())
                    .font(Typo.mono(11, .semibold)).tracking(2).foregroundStyle(Palette.lime)
                ForEach(grouped[day] ?? []) { meal in mealCard(meal) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// MACRO plans: the prescribed targets (plan-level or per-day).
    @ViewBuilder
    private func macroTargetsSection(_ p: CoachNutritionDetailDTO) -> some View {
        if p.planKind == "WEEKLY", let targets = p.dayTargets, !targets.isEmpty {
            let names = ["LUN": "Lunedì", "MAR": "Martedì", "MER": "Mercoledì", "GIO": "Giovedì",
                         "VEN": "Venerdì", "SAB": "Sabato", "DOM": "Domenica"]
            ForEach(targets) { t in
                HStack(spacing: 10) {
                    Text(names[t.dayOfWeek] ?? t.dayOfWeek)
                        .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                        .frame(width: 90, alignment: .leading)
                    Spacer()
                    targetCell(t.kcal, "kcal", Palette.amber)
                    targetCell(t.protein, "P", Palette.cyan)
                    targetCell(t.carb, "C", Palette.lime)
                    targetCell(t.fat, "G", Palette.phase)
                }
                .padding(.horizontal, 14).padding(.vertical, 12).voltPanel()
            }
        } else {
            macroBar(CoachMacros(kcal: Double(p.dailyKcal ?? 0),
                                 protein: Double(p.proteinTargetG ?? 0),
                                 carb: Double(p.carbTargetG ?? 0),
                                 fat: Double(p.fatTargetG ?? 0)))
        }
    }

    private func targetCell(_ v: Int?, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v.map(String.init) ?? "—").font(Typo.mono(12, .bold)).foregroundStyle(c)
            Text(l).font(Typo.mono(8, .semibold)).foregroundStyle(Palette.textLow)
        }
        .frame(minWidth: 38)
    }

    private func macroBar(_ m: CoachMacros) -> some View {
        HStack(spacing: 10) {
            macro("\(Int(m.kcal))", "kcal", Palette.amber)
            macro("\(Int(m.protein))g", "Pro", Palette.cyan)
            macro("\(Int(m.carb))g", "Carb", Palette.lime)
            macro("\(Int(m.fat))g", "Fat", Palette.phase)
        }
    }
    private func macro(_ v: String, _ l: String, _ a: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(Typo.poster(20)).foregroundStyle(a).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(Typo.mono(9, .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).voltPanel(radius: 14)
    }

    private func mealCard(_ meal: CoachMealDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meal.name).font(Typo.body(16, .bold)).foregroundStyle(Palette.textHi)
            ForEach(meal.items) { it in
                HStack {
                    Text(it.name).font(Typo.body(14)).foregroundStyle(Palette.textHi).lineLimit(1)
                    Spacer(minLength: 8)
                    if let q = it.quantityG {
                        Text("\(Int(q)) g").font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
                    }
                    if let k = it.kcal {
                        Text("· \(Int(k)) kcal").font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                    }
                }
            }
            if let n = meal.notes, !n.isEmpty {
                Text(n).font(Typo.body(12)).foregroundStyle(Palette.textLow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }
}

// MARK: - Shared bits

private func header(title: String, subtitle: String, chips: [String], accent: Color) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).font(Typo.poster(30)).foregroundStyle(Palette.textHi)
            .fixedSize(horizontal: false, vertical: true)
        if !subtitle.isEmpty {
            Text(subtitle).font(Typo.body(14)).foregroundStyle(Palette.textMid)
        }
        if !chips.isEmpty {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    Text(c).font(Typo.mono(10, .semibold)).tracking(1)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                }
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func noteCard(_ text: String) -> some View {
    Text(text).font(Typo.body(14)).foregroundStyle(Palette.textMid)
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
}
