//
//  ProfileView.swift
//  "Altro" dell'atleta — hub a rettangoli (come l'Altro del coach): identità in
//  testa, poi una griglia di sezioni (andamento, percorso, messaggi, agenda,
//  abbonamento, notifiche, profilo & impostazioni, anamnesi, aiuto).
//  Profilo e Impostazioni sono un'unica voce (AthleteProfileView), come nel
//  coach; login/logout vive lì, non più in questo hub.
//

import SwiftUI

struct AthleteMoreView: View {
    @EnvironmentObject var app: AppState
    @Binding var path: NavigationPath
    @State private var appear = false

    private enum Route: Hashable {
        case andamento, percorso, messaggi, agenda, abbonamento
        case notifiche, profiloImpostazioni, anamnesi, aiuto
    }

    private struct Item: Identifiable {
        let route: Route
        var id: Route { route }
        let icon: String
        let title: String
        let subtitle: String
        let accent: Color
    }

    private let items: [Item] = [
        .init(route: .andamento, icon: "chart.xyaxis.line", title: "Il mio andamento",
              subtitle: "Peso, circonferenze e pliche", accent: Palette.cyan),
        .init(route: .percorso, icon: "map.fill", title: "Il mio percorso",
              subtitle: "Piani, diete e check", accent: Palette.bronze),
        .init(route: .messaggi, icon: "bubble.left.and.bubble.right.fill", title: "Messaggi",
              subtitle: "Parla con il tuo coach", accent: Palette.violet),
        .init(route: .agenda, icon: "calendar", title: "Agenda",
              subtitle: "Appuntamenti e sessioni", accent: Palette.cyan),
        .init(route: .abbonamento, icon: "crown.fill", title: "Abbonamento",
              subtitle: "Il tuo piano", accent: Palette.magenta),
        .init(route: .notifiche, icon: "bell.fill", title: "Notifiche",
              subtitle: "Centro notifiche", accent: Palette.amber),
        .init(route: .anamnesi, icon: "doc.text.magnifyingglass", title: "Prima Valutazione",
              subtitle: "Anamnesi e fabbisogni", accent: Palette.lime),
        .init(route: .profiloImpostazioni, icon: "person.crop.square.fill", title: "Profilo & Impostazioni",
              subtitle: "I tuoi dati e preferenze", accent: Palette.amber),
        .init(route: .aiuto, icon: "questionmark.circle.fill", title: "Aiuto",
              subtitle: "Guida e supporto", accent: Palette.violet),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                identityCard.revealUp(appear, index: 0)

                Text("GESTIONE").voltEyebrow().padding(.top, 4).revealUp(appear, index: 1)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) { card(item) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
                .revealUp(appear, index: 2)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .andamento:            ProgressTrackerView()
                case .percorso:             JourneyView()
                case .messaggi:             ChatListView()
                case .agenda:               AgendaView()
                case .abbonamento:          SubscriptionView()
                case .notifiche:            NotificheView()
                case .profiloImpostazioni:  AthleteProfileView()
                case .anamnesi:             AnamnesisView()
                case .aiuto:                HelpView()
                }
            }
            .navigationDestination(for: ConversationDTO.self) { conv in
                ChatDetailView(conversation: conv)
            }
        }
        .tint(Palette.amber)
        .onAppear { appear = true }
    }

    private func card(_ item: Item) -> some View {
        HubTile(icon: item.icon, title: item.title, subtitle: item.subtitle, accent: item.accent)
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            AvatarView(url: app.avatarUrl, initials: initials, size: 66, initialsSize: 26, glow: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.user?.displayName ?? "Atleta")
                    .font(Typo.display(24)).foregroundStyle(Palette.textHi)
                Text(app.user?.email ?? "").font(Typo.mono(12)).foregroundStyle(Palette.textMid)
                Text((app.user?.role ?? "ATLETA").uppercased())
                    .font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.amber)
            }
            Spacer()
        }
        .padding(18).voltPanel(Palette.amber.opacity(0.4))
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }
}
