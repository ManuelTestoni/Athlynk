//
//  CoachMoreView.swift
//  "Altro" hub — entry point to the secondary coach areas: athletes, chat,
//  agenda, subscriptions, resource library, analytics, notifications and the
//  coach profile. (Allenamento / Nutrizione / Check are now primary tabs.)
//

import SwiftUI

enum CoachRoute: Hashable {
    case clients, chat, agenda, subscriptions, resources, analytics, notifications, profile
}

struct CoachMoreView: View {
    @EnvironmentObject private var app: AppState
    @State private var path = NavigationPath()
    /// Deep-link requested from the Home dashboard quick actions (Atleti/Chat/Agenda).
    @Binding var pending: CoachRoute?

    private struct Item: Identifiable {
        let id = UUID()
        let route: CoachRoute
        let icon: String
        let title: String
        let subtitle: String
        let accent: Color
    }

    private let items: [Item] = [
        .init(route: .clients, icon: "person.2.fill", title: "Atleti",
              subtitle: "I tuoi clienti", accent: Palette.cyan),
        .init(route: .chat, icon: "bubble.left.fill", title: "Chat",
              subtitle: "Messaggi con gli atleti", accent: Palette.violet),
        .init(route: .agenda, icon: "calendar", title: "Agenda",
              subtitle: "Appuntamenti", accent: Palette.amber),
        .init(route: .subscriptions, icon: "creditcard.fill", title: "Abbonamenti",
              subtitle: "Piani e ricavi", accent: Palette.bronze),
        .init(route: .resources, icon: "books.vertical.fill", title: "Libreria Risorse",
              subtitle: "Modelli riutilizzabili", accent: Palette.violet),
        .init(route: .analytics, icon: "chart.line.uptrend.xyaxis", title: "Analisi Progressi",
              subtitle: "Metriche dello studio", accent: Palette.cyan),
        .init(route: .notifications, icon: "bell.fill", title: "Notifiche",
              subtitle: "Centro notifiche", accent: Palette.phase),
        .init(route: .profile, icon: "person.crop.square.fill", title: "Profilo & Impostazioni",
              subtitle: "Il tuo profilo pubblico", accent: Palette.bronze),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Studio", title: "Altro",
                             subtitle: "Strumenti e gestione", accent: Palette.phase)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    ForEach(items) { item in
                        Button { Haptics.tap(); path.append(item.route) } label: { card(item) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationDestination(for: CoachRoute.self) { route in
                switch route {
                case .clients:       CoachClientsView()
                case .chat:          CoachMessagesView()
                case .agenda:        CoachAgendaView()
                case .subscriptions: CoachSubscriptionsView()
                case .resources:     CoachResourcesView()
                case .analytics:     CoachAnalyticsView()
                case .notifications: CoachNotificationsView()
                case .profile:       CoachProfileView()
                }
            }
        }
        .onAppear(perform: consumePending)
        .onChange(of: pending) { _, _ in consumePending() }
    }

    /// Push a deep-link route requested before this tab became active.
    private func consumePending() {
        guard let route = pending else { return }
        path.append(route)
        pending = nil
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: item.icon).font(.system(size: 22, weight: .bold))
                .foregroundStyle(item.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(Typo.body(15, .bold)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(item.subtitle).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(16).voltPanel()
    }
}
