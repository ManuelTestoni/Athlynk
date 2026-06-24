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
        if !adherence.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionTitle(eyebrow: "Programma", title: "Aderenza settimanale", accent: accent)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(adherence.suffix(12)) { p in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(adherenceColor(p.pct))
                            .frame(height: max(4, 110 * p.pct / 100))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110, alignment: .bottom)
                .padding(14).voltPanel()
            }
        }
    }

    private func adherenceColor(_ pct: Double) -> Color {
        pct >= 80 ? Palette.lime : (pct >= 50 ? Palette.amber : Palette.magenta)
    }

    // MARK: RPE (sparkline)

    @ViewBuilder private var rpeSection: some View {
        let pts = rpe.compactMap { $0.avgRpe }
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                CoachSectionTitle(eyebrow: "Intensità", title: "Andamento RPE medio", accent: accent)
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    Path { path in
                        for (i, v) in pts.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(max(pts.count - 1, 1))
                            let y = h * (1 - CGFloat(v) / 10)
                            i == 0 ? path.move(to: .init(x: x, y: y)) : path.addLine(to: .init(x: x, y: y))
                        }
                    }
                    .stroke(accent, style: .init(lineWidth: 2, lineJoin: .round))
                }
                .frame(height: 90)
                .padding(14).voltPanel()
            }
        }
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
