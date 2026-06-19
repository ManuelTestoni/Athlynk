//
//  DashboardView.swift
//  The "Hub" (Stitch: Dashboard Principale): greeting, quick metrics, today's
//  session, next meal, and the latest coach message — each tapping through to
//  its domain tab.
//

import SwiftUI
import Combine

@MainActor
final class DashboardVM: ObservableObject {
    @Published var workouts: [WorkoutPlanDTO] = []
    @Published var nutrition: [NutritionPlanDTO] = []
    @Published var checks: [CheckDTO] = []
    @Published var conversations: [ConversationDTO] = []
    @Published var loading = true

    private var isLoading = false

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let cache = AppDataCache.shared
        if !force,
           let w: [WorkoutPlanDTO]   = cache.get("dashboard.workouts"),
           let n: [NutritionPlanDTO] = cache.get("dashboard.nutrition"),
           let c: [CheckDTO]         = cache.get("dashboard.checks"),
           let v: [ConversationDTO]  = cache.get("dashboard.conversations") {
            workouts = w; nutrition = n; checks = c; conversations = v
            loading = false; return
        }
        loading = true
        async let w = APIClient.shared.workouts()
        async let n = APIClient.shared.nutrition()
        async let c = APIClient.shared.checks()
        async let v = APIClient.shared.conversations()
        if let r = try? await w { workouts = r;      cache.set("dashboard.workouts", r) }
        if let r = try? await n { nutrition = r;     cache.set("dashboard.nutrition", r) }
        if let r = try? await c { checks = r;        cache.set("dashboard.checks", r) }
        if let r = try? await v { conversations = r; cache.set("dashboard.conversations", r) }
        loading = false
    }

    var sessionsPerWeek: Int { workouts.first?.frequencyPerWeek ?? workouts.first?.days.count ?? 0 }
    var dailyKcal: Int { nutrition.first?.dailyKcal ?? 0 }

    /// First session of the active plan, shown as "today's" workout.
    var todayDay: WorkoutDayDTO? { workouts.first?.days.first }
    var nextMeal: MealDTO? { nutrition.first?.days.first?.meals.first }
    var lastConversation: ConversationDTO? { conversations.first }
}

struct DashboardView: View {
    @Binding var tab: AppTab
    @EnvironmentObject var app: AppState
    @StateObject private var vm = DashboardVM()
    @State private var appear = false
    @State private var loadToken = UUID()

    var body: some View {
        ScreenScroll {
            // Greeting hero
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("\(greeting), ATLETA")
                        .font(Typo.mono(11, .semibold)).tracking(3)
                        .textCase(.uppercase).foregroundStyle(Palette.bronze)
                    Spacer()
                    AvatarView(url: app.avatarUrl, initials: initials, size: 40, initialsSize: 16)
                }
                Text(app.greetingName.uppercased())
                    .font(Typo.poster(52)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.55)
                if let goal = app.me?.profile?.primaryGoal, !goal.isEmpty {
                    Text(goal.uppercased())
                        .font(Typo.mono(12, .bold)).tracking(2).foregroundStyle(Palette.lime)
                }
                Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
            }
            .revealUp(appear, index: 0)

            // Quick metrics
            HStack(spacing: 12) {
                metric(value: "\(vm.sessionsPerWeek)",
                       suffix: "/sett", label: "Allenamenti", color: Palette.magenta)
                metric(value: "\(vm.checks.count)",
                       suffix: "", label: "Check aperti", color: Palette.violet)
                metric(value: vm.dailyKcal > 0 ? "\(vm.dailyKcal)" : "—",
                       suffix: "kcal", label: "Target gior.", color: Palette.lime)
            }
            .revealUp(appear, index: 1)

            if vm.loading {
                DashboardSkeleton()
            } else {
                // Today's session
                Text("OGGI").voltEyebrow().padding(.top, 6).revealUp(appear, index: 2)
                todayCard.revealUp(appear, index: 3)

                // Next meal
                if vm.nextMeal != nil {
                    Text("PROSSIMO PASTO").voltEyebrow().padding(.top, 2).revealUp(appear, index: 4)
                    mealCard.revealUp(appear, index: 5)
                }

                // Coach message
                if let conv = vm.lastConversation, let msg = conv.lastMessage, !msg.isEmpty {
                    Text("DAL TUO COACH").voltEyebrow().padding(.top, 2).revealUp(appear, index: 6)
                    coachCard(conv, message: msg).revealUp(appear, index: 7)
                }
            }
        }
        .onAppear { appear = true }
        .task(id: loadToken) { await vm.load() }
        .refreshable { await vm.load(force: true) }
        .onRemoteChange(["WORKOUT_ASSIGNED", "NUTRITION_ASSIGNED", "CHECK_REVIEWED",
                         "COACH_FEEDBACK", "MESSAGE"]) { loadToken = UUID() }
    }

    // MARK: Cards

    private var todayCard: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .train }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                if let day = vm.todayDay {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((day.dayName ?? "Sessione").uppercased())
                                .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.magenta)
                            Text(day.focusArea ?? day.label)
                                .font(Typo.display(24)).foregroundStyle(Palette.textHi)
                        }
                        Spacer()
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 22, weight: .black)).foregroundStyle(Palette.magenta)
                    }
                    HStack(spacing: 18) {
                        iconStat("figure.strengthtraining.traditional", "\(day.exercises.count) esercizi")
                        iconStat("repeat", "\(totalSets(day)) serie")
                    }
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Text("INIZIA").font(Typo.mono(12, .black)).tracking(2)
                            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .black))
                        }
                        .foregroundStyle(Palette.void0)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(Palette.magenta))
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.magenta)
                        Text("Nessuna scheda attiva")
                            .font(Typo.body(15)).foregroundStyle(Palette.textMid)
                        Spacer()
                    }
                }
            }
            .padding(18).voltPanel(Palette.magenta.opacity(0.4))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var mealCard: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .fuel }
        } label: {
            let meal = vm.nextMeal!
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meal.name).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                        if let t = meal.timeOfDay {
                            Text(t).font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                        }
                    }
                    Spacer()
                    Text("\(Int(meal.kcal)) kcal")
                        .font(Typo.mono(14, .bold)).foregroundStyle(Palette.lime)
                }
                HStack(spacing: 10) {
                    macroChip("PRO", grams: meal.items.reduce(0) { $0 + $1.protein }, Palette.magenta)
                    macroChip("CARB", grams: meal.items.reduce(0) { $0 + $1.carbs }, Palette.cyan)
                    macroChip("FAT", grams: meal.items.reduce(0) { $0 + $1.fat }, Palette.amber)
                }
            }
            .padding(18).voltPanel(Palette.lime.opacity(0.4))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func coachCard(_ conv: ConversationDTO, message: String) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .altro }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(Palette.cyan.opacity(0.18)).frame(width: 46, height: 46)
                    Text(String(conv.coach?.firstName.first ?? "C"))
                        .font(Typo.poster(20)).foregroundStyle(Palette.cyan)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conv.coach?.fullName ?? "Coach")
                            .font(Typo.display(17)).foregroundStyle(Palette.textHi)
                        Spacer()
                        if let t = conv.lastMessageAt {
                            Text(relative(t)).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                        }
                    }
                    Text(message)
                        .font(Typo.body(14)).foregroundStyle(Palette.textMid).lineLimit(2)
                }
            }
            .padding(16).voltPanel(Palette.cyan.opacity(0.35))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Bits

    private func metric(value: String, suffix: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(Typo.poster(30)).foregroundStyle(color)
                if !suffix.isEmpty {
                    Text(suffix).font(Typo.mono(10, .bold)).foregroundStyle(color.opacity(0.7))
                }
            }
            Text(label.uppercased())
                .font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14).padding(.horizontal, 12)
        .voltPanel(color.opacity(0.35))
    }

    private func iconStat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textMid)
            Text(text).font(Typo.mono(12, .semibold)).foregroundStyle(Palette.textMid)
        }
    }

    private func macroChip(_ label: String, grams: Double, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(grams))g").font(Typo.mono(14, .black)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    // MARK: Helpers

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "BUONGIORNO" : (h < 18 ? "BUON POMERIGGIO" : "BUONASERA")
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func totalSets(_ day: WorkoutDayDTO) -> Int {
        day.exercises.reduce(0) { $0 + ($1.setCount ?? 0) }
    }

    private func relative(_ iso: String) -> String {
        guard let d = ISO8601.parse(iso) else { return "" }
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "it_IT")
        return f.localizedString(for: d, relativeTo: Date())
    }
}
