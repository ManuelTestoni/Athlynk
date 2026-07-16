//
//  NutritionPlanDetailView.swift
//  "La dieta intera" — full detail of one nutrition plan, opened by tapping its
//  card in NutritionView. Mobile translation of the web app's piano_detail.html
//  (day/meal filter + weekly table): a vertical day-list with a meal-type
//  filter row stands in for the web "Tabella" grid, which doesn't fit a phone.
//

import SwiftUI

struct NutritionPlanDetailView: View {
    let plan: NutritionPlanDTO
    @State private var mealFilter: String?
    @State private var appear = false

    private var days: [DietDayDTO] { DietWeekday.sorted(plan.days) }

    /// Distinct meal time-slots across the plan, in first-seen order.
    private var mealTypes: [String] {
        var seen = Set<String>(); var out: [String] = []
        for d in plan.days {
            for m in d.meals {
                if let t = m.timeOfDay, !t.isEmpty, seen.insert(t).inserted { out.append(t) }
            }
        }
        return out
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header.revealUp(appear, index: 0)
                    content
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("TARGET GIORNALIERO")
                    .font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                Spacer()
                Text("\(plan.dailyKcal ?? 0)").font(Typo.poster(28)).foregroundStyle(Palette.lime)
                Text("kcal").font(Typo.mono(11, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            }
            Rectangle().fill(Palette.lime).frame(height: 1).opacity(0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (plan.planMode, plan.planKind) {
        case ("MACRO", "WEEKLY"): macroWeeklyList
        case ("MACRO", _):        macroDailySummary
        case (_, "WEEKLY"):       foodWeeklyList
        default:                  foodDailyList
        }
    }

    // MARK: FOOD + WEEKLY — day blocks + meal-type filter

    private var foodWeeklyList: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !mealTypes.isEmpty { filterChips.revealUp(appear, index: 1) }
            ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                dayBlock(day).revealUp(appear, index: i + 2)
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, label: "Tutti")
                ForEach(mealTypes, id: \.self) { t in filterChip(t, label: t) }
            }
        }
    }

    private func filterChip(_ value: String?, label: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { mealFilter = value }
        } label: {
            Text(label)
                .font(Typo.body(12, .semibold))
                .foregroundStyle(mealFilter == value ? Palette.void0 : Palette.textMid)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(mealFilter == value ? Palette.lime : Palette.void2))
        }
        .buttonStyle(.plain)
    }

    private func dayBlock(_ day: DietDayDTO) -> some View {
        let meals = mealFilter == nil ? day.meals : day.meals.filter { $0.timeOfDay == mealFilter }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((DietWeekday.long[day.dayOfWeek] ?? day.dayOfWeek).uppercased())
                    .font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Spacer()
                Text("\(Int(day.meals.reduce(0) { $0 + $1.kcal })) kcal")
                    .font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime)
            }
            if meals.isEmpty {
                Text(mealFilter == nil ? "Nessun pasto previsto" : "Nessun pasto in questa fascia")
                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
            } else {
                ForEach(meals) { meal in
                    NavigationLink(value: meal) { mealRow(meal) }
                        .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(16).voltPanel(Palette.lime.opacity(0.3))
    }

    // MARK: FOOD + DAILY — flat meal list

    private var foodDailyList: some View {
        let meals = plan.days.first?.meals ?? []
        return VStack(alignment: .leading, spacing: 10) {
            if meals.isEmpty {
                EmptyPanel(icon: "fork.knife", text: "Nessun pasto previsto per questo piano.", color: Palette.lime)
            } else {
                ForEach(meals) { meal in
                    NavigationLink(value: meal) { mealRow(meal) }
                        .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }

    private func mealRow(_ meal: MealDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                if let t = meal.timeOfDay, !t.isEmpty {
                    Text(t).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            Text("\(Int(meal.kcal)) kcal").font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(.vertical, 10).padding(.horizontal, 12).voltPanel(radius: 12)
    }

    // MARK: MACRO + WEEKLY — target per weekday, opens that day's diary

    private var macroWeeklyList: some View {
        let weekDates = DietWeekday.thisWeekISODates()
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                NavigationLink {
                    MacroLogView(assignmentId: plan.assignmentId, planTitle: plan.title,
                                 logDate: DietWeekday.isoDate(for: day.dayOfWeek), weekDates: weekDates)
                } label: { macroDayRow(day) }
                    .buttonStyle(PressableButtonStyle())
                    .revealUp(appear, index: i + 1)
            }
        }
    }

    private func macroDayRow(_ day: DietDayDTO) -> some View {
        HStack(spacing: 12) {
            Text((DietWeekday.long[day.dayOfWeek] ?? day.dayOfWeek).uppercased())
                .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Spacer()
            Text("\(day.targetKcal ?? 0) kcal").font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(14).voltPanel(Palette.lime.opacity(0.3))
    }

    // MARK: MACRO + DAILY — single target summary

    private var macroDailySummary: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                macroCol("PRO", plan.proteinTargetG, Palette.magenta)
                macroCol("CARB", plan.carbTargetG, Palette.cyan)
                macroCol("FAT", plan.fatTargetG, Palette.amber)
            }
            NavigationLink {
                MacroLogView(assignmentId: plan.assignmentId, planTitle: plan.title)
            } label: {
                HStack {
                    Text("Apri il diario di oggi").font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textLow)
                }
                .padding(14).voltPanel(Palette.lime.opacity(0.3))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .revealUp(appear, index: 1)
    }

    private func macroCol(_ label: String, _ grams: Int?, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(grams.map { "\($0)g" } ?? "—")
                .font(Typo.mono(18, .black)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }
}
