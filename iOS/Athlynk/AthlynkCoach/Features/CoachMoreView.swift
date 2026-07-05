//
//  CoachMoreView.swift
//  "Altro" hub — entry point to the secondary coach areas: athletes, chat,
//  agenda, subscriptions, resource library, analytics, notifications and the
//  coach profile. (Allenamento / Nutrizione / Check are now primary tabs.)
//

import SwiftUI

enum CoachRoute: Hashable, Identifiable {
    case clients, chat, agenda, subscriptions, resources, analytics, notifications, profile
    var id: Self { self }
}

struct CoachMoreView: View {
    @EnvironmentObject private var app: AppState
    @Binding var path: NavigationPath

    private struct Item: Identifiable {
        let route: CoachRoute
        var id: CoachRoute { route }
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

    @State private var appear = false

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Studio", title: "Altro",
                             subtitle: "Strumenti e gestione", accent: Palette.phase)
                    .revealUp(appear, index: 0)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { Haptics.tap(); path.append(item.route) } label: { card(item) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: i / 2 + 1)
                    }
                }
            }
            .onAppear { appear = true }
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
    }

    private func card(_ item: Item) -> some View {
        HubTile(icon: item.icon, title: item.title, subtitle: item.subtitle, accent: item.accent)
    }
}
