//
//  CoachAnalyticsView.swift
//  "Analisi Progressi (Coach)" — practice-wide metrics + an 8-week check-volume
//  sparkline drawn with native shapes (no chart dependency).
//

import SwiftUI

struct CoachAnalyticsView: View {
    @State private var data: CoachAnalyticsDTO?
    @State private var business: CoachBusinessDTO?
    @State private var risk: [CoachRiskClient] = []
    @State private var loading = true
    @State private var appear = false

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Studio", title: "Analisi",
                         subtitle: "L'andamento del tuo lavoro", accent: Palette.cyan)
                .revealUp(appear, index: 0)
            if loading && data == nil {
                CoachAnalyticsSkeleton()
            } else if let d = data {
                if let b = business { businessGrid(b).revealUp(appear, index: 1) }
                if !risk.isEmpty { atRiskSection().revealUp(appear, index: 2) }
                HStack(spacing: 14) {
                    CoachStatTile(value: "\(d.activeClients)", label: "Atleti attivi",
                                  icon: "person.2.fill", accent: Palette.cyan)
                    CoachStatTile(value: "\(d.totalChecks)", label: "Check totali",
                                  icon: "checkmark.seal.fill", accent: Palette.bronze)
                }
                .revealUp(appear, index: 3)
                reviewRateCard(d).revealUp(appear, index: 4)
                chartCard(d).revealUp(appear, index: 5)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Business KPIs + churn risk (from the nightly rollups)

    private func kpi(_ v: Double?, _ suffix: String = "") -> String {
        guard let v else { return "—" }
        let n = v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
        return "\(n)\(suffix)"
    }

    private func businessGrid(_ b: CoachBusinessDTO) -> some View {
        let k = b.kpis
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: "Business", title: "Studio in cifre", accent: Palette.amber)
            LazyVGrid(columns: cols, spacing: 14) {
                CoachStatTile(value: kpi(k.atRiskClientsCount), label: "A rischio",
                              icon: "exclamationmark.triangle.fill", accent: Palette.amber,
                              flag: (k.atRiskClientsCount ?? 0) > 0 ? "ATTENZIONE" : nil)
                CoachStatTile(value: kpi(k.renewalsDue7d), label: "Rinnovi 7gg",
                              icon: "calendar.badge.clock", accent: Palette.cyan)
                CoachStatTile(value: kpi(k.monthlyRevenue, "€"), label: "Ricavo attivo",
                              icon: "eurosign.circle.fill", accent: Palette.lime)
                CoachStatTile(value: kpi(k.churnRate30d, "%"), label: "Churn 30gg",
                              icon: "chart.line.downtrend.xyaxis", accent: Palette.phase)
            }
        }
    }

    private func atRiskSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Churn", title: "Clienti a rischio", accent: Palette.phase)
            ForEach(risk) { c in riskCard(c) }
        }
    }

    private func riskCard(_ c: CoachRiskClient) -> some View {
        let accent: Color = c.riskClass == "high" ? Palette.phase
            : (c.riskClass == "medium" ? Palette.amber : Palette.lime)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoachClientAvatar(url: c.profileImageUrl, initials: initials(c.displayName), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    Text(riskLabel(c.riskClass)).font(Typo.mono(10, .bold)).tracking(1)
                        .textCase(.uppercase).foregroundStyle(accent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(c.riskScore)").font(Typo.poster(26)).foregroundStyle(accent)
                    if let p = c.riskProbabilityMl {
                        Text("ML \(Int((p * 100).rounded()))%").font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                    }
                }
            }
            if !c.reasons.isEmpty {
                FlowChips(labels: c.reasons.map(\.label), accent: accent)
            }
        }
        .padding(14).voltPanel(accent.opacity(0.25))
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
    private func riskLabel(_ cls: String) -> String {
        ["high": "Rischio alto", "medium": "Rischio medio", "low": "Rischio basso"][cls] ?? cls
    }

    private func reviewRateCard(_ d: CoachAnalyticsDTO) -> some View {
        HStack(spacing: 18) {
            RingGauge(progress: d.reviewRate / 100, color: Palette.lime, lineWidth: 10,
                      label: "Revisione", value: "\(Int(d.reviewRate))%")
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("TASSO DI REVISIONE").voltEyebrow()
                Text("\(d.reviewedChecks) check su \(d.totalChecks) hanno ricevuto un feedback.")
                    .font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18).voltPanel()
    }

    private func chartCard(_ d: CoachAnalyticsDTO) -> some View {
        let maxVal = max(d.checksSeries.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            CoachSectionTitle(eyebrow: "8 settimane", title: "Check ricevuti", accent: Palette.bronze)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(d.checksSeries) { pt in
                    VStack(spacing: 6) {
                        Text("\(pt.count)").font(Typo.mono(9, .bold)).foregroundStyle(Palette.textMid)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.bronze, Palette.amber],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(height: max(6, CGFloat(pt.count) / CGFloat(maxVal) * 120))
                        Text(weekLabel(pt.weekStart)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)
        }
        .padding(18).voltPanel()
    }

    private func weekLabel(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return "" }
        let out = DateFormatter(); out.locale = Locale(identifier: "it_IT"); out.dateFormat = "d/M"
        return out.string(from: d)
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let a = APIClient.shared.coachAnalytics()
        async let b = APIClient.shared.coachAnalyticsBusiness()
        async let r = APIClient.shared.coachAnalyticsRisk(riskClass: "all")
        data = try? await a
        business = try? await b
        risk = ((try? await r)?.clients ?? []).filter { $0.riskClass != "low" }
    }
}

/// Wrapping row of small reason-code chips. Explains *why* a client is at risk.
private struct FlowChips: View {
    let labels: [String]
    var accent: Color = Palette.bronze

    var body: some View {
        FlexWrap(spacing: 6, lineSpacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(Typo.mono(9, .semibold)).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }
        }
    }
}

/// Minimal flow layout: lays children left-to-right, wrapping to a new line when
/// the row overflows. Avoids a dependency for the few chips we render.
private struct FlexWrap: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
