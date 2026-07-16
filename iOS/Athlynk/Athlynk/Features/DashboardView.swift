//
//  DashboardView.swift
//  The "Hub" (Stitch: Dashboard Principale): greeting, 4 KPI cards + 4 quick-nav
//  cards (mirrors the coach dashboard), today's session, next meal, and the
//  latest coach message — each tapping through to its domain tab or a sheet.
//

import SwiftUI
import Combine

@MainActor
final class DashboardVM: ObservableObject {
    @Published var workouts: [WorkoutPlanDTO] = []
    @Published var nutrition: [NutritionPlanDTO] = []
    @Published var conversations: [ConversationDTO] = []
    @Published var summary: DashboardSummaryDTO?
    @Published var loading = true

    private var isLoading = false

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let cache = AppDataCache.shared
        if !force,
           let w: [WorkoutPlanDTO]   = cache.get("dashboard.workouts"),
           let n: [NutritionPlanDTO] = cache.get("dashboard.nutrition"),
           let v: [ConversationDTO]  = cache.get("dashboard.conversations"),
           let s: DashboardSummaryDTO = cache.get("dashboard.summary") {
            workouts = w; nutrition = n; conversations = v; summary = s
            loading = false; return
        }
        loading = true
        async let w = APIClient.shared.workouts()
        async let n = APIClient.shared.nutrition()
        async let v = APIClient.shared.conversations()
        async let s = APIClient.shared.dashboardSummary()
        do { workouts = try await w;      cache.set("dashboard.workouts", workouts) }
        catch { print("DashboardVM.load workouts failed: \(error.localizedDescription)") }
        do { nutrition = try await n;     cache.set("dashboard.nutrition", nutrition) }
        catch { print("DashboardVM.load nutrition failed: \(error.localizedDescription)") }
        do { conversations = try await v; cache.set("dashboard.conversations", conversations) }
        catch { print("DashboardVM.load conversations failed: \(error.localizedDescription)") }
        do { summary = try await s;       cache.set("dashboard.summary", summary!) }
        catch { print("DashboardVM.load summary failed: \(error.localizedDescription)") }
        loading = false
    }

    var sessionsThisWeek: Int { summary?.sessionsThisWeek ?? 0 }
    var kcalTargetDisplay: String {
        guard let k = summary?.kcalTarget, k > 0 else { return "—" }
        return "\(Int(k))"
    }
    var daysToRenewalDisplay: String {
        guard let d = summary?.daysToRenewal else { return "—" }
        return "\(d)"
    }
    var weightCurrentDisplay: String {
        guard let w = summary?.weightCurrent else { return "—" }
        return String(format: "%.1f", w)
    }

    /// First session of the active plan, shown as "today's" workout.
    var todayDay: WorkoutDayDTO? { workouts.first?.days.first }
    var nextMeal: MealDTO? { nutrition.first?.days.first?.meals.first }
    var lastConversation: ConversationDTO? { conversations.first }
}

/// Deep-link destinations from the dashboard's quick-nav cards that don't
/// have a dedicated tab — presented as a sheet, same idiom as the coach
/// dashboard's `CoachRoute` sheet routing.
private enum AthleteQuickRoute: Identifiable {
    case abbonamento, andamento, integratori, chat, agenda, percorso
    var id: Self { self }
}

struct DashboardView: View {
    @Binding var tab: AppTab
    @EnvironmentObject var app: AppState
    @StateObject private var vm = DashboardVM()
    @State private var appear = false
    @State private var loadToken = UUID()
    @State private var sheetRoute: AthleteQuickRoute?

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
                Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
            }
            .revealUp(appear, index: 0)

            statsGrid.revealUp(appear, index: 1)
            quickActions.revealUp(appear, index: 2)

            if vm.loading {
                DashboardSkeleton()
            } else {
                // Today's session
                Text("OGGI").voltEyebrow().padding(.top, 6).revealUp(appear, index: 3)
                todayCard.revealUp(appear, index: 4)

                // Next meal
                if vm.nextMeal != nil {
                    Text("PROSSIMO PASTO").voltEyebrow().padding(.top, 2).revealUp(appear, index: 5)
                    mealCard.revealUp(appear, index: 6)
                }

                // Coach message
                if let conv = vm.lastConversation, let msg = conv.lastMessage, !msg.isEmpty {
                    Text("DAL TUO COACH").voltEyebrow().padding(.top, 2).revealUp(appear, index: 7)
                    coachCard(conv, message: msg).revealUp(appear, index: 8)
                }
            }
        }
        .onAppear { appear = true }
        .task(id: loadToken) { await vm.load() }
        .refreshable { await vm.load(force: true) }
        .onRemoteChange(["WORKOUT_ASSIGNED", "NUTRITION_ASSIGNED", "CHECK_REVIEWED",
                         "COACH_FEEDBACK", "MESSAGE"]) { loadToken = UUID() }
        .sheet(item: $sheetRoute) { route in
            NavigationStack {
                sheetDestination(route)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { sheetRoute = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            }
                            .tint(Palette.textHi)
                        }
                    }
            }
        }
    }

    // MARK: 4 big cards + 4 small cards

    private var statsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: cols, spacing: 14) {
            statTile(value: "\(vm.sessionsThisWeek)", label: "Sessioni Settimana",
                     icon: "dumbbell.fill", accent: Palette.magenta) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .train }
            }
            statTile(value: vm.kcalTargetDisplay, label: "Target Giornaliero",
                     icon: "flame.fill", accent: Palette.lime) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .fuel }
            }
            statTile(value: vm.daysToRenewalDisplay, label: "Abbonamento",
                     icon: "crown.fill", accent: Palette.amber) { sheetRoute = .abbonamento }
            statTile(value: vm.weightCurrentDisplay, label: "Peso attuale",
                     icon: "scalemass.fill", accent: Palette.cyan) { sheetRoute = .andamento }
        }
    }

    private func statTile(value: String, label: String, icon: String, accent: Color,
                           action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            CoachStatTile(value: value, label: label, icon: icon, accent: accent)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            CoachQuickAction(icon: "pills.fill", label: "Integratori", accent: Palette.lime) {
                sheetRoute = .integratori
            }
            CoachQuickAction(icon: "bubble.left.and.bubble.right.fill", label: "Chat",
                             accent: Palette.violet) { sheetRoute = .chat }
            CoachQuickAction(icon: "calendar", label: "Agenda", accent: Palette.cyan) {
                sheetRoute = .agenda
            }
            CoachQuickAction(icon: "map.fill", label: "Percorso", accent: Palette.bronze) {
                sheetRoute = .percorso
            }
        }
    }

    @ViewBuilder
    private func sheetDestination(_ route: AthleteQuickRoute) -> some View {
        switch route {
        case .abbonamento:  SubscriptionView()
        case .andamento:    ProgressTrackerView()
        case .integratori:  SupplementsView()
        case .chat:         ChatListView()
        case .agenda:       AgendaView()
        case .percorso:     JourneyView()
        }
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
                    .padding(.top, 14)
            }
            .padding(16).voltPanel(Palette.cyan.opacity(0.35))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: Bits

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
