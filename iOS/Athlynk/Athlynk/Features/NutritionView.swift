//
//  NutritionView.swift
//  Stitch "Piani Nutrizionali": plan summary cards (ATTIVO badge, daily target,
//  macro split, Pro/Car/Fat columns) + meal breakdown for the active plan.
//

import SwiftUI

struct NutritionView: View {
    @EnvironmentObject var app: AppState
    @Binding var path: NavigationPath
    @State private var plans: [NutritionPlanDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false
    @State private var loadToken = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Alimentazione",
                             title: "I TUOI\nPIANI",
                             subtitle: "I tuoi piani nutrizionali attivi e i target giornalieri di macro.",
                             initials: initials,
                             accent: Palette.lime)
                    .revealUp(appear, index: 0)

                NavigationLink { SupplementsView() } label: { supplementsLink }
                    .buttonStyle(PressableButtonStyle())
                    .revealUp(appear, index: 1)

                if loading {
                    NutritionSkeleton()
                } else if let error {
                    EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                } else if plans.isEmpty {
                    EmptyPanel(icon: "fork.knife", text: "Non hai ancora una dieta. Chiedi al tuo coach o nutrizionista di assegnartene una.")
                } else {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { i, plan in
                        planCard(plan, active: i == 0).revealUp(appear, index: i + 2)
                    }
                    if let plan = plans.first {
                        if plan.planMode == "MACRO" {
                            macroDiaryLink(plan).revealUp(appear, index: 2)
                            macroHistoryLink(plan).revealUp(appear, index: 3)
                        } else if plan.planKind == "WEEKLY" {
                            weekCarousel(plan)
                        } else {
                            mealsSection(plan)
                        }
                    }
                }
            }
            .navigationDestination(for: MealDTO.self) { meal in
                MealDetailView(meal: meal)
            }
            .navigationDestination(for: DietDayDTO.self) { day in
                DietDayDetailView(day: day)
            }
        }
        .tint(Palette.lime)
        .onAppear { appear = true }
        .task(id: loadToken) { await load() }
        .refreshable { await load(force: true) }
        .onRemoteChange(["NUTRITION_ASSIGNED", "SUPPLEMENT_ASSIGNED"]) { plans = []; loadToken = UUID() }
    }

    private var supplementsLink: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.amber.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "pills.fill")
                    .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.amber)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Integratori").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                Text("Il tuo protocollo")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                .foregroundStyle(Palette.amber)
        }
        .padding(16).voltPanel(Palette.amber.opacity(0.35))
    }

    private func planCard(_ plan: NutritionPlanDTO, active: Bool) -> some View {
        let kcal = plan.dailyKcal ?? dayTotalsKcal(plan)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if active { StatusBadge(text: "Attivo", color: Palette.lime) }
                    Text(plan.title).font(Typo.display(22)).foregroundStyle(Palette.textHi)
                }
                Spacer()
                if let coach = plan.coach { CoachChip(coach: coach, color: Palette.lime) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("TARGET GIORNALIERO")
                    .font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                Spacer()
                Text("\(kcal)").font(Typo.poster(28)).foregroundStyle(Palette.lime)
                Text("kcal").font(Typo.mono(11, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            }

            if let split = macroSplit(plan) {
                Text("MACROS  \(split)")
                    .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.textMid)
            }

            HStack(spacing: 10) {
                macroCol("PRO", plan.proteinTargetG, Palette.magenta)
                macroCol("CARB", plan.carbTargetG, Palette.cyan)
                macroCol("FAT", plan.fatTargetG, Palette.amber)
            }
        }
        .padding(18)
        .voltPanel(Palette.lime.opacity(0.4))
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

    /// kcal-based macro split, e.g. "40/40/20" (P/C/F).
    private func macroSplit(_ plan: NutritionPlanDTO) -> String? {
        guard let p = plan.proteinTargetG, let c = plan.carbTargetG, let f = plan.fatTargetG else { return nil }
        let pk = Double(p * 4), ck = Double(c * 4), fk = Double(f * 9)
        let total = pk + ck + fk
        guard total > 0 else { return nil }
        func pct(_ v: Double) -> Int { Int((v / total * 100).rounded()) }
        return "\(pct(pk))/\(pct(ck))/\(pct(fk))"
    }

    private func macroDiaryLink(_ plan: NutritionPlanDTO) -> some View {
        NavigationLink {
            MacroLogView(assignmentId: plan.assignmentId, planTitle: plan.title)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.lime.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 22, weight: .black)).foregroundStyle(Palette.lime)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diario di oggi").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                    Text("Registra gli alimenti e traccia le calorie")
                        .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                    .foregroundStyle(Palette.lime)
            }
            .padding(16).voltPanel(Palette.lime.opacity(0.4))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func macroHistoryLink(_ plan: NutritionPlanDTO) -> some View {
        NavigationLink {
            MacroHistoryView(assignmentId: plan.assignmentId, planTitle: plan.title)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.cyan.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 21, weight: .black)).foregroundStyle(Palette.cyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storico pasti").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                    Text("Rivedi e modifica i giorni passati")
                        .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                    .foregroundStyle(Palette.cyan)
            }
            .padding(16).voltPanel(Palette.cyan.opacity(0.4))
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// WEEKLY FOOD plans: swipe through the 7 days (neighbours peek at the edges),
    /// tap a day to open its meals.
    @ViewBuilder
    private func weekCarousel(_ plan: NutritionPlanDTO) -> some View {
        let days = DietWeekday.sorted(plan.days)
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PIANO SETTIMANALE").voltEyebrow().padding(.top, 6)
                Text("Scorri i giorni · tocca per i dettagli")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid)
            }
            .revealUp(appear, index: 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(days) { day in
                        NavigationLink(value: day) { dayCarouselCard(day) }
                            .buttonStyle(PressableButtonStyle())
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 34, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .revealUp(appear, index: 3)
        }
    }

    private func dayCarouselCard(_ day: DietDayDTO) -> some View {
        let kcal = Int(day.meals.reduce(0) { $0 + $1.kcal })
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text((DietWeekday.long[day.dayOfWeek] ?? day.dayOfWeek).uppercased())
                    .font(Typo.display(20)).foregroundStyle(Palette.textHi)
                Spacer()
                Text(DietWeekday.short[day.dayOfWeek] ?? "")
                    .font(Typo.mono(11, .black)).tracking(1.5).foregroundStyle(Palette.lime)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(kcal)").font(Typo.poster(34)).foregroundStyle(Palette.lime)
                Text("kcal").font(Typo.mono(12, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
                Spacer()
            }
            Divider().overlay(Palette.lime.opacity(0.2))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(day.meals.prefix(4)) { meal in
                    HStack {
                        Circle().fill(Palette.lime).frame(width: 5, height: 5)
                        Text(meal.name).font(Typo.body(13)).foregroundStyle(Palette.textHi).lineLimit(1)
                        Spacer()
                        Text("\(Int(meal.kcal))").font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                    }
                }
                if day.meals.count > 4 {
                    Text("+\(day.meals.count - 4) altri pasti")
                        .font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
                }
                if day.meals.isEmpty {
                    Text("Nessun pasto previsto").font(Typo.body(12)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("Dettagli").font(Typo.mono(10, .bold)).foregroundStyle(Palette.lime)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.lime)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .voltPanel(Palette.lime.opacity(0.4))
    }

    @ViewBuilder
    private func mealsSection(_ plan: NutritionPlanDTO) -> some View {
        let meals = plan.days.first?.meals ?? []
        if !meals.isEmpty {
            Text("PASTI").voltEyebrow().padding(.top, 6).revealUp(appear, index: 2)
            ForEach(Array(meals.enumerated()), id: \.element.id) { i, meal in
                NavigationLink(value: meal) { mealCard(meal, index: i) }
                    .buttonStyle(PressableButtonStyle())
                    .revealUp(appear, index: i + 3)
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

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func load(force: Bool = false) async {
        // Keep the current list on refresh; only replace on a successful refetch.
        if !force, !plans.isEmpty { return }
        loading = true; error = nil
        do { plans = try await APIClient.shared.nutrition() }
        catch is CancellationError { loading = false; return }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
