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
    @State private var plan: CoachWorkoutDetailDTO?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            if let p = plan {
                header(title: p.title,
                       subtitle: [p.goal, p.level].compactMap { $0 }.joined(separator: " · "),
                       chips: [p.planKind, p.durationWeeks.map { "\($0) sett." },
                               p.frequencyPerWeek.map { "\($0)x/sett" }].compactMap { $0 },
                       accent: Palette.cyan)
                if let d = p.description, !d.isEmpty { noteCard(d) }
                if p.days.isEmpty {
                    EmptyPanel(icon: "dumbbell", text: "Nessun giorno in questa scheda.")
                } else {
                    ForEach(p.days) { day in dayCard(day) }
                }
            } else if loading {
                LoadingPanel()
            } else {
                EmptyPanel(icon: "exclamationmark.triangle", text: "Scheda non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { plan = try? await APIClient.shared.coachWorkoutDetail(planId: planId); loading = false }
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
    @State private var plan: CoachNutritionDetailDTO?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            if let p = plan {
                header(title: p.title,
                       subtitle: [p.planMode, p.planKind].compactMap { $0 }.joined(separator: " · "),
                       chips: [p.dailyKcal.map { "\($0) kcal" }].compactMap { $0 },
                       accent: Palette.lime)
                macroBar(p.totals)
                if let d = p.description, !d.isEmpty { noteCard(d) }
                if p.meals.isEmpty {
                    EmptyPanel(icon: "fork.knife", text: "Nessun pasto in questo piano.")
                } else {
                    ForEach(p.meals) { meal in mealCard(meal) }
                }
            } else if loading {
                LoadingPanel()
            } else {
                EmptyPanel(icon: "exclamationmark.triangle", text: "Piano non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { plan = try? await APIClient.shared.coachNutritionDetail(planId: planId); loading = false }
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
