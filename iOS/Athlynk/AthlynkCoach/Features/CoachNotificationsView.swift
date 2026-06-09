//
//  CoachNotificationsView.swift
//  "Centro Notifiche (Coach)" — reuses the shared /api/v1/notifications feed
//  (the endpoint is keyed on target_user, so it serves coaches too).
//

import SwiftUI

struct CoachNotificationsView: View {
    @State private var items: [NotificationDTO] = []
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Aggiornamenti", title: "Notifiche",
                         subtitle: "Tutto ciò che accade nello studio", accent: Palette.phase)
            if loading && items.isEmpty {
                AvatarRowsSkeleton(accent: Palette.phase)
            } else if items.isEmpty {
                EmptyPanel(icon: "bell.slash", text: "Nessuna notifica.")
            } else {
                ForEach(items) { n in row(n) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onRemoteChange { Task { await load() } }
        .refreshable { await load() }
    }

    private func row(_ n: NotificationDTO) -> some View {
        Button {
            guard !n.isRead else { return }
            Task { try? await APIClient.shared.markNotificationRead(id: n.id); await load() }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon(n.type)).font(.system(size: 15, weight: .bold))
                    .foregroundStyle(n.isRead ? Palette.textLow : Palette.bronze)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill((n.isRead ? Palette.textLow : Palette.bronze).opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    if let body = n.body, !body.isEmpty {
                        Text(body).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(3)
                    }
                    Text(CoachDate.relative(n.createdAt)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
                Spacer()
                if !n.isRead { Circle().fill(Palette.bronze).frame(width: 8, height: 8) }
            }
            .padding(14).voltPanel()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func icon(_ type: String) -> String {
        switch type.uppercased() {
        case "CHECK_SUBMITTED": return "checkmark.seal.fill"
        case "MESSAGE": return "bubble.left.fill"
        default: return "bell.fill"
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        items = (try? await APIClient.shared.notifications().notifications) ?? []
    }
}
