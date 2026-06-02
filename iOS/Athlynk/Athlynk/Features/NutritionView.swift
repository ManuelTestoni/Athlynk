//
//  NutritionView.swift
//  Active nutrition plan: macro target rings + meal breakdown.
//

import SwiftUI

struct NutritionView: View {
    @State private var plans: [NutritionPlanDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 6) {
                Text("CARBURANTE").voltEyebrow()
                GlitchText(text: "FUEL", size: 56)
            }
            .revealUp(appear, index: 0)

            if loading {
                LoadingPanel(text: "Carico il piano…")
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.lime)
            } else if let plan = plans.first {
                macroBoard(plan).revealUp(appear, index: 1)
                mealsSection(plan)
            } else {
                EmptyPanel(icon: "fork.knife", text: "Nessun piano nutrizionale attivo.")
            }
        }
        .onAppear { appear = true }
        .task { await load() }
        .refreshable { await load() }
    }

    private func macroBoard(_ plan: NutritionPlanDTO) -> some View {
        let kcal = plan.dailyKcal ?? dayTotalsKcal(plan)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title).font(Typo.display(22)).foregroundStyle(Palette.textHi)
                    Text(plan.planMode == "MACRO" ? "MODALITÀ MACRO" : "MODALITÀ ALIMENTI")
                        .font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.lime)
                }
                Spacer()
                if let coach = plan.coach { CoachChip(coach: coach, color: Palette.lime) }
            }

            HStack(alignment: .top, spacing: 0) {
                bigKcal(kcal)
                Divider().frame(height: 70).overlay(Palette.line)
                VStack(spacing: 12) {
                    macroBar("PROTEINE", plan.proteinTargetG, Palette.magenta)
                    macroBar("CARBO", plan.carbTargetG, Palette.cyan)
                    macroBar("GRASSI", plan.fatTargetG, Palette.amber)
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 16)
            }
        }
        .padding(18)
        .voltPanel(Palette.lime.opacity(0.4))
    }

    private func bigKcal(_ kcal: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RollingNumber(value: kcal, size: 44, color: Palette.lime)
            Text("KCAL / GIORNO").font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
        }
        .frame(width: 130, alignment: .leading)
    }

    private func macroBar(_ label: String, _ grams: Int?, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Typo.mono(9, .bold)).tracking(1)
                .foregroundStyle(Palette.textMid).frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.void2)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * fraction(grams))
                        .neonGlow(color, radius: 5)
                }
            }
            .frame(height: 7)
            Text(grams.map { "\($0)g" } ?? "—")
                .font(Typo.mono(12, .bold)).foregroundStyle(Palette.textHi)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func fraction(_ g: Int?) -> CGFloat {
        guard let g else { return 0 }
        return min(CGFloat(g) / 300.0, 1)   // visual scale only
    }

    @ViewBuilder
    private func mealsSection(_ plan: NutritionPlanDTO) -> some View {
        let meals = plan.days.first?.meals ?? []
        if !meals.isEmpty {
            Text("PASTI").voltEyebrow().padding(.top, 6).revealUp(appear, index: 2)
            ForEach(Array(meals.enumerated()), id: \.element.id) { i, meal in
                mealCard(meal, index: i).revealUp(appear, index: i + 3)
            }
        }
    }

    private func mealCard(_ meal: MealDTO, index: Int) -> some View {
        let accent = Palette.accent(index)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meal.name).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                if let t = meal.timeOfDay {
                    Text(t).font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                }
                Spacer()
                Text("\(Int(meal.kcal)) kcal")
                    .font(Typo.mono(13, .bold)).foregroundStyle(accent)
            }
            ForEach(meal.items) { item in
                HStack {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text(item.name ?? "—").font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    Spacer()
                    Text("\(Int(item.quantityG))g")
                        .font(Typo.mono(12)).foregroundStyle(Palette.textMid)
                }
            }
        }
        .padding(16)
        .voltPanel(accent.opacity(0.35))
    }

    private func dayTotalsKcal(_ plan: NutritionPlanDTO) -> Int {
        Int((plan.days.first?.meals.reduce(0) { $0 + $1.kcal }) ?? 0)
    }

    private func load() async {
        loading = true; error = nil
        do { plans = try await APIClient.shared.nutrition() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
