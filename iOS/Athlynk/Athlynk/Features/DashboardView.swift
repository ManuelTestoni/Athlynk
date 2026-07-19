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

    // Customizable layout (synced with the web grid — array order is canonical).
    @Published var layoutWidgets: [DashboardWidgetDTO] = []
    @Published var catalog: [WidgetCatalogItemDTO] = []
    // Extra data only fetched when the matching widget is in the layout.
    @Published var weights: [Double] = []          // chronological
    @Published var checksDue: [CheckDTO] = []

    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        let cache = AppDataCache.shared
        if !force,
           let w: [WorkoutPlanDTO]   = cache.get("dashboard.workouts"),
           let n: [NutritionPlanDTO] = cache.get("dashboard.nutrition"),
           let v: [ConversationDTO]  = cache.get("dashboard.conversations"),
           let s: DashboardSummaryDTO = cache.get("dashboard.summary"),
           let l: DashboardLayoutDTO = cache.get("dashboard.layout"),
           let c: [WidgetCatalogItemDTO] = cache.get("dashboard.catalog") {
            workouts = w; nutrition = n; conversations = v; summary = s
            layoutWidgets = l.widgets; catalog = c
            loading = false
            await loadWidgetExtras()
            return
        }
        loading = true
        async let w = APIClient.shared.workouts()
        async let n = APIClient.shared.nutrition()
        async let v = APIClient.shared.conversations()
        async let s = APIClient.shared.dashboardSummary()
        async let l = APIClient.shared.dashboardLayout()
        do { workouts = try await w;      cache.set("dashboard.workouts", workouts) }
        catch { print("DashboardVM.load workouts failed: \(error.localizedDescription)") }
        do { nutrition = try await n;     cache.set("dashboard.nutrition", nutrition) }
        catch { print("DashboardVM.load nutrition failed: \(error.localizedDescription)") }
        do { conversations = try await v; cache.set("dashboard.conversations", conversations) }
        catch { print("DashboardVM.load conversations failed: \(error.localizedDescription)") }
        do { summary = try await s;       cache.set("dashboard.summary", summary!) }
        catch { print("DashboardVM.load summary failed: \(error.localizedDescription)") }
        do {
            let resp = try await l
            layoutWidgets = resp.layout.widgets; catalog = resp.catalog
            cache.set("dashboard.layout", resp.layout)
            cache.set("dashboard.catalog", resp.catalog)
        } catch { print("DashboardVM.load layout failed: \(error.localizedDescription)") }
        loading = false
        await loadWidgetExtras()
    }

    /// Data for widgets outside the classic dashboard payload — fetched only
    /// when the widget is actually placed.
    private func loadWidgetExtras() async {
        let types = Set(layoutWidgets.map(\.type))
        if types.contains("weight_trend"), weights.isEmpty {
            if let p = try? await APIClient.shared.progress() {
                weights = p.entries.compactMap(\.weightKg).reversed()
            }
        }
        if types.contains("checks_due"), checksDue.isEmpty {
            checksDue = (try? await APIClient.shared.checks()) ?? []
        }
    }

    /// Re-fetch just the layout (scene foreground → pick up edits made on web).
    func refreshLayout() async {
        guard let resp = try? await APIClient.shared.dashboardLayout() else { return }
        layoutWidgets = resp.layout.widgets; catalog = resp.catalog
        AppDataCache.shared.set("dashboard.layout", resp.layout)
        AppDataCache.shared.set("dashboard.catalog", resp.catalog)
        await loadWidgetExtras()
    }

    /// Debounced autosave (mirrors the web grid's 600ms debounce).
    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = DashboardLayoutDTO(version: 1, widgets: layoutWidgets)
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let resp = try await APIClient.shared.updateDashboardLayout(snapshot)
                AppDataCache.shared.set("dashboard.layout", resp.layout)
            } catch {
                print("DashboardVM.scheduleSave failed: \(error.localizedDescription)")
            }
            _ = self
        }
    }

    func resetLayout() async {
        do {
            let resp = try await APIClient.shared.resetDashboardLayout()
            layoutWidgets = resp.layout.widgets
            AppDataCache.shared.set("dashboard.layout", resp.layout)
            await loadWidgetExtras()
        } catch {
            print("DashboardVM.resetLayout failed: \(error.localizedDescription)")
        }
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
    /// The active FOOD plan's meals for TODAY (MACRO plans have no meal list —
    /// their "next meal" concept doesn't apply, the diary card covers those).
    private var foodPlan: NutritionPlanDTO? { nutrition.first { $0.planMode != "MACRO" } }
    var nextMealPlan: NutritionPlanDTO? { foodPlan }
    var todaysMeals: [MealDTO] {
        guard let plan = foodPlan else { return [] }
        let todayCode = DietWeekday.todayCode()
        return (plan.days.first { $0.dayOfWeek == todayCode } ?? plan.days.first)?.meals ?? []
    }
    var nextMeal: MealDTO? { todaysMeals.first }
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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = DashboardVM()
    @State private var appear = false
    @State private var loadToken = UUID()
    @State private var sheetRoute: AthleteQuickRoute?
    @State private var mealFlipped = false
    @State private var mealSquashed = false
    @State private var chatDetailConv: ConversationDTO?
    @State private var showEdit = false

    var body: some View {
        ScreenScroll {
            // Greeting hero (fixed — never part of the customizable grid)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("\(greeting), ATLETA")
                        .font(Typo.mono(11, .semibold)).tracking(3)
                        .textCase(.uppercase).foregroundStyle(Palette.bronze)
                    Spacer()
                    Button {
                        Haptics.tap(); showEdit = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textMid)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.void1))
                    }
                    .buttonStyle(PressableButtonStyle())
                    AvatarView(url: app.avatarUrl, initials: initials, size: 40, initialsSize: 16)
                }
                Text(app.greetingName.uppercased())
                    .font(Typo.poster(52)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
            }
            .revealUp(appear, index: 0)

            // KPI row (fixed)
            statsGrid.revealUp(appear, index: 1)

            if vm.loading {
                DashboardSkeleton()
            } else {
                // Customizable widgets — rendered in the canonical array order
                // shared with the web grid.
                ForEach(Array(vm.layoutWidgets.enumerated()), id: \.element.id) { idx, widget in
                    widgetView(widget).revealUp(appear, index: 2 + idx)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.layoutWidgets)
        .onAppear { appear = true }
        .task(id: loadToken) { await vm.load() }
        .refreshable { await vm.load(force: true) }
        .onChange(of: scenePhase) { _, phase in
            // Pick up layout edits made on the web while the app was backgrounded.
            if phase == .active { Task { await vm.refreshLayout() } }
        }
        .onRemoteChange(["WORKOUT_ASSIGNED", "NUTRITION_ASSIGNED", "CHECK_REVIEWED",
                         "COACH_FEEDBACK", "MESSAGE"]) { loadToken = UUID() }
        .sheet(isPresented: $showEdit) {
            DashboardEditSheet(
                widgets: $vm.layoutWidgets,
                catalog: vm.catalog,
                onChanged: { vm.scheduleSave() },
                onReset: { Task { await vm.resetLayout() } }
            )
        }
        .sheet(item: $sheetRoute) { route in
            NavigationStack {
                sheetDestination(route)
                    .navigationDestination(for: ConversationDTO.self) { conv in
                        ChatDetailView(conversation: conv)
                    }
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
        .sheet(item: $chatDetailConv) { conv in
            NavigationStack {
                ChatDetailView(conversation: conv)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { chatDetailConv = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                            }
                            .tint(Palette.textHi)
                        }
                    }
            }
        }
    }

    // MARK: Widget dispatch (customizable grid)

    @ViewBuilder
    private func widgetView(_ widget: DashboardWidgetDTO) -> some View {
        switch widget.type {
        case "quick_actions":
            quickActions
        case "next_workout":
            VStack(alignment: .leading, spacing: 10) {
                Text("OGGI").voltEyebrow().padding(.top, 6)
                todayCard
            }
        case "next_meal":
            if let plan = vm.nextMealPlan {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PROSSIMO PASTO").voltEyebrow().padding(.top, 2)
                    mealCard(plan)
                }
            }
        case "coach_message":
            if let conv = vm.lastConversation, let msg = conv.lastMessage, !msg.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DAL TUO COACH").voltEyebrow().padding(.top, 2)
                    coachCard(conv, message: msg)
                }
            }
        case "weight_trend":
            weightTrendWidget
        case "training_loads":
            linkWidget(title: "Carichi principali",
                       subtitle: "La progressione dei tuoi esercizi chiave",
                       icon: "dumbbell.fill", accent: Palette.magenta) { sheetRoute = .andamento }
        case "weekly_volume":
            linkWidget(title: "Volume settimanale",
                       subtitle: "Quanto ti sei allenato, settimana per settimana",
                       icon: "chart.bar.fill", accent: Palette.cyan) { sheetRoute = .andamento }
        case "journey_timeline":
            linkWidget(title: "Percorso",
                       subtitle: "Le tappe del tuo percorso con il coach",
                       icon: "map.fill", accent: Palette.bronze) { sheetRoute = .percorso }
        case "checks_due":
            checksDueWidget
        case "nav_shortcuts":
            navShortcutsWidget
        default:
            EmptyView()
        }
    }

    /// Weight sparkline drawn with native shapes (no chart dependency —
    /// same approach as CoachAnalyticsView's bars).
    private var weightTrendWidget: some View {
        Button {
            Haptics.tap(); sheetRoute = .andamento
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ANDAMENTO PESO")
                        .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                    Spacer()
                    Text(vm.weightCurrentDisplay + " kg")
                        .font(Typo.mono(13, .bold)).foregroundStyle(Palette.cyan)
                }
                if vm.weights.count >= 2 {
                    SparklineView(values: vm.weights, accent: Palette.cyan)
                        .frame(height: 56)
                } else {
                    Text("Nessuna rilevazione ancora: compila un check per iniziare.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                }
            }
            .padding(18).voltPanel(Palette.cyan.opacity(0.35))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var checksDueWidget: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .check }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CHECK DA COMPILARE")
                        .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                    Spacer()
                    Image(systemName: "checklist")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.amber)
                }
                if vm.checksDue.isEmpty {
                    Text("Tutto in ordine: nessun check in attesa.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                } else {
                    ForEach(vm.checksDue.prefix(3)) { check in
                        HStack {
                            Text(check.title)
                                .font(Typo.body(14, .medium)).foregroundStyle(Palette.textHi)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textLow)
                        }
                    }
                }
            }
            .padding(18).voltPanel(Palette.amber.opacity(0.35))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var navShortcutsWidget: some View {
        HStack(spacing: 12) {
            CoachQuickAction(icon: "dumbbell.fill", label: "Allenamento", accent: Palette.magenta) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .train }
            }
            CoachQuickAction(icon: "fork.knife", label: "Nutrizione", accent: Palette.lime) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .fuel }
            }
            CoachQuickAction(icon: "camera.fill", label: "Check", accent: Palette.cyan) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .check }
            }
        }
    }

    private func linkWidget(title: String, subtitle: String, icon: String,
                            accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                    Text(subtitle).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(16).voltPanel(accent.opacity(0.3))
        }
        .buttonStyle(PressableButtonStyle())
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

    private func mealCard(_ plan: NutritionPlanDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(mealFlipped ? "PIANO — OVERVIEW" : "PROSSIMO PASTO")
                    .font(Typo.mono(9, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                Spacer()
                Button {
                    Haptics.soft()
                    withAnimation(.easeIn(duration: 0.16)) { mealSquashed = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        mealFlipped.toggle()
                        withAnimation(.easeOut(duration: 0.22)) { mealSquashed = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mealFlipped ? "fork.knife" : "chart.pie.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(mealFlipped ? "Pasto" : "Piano").font(Typo.mono(10, .bold))
                    }
                    .foregroundStyle(Palette.lime)
                }
                .buttonStyle(.plain)
            }

            Group {
                if mealFlipped { planOverviewFace(plan) } else { nextMealFace }
            }
            .scaleEffect(x: mealSquashed ? 0.0 : 1.0, anchor: .center)
        }
        .padding(18).voltPanel(Palette.lime.opacity(0.4))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = .fuel }
        }
    }

    @ViewBuilder
    private var nextMealFace: some View {
        if let meal = vm.nextMeal {
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
        } else {
            Text("Nessun pasto previsto per oggi.").font(Typo.body(14)).foregroundStyle(Palette.textMid)
        }
    }

    private func planOverviewFace(_ plan: NutritionPlanDTO) -> some View {
        let t = plan.overviewTargets
        return VStack(alignment: .leading, spacing: 12) {
            Text(plan.title).font(Typo.display(18)).foregroundStyle(Palette.textHi)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(t.kcal)").font(Typo.poster(26)).foregroundStyle(Palette.lime)
                Text("kcal/giorno").font(Typo.mono(11, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            }
            HStack(spacing: 10) {
                macroChip("PRO", grams: Double(t.protein ?? 0), Palette.magenta)
                macroChip("CARB", grams: Double(t.carb ?? 0), Palette.cyan)
                macroChip("FAT", grams: Double(t.fat ?? 0), Palette.amber)
            }
        }
    }

    private func coachCard(_ conv: ConversationDTO, message: String) -> some View {
        Button {
            Haptics.tap()
            chatDetailConv = conv
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
