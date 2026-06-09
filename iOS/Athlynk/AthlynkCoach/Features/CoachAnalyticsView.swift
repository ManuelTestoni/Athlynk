//
//  CoachAnalyticsView.swift
//  "Analisi Progressi (Coach)" — practice-wide metrics + an 8-week check-volume
//  sparkline drawn with native shapes (no chart dependency).
//

import SwiftUI

struct CoachAnalyticsView: View {
    @State private var data: CoachAnalyticsDTO?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Studio", title: "Analisi",
                         subtitle: "L'andamento del tuo lavoro", accent: Palette.cyan)
            if loading && data == nil {
                CoachAnalyticsSkeleton()
            } else if let d = data {
                HStack(spacing: 14) {
                    CoachStatTile(value: "\(d.activeClients)", label: "Atleti attivi",
                                  icon: "person.2.fill", accent: Palette.cyan)
                    CoachStatTile(value: "\(d.totalChecks)", label: "Check totali",
                                  icon: "checkmark.seal.fill", accent: Palette.bronze)
                }
                reviewRateCard(d)
                chartCard(d)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
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

    private func load() async { loading = true; defer { loading = false }
        data = try? await APIClient.shared.coachAnalytics() }
}
