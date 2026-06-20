//
//  CoachDashboardView.swift
//  "Dashboard Coach" — KPIs, quick actions, today's agenda, recent activity.
//

import SwiftUI

struct CoachDashboardView: View {
    @Binding var tab: CoachTab
    /// Deep-link into the "Altro" hub for sections that no longer have a tab.
    @State private var sheetRoute: CoachRoute?
    @EnvironmentObject private var app: AppState
    @State private var data: CoachDashboardDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var loadToken = UUID()
    @State private var fetching = false

    var body: some View {
        ScreenScroll {
            header

            if loading && data == nil {
                CoachDashboardSkeleton()
            } else if let data {
                statsGrid(data.stats)
                quickActions
                if !data.agenda.isEmpty { agendaSection(data.agenda) }
                insightCard(data.insight)
                if !data.activity.isEmpty { activitySection(data.activity) }
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.bronze)
            }
        }
        .task(id: loadToken) { await load() }
        .onRemoteChange { loadToken = UUID() }
        .refreshable { await load(force: true) }
        .sheet(item: $sheetRoute) { route in
            NavigationStack { sheetDestination(route) }
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
                          icon: "person.2.fill", accent: Palette.cyan)
            CoachStatTile(value: "\(s.pendingChecks)", label: "Check in attesa",
                          icon: "checkmark.seal.fill", accent: Palette.bronze,
                          flag: s.pendingChecks > 0 ? "DA FARE" : nil)
            CoachStatTile(value: "\(s.appointmentsToday)", label: "Appuntamenti oggi",
                          icon: "calendar", accent: Palette.amber)
            CoachStatTile(value: "\(s.unreadMessages)", label: "Messaggi",
                          icon: "bubble.left.fill", accent: Palette.violet,
                          flag: s.unreadMessages > 0 ? "NUOVI" : nil)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            CoachQuickAction(icon: "person.crop.circle.badge.checkmark", label: "Atleti",
                             accent: Palette.cyan) { sheetRoute = .clients }
            CoachQuickAction(icon: "checkmark.seal.fill", label: "Revisione", accent: Palette.bronze) {
                tab = .check
            }
            CoachQuickAction(icon: "calendar.badge.clock", label: "Agenda", accent: Palette.amber) {
                sheetRoute = .agenda
            }
            CoachQuickAction(icon: "bubble.left.and.bubble.right.fill", label: "Chat",
                             accent: Palette.violet) { sheetRoute = .chat }
        }
    }

    @ViewBuilder
    private func sheetDestination(_ route: CoachRoute) -> some View {
        switch route {
        case .clients: CoachClientsView()
        case .chat:    CoachMessagesView()
        case .agenda:  CoachAgendaView()
        default:       EmptyView()
        }
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
        if !force, let cached: CoachDashboardDTO = cache.get("coach.dashboard") {
            data = cached; loading = false; return
        }
        fetching = true; loading = true
        do {
            let d = try await APIClient.shared.coachDashboard()
            data = d
            cache.set("coach.dashboard", d)
            error = nil
        } catch { self.error = error.localizedDescription }
        fetching = false; loading = false
    }
}
