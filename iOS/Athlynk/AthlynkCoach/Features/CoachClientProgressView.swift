//
//  CoachClientProgressView.swift
//  Native "Progressi" hub for a client — mirrors the web progressi page:
//  KPI summary, adherence + RPE trends, and links into the per-exercise charts
//  and the full session history. Backed by the (now token-enabled) web
//  /api/coach/clienti/<id>/progressi/* endpoints.
//

import SwiftUI

struct CoachClientProgressView: View {
    let clientId: Int

    @State private var kpi: CoachProgressKpiDTO?
    @State private var adherence: [AdherencePointDTO] = []
    @State private var rpe: [RpePointDTO] = []
    @State private var loading = true
    @State private var selAdh: Int?     // tapped adherence bar
    @State private var selRpe: Int?     // dragged RPE node

    private let accent = Palette.magenta

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Andamento", title: "Progressi",
                         subtitle: "Sintesi allenamenti", accent: accent)

            if loading && kpi == nil {
                AvatarRowsSkeleton(accent: accent)
            } else {
                kpiGrid
                adherenceSection
                rpeSection
                links
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: KPI

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            kpiCard("\(kpi?.totalSessions ?? 0)", "Sessioni totali", "figure.run")
            kpiCard(kpi?.overallAdherencePct.map { "\(Int($0))%" } ?? "—", "Aderenza", "target")
            kpiCard(setsText, "Serie / sessione", "square.stack.3d.up.fill")
            kpiCard("\(kpi?.streakDays ?? 0) gg", "Streak", "flame.fill")
        }
    }

    private var setsText: String {
        guard let v = kpi?.avgSetsPerSession else { return "—" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func kpiCard(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
            Text(value).font(Typo.poster(26)).foregroundStyle(Palette.textHi)
            Text(label.uppercased()).font(Typo.mono(9, .semibold)).tracking(1).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).voltPanel(radius: 14)
    }

    // MARK: Adherence (vertical bars, colour by threshold)

    @ViewBuilder private var adherenceSection: some View {
        let pts = Array(adherence.suffix(12))
        if !pts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionTitle(eyebrow: "Programma", title: "Aderenza settimanale", accent: accent)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allenamenti completati su quelli pianificati, per settimana. Tocca una barra.")
                        .font(Typo.mono(9)).foregroundStyle(Palette.textMid)
                    chartLegend([("≥ 80%", Palette.lime), ("50–79%", Palette.amber), ("< 50%", Palette.magenta)])
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array(pts.enumerated()), id: \.element.id) { i, p in
                            VStack(spacing: 4) {
                                Text(selAdh == i ? "\(Int(p.pct))%" : " ")
                                    .font(Typo.mono(8, .bold)).foregroundStyle(Palette.textHi)
                                    .lineLimit(1).fixedSize()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(adherenceColor(p.pct))
                                    .frame(height: max(4, 110 * p.pct / 100))
                                    .overlay(selAdh == i ? RoundedRectangle(cornerRadius: 3)
                                        .stroke(Palette.textHi, lineWidth: 1.5) : nil)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { Haptics.tap(); selAdh = (selAdh == i ? nil : i) }
                        }
                    }
                    .frame(height: 130, alignment: .bottom)
                    HStack {
                        Text(weekShort(pts.first?.week)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                        Spacer()
                        Text("media \(avgAdh(pts))%").font(Typo.mono(8, .bold)).foregroundStyle(Palette.textMid)
                        Spacer()
                        Text(weekShort(pts.last?.week)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                    }
                }
                .padding(14).voltPanel()
            }
        }
    }

    private func adherenceColor(_ pct: Double) -> Color {
        pct >= 80 ? Palette.lime : (pct >= 50 ? Palette.amber : Palette.magenta)
    }

    private func avgAdh(_ pts: [AdherencePointDTO]) -> Int {
        guard !pts.isEmpty else { return 0 }
        return Int((pts.map(\.pct).reduce(0, +) / Double(pts.count)).rounded())
    }

    // MARK: RPE (line with y-axis + drag tooltip)

    @ViewBuilder private var rpeSection: some View {
        let pts = rpe.compactMap { p in p.avgRpe.map { (p.week, $0) } }
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionTitle(eyebrow: "Intensità", title: "Andamento RPE medio", accent: accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sforzo percepito medio per settimana · scala 1–10 (più alto = più intenso). Trascina per leggere i valori.")
                        .font(Typo.mono(9)).foregroundStyle(Palette.textMid)
                    rpeChart(pts)
                    HStack {
                        Text(weekShort(pts.first?.0)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                        Spacer()
                        Text(weekShort(pts.last?.0)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                    }
                    .padding(.leading, 26)
                }
                .padding(14).voltPanel()
            }
        }
    }

    private func rpeChart(_ pts: [(String, Double)]) -> some View {
        let yAxisW: CGFloat = 26
        return GeometryReader { geo in
            let pw = geo.size.width - yAxisW
            let ph = geo.size.height
            func xf(_ i: Int) -> CGFloat { yAxisW + pw * CGFloat(i) / CGFloat(max(pts.count - 1, 1)) }
            func yf(_ v: Double) -> CGFloat { ph * (1 - CGFloat(v) / 10) }
            let nodes = pts.enumerated().map { CGPoint(x: xf($0.offset), y: yf($0.element.1)) }

            ZStack(alignment: .topLeading) {
                // Gridlines + Y labels (10 / 5 / 0)
                ForEach([10, 5, 0], id: \.self) { val in
                    let y = yf(Double(val))
                    Path { p in p.move(to: .init(x: yAxisW, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)) }
                        .stroke(Palette.line.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Text("\(val)").font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                        .frame(width: yAxisW - 6, alignment: .trailing)
                        .position(x: (yAxisW - 6) / 2, y: max(6, min(ph - 6, y)))
                }
                Path { p in
                    guard let f = nodes.first else { return }
                    p.move(to: f); nodes.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                ForEach(Array(nodes.enumerated()), id: \.offset) { i, n in
                    Circle().fill(selRpe == i ? accent : Palette.void0)
                        .overlay(Circle().stroke(accent, lineWidth: 2))
                        .frame(width: selRpe == i ? 11 : 7, height: selRpe == i ? 11 : 7)
                        .position(n)
                }
                if let i = selRpe, i < pts.count {
                    let n = nodes[i]
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f", pts[i].1)).font(Typo.mono(11, .bold)).foregroundStyle(Palette.textHi)
                        Text(weekShort(pts[i].0)).font(Typo.mono(8)).foregroundStyle(Palette.textMid)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.void1))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.5), lineWidth: 1))
                    .position(x: min(max(n.x, 40), geo.size.width - 40), y: 14)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard !nodes.isEmpty else { return }
                        if let nr = nodes.enumerated().min(by: {
                            abs($0.element.x - g.location.x) < abs($1.element.x - g.location.x)
                        }) {
                            if selRpe != nr.offset { Haptics.tap() }
                            selRpe = nr.offset
                        }
                    }
                    .onEnded { _ in selRpe = nil }
            )
        }
        .frame(height: 120)
    }

    // Legend chip row shared by the charts.
    private func chartLegend(_ items: [(String, Color)]) -> some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { label, color in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                    Text(label).font(Typo.mono(9)).foregroundStyle(Palette.textMid)
                }
            }
        }
    }

    /// "2026-W24" → "S24"; otherwise the raw label (e.g. a short date).
    private func weekShort(_ week: String?) -> String {
        guard let week, !week.isEmpty else { return "—" }
        if let r = week.range(of: #"W\d{1,2}"#, options: .regularExpression) {
            return "S" + week[r].dropFirst()  // e.g. "W24" → "S24"
        }
        return week
    }

    // MARK: Links to the richer screens

    private var links: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Dettaglio", title: "Approfondisci", accent: accent)
            linkRow("chart.xyaxis.line", "Progressioni carichi",
                    "Volume e top set per esercizio", CoachClientWorkoutRoute(clientId: clientId))
            linkRow("clock.arrow.circlepath", "Storico sessioni",
                    "Allenamenti passati e serie registrate", CoachSessionsRoute(clientId: clientId))
        }
    }

    private func linkRow<R: Hashable>(_ icon: String, _ title: String, _ sub: String, _ route: R) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    Text(sub).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(14).voltPanel()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let k = APIClient.shared.coachClientKpi(clientId: clientId)
        async let a = APIClient.shared.coachClientAdherence(clientId: clientId)
        async let r = APIClient.shared.coachClientRpe(clientId: clientId)
        kpi = try? await k
        adherence = (try? await a) ?? []
        rpe = (try? await r) ?? []
    }
}
