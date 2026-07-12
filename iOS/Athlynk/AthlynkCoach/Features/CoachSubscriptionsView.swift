//
//  CoachSubscriptionsView.swift
//  "Gestione Abbonamenti (Coach)" — plans, active subscriptions and revenue.
//

import SwiftUI
import AuthenticationServices

struct CoachSubscriptionsView: View {
    @State private var header: (activeCount: Int, monthlyRevenue: Double, currency: String, plans: [CoachPlanSummary])?
    @State private var subs: [CoachSubscriptionRow] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var appear = false
    @State private var chargesEnabled = false
    @State private var connecting = false
    @State private var connectError: String?
    private let webFlow = StripeWebFlow()

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Ricavi", title: "Abbonamenti",
                         subtitle: "Piani e clienti paganti", accent: Palette.amber)
                .revealUp(appear, index: 0)

            if !chargesEnabled {
                connectBanner.revealUp(appear, index: 1)
            }

            if loading && header == nil {
                CoachSubscriptionsSkeleton()
            } else if let h = header {
                HStack(spacing: 14) {
                    CoachStatTile(value: "€\(Int(h.monthlyRevenue))", label: "Ricavo attivo",
                                  icon: "eurosign.circle.fill", accent: Palette.amber)
                    CoachStatTile(value: "\(h.activeCount)", label: "Abbonati attivi",
                                  icon: "person.badge.shield.checkmark.fill", accent: Palette.lime)
                }
                .revealUp(appear, index: 1)

                CoachSectionTitle(eyebrow: "Offerta", title: "Piani", accent: Palette.amber)
                    .revealUp(appear, index: 2)
                if h.plans.isEmpty {
                    EmptyPanel(icon: "creditcard", text: "Nessun piano creato.")
                } else {
                    ForEach(Array(h.plans.enumerated()), id: \.element.id) { i, p in
                        planRow(p).revealUp(appear, index: min(i, 4) + 3)
                    }
                }

                if !subs.isEmpty {
                    GreekDivider(color: Palette.amber)
                    CoachSectionTitle(eyebrow: "Clienti", title: "Abbonamenti", accent: Palette.cyan)
                    ForEach(subs) { s in subRow(s) }
                }
                if hasMore {
                    LoadMoreButton(loading: loadingMore, accent: Palette.cyan) { Task { await loadMore() } }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func planRow(_ p: CoachPlanSummary) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                Text("€\(String(format: "%.0f", p.price)) · \(p.billingInterval ?? p.planType ?? "")")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                StatusBadge(text: p.isOnlinePurchasable ? "Online" : "Solo manuale",
                            color: p.isOnlinePurchasable ? Palette.lime : Palette.textLow,
                            filled: p.isOnlinePurchasable)
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

    private var connectBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill").foregroundStyle(Palette.amber)
                Text("Collega Stripe per vendere online").font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            }
            Text("Senza un account Stripe collegato i tuoi piani restano assegnabili solo manualmente (pagamento in studio).")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
            if let connectError {
                Text(connectError).font(Typo.body(12)).foregroundStyle(Palette.danger)
            }
            NeonButton(title: "Collega Stripe", icon: "arrow.up.right.square", color: Palette.amber,
                       loading: connecting, compact: true) {
                Task { await startConnect() }
            }
        }
        .padding(16).voltPanel()
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

    private func load() async {
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachSubscriptions(offset: 0) {
            header = (res.activeCount, res.monthlyRevenue, res.currency, res.plans)
            subs = res.subscriptions; hasMore = res.hasMore
            chargesEnabled = res.stripeConnectChargesEnabled
        }
    }

    private func startConnect() async {
        connecting = true; connectError = nil
        defer { connecting = false }
        do {
            let urlString = try await APIClient.shared.coachConnectStart()
            guard let url = URL(string: urlString) else { throw APIError.badURL }
            _ = try await webFlow.run(url: url, callbackScheme: "athlynkcoach")
            if let status = try? await APIClient.shared.coachConnectStatus() {
                chargesEnabled = status.stripeConnectChargesEnabled
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the web view — not an error worth surfacing.
        } catch {
            connectError = "Impossibile collegare Stripe. Riprova."
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachSubscriptions(offset: subs.count) {
            let known = Set(subs.map(\.id))
            subs.append(contentsOf: res.subscriptions.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        }
    }
}
