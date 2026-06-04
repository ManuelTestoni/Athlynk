//
//  ProfileView.swift
//  Stitch "Profilo Atleta": avatar block, stat cards, your professionals, a
//  settings list, notifications, and logout.
//
//  Rows whose destination screens have no API wired yet (Modifica profilo,
//  Abbonamento, Aiuto) are placeholders until their endpoints are connected.
//

import SwiftUI
import Combine

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                identityCard.revealUp(appear, index: 0)
                statRow.revealUp(appear, index: 1)

                Text("I TUOI PROFESSIONISTI").voltEyebrow().padding(.top, 4)
                    .revealUp(appear, index: 2)
                coachList.revealUp(appear, index: 3)

                Text("ACCOUNT").voltEyebrow().padding(.top, 4).revealUp(appear, index: 4)
                VStack(spacing: 10) {
                    navRow(icon: "bubble.left.and.bubble.right.fill", title: "Messaggi", color: Palette.cyan) {
                        ChatListView()
                    }
                    navRow(icon: "map.fill", title: "Il mio percorso", color: Palette.bronze) {
                        JourneyView()
                    }
                    navRow(icon: "calendar", title: "Agenda", color: Palette.cyan) {
                        AgendaView()
                    }
                    navRow(icon: "crown.fill", title: "Abbonamento", color: Palette.magenta) {
                        SubscriptionView()
                    }
                    navRow(icon: "bell.fill", title: "Notifiche", color: Palette.violet) {
                        NotificheView()
                    }
                    navRow(icon: "person.fill", title: "Modifica profilo", color: Palette.amber) {
                        EditProfileView()
                    }
                    navRow(icon: "doc.text.magnifyingglass", title: "Anamnesi", color: Palette.lime) {
                        AnamnesisView()
                    }
                    navRow(icon: "gearshape.fill", title: "Impostazioni", color: Palette.cyan) {
                        SettingsView()
                    }
                    navRow(icon: "questionmark.circle.fill", title: "Aiuto", color: Palette.violet) {
                        HelpView()
                    }
                }
                .revealUp(appear, index: 5)

                NeonButton(title: "Esci", icon: "power", color: Palette.magenta, filled: false) {
                    app.logout()
                }
                .padding(.top, 8)
                .revealUp(appear, index: 6)
            }
            .navigationDestination(for: ConversationDTO.self) { conv in
                ChatDetailView(conversation: conv)
            }
        }
        .tint(Palette.amber)
        .onAppear { appear = true }
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

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .black)).foregroundStyle(color)
                .frame(width: 28)
            Text(title).font(Typo.display(17)).foregroundStyle(Palette.textHi)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                .foregroundStyle(color)
        }
        .padding(14).voltPanel(color.opacity(0.35))
    }

    private func navRow<Destination: View>(icon: String, title: String, color: Color,
                                           @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            settingsRow(icon: icon, title: title, color: color)
        }
        .buttonStyle(PressableButtonStyle())
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
