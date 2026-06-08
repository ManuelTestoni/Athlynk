//
//  CoachMoreView.swift
//  "Altro" hub — entry point to the secondary coach areas: check review, plan
//  & nutrition management, subscriptions, resource library, analytics,
//  notifications and the coach profile.
//

import SwiftUI

enum CoachRoute: Hashable {
    case checks, workouts, nutrition, subscriptions, resources, analytics, notifications, profile
}

struct CoachMoreView: View {
    @EnvironmentObject private var app: AppState
    @State private var path = NavigationPath()

    private struct Item: Identifiable {
        let id = UUID()
        let route: CoachRoute
        let icon: String
        let title: String
        let subtitle: String
        let accent: Color
    }

    private let items: [Item] = [
        .init(route: .checks, icon: "checkmark.seal.fill", title: "Revisione Check-in",
              subtitle: "Leggi e commenta i check", accent: Palette.bronze),
        .init(route: .workouts, icon: "dumbbell.fill", title: "Allenamenti",
              subtitle: "Schede e assegnazioni", accent: Palette.cyan),
        .init(route: .nutrition, icon: "flame.fill", title: "Nutrizione",
              subtitle: "Piani alimentari", accent: Palette.lime),
        .init(route: .subscriptions, icon: "creditcard.fill", title: "Abbonamenti",
              subtitle: "Piani e ricavi", accent: Palette.amber),
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
                case .checks:        CoachChecksView()
                case .workouts:      CoachWorkoutsView()
                case .nutrition:     CoachNutritionView()
                case .subscriptions: CoachSubscriptionsView()
                case .resources:     CoachResourcesView()
                case .analytics:     CoachAnalyticsView()
                case .notifications: CoachNotificationsView()
                case .profile:       CoachProfileView()
                }
            }
            .navigationDestination(for: CheckRoute.self) { CoachCheckDetailView(responseId: $0.id) }
            .onReceive(NotificationCenter.default.publisher(for: .coachOpenChecks)) { _ in
                path.append(CoachRoute.checks)
            }
        }
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
