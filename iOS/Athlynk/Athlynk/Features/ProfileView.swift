//
//  ProfileView.swift
//  "You": identity, your professionals, notifications, chat, logout.
//

import SwiftUI
import Combine

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var notifications: [NotificationDTO] = []
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                identityCard.revealUp(appear, index: 0)

                Text("I TUOI PROFESSIONISTI").voltEyebrow().padding(.top, 4)
                    .revealUp(appear, index: 1)
                coachList.revealUp(appear, index: 2)

                NavigationLink {
                    ChatListView()
                } label: {
                    actionRow(icon: "bubble.left.and.bubble.right.fill",
                              title: "Messaggi", color: Palette.cyan)
                }
                .buttonStyle(PressableButtonStyle())
                .revealUp(appear, index: 3)

                Text("NOTIFICHE").voltEyebrow().padding(.top, 4).revealUp(appear, index: 4)
                if notifications.isEmpty {
                    EmptyPanel(icon: "bell.slash", text: "Nessuna notifica.").revealUp(appear, index: 5)
                } else {
                    ForEach(Array(notifications.prefix(8).enumerated()), id: \.element.id) { i, n in
                        notifRow(n).revealUp(appear, index: i + 5)
                    }
                }

                NeonButton(title: "Esci", icon: "power", color: Palette.magenta, filled: false) {
                    app.logout()
                }
                .padding(.top, 8)
                .revealUp(appear, index: 14)
            }
            .navigationDestination(for: ConversationDTO.self) { conv in
                ChatDetailView(conversation: conv)
            }
        }
        .tint(Palette.amber)
        .onAppear { appear = true }
        .task { notifications = (try? await APIClient.shared.notifications()) ?? [] }
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Palette.amber, Palette.magenta],
                                             startPoint: .top, endPoint: .bottom))
                    .frame(width: 66, height: 66).neonGlow(Palette.amber, radius: 12)
                Text(initials).font(Typo.poster(26)).foregroundStyle(Palette.void0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(app.user?.displayName ?? "Atleta")
                    .font(Typo.display(24)).foregroundStyle(Palette.textHi)
                Text(app.user?.email ?? "").font(Typo.mono(12)).foregroundStyle(Palette.textMid)
            }
            Spacer()
        }
        .padding(18).voltPanel(Palette.amber.opacity(0.4))
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
                }
                .padding(14).voltPanel(Palette.violet.opacity(0.35))
            }
        }
    }

    private func actionRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .black)).foregroundStyle(color)
                .frame(width: 30)
            Text(title).font(Typo.display(18)).foregroundStyle(Palette.textHi)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .black))
                .foregroundStyle(color)
        }
        .padding(16).voltPanel(color.opacity(0.35))
    }

    private func notifRow(_ n: NotificationDTO) -> some View {
        HStack(spacing: 12) {
            Circle().fill(n.isRead ? Palette.textLow : Palette.cyan)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                if let b = n.body { Text(b).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(2) }
            }
            Spacer()
        }
        .padding(14).voltPanel()
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }
}
