//
//  CheckoutView.swift
//  Stitch "Checkout": order summary, then a real Stripe Checkout Session
//  (see APIClient.checkoutStart) opened in a system web view via
//  StripeWebFlow. Payment details are collected on Stripe's hosted page, not
//  in this app — "Conferma e paga" only starts the session and waits for the
//  redirect back. Fulfilment happens server-side on the webhook; this screen
//  never marks the purchase paid itself.
//

import SwiftUI
import AuthenticationServices

struct CheckoutView: View {
    let plan: SubscriptionPlanDTO
    @State private var paid = false
    @State private var processing = false
    @State private var errorMessage: String?
    private let webFlow = StripeWebFlow()

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.magenta, Palette.violet, Palette.bronze])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryCard
                    totalCard
                    if let errorMessage {
                        Text(errorMessage).font(Typo.body(13)).foregroundStyle(Palette.danger)
                    }
                    NeonButton(title: processing ? "Elaborazione…" : "Conferma e paga",
                               icon: "lock.fill", color: Palette.bronze, loading: processing) {
                        Task { await pay() }
                    }
                    Text("Pagamento sicuro gestito da Stripe.")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $paid) { CheckoutSuccessView(plan: plan) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RIEPILOGO ORDINE").voltEyebrow()
            Text(plan.name).font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = plan.planType, !t.isEmpty {
                Text(t.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.bronze)
            }
            if let desc = plan.description, !desc.isEmpty {
                Text(desc).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            }
            ForEach(Array(plan.includedServices.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .black))
                        .foregroundStyle(Palette.lime)
                    Text(s).font(Typo.body(13)).foregroundStyle(Palette.textHi)
                    Spacer()
                }
            }
            if let coach = plan.coach {
                HStack { Spacer(); CoachChip(coach: coach, color: Palette.bronze) }
            }
        }
        .padding(18).voltPanel(Palette.bronze.opacity(0.4))
    }

    private var totalCard: some View {
        HStack {
            Text("TOTALE").font(Typo.mono(11, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            Spacer()
            Text(priceLabel).font(Typo.poster(30)).foregroundStyle(Palette.bronze)
            if let interval = plan.billingInterval {
                Text("/ \(interval)").font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
            }
        }
        .padding(18).voltPanel(Palette.bronze.opacity(0.45))
    }

    private var priceLabel: String {
        let symbol = plan.currency == "EUR" ? "€" : plan.currency + " "
        let n = plan.price.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(plan.price)) : String(format: "%.2f", plan.price)
        return "\(symbol)\(n)"
    }

    private func pay() async {
        processing = true; errorMessage = nil
        defer { processing = false }
        do {
            let urlString = try await APIClient.shared.checkoutStart(planId: plan.id)
            guard let url = URL(string: urlString) else { throw APIError.badURL }
            let callback = try await webFlow.run(url: url, callbackScheme: "athlynk")
            let host = callback.host ?? ""
            if host == "checkout-return" {
                Haptics.success()
                paid = true
            } else {
                errorMessage = "Pagamento annullato."
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the web view — not an error worth surfacing.
        } catch {
            errorMessage = "Impossibile completare il pagamento. Riprova."
        }
    }
}

struct CheckoutSuccessView: View {
    let plan: SubscriptionPlanDTO
    @Environment(\.dismiss) private var dismiss
    @State private var burst = 0

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.bronze, Palette.lime])
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle().fill(Palette.lime.opacity(0.16)).frame(width: 140, height: 140)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 72, weight: .black))
                        .foregroundStyle(Palette.lime).neonGlow(Palette.lime, radius: 20)
                }
                Text("PAGAMENTO\nRIUSCITO").font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                    .multilineTextAlignment(.center)
                Text("Il tuo abbonamento «\(plan.name)» è attivo. Buon allenamento!")
                    .font(Typo.body(15)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Spacer()
                NeonButton(title: "Fatto", icon: "checkmark", color: Palette.lime) { dismiss() }
                    .padding(.horizontal, 26).padding(.bottom, AppLayout.tabBarClearance)
            }
            ParticleBurst(trigger: burst)
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { burst += 1 }
    }
}
