//
//  SubscriptionView.swift
//  Stitch "Il Mio Abbonamento": the athlete's active subscription plan, price,
//  billing window, included services, and the coach who owns the plan.
//  Backed by GET /api/v1/subscription (ClientSubscription + SubscriptionPlan).
//

import SwiftUI

struct SubscriptionView: View {
    @State private var sub: SubscriptionDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.amber, Palette.violet, Palette.magenta])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        SubscriptionSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if let sub {
                        planCard(sub).revealUp(appear, index: 0)
                        if !sub.plan.includedServices.isEmpty {
                            servicesCard(sub.plan.includedServices).revealUp(appear, index: 1)
                        }
                    } else {
                        EmptyPanel(icon: "crown", text: "Nessun abbonamento attivo.")
                    }

                    if !loading {
                        NavigationLink { PricingView() } label: { pricingLink }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: 2)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Abbonamento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: loading) { _, l in if !l { appear = true } }
    }

    private var pricingLink: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.bronze.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "tag.fill")
                    .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.bronze)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Piani e prezzi").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                Text("Esplora gli abbonamenti disponibili")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                .foregroundStyle(Palette.bronze)
        }
        .padding(16).voltPanel(Palette.bronze.opacity(0.35))
    }

    private func planCard(_ sub: SubscriptionDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(text: statusLabel(sub.status),
                                color: isActive(sub.status) ? Palette.lime : Palette.amber)
                    Text(sub.plan.name).font(Typo.display(26)).foregroundStyle(Palette.textHi)
                    if let t = sub.plan.planType {
                        Text(t.uppercased()).font(Typo.mono(10, .bold)).tracking(2)
                            .foregroundStyle(Palette.magenta)
                    }
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .black)).foregroundStyle(Palette.amber)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(priceLabel(sub.plan)).font(Typo.poster(34)).foregroundStyle(Palette.amber)
                if let interval = sub.plan.billingInterval {
                    Text("/ \(interval)").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                }
            }

            if let desc = sub.plan.description, !desc.isEmpty {
                Text(desc).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            }

            Divider().overlay(Palette.line)

            VStack(spacing: 10) {
                infoRow("Inizio", dateLabel(sub.startDate))
                infoRow("Scadenza", dateLabel(sub.endDate))
                infoRow("Pagamento", (sub.paymentStatus ?? "—").capitalized)
                infoRow("Rinnovo auto.", sub.autoRenew ? "Attivo" : "Disattivo")
            }

            if let coach = sub.plan.coach {
                HStack { Spacer(); CoachChip(coach: coach, color: Palette.magenta) }
            }
        }
        .padding(18).voltPanel(Palette.amber.opacity(0.45))
    }

    private func servicesCard(_ services: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SERVIZI INCLUSI").voltEyebrow()
            ForEach(Array(services.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .black)).foregroundStyle(Palette.lime)
                    Text(s).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    Spacer()
                }
            }
        }
        .padding(18).voltPanel(Palette.lime.opacity(0.35))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            Spacer()
            Text(value).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
        }
    }

    private func priceLabel(_ plan: SubscriptionPlanDTO) -> String {
        let symbol = plan.currency == "EUR" ? "€" : plan.currency + " "
        let n = plan.price.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(plan.price)) : String(format: "%.2f", plan.price)
        return "\(symbol)\(n)"
    }

    private func statusLabel(_ s: String) -> String {
        switch s.lowercased() {
        case "active", "attivo": return "Attivo"
        case "expired", "scaduto": return "Scaduto"
        case "pending": return "In attesa"
        default: return s.capitalized
        }
    }
    private func isActive(_ s: String) -> Bool { ["active", "attivo"].contains(s.lowercased()) }

    private func dateLabel(_ iso: String?) -> String {
        guard let iso, let d = ISO8601.parse(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: d)
    }

    private func load() async {
        loading = true; error = nil
        do { sub = try await APIClient.shared.subscription() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
