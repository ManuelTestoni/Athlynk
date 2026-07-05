//
//  CoachClientsView.swift
//  "Lista Clienti Coach" + "Profilo Atleta (Vista Coach)".
//

import SwiftUI

struct CoachClientsView: View {
    @State private var rows: [CoachClientRow] = []
    @State private var total = 0
    @State private var active = 0
    @State private var query = ""
    @State private var statusFilter = ""   // "" | ACTIVE | INACTIVE
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var showAddClient = false
    @State private var appear = false

    private let filters: [(String, String)] = [("", "Tutti"), ("ACTIVE", "Attivi"), ("INACTIVE", "Sospesi")]

    var body: some View {
        ScreenScroll {
                ScreenHeader(eyebrow: "I tuoi atleti", title: "Atleti",
                             subtitle: "\(active) attivi · \(total) totali", accent: Palette.cyan)

                searchBar

                HStack(spacing: 8) {
                    ForEach(filters, id: \.0) { f in
                        let on = statusFilter == f.0
                        Button {
                            statusFilter = f.0; Task { await load() }
                        } label: {
                            Text(f.1).font(Typo.mono(11, .bold)).tracking(1).textCase(.uppercase)
                                .foregroundStyle(on ? Palette.void0 : Palette.textMid)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background { if on { Capsule().fill(Palette.cyan) }
                                    else { Capsule().stroke(Palette.line, lineWidth: 1) } }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { showAddClient = true } label: {
                        Label("Atleta", systemImage: "person.badge.plus")
                            .font(Typo.mono(11, .bold)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(Palette.void0)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.cyan))
                    }
                    .buttonStyle(.plain)
                }

                if loading && rows.isEmpty {
                    AvatarRowsSkeleton(accent: Palette.cyan)
                } else if rows.isEmpty {
                    EmptyPanel(icon: "person.2", text: "Nessun atleta trovato.")
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        NavigationLink(value: r.id) { clientCard(r) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: min(i, 8))
                    }
                    if hasMore {
                        LoadMoreButton(loading: loadingMore, accent: Palette.cyan) { Task { await loadMore() } }
                    }
                }
            }
        .navigationDestination(for: Int.self) { CoachClientDetailView(clientId: $0) }
        .sheet(isPresented: $showAddClient) {
            CoachAddClientView { await load() }
        }
        .task { Analytics.shared.capture(.clientListViewed); await load() }
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .onRemoteChange { Task { await load() } }
        .refreshable { await load() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.cyan)
            TextField("", text: $query, prompt: Text("Cerca atleta…").foregroundStyle(Palette.textLow))
                .font(Typo.body(15)).tint(Palette.cyan)
                .textInputAutocapitalization(.words)
                .onSubmit { Task { await load() } }
            if !query.isEmpty {
                Button { query = ""; Task { await load() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textLow)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .voltPanel(radius: 14)
    }

    private func clientCard(_ r: CoachClientRow) -> some View {
        HStack(spacing: 14) {
            CoachClientAvatar(url: r.profileImageUrl, initials: r.initials, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.displayName).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                Text(r.activeWorkout ?? r.relationshipLabel)
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
                HStack(spacing: 6) {
                    StatusBadge(text: r.relationshipLabel, color: Palette.cyan, filled: false)
                    if let last = r.lastCheckAt {
                        Text("Check \(CoachDate.relative(last))")
                            .font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let res = try await APIClient.shared.coachClients(query: query, status: statusFilter)
            rows = res.clients; total = res.total; active = res.active
            hasMore = res.hasMore; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let res = try await APIClient.shared.coachClients(query: query, status: statusFilter,
                                                              offset: rows.count)
            let known = Set(rows.map(\.id))
            rows.append(contentsOf: res.clients.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Client detail ("Profilo Atleta — Vista Coach")

struct CoachClientDetailView: View {
    let clientId: Int
    @State private var data: CoachClientDetailDTO?
    @State private var progress: [CoachProgressEntry] = []
    @State private var percorso: JourneyResponse?
    @State private var showAddMeasurement = false
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            if let d = data {
                profileHeader(d)
                if let r = d.relationship.startDate {
                    Text("Cliente dal \(CoachDate.dayMonth(r))")
                        .font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                }
                statRow(d)
                chartsSection
                assignmentsSection(d)
                workoutSection
                percorsoSection
                checksSection(d)
            } else if loading {
                CoachClientDetailSkeleton()
            } else {
                EmptyPanel(icon: "person.crop.circle.badge.exclamationmark", text: "Atleta non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CoachClientWorkoutRoute.self) { r in
            CoachClientWorkoutView(clientId: r.clientId)
        }
        .navigationDestination(for: CoachJourneyRoute.self) { r in
            CoachJourneyView(clientId: r.clientId)
        }
        .navigationDestination(for: CoachProgressRoute.self) { r in
            CoachClientProgressView(clientId: r.clientId)
        }
        .navigationDestination(for: CoachSessionsRoute.self) { r in
            CoachSessionsView(clientId: r.clientId)
        }
        .navigationDestination(for: CoachClientMacroHistoryRoute.self) { r in
            CoachMacroHistoryView(clientId: r.clientId)
        }
        .navigationDestination(for: CoachSessionRoute.self) { r in
            SessionDetailView(accent: Palette.magenta) {
                try await APIClient.shared.coachSessionDetail(r.sessionId)
            }
        }
        .sheet(isPresented: $showAddMeasurement) {
            AddMeasurementSheet(accent: Palette.cyan) { type, key, value, date in
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                try await APIClient.shared.coachAddMeasurement(
                    clientId: clientId, type: type, key: key, value: value, date: f.string(from: date))
                progress = (try? await APIClient.shared.coachClientProgress(clientId: clientId)) ?? []
            }
            .presentationDetents([.medium, .large])
        }
        .task { await load() }
    }

    private func profileHeader(_ d: CoachClientDetailDTO) -> some View {
        VStack(spacing: 12) {
            CoachClientAvatar(url: d.client.profileImageUrl, initials: d.client.initials, size: 92)
            Text(d.client.displayName).font(Typo.poster(32)).foregroundStyle(Palette.textHi)

            StatusBadge(text: d.relationship.status ?? "—",
                        color: (d.relationship.status == "ACTIVE") ? Palette.lime : Palette.textLow)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statRow(_ d: CoachClientDetailDTO) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            miniStat(d.client.weightKg.map { String(format: "%.1f", $0) } ?? "—", "Peso kg")
            miniStat("\(d.checks.count)", "Check")
        }
    }

    private func miniStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(Typo.poster(26)).foregroundStyle(Palette.textHi)
            Text(l).font(Typo.mono(9, .semibold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).voltPanel(radius: 14)
    }

    private func assignmentsSection(_ d: CoachClientDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Programma", title: "Assegnazioni attive")
            assignRow("dumbbell.fill", "Allenamento", d.activeWorkout?.title ?? "Nessuno", Palette.cyan)
            assignRow("flame.fill", "Nutrizione", d.activeNutrition?.title ?? "Nessuno", Palette.lime)
            if d.activeNutrition?.planMode == "MACRO" {
                NavigationLink(value: CoachClientMacroHistoryRoute(clientId: clientId)) {
                    assignRow("clock.arrow.circlepath", "Storico pasti",
                              "Vedi cosa ha registrato l'atleta", Palette.lime, chevron: true)
                }
                .buttonStyle(.plain)
            }
            if let sub = d.activeSubscription {
                assignRow("creditcard.fill", "Abbonamento",
                          "\(sub.name) · €\(String(format: "%.0f", sub.price))", Palette.amber)
            }
            if !d.supplementSheets.isEmpty {
                assignRow("pills.fill", "Integratori",
                          d.supplementSheets.map(\.title).joined(separator: ", "), Palette.violet)
            }
        }
    }

    private func assignRow(_ icon: String, _ label: String, _ value: String, _ accent: Color,
                           chevron: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typo.mono(10, .semibold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Palette.textMid)
                Text(value).font(Typo.body(15, .medium)).foregroundStyle(Palette.textHi).lineLimit(1)
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
        .padding(14).voltPanel()
    }

    private func checksSection(_ d: CoachClientDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Storico", title: "Check recenti", accent: Palette.bronze)
            if d.checks.isEmpty {
                EmptyPanel(icon: "checkmark.seal", text: "Nessun check inviato.")
            } else {
                ForEach(d.checks) { c in
                    NavigationLink(value: CheckRoute(id: c.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: c.reviewed ? "checkmark.seal.fill" : "seal")
                                .foregroundStyle(c.reviewed ? Palette.lime : Palette.bronze)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                                Text(CoachDate.dayMonth(c.submittedAt)).font(Typo.mono(10))
                                    .foregroundStyle(Palette.textLow)
                            }
                            Spacer()
                            if let w = c.weightKg {
                                Text("\(String(format: "%.1f", w)) kg")
                                    .font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                            }
                        }
                        .padding(14).voltPanel()
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .navigationDestination(for: CheckRoute.self) { CoachCheckDetailView(responseId: $0.id) }
    }

    // MARK: Charts — andamento (weight weekly means + circ/skinfold, shared component)

    private var measurementSamples: [MeasurementSample] {
        progress.compactMap { e in
            guard let d = CoachDate.parse(e.submittedAt) else { return nil }
            return MeasurementSample(
                date: d,
                weightKg: e.weightKg,
                circumferences: e.measurements.compactMapValues { Double($0) },
                skinfolds: e.skinfolds.compactMapValues { Double($0) }
            )
        }
    }

    @ViewBuilder private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CoachSectionTitle(eyebrow: "Andamento", title: "Grafici", accent: Palette.cyan)
                Spacer()
                Button { showAddMeasurement = true } label: {
                    Label("Misura", systemImage: "plus")
                        .font(Typo.mono(10, .bold)).tracking(1)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().stroke(Palette.cyan, lineWidth: 1))
                        .foregroundStyle(Palette.cyan)
                }
            }
            if measurementSamples.count >= 2 {
                MeasurementTrends(samples: measurementSamples, accent: Palette.cyan)
            } else {
                EmptyPanel(icon: "chart.xyaxis.line", text: "Aggiungi una misura o assegna check\nper mostrare i grafici.")
            }
        }
    }

    // MARK: Andamento esercizi — drill into the athlete's active workout

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Andamento", title: "Allenamento", accent: Palette.magenta)
            NavigationLink(value: CoachProgressRoute(clientId: clientId)) {
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.magenta).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Progressi").font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                        Text("KPI, aderenza, RPE, carichi e storico sessioni")
                            .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.textLow)
                }
                .padding(14).voltPanel()
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    // MARK: Percorso — last event + link to the full managed timeline

    private var percorsoSection: some View {
        let events = (percorso?.events ?? []).sorted { $0.date > $1.date }
        let phaseCount = percorso?.phases.count ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CoachSectionTitle(eyebrow: "Programmazione", title: "Percorso", accent: Palette.phase)
                Spacer()
                NavigationLink(value: CoachJourneyRoute(clientId: clientId)) {
                    HStack(spacing: 4) {
                        Text("Gestisci").font(Typo.mono(10, .bold)).tracking(1).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Palette.phase)
                }
            }
            NavigationLink(value: CoachJourneyRoute(clientId: clientId)) {
                lastEventCard(events.first, phaseCount: phaseCount)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    @ViewBuilder private func lastEventCard(_ ev: JourneyEventDTO?, phaseCount: Int) -> some View {
        if let ev {
            let m = coachJourneyMeta(ev.type)
            HStack(spacing: 14) {
                Image(systemName: m.icon).font(.system(size: 16, weight: .bold))
                    .foregroundStyle(m.color).frame(width: 34, height: 34)
                    .background(Circle().fill(m.color.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.label.uppercased()).font(Typo.mono(9, .bold)).tracking(1.5).foregroundStyle(m.color)
                        Text("· ultimo").font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                    }
                    Text(ev.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                    Text(CoachDate.dayMonth(ev.date)).font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(14).voltPanel(Palette.phase.opacity(0.3))
        } else {
            HStack(spacing: 14) {
                Image(systemName: "flag").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.phase).frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.phase.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseCount > 0 ? "\(phaseCount) fasi nel percorso" : "Percorso vuoto")
                        .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    Text("Tocca per gestire fasi ed eventi").font(Typo.body(12)).foregroundStyle(Palette.textMid)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(14).voltPanel(Palette.phase.opacity(0.3))
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let detail = APIClient.shared.coachClient(id: clientId)
        async let prog = APIClient.shared.coachClientProgress(clientId: clientId)
        data = try? await detail
        progress = (try? await prog) ?? []
        await loadPercorso()
    }

    private func loadPercorso() async {
        percorso = try? await APIClient.shared.coachClientPercorso(clientId: clientId, offset: 0)
    }
}

// MARK: - Compact line/area trend chart (volt style, no external deps)

struct CoachTrendChart: View {
    let values: [Double]
    var accent: Color = Palette.cyan

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * w : 0
                let y = h - CGFloat((v - lo) / span) * (h - 16) - 8
                return CGPoint(x: x, y: y)
            }
            ZStack {
                // Area fill
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    if let last = pts.last { p.addLine(to: CGPoint(x: last.x, y: h)) }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                // Line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // Endpoint dot
                if let last = pts.last {
                    Circle().fill(accent).frame(width: 8, height: 8)
                        .neonGlow(accent, radius: 6).position(last)
                }
            }
        }
    }
}

/// Hashable route wrapper so a check id can coexist with the Int client route.
struct CheckRoute: Hashable { let id: Int }
struct CoachClientWorkoutRoute: Hashable { let clientId: Int }
struct CoachJourneyRoute: Hashable { let clientId: Int }
struct CoachProgressRoute: Hashable { let clientId: Int }
struct CoachSessionsRoute: Hashable { let clientId: Int }
struct CoachSessionRoute: Hashable { let sessionId: Int }

/// Paged list of a client's past sessions; rows push the shared SessionDetailView.
struct CoachSessionsView: View {
    let clientId: Int
    @State private var sessions: [SessionBriefDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?

    var body: some View {
        ScreenScroll {
            if loading {
                ProgressView().tint(Palette.magenta).frame(maxWidth: .infinity).padding(.top, 60)
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
            } else if sessions.isEmpty {
                EmptyPanel(icon: "clock.arrow.circlepath", text: "Nessuna sessione registrata.")
            } else {
                ForEach(sessions) { s in
                    NavigationLink(value: CoachSessionRoute(sessionId: s.id)) { row(s) }
                        .buttonStyle(PressableButtonStyle())
                }
                if hasMore {
                    LoadMoreButton(loading: loadingMore, accent: Palette.magenta) { Task { await loadMore() } }
                }
            }
        }
        .navigationTitle("Storico sessioni")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ s: SessionBriefDTO) -> some View {
        let statusColor = s.completed ? Palette.lime : (s.interrupted ? Palette.amber : Palette.textLow)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.dayName ?? "Sessione").font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                HStack(spacing: 12) {
                    Text(CoachDate.dayMonth(s.startedAt)).font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                    if let d = s.durationMinutes {
                        Label("\(d) min", systemImage: "timer").font(Typo.mono(10)).foregroundStyle(Palette.textMid)
                    }
                    if let r = s.avgRpe {
                        Label(String(format: "RPE %.1f", r), systemImage: "flame.fill")
                            .font(Typo.mono(10)).foregroundStyle(Palette.textMid)
                    }
                }
            }
            Spacer()
            Image(systemName: s.completed ? "checkmark.seal.fill" : (s.interrupted ? "exclamationmark.triangle.fill" : "circle"))
                .font(.system(size: 18, weight: .black)).foregroundStyle(statusColor)
        }
        .padding(14).voltPanel(statusColor.opacity(0.4))
    }

    private func load() async {
        loading = true; error = nil
        do {
            let page = try await APIClient.shared.coachClientSessions(clientId: clientId)
            sessions = page.sessions
            hasMore = page.hasMore ?? false
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, !loading else { return }
        loadingMore = true; defer { loadingMore = false }
        guard let page = try? await APIClient.shared.coachClientSessions(clientId: clientId, offset: sessions.count)
        else { return }
        let known = Set(sessions.map(\.id))
        sessions.append(contentsOf: page.sessions.filter { !known.contains($0.id) })
        hasMore = page.hasMore ?? false
    }
}
struct CoachExerciseTrendRoute: Hashable { let clientId: Int; let exercise: ExerciseDTO }

// MARK: - Client active workout → per-exercise trend (coach view)

struct CoachClientWorkoutView: View {
    let clientId: Int
    @State private var data: CoachClientWorkoutDTO?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Andamento", title: "Esercizi",
                         subtitle: data?.plan?.title ?? "Allenamento attivo", accent: Palette.magenta)
            if loading && data == nil {
                AvatarRowsSkeleton(accent: Palette.magenta)
            } else if let d = data, d.plan != nil, !d.days.isEmpty {
                ForEach(d.days) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        CoachSectionTitle(eyebrow: "Giorno", title: day.label, accent: Palette.magenta)
                        ForEach(day.exercises) { ex in
                            NavigationLink(value: CoachExerciseTrendRoute(clientId: clientId, exercise: ex)) {
                                exerciseRow(ex)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            } else {
                EmptyPanel(icon: "dumbbell", text: "Nessun allenamento attivo assegnato.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CoachExerciseTrendRoute.self) { r in
            CoachExerciseTrendView(clientId: r.clientId, exercise: r.exercise)
        }
        .task { await load() }
    }

    private func exerciseRow(_ ex: ExerciseDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.magenta).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                if let m = ex.targetMuscleGroup, !m.isEmpty {
                    Text(m.uppercased()).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            Image(systemName: "chart.xyaxis.line").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        data = try? await APIClient.shared.coachClientWorkout(clientId: clientId)
    }
}

struct CoachExerciseTrendView: View {
    let clientId: Int
    let exercise: ExerciseDTO

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Esercizio", title: exercise.name,
                         subtitle: exercise.targetMuscleGroup ?? "Andamento", accent: Palette.magenta)
            ExerciseTrendCard {
                try await APIClient.shared.coachExerciseTrend(clientId: clientId, workoutExerciseId: exercise.id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add phase (coach)

struct CoachAddPhaseView: View {
    let clientId: Int
    let editing: JourneyPhaseDTO?
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var note: String
    @State private var startDate: Date
    @State private var durationValue: Int
    @State private var durationUnit: String
    @State private var saving = false
    @State private var error: String?

    init(clientId: Int, editing: JourneyPhaseDTO? = nil, onSaved: @escaping () -> Void) {
        self.clientId = clientId
        self.editing = editing
        self.onSaved = onSaved
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        _title = State(initialValue: editing?.title ?? "")
        _note = State(initialValue: editing?.note ?? "")
        _startDate = State(initialValue: editing.flatMap { f.date(from: $0.start) } ?? Date())
        _durationValue = State(initialValue: editing?.durationValue ?? 4)
        _durationUnit = State(initialValue: editing?.durationUnit ?? "WEEKS")
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Percorso", title: editing == nil ? "Nuova fase" : "Modifica fase",
                             subtitle: "Scandisci il percorso dell'atleta", accent: Palette.phase)

                field("Titolo") {
                    TextField("", text: $title, prompt: Text("Es. Definizione").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.phase)
                }
                field("Inizio") {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().tint(Palette.phase)
                }
                field("Durata") {
                    HStack(spacing: 12) {
                        Stepper(value: $durationValue, in: 1...52) {
                            Text("\(durationValue)").font(Typo.mono(16, .bold)).foregroundStyle(Palette.textHi)
                        }
                        Picker("", selection: $durationUnit) {
                            Text("Settimane").tag("WEEKS")
                            Text("Mesi").tag("MONTHS")
                        }
                        .pickerStyle(.segmented).frame(width: 170)
                    }
                }
                field("Note") {
                    TextField("", text: $note, prompt: Text("Opzionale").foregroundStyle(Palette.textLow),
                              axis: .vertical)
                        .font(Typo.body(15)).tint(Palette.phase).lineLimit(2...5)
                }

                if let error {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber)
                }

                NeonButton(title: saving ? "Salvataggio…" : (editing == nil ? "Aggiungi fase" : "Salva modifiche"),
                           icon: "flag.fill", color: Palette.phase) {
                    Task { await save() }
                }
                .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 6)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .voltPanel(radius: 14)
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        error = nil
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanNote = note.trimmingCharacters(in: .whitespaces)
        do {
            if let editing {
                _ = try await APIClient.shared.coachUpdatePhase(
                    clientId: clientId, phaseId: editing.id,
                    title: cleanTitle, startDate: f.string(from: startDate),
                    durationValue: durationValue, durationUnit: durationUnit, note: cleanNote)
            } else {
                _ = try await APIClient.shared.coachAddPhase(
                    clientId: clientId, title: cleanTitle, startDate: f.string(from: startDate),
                    durationValue: durationValue, durationUnit: durationUnit, note: cleanNote)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = "Impossibile salvare la fase. Riprova."
        }
    }
}

// MARK: - Aggiungi atleta (onboarding, come la web app)

struct CoachAddClientView: View {
    /// Called after a successful create so the list can refresh.
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var gender = ""           // "" | M | F
    @State private var plans: [CoachSubscriptionPlanDTO] = []
    @State private var planId: Int?
    @State private var loadingPlans = true
    @State private var saving = false
    @State private var error: String?

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") && planId != nil && !saving
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Onboarding", title: "Aggiungi atleta",
                             subtitle: "Riceverà un'email per impostare la password", accent: Palette.cyan)

                field("Nome") {
                    TextField("", text: $firstName, prompt: Text("Mario").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan).textContentType(.givenName)
                }
                field("Cognome") {
                    TextField("", text: $lastName, prompt: Text("Rossi").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan).textContentType(.familyName)
                }
                field("Email") {
                    TextField("", text: $email, prompt: Text("mario@email.com").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().textContentType(.emailAddress)
                }
                field("Telefono") {
                    TextField("", text: $phone, prompt: Text("Opzionale").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan).keyboardType(.phonePad)
                }
                field("Sesso") {
                    Picker("", selection: $gender) {
                        Text("Non indicato").tag("")
                        Text("Uomo").tag("M")
                        Text("Donna").tag("F")
                    }
                    .pickerStyle(.segmented)
                }
                field("Data di nascita") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Imposta data", isOn: $hasBirthDate.animation())
                            .font(Typo.body(13)).tint(Palette.cyan)
                        if hasBirthDate {
                            DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden().tint(Palette.cyan)
                        }
                    }
                }
                field("Piano di abbonamento") {
                    if loadingPlans {
                        Text("Caricamento…").font(Typo.body(13)).foregroundStyle(Palette.textLow)
                    } else if plans.isEmpty {
                        Text("Nessun piano attivo. Crea un piano dal web.")
                            .font(Typo.body(13)).foregroundStyle(Palette.amber)
                    } else {
                        Picker("", selection: $planId) {
                            ForEach(plans) { p in
                                Text("\(p.name) · €\(String(format: "%.0f", p.price))").tag(Optional(p.id))
                            }
                        }
                        .pickerStyle(.menu).tint(Palette.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber)
                }

                NeonButton(title: saving ? "Creazione…" : "Crea atleta", icon: "person.badge.plus",
                           color: Palette.cyan) {
                    Task { await save() }
                }
                .disabled(!canSave)
                .padding(.top, 6)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .task { await loadPlans() }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .voltPanel(radius: 14)
        }
    }

    private func loadPlans() async {
        loadingPlans = true; defer { loadingPlans = false }
        plans = (try? await APIClient.shared.coachSubscriptionPlans()) ?? []
        if planId == nil { planId = plans.first?.id }
    }

    private func save() async {
        guard let planId else { return }
        saving = true; defer { saving = false }
        error = nil
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        do {
            try await APIClient.shared.coachCreateClient(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                phone: phone.isEmpty ? nil : phone,
                birthDate: hasBirthDate ? f.string(from: birthDate) : nil,
                gender: gender.isEmpty ? nil : gender,
                subscriptionPlanId: planId,
                paymentNotes: nil)
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Impossibile creare l'atleta. Riprova."
        }
    }
}

// MARK: - Coach journey ("Percorso" gestibile)
//
// Same timeline the athlete sees in "Il mio percorso", but the coach can add,
// edit and delete phases. Events (assigned plans, diets, checks) are read-only;
// phases carry edit/delete controls.

func coachJourneyMeta(_ type: String) -> (icon: String, label: String, color: Color) {
    switch type {
    case "allenamento": return ("dumbbell.fill", "Allenamento", Palette.magenta)
    case "nutrizione":  return ("leaf.fill", "Nutrizione", Palette.lime)
    case "check":       return ("chart.xyaxis.line", "Check", Palette.cyan)
    default:            return ("circle.fill", type.capitalized, Palette.bronze)
    }
}

struct CoachJourneyView: View {
    let clientId: Int
    @State private var events: [JourneyEventDTO] = []
    @State private var phases: [JourneyPhaseDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var filter: String?               // nil = all
    @State private var showPhaseSheet = false
    @State private var editingPhase: JourneyPhaseDTO?

    private enum Item: Identifiable {
        case event(JourneyEventDTO), phase(JourneyPhaseDTO)
        var id: String {
            switch self {
            case .event(let e): return "e-\(e.id)"
            case .phase(let p): return "p-\(p.id)"
            }
        }
        var date: String {
            switch self {
            case .event(let e): return e.date
            case .phase(let p): return p.start
            }
        }
    }

    private var shown: [Item] {
        var items: [Item] = []
        if filter == nil || filter == "fase" { items += phases.map(Item.phase) }
        if filter == nil { items += events.map(Item.event) }
        else if filter != "fase" { items += events.filter { $0.type == filter }.map(Item.event) }
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Programmazione", title: "Percorso",
                         subtitle: "Fasi ed eventi dell'atleta", accent: Palette.phase)

            Button { Haptics.tap(); editingPhase = nil; showPhaseSheet = true } label: {
                Label("Aggiungi fase", systemImage: "flag.fill")
                    .font(Typo.mono(11, .bold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Palette.void0)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Capsule().fill(Palette.phase))
            }
            .buttonStyle(PressableButtonStyle())

            if !events.isEmpty || !phases.isEmpty { filters }

            if loading && events.isEmpty && phases.isEmpty {
                AvatarRowsSkeleton(accent: Palette.phase)
            } else if shown.isEmpty {
                EmptyPanel(icon: "map", text: "Nessun avvenimento.\nAggiungi una fase per scandire il percorso.")
            } else {
                ForEach(shown) { item in
                    switch item {
                    case .event(let ev): eventRow(ev)
                    case .phase(let ph): phaseRow(ph)
                    }
                }
                if hasMore && filter != "fase" {
                    LoadMoreButton(loading: loadingMore, accent: Palette.phase) { Task { await loadMore() } }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhaseSheet) {
            CoachAddPhaseView(clientId: clientId, editing: editingPhase) { Task { await load() } }
        }
        .task { await load() }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "Tutto", Palette.phase)
                chip("allenamento", "Allenamento", Palette.magenta)
                chip("nutrizione", "Nutrizione", Palette.lime)
                chip("check", "Check", Palette.cyan)
                if !phases.isEmpty { chip("fase", "Fasi", Palette.phase) }
            }
        }
    }

    private func chip(_ value: String?, _ label: String, _ color: Color) -> some View {
        let on = filter == value
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = value }
        } label: {
            Text(label).font(Typo.mono(11, .bold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(on ? Palette.void0 : Palette.textMid)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background { if on { Capsule().fill(color) } else { Capsule().stroke(Palette.line, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ ev: JourneyEventDTO) -> some View {
        let m = coachJourneyMeta(ev.type)
        return HStack(spacing: 14) {
            Image(systemName: m.icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(m.color).frame(width: 34, height: 34)
                .background(Circle().fill(m.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.label.uppercased()).font(Typo.mono(9, .bold)).tracking(1.5).foregroundStyle(m.color)
                    Spacer()
                    Text(CoachDate.dayMonth(ev.date)).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                }
                Text(ev.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                if let sub = ev.subtitle, !sub.isEmpty {
                    Text(sub).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                }
            }
        }
        .padding(14).voltPanel(m.color.opacity(0.28))
    }

    private func phaseRow(_ ph: JourneyPhaseDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag.fill").font(.system(size: 14, weight: .black)).foregroundStyle(Palette.phase)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(ph.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text("\(CoachDate.dayMonth(ph.start)) → \(CoachDate.dayMonth(ph.end))")
                    .font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
                if !ph.note.isEmpty {
                    Text(ph.note).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                }
            }
            Spacer()
            Button { Haptics.tap(); editingPhase = ph; showPhaseSheet = true } label: {
                Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.phase)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                Task {
                    try? await APIClient.shared.coachDeletePhase(clientId: clientId, phaseId: ph.id)
                    await load()
                }
            } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .buttonStyle(.plain)
        }
        .padding(14).voltPanel(Palette.phase.opacity(0.4))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.phase.opacity(0.4), lineWidth: 1.5))
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let r = try? await APIClient.shared.coachClientPercorso(clientId: clientId, offset: 0) {
            events = r.events; phases = r.phases; hasMore = r.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let r = try? await APIClient.shared.coachClientPercorso(clientId: clientId, offset: events.count) {
            let known = Set(events.map(\.id))
            events.append(contentsOf: r.events.filter { !known.contains($0.id) })
            hasMore = r.hasMore
        }
    }
}
