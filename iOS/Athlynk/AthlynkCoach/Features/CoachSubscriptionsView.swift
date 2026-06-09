//
//  CoachSubscriptionsView.swift
//  "Gestione Abbonamenti (Coach)" — plans, active subscriptions and revenue.
//

import SwiftUI

struct CoachSubscriptionsView: View {
    @State private var data: CoachSubscriptionsDTO?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Ricavi", title: "Abbonamenti",
                         subtitle: "Piani e clienti paganti", accent: Palette.amber)
            if loading && data == nil {
                CoachSubscriptionsSkeleton()
            } else if let d = data {
                HStack(spacing: 14) {
                    CoachStatTile(value: "€\(Int(d.monthlyRevenue))", label: "Ricavo attivo",
                                  icon: "eurosign.circle.fill", accent: Palette.amber)
                    CoachStatTile(value: "\(d.activeCount)", label: "Abbonati attivi",
                                  icon: "person.badge.shield.checkmark.fill", accent: Palette.lime)
                }

                CoachSectionTitle(eyebrow: "Offerta", title: "Piani", accent: Palette.amber)
                if d.plans.isEmpty {
                    EmptyPanel(icon: "creditcard", text: "Nessun piano creato.")
                } else {
                    ForEach(d.plans) { p in planRow(p) }
                }

                if !d.subscriptions.isEmpty {
                    CoachSectionTitle(eyebrow: "Clienti", title: "Abbonamenti", accent: Palette.cyan)
                    ForEach(d.subscriptions) { s in subRow(s) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func planRow(_ p: CoachPlanSummary) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                Text("€\(String(format: "%.0f", p.price)) · \(p.billingInterval ?? p.planType ?? "")")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(p.activeCount)").font(Typo.poster(24)).foregroundStyle(Palette.amber)
                Text("attivi").font(Typo.mono(8, .semibold)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Palette.textLow)
            }
            if !p.isActive { StatusBadge(text: "Off", color: Palette.textLow, filled: false) }
        }
        .padding(14).voltPanel()
    }

    private func subRow(_ s: CoachSubscriptionRow) -> some View {
        HStack(spacing: 12) {
            CoachClientAvatar(url: s.client.profileImageUrl, initials: s.client.initials, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.client.displayName).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text(s.planName).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            StatusBadge(text: s.status, color: s.status == "ACTIVE" ? Palette.lime : Palette.textLow)
        }
        .padding(14).voltPanel()
    }

    private func load() async { loading = true; defer { loading = false }
        data = try? await APIClient.shared.coachSubscriptions() }
}
