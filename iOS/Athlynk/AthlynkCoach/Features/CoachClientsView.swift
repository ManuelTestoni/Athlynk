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
    @State private var error: String?

    private let filters: [(String, String)] = [("", "Tutti"), ("ACTIVE", "Attivi"), ("INACTIVE", "Sospesi")]

    var body: some View {
        NavigationStack {
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
                }

                if loading && rows.isEmpty {
                    LoadingPanel()
                } else if rows.isEmpty {
                    EmptyPanel(icon: "person.2", text: "Nessun atleta trovato.")
                } else {
                    ForEach(rows) { r in
                        NavigationLink(value: r.id) { clientCard(r) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationDestination(for: Int.self) { CoachClientDetailView(clientId: $0) }
            .task { await load() }
            .onRemoteChange { Task { await load() } }
            .refreshable { await load() }
        }
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
                Text(r.activeWorkout ?? r.primaryGoal ?? r.relationshipLabel)
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
            rows = res.clients; total = res.total; active = res.active; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Client detail ("Profilo Atleta — Vista Coach")

struct CoachClientDetailView: View {
    let clientId: Int
    @State private var data: CoachClientDetailDTO?
    @State private var progress: [CoachProgressEntry] = []
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
                checksSection(d)
            } else if loading {
                LoadingPanel()
            } else {
                EmptyPanel(icon: "person.crop.circle.badge.exclamationmark", text: "Atleta non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func profileHeader(_ d: CoachClientDetailDTO) -> some View {
        VStack(spacing: 12) {
            CoachClientAvatar(url: d.client.profileImageUrl, initials: d.client.initials, size: 92)
            Text(d.client.displayName).font(Typo.poster(32)).foregroundStyle(Palette.textHi)
            if let goal = d.client.primaryGoal {
                Text(goal.uppercased()).font(Typo.mono(11, .semibold)).tracking(2)
                    .foregroundStyle(Palette.bronze)
            }
            StatusBadge(text: d.relationship.status ?? "—",
                        color: (d.relationship.status == "ACTIVE") ? Palette.lime : Palette.textLow)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statRow(_ d: CoachClientDetailDTO) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            miniStat("\(d.client.heightCm.map { "\($0)" } ?? "—")", "Altezza cm")
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

    private func assignRow(_ icon: String, _ label: String, _ value: String, _ accent: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typo.mono(10, .semibold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Palette.textMid)
                Text(value).font(Typo.body(15, .medium)).foregroundStyle(Palette.textHi).lineLimit(1)
            }
            Spacer()
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

    // MARK: Charts (weight + measurement trend from the athlete's checks)

    private var weightPoints: [Double] {
        progress.reversed().compactMap { $0.weightKg }   // oldest → newest
    }

    @ViewBuilder private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Andamento", title: "Grafici", accent: Palette.cyan)
            if weightPoints.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("PESO").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                        Spacer()
                        if let last = weightPoints.last {
                            Text("\(String(format: "%.1f", last)) kg")
                                .font(Typo.mono(13, .bold)).foregroundStyle(Palette.cyan)
                        }
                    }
                    CoachTrendChart(values: weightPoints, accent: Palette.cyan)
                        .frame(height: 130)
                    HStack {
                        Text("\(weightPoints.count) check").font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                        Spacer()
                        if let first = weightPoints.first, let last = weightPoints.last {
                            let delta = last - first
                            Text(String(format: "%+.1f kg", delta))
                                .font(Typo.mono(10, .bold))
                                .foregroundStyle(delta <= 0 ? Palette.lime : Palette.amber)
                        }
                    }
                }
                .padding(16).voltPanel()
            } else {
                EmptyPanel(icon: "chart.xyaxis.line", text: "Servono almeno 2 check con il peso\nper mostrare i grafici.")
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let detail = APIClient.shared.coachClient(id: clientId)
        async let prog = APIClient.shared.coachClientProgress(clientId: clientId)
        data = try? await detail
        progress = (try? await prog) ?? []
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
