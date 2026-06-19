//
//  ProfileView.swift
//  "Altro" dell'atleta — hub a rettangoli (come l'Altro del coach): identità in
//  testa, i tuoi professionisti, poi una griglia di sezioni (andamento, percorso,
//  messaggi, agenda, abbonamento, notifiche, profilo, anamnesi, impostazioni, aiuto)
//  e il logout.
//

import SwiftUI

struct AthleteMoreView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false

    private enum Route: Hashable {
        case andamento, percorso, messaggi, agenda, abbonamento
        case notifiche, profilo, anamnesi, impostazioni, aiuto
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
        .init(route: .profilo, icon: "person.fill", title: "Modifica profilo",
              subtitle: "I tuoi dati", accent: Palette.amber),
        .init(route: .anamnesi, icon: "doc.text.magnifyingglass", title: "Anamnesi",
              subtitle: "Storia clinica e sportiva", accent: Palette.lime),
        .init(route: .impostazioni, icon: "gearshape.fill", title: "Impostazioni",
              subtitle: "Preferenze e privacy", accent: Palette.cyan),
        .init(route: .aiuto, icon: "questionmark.circle.fill", title: "Aiuto",
              subtitle: "Guida e supporto", accent: Palette.violet),
    ]

    var body: some View {
        NavigationStack {
            ScreenScroll {
                identityCard.revealUp(appear, index: 0)
                statRow.revealUp(appear, index: 1)

                Text("I TUOI PROFESSIONISTI").voltEyebrow().padding(.top, 4)
                    .revealUp(appear, index: 2)
                coachList.revealUp(appear, index: 3)

                Text("GESTIONE").voltEyebrow().padding(.top, 4).revealUp(appear, index: 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) { card(item) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
                .revealUp(appear, index: 5)

                NeonButton(title: "Esci", icon: "power", color: Palette.magenta, filled: false) {
                    app.logout()
                }
                .padding(.top, 8)
                .revealUp(appear, index: 6)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .andamento:    ProgressTrackerView()
                case .percorso:     JourneyView()
                case .messaggi:     ChatListView()
                case .agenda:       AgendaView()
                case .abbonamento:  SubscriptionView()
                case .notifiche:    NotificheView()
                case .profilo:      EditProfileView()
                case .anamnesi:     AnamnesisView()
                case .impostazioni: SettingsView()
                case .aiuto:        HelpView()
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
        .padding(16).voltPanel(item.accent.opacity(0.35))
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

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard("Altezza", app.me?.profile?.heightCm.map { "\($0) cm" } ?? "—", Palette.cyan)
            statCard("Obiettivo", goalLabel, Palette.magenta)
            statCard("Livello", levelLabel, Palette.lime)
        }
    }

    private func statCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Typo.display(18)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .voltPanel(color.opacity(0.35))
    }

    @ViewBuilder
    private var coachList: some View {
        let coaches = [app.me?.coach, app.me?.trainer, app.me?.nutritionist].compactMap { $0 }
        let unique = Array(Dictionary(grouping: coaches, by: \.id).values.compactMap(\.first))
        if unique.isEmpty {
            EmptyPanel(icon: "person.crop.circle.badge.questionmark",
                       text: "Nessun coach collegato.")
        } else {
            ForEach(unique) { coach in
                NavigationLink { CoachDetailView(coachId: coach.id) } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Palette.violet.opacity(0.18))
                                .frame(width: 48, height: 48)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.violet)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coach.fullName).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                            Text((coach.specialization ?? coach.professionalType ?? "Coach"))
                                .font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.violet)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                            .foregroundStyle(Palette.violet)
                    }
                    .padding(14).voltPanel(Palette.violet.opacity(0.35))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var goalLabel: String {
        let g = app.me?.profile?.primaryGoal ?? ""
        return g.isEmpty ? "—" : g.capitalized
    }
    private var levelLabel: String {
        let l = app.me?.profile?.activityLevel ?? ""
        return l.isEmpty ? "—" : l.capitalized
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }
}
