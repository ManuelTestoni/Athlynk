//
//  CoachDashboardView.swift
//  "Dashboard Coach" — KPIs, quick actions, today's agenda, recent activity.
//

import SwiftUI

struct CoachDashboardView: View {
    @Binding var tab: CoachTab
    /// Deep-link into the "Altro" hub for sections that no longer have a tab.
    @State private var sheetRoute: CoachRoute?
    @State private var creatingWorkout = false
    @State private var creatingNutrition = false
    @State private var checkPickerMode: CoachQuickCheckMode?
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var data: CoachDashboardDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var loadToken = UUID()
    @State private var fetching = false
    @State private var appear = false

    // Customizable layout (synced with the web grid — array order is canonical).
    @State private var layoutWidgets: [DashboardWidgetDTO] = []
    @State private var catalog: [WidgetCatalogItemDTO] = []
    @State private var pinnedRows: [PinnedAthleteDTO] = []
    @State private var showEdit = false
    @State private var pinPickerIndex: PinIndex?
    @State private var saveTask: Task<Void, Never>?

    /// Identifiable wrapper so an Int index can drive `.sheet(item:)`.
    private struct PinIndex: Identifiable {
        let i: Int
        var id: Int { i }
    }

    var body: some View {
        ScreenScroll {
            header.revealUp(appear, index: 0)

            if loading && data == nil {
                CoachDashboardSkeleton()
            } else if let data {
                // KPI row (fixed — never part of the customizable grid)
                statsGrid(data.stats).revealUp(appear, index: 1)
                // Customizable widgets, canonical order shared with web.
                ForEach(Array(layoutWidgets.enumerated()), id: \.element.id) { idx, widget in
                    widgetView(widget, data: data).revealUp(appear, index: 2 + idx)
                }
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: layoutWidgets)
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .onAppear { if data != nil { appear = true } }
        .task(id: loadToken) { await load() }
        .onRemoteChange { loadToken = UUID() }
        .refreshable { await load(force: true) }
        .onChange(of: scenePhase) { _, phase in
            // Pick up layout edits made on the web while the app was backgrounded.
            if phase == .active { Task { await refreshLayout() } }
        }
        .sheet(isPresented: $showEdit) {
            DashboardEditSheet(
                widgets: $layoutWidgets,
                catalog: catalog,
                onChanged: { scheduleSave() },
                onReset: { Task { await resetLayout() } },
                onConfigure: { index in pinPickerIndex = PinIndex(i: index) }
            )
        }
        .sheet(item: $pinPickerIndex) { wrapped in
            CoachPinnedAthletePicker(
                selected: layoutWidgets.indices.contains(wrapped.i)
                    ? (layoutWidgets[wrapped.i].config?.clientIds ?? []) : []
            ) { ids in
                guard layoutWidgets.indices.contains(wrapped.i) else { return }
                layoutWidgets[wrapped.i].config = DashboardWidgetConfigDTO(clientIds: ids)
                scheduleSave()
                Task { await loadPinned() }
            }
        }
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
            // A drill-in (client detail) hides the tab bar; restore it whenever
            // the sheet closes so the shell isn't left without its bar.
            .onDisappear { app.tabBarHidden = false }
        }
        .sheet(isPresented: $creatingWorkout, onDismiss: { loadToken = UUID() }) {
            CoachPlanCreateView(kind: .workout)
        }
        .sheet(isPresented: $creatingNutrition, onDismiss: { loadToken = UUID() }) {
            CoachPlanCreateView(kind: .nutrition)
        }
        .sheet(item: $checkPickerMode) { mode in
            CoachQuickCheckPickerSheet(mode: mode)
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Buongiorno" : (h < 18 ? "Buon pomeriggio" : "Buonasera")
        let name = data?.coach.firstName ?? app.user?.firstName ?? ""
        return name.isEmpty ? "\(part), Coach" : "\(part), \(name)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("DASHBOARD").font(Typo.mono(11, .semibold)).tracking(3)
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
                CoachClientAvatar(url: app.avatarUrl, initials: data?.coach.initials ?? "C", size: 40)
            }
            Text(greeting)
                .font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
            Text(CoachDate.todayTitle())
                .font(Typo.body(14)).foregroundStyle(Palette.textMid)
            Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
        }
    }

    private func statsGrid(_ s: CoachStats) -> some View {
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: cols, spacing: 14) {
            CoachStatTile(value: "\(s.activeClients)", label: "Atleti attivi",
                          icon: "person.2.fill", accent: Palette.cyan) { sheetRoute = .clients }
            CoachStatTile(value: "\(s.pendingChecks)", label: "Check in attesa",
                          icon: "checkmark.seal.fill", accent: Palette.bronze,
                          flag: s.pendingChecks > 0 ? "DA FARE" : nil) { tab = .check }
            CoachStatTile(value: "\(s.appointmentsToday)", label: "Appuntamenti oggi",
                          icon: "calendar", accent: Palette.amber) { sheetRoute = .agenda }
            CoachStatTile(value: "\(s.unreadMessages)", label: "Messaggi",
                          icon: "bubble.left.fill", accent: Palette.violet,
                          flag: s.unreadMessages > 0 ? "NUOVI" : nil) { sheetRoute = .chat }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            CoachQuickAction(icon: "dumbbell.fill", label: "Allenamento", accent: Palette.cyan,
                             badge: "plus") { creatingWorkout = true }
            CoachQuickAction(icon: "flame.fill", label: "Nutrizione", accent: Palette.lime,
                             badge: "plus") { creatingNutrition = true }
            CoachQuickAction(icon: "checkmark.seal.fill", label: "Compila Check", accent: Palette.bronze) {
                checkPickerMode = .fill
            }
            CoachQuickAction(icon: "paperplane.fill", label: "Assegna Check", accent: Palette.violet) {
                checkPickerMode = .assign
            }
        }
    }

    @ViewBuilder
    private func sheetDestination(_ route: CoachRoute) -> some View {
        switch route {
        case .clients:       CoachClientsView()
        case .chat:          CoachMessagesView()
        case .agenda:        CoachAgendaView()
        case .analytics:     CoachAnalyticsView()
        case .subscriptions: CoachSubscriptionsView()
        default:             EmptyView()
        }
    }

    // MARK: Widget dispatch (customizable grid)

    @ViewBuilder
    private func widgetView(_ widget: DashboardWidgetDTO, data: CoachDashboardDTO) -> some View {
        switch widget.type {
        case "quick_actions":
            quickActions
        case "agenda_today":
            if !data.agenda.isEmpty { agendaSection(data.agenda) }
        case "activity_feed":
            if !data.activity.isEmpty { activitySection(data.activity) }
        case "pending_checks":
            pendingChecksWidget(data.stats)
        case "unread_messages":
            unreadMessagesWidget(data.stats)
        case "pinned_athletes":
            pinnedAthletesWidget
        case "recent_clients":
            linkWidget(title: "Atleti recenti",
                       subtitle: "Gli ultimi atleti registrati nel tuo studio",
                       icon: "person.2.fill", accent: Palette.cyan) { sheetRoute = .clients }
        case "subscription_plans":
            linkWidget(title: "Piani attivi",
                       subtitle: "I tuoi piani di abbonamento in vendita",
                       icon: "creditcard.fill", accent: Palette.amber) { sheetRoute = .subscriptions }
        case "business_kpis":
            linkWidget(title: "KPI business",
                       subtitle: "Ricavi, rinnovi e churn a colpo d'occhio",
                       icon: "chart.line.uptrend.xyaxis", accent: Palette.bronze) { sheetRoute = .analytics }
        case "churn_risk":
            linkWidget(title: "Rischio abbandono",
                       subtitle: "Gli atleti a rischio secondo il modello",
                       icon: "exclamationmark.triangle.fill", accent: Palette.danger) { sheetRoute = .analytics }
        case "revenue_chart":
            linkWidget(title: "Andamento ricavi",
                       subtitle: "La curva dei ricavi degli ultimi mesi",
                       icon: "chart.xyaxis.line", accent: Palette.lime) { sheetRoute = .analytics }
        case "checks_volume_chart":
            insightCard(data.insight)
        default:
            EmptyView()
        }
    }

    private func pendingChecksWidget(_ s: CoachStats) -> some View {
        Button {
            Haptics.tap(); tab = .check
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.bronze)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bronze.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check da rivedere").font(Typo.display(17)).foregroundStyle(Palette.textHi)
                    Text(s.pendingChecks == 0
                         ? "Tutto rivisto — nessun check in coda"
                         : "\(s.pendingChecks) check aspettano il tuo feedback")
                        .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                if s.pendingChecks > 0 {
                    Text("\(s.pendingChecks)")
                        .font(Typo.mono(14, .black)).foregroundStyle(Palette.void0)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.bronze))
                }
            }
            .padding(16).voltPanel(Palette.bronze.opacity(0.3))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func unreadMessagesWidget(_ s: CoachStats) -> some View {
        Button {
            Haptics.tap(); sheetRoute = .chat
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.violet)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.violet.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Messaggi non letti").font(Typo.display(17)).foregroundStyle(Palette.textHi)
                    Text(s.unreadMessages == 0
                         ? "Nessuna conversazione in attesa"
                         : "\(s.unreadMessages) conversazioni aspettano una risposta")
                        .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(16).voltPanel(Palette.violet.opacity(0.3))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var pinnedAthletesWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: "In evidenza", title: "I tuoi atleti", accent: Palette.cyan)
            if pinnedRows.isEmpty {
                Button {
                    Haptics.tap(); showEdit = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.cyan)
                        Text("Scegli fino a 6 atleti da tenere sotto controllo")
                            .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                        Spacer()
                        Text("Scegli").font(Typo.mono(11, .bold)).tracking(1)
                            .foregroundStyle(Palette.control)
                    }
                    .padding(16).voltPanel()
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pinnedRows.enumerated()), id: \.element.id) { i, a in
                        HStack(spacing: 12) {
                            CoachClientAvatar(url: a.profileImageUrl,
                                              initials: initials(of: a), size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.displayName)
                                    .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                                Text(a.lastCheckAt == nil
                                     ? "Nessun check"
                                     : "Ultimo check \(CoachDate.relative(a.lastCheckAt ?? ""))")
                                    .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                            }
                            Spacer()
                            if let delta = a.weightDelta {
                                Text(String(format: "%+.1f kg", delta))
                                    .font(Typo.mono(11, .bold))
                                    .foregroundStyle(delta <= 0 ? Palette.success : Palette.amber)
                            }
                            if a.hasPendingCheck {
                                Circle().fill(Palette.bronze).frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 10)
                        if i < pinnedRows.count - 1 { Divider().background(Palette.line) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4).voltPanel()
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

    private func initials(of a: PinnedAthleteDTO) -> String {
        let f = a.firstName.first.map(String.init) ?? ""
        let l = a.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func agendaSection(_ items: [CoachAgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: "Oggi", title: "Agenda", accent: Palette.amber)
            ForEach(items) { a in
                HStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text(CoachDate.time(a.start)).font(Typo.mono(15, .bold))
                            .foregroundStyle(Palette.textHi)
                    }
                    .frame(width: 54)
                    Rectangle().fill(Palette.amber).frame(width: 2).opacity(0.6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.client?.displayName ?? a.title)
                            .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                        Text(a.title).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.textLow)
                }
                .padding(14).voltPanel()
            }
        }
    }

    private func insightCard(_ insight: CoachInsight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.bronze)
            VStack(alignment: .leading, spacing: 4) {
                Text("PERFORMANCE INSIGHT").voltEyebrow()
                Text(insight.text).font(Typo.body(15, .medium))
                    .foregroundStyle(Palette.textHi).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel()
    }

    private func activitySection(_ items: [CoachActivity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: "Stream", title: "Attività recente", accent: Palette.cyan)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: n.type))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.accent(i))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.accent(i).opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                            if let body = n.body, !body.isEmpty {
                                Text(body).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(CoachDate.relative(n.createdAt)).font(Typo.mono(9))
                            .foregroundStyle(Palette.textLow)
                    }
                    .padding(.vertical, 10)
                    if i < items.count - 1 { Divider().background(Palette.line) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4).voltPanel()
        }
    }

    private func icon(for type: String) -> String {
        switch type.uppercased() {
        case "CHECK_SUBMITTED": return "checkmark.seal.fill"
        case "MESSAGE": return "bubble.left.fill"
        case "WORKOUT_ASSIGNED": return "dumbbell.fill"
        case "NUTRITION_ASSIGNED": return "flame.fill"
        default: return "bell.fill"
        }
    }

    private func load(force: Bool = false) async {
        guard !fetching else { return }
        let cache = AppDataCache.shared
        if !force,
           let cached: CoachDashboardDTO = cache.get("coach.dashboard"),
           let l: DashboardLayoutDTO = cache.get("coach.dashboard.layout"),
           let c: [WidgetCatalogItemDTO] = cache.get("coach.dashboard.catalog") {
            data = cached; layoutWidgets = l.widgets; catalog = c
            loading = false
            await loadPinned()
            return
        }
        fetching = true; loading = true
        async let layoutFetch = APIClient.shared.dashboardLayout()
        do {
            let d = try await APIClient.shared.coachDashboard()
            data = d
            cache.set("coach.dashboard", d)
            error = nil
        } catch { self.error = error.localizedDescription }
        do {
            let resp = try await layoutFetch
            layoutWidgets = resp.layout.widgets; catalog = resp.catalog
            cache.set("coach.dashboard.layout", resp.layout)
            cache.set("coach.dashboard.catalog", resp.catalog)
        } catch { print("CoachDashboard layout load failed: \(error.localizedDescription)") }
        fetching = false; loading = false
        await loadPinned()
    }

    // MARK: Layout sync

    /// Rows for the pinned-athletes widget (only when it's placed and configured).
    private func loadPinned() async {
        guard let widget = layoutWidgets.first(where: { $0.type == "pinned_athletes" }),
              let ids = widget.config?.clientIds, !ids.isEmpty else {
            pinnedRows = []
            return
        }
        pinnedRows = (try? await APIClient.shared.pinnedAthletes(ids: ids)) ?? []
    }

    /// Re-fetch just the layout (scene foreground → pick up edits made on web).
    private func refreshLayout() async {
        guard let resp = try? await APIClient.shared.dashboardLayout() else { return }
        layoutWidgets = resp.layout.widgets; catalog = resp.catalog
        AppDataCache.shared.set("coach.dashboard.layout", resp.layout)
        AppDataCache.shared.set("coach.dashboard.catalog", resp.catalog)
        await loadPinned()
    }

    /// Debounced autosave (mirrors the web grid's 600ms debounce).
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = DashboardLayoutDTO(version: 1, widgets: layoutWidgets)
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let resp = try await APIClient.shared.updateDashboardLayout(snapshot)
                AppDataCache.shared.set("coach.dashboard.layout", resp.layout)
            } catch {
                print("CoachDashboard scheduleSave failed: \(error.localizedDescription)")
            }
        }
    }

    private func resetLayout() async {
        do {
            let resp = try await APIClient.shared.resetDashboardLayout()
            layoutWidgets = resp.layout.widgets
            AppDataCache.shared.set("coach.dashboard.layout", resp.layout)
            await loadPinned()
        } catch {
            print("CoachDashboard resetLayout failed: \(error.localizedDescription)")
        }
    }
}
