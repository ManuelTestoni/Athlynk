//
//  PricingView.swift
//  Stitch "Piani e Prezzi": the subscription plans offered by the athlete's
//  coaches. Backed by GET /api/v1/plans (SubscriptionPlan). The actual purchase
//  (Stitch "Checkout") needs a payment integration — "Scegli" is a placeholder.
//

import SwiftUI

struct PricingView: View {
    @State private var plans: [SubscriptionPlanDTO] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.magenta, Palette.violet, Palette.bronze])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if loading {
                        PricingSkeleton(count: 2)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.bronze)
                    } else if plans.isEmpty {
                        EmptyPanel(icon: "tag", text: "Nessun piano disponibile al momento.")
                    } else {
                        ForEach(Array(plans.enumerated()), id: \.element.id) { i, plan in
                            planCard(plan, featured: i == 0)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Piani e Prezzi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABBONAMENTI").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.bronze)
            Text("Piani e Prezzi").font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            Text("Scegli il percorso di coaching più adatto ai tuoi obiettivi.")
                .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
        }
    }

    private func planCard(_ plan: SubscriptionPlanDTO, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if featured { StatusBadge(text: "Consigliato", color: Palette.bronze) }
                    Text(plan.name).font(Typo.display(24)).foregroundStyle(Palette.textHi)
                    if let t = plan.planType, !t.isEmpty {
                        Text(t.uppercased()).font(Typo.mono(9, .bold)).tracking(2)
                            .foregroundStyle(Palette.bronze)
                    }
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(priceLabel(plan)).font(Typo.poster(36)).foregroundStyle(Palette.bronze)
                if let interval = plan.billingInterval {
                    Text("/ \(interval)").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                }
            }

            if let desc = plan.description, !desc.isEmpty {
                Text(desc).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            }

            if !plan.includedServices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.includedServices.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .black)).foregroundStyle(Palette.lime)
                            Text(s).font(Typo.body(13)).foregroundStyle(Palette.textHi)
                            Spacer()
                        }
                    }
                }
            }

            if let coach = plan.coach {
                HStack { Spacer(); CoachChip(coach: coach, color: Palette.bronze) }
            }

            NavigationLink { CheckoutView(plan: plan) } label: {
                HStack(spacing: 8) {
                    Text("Scegli").font(Typo.body(16, .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(featured ? Palette.void0 : Palette.textHi)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background { if featured { Palette.bronze } }
                .overlay(Capsule().stroke(featured ? .clear : Palette.line, lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18).voltPanel(Palette.bronze.opacity(featured ? 0.55 : 0.35))
    }

    private func priceLabel(_ plan: SubscriptionPlanDTO) -> String {
        let symbol = plan.currency == "EUR" ? "€" : plan.currency + " "
        let n = plan.price.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(plan.price)) : String(format: "%.2f", plan.price)
        return "\(symbol)\(n)"
    }

    private func load() async {
        loading = true; error = nil
        do { plans = try await APIClient.shared.plans() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
