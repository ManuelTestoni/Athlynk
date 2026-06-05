//
//  NotificheView.swift
//  Stitch "Notifiche Atleta": the full notification feed. Tapping an unread
//  notification marks it read via POST /api/v1/notifications/{id}/read.
//

import SwiftUI

struct NotificheView: View {
    @State private var items: [NotificationDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.amber, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if loading {
                        AvatarRowsSkeleton(accent: Palette.cyan, count: 6)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.cyan)
                    } else if items.isEmpty {
                        EmptyPanel(icon: "bell.slash", text: "Nessuna notifica.")
                    } else {
                        ForEach(items) { n in
                            Button { Task { await markRead(n) } } label: { row(n) }
                                .buttonStyle(PressableButtonStyle())
                                .onAppear { if n.id == items.last?.id { Task { await loadMore() } } }
                        }
                        if loadingMore {
                            ProgressView().tint(Palette.cyan).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .onRemoteChange { Task { await load() } }
    }

    private func row(_ n: NotificationDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill((n.isRead ? Palette.textLow : Palette.cyan).opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon(n.type))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(n.isRead ? Palette.textLow : Palette.cyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title)
                    .font(Typo.body(15, n.isRead ? .regular : .semibold))
                    .foregroundStyle(Palette.textHi)
                if let b = n.body, !b.isEmpty {
                    Text(b).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(3)
                }
                if let t = n.createdAt {
                    Text(relative(t)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            if !n.isRead {
                Circle().fill(Palette.cyan).frame(width: 8, height: 8).neonGlow(Palette.cyan, radius: 4)
            }
        }
        .padding(14).voltPanel((n.isRead ? Palette.line : Palette.cyan.opacity(0.35)))
        .opacity(n.isRead ? 0.75 : 1)
    }

    private func icon(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("message") || t.contains("chat"): return "bubble.left.fill"
        case let t where t.contains("check"): return "checkmark.seal.fill"
        case let t where t.contains("workout") || t.contains("allenamento"): return "dumbbell.fill"
        case let t where t.contains("nutrition") || t.contains("nutriz"): return "flame.fill"
        case let t where t.contains("appointment") || t.contains("agenda"): return "calendar"
        default: return "bell.fill"
        }
    }

    private func relative(_ iso: String) -> String {
        guard let d = ISO8601.parse(iso) else { return "" }
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "it_IT")
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func markRead(_ n: NotificationDTO) async {
        guard !n.isRead else { return }
        Haptics.tap()
        try? await APIClient.shared.markNotificationRead(id: n.id)
        if let i = items.firstIndex(where: { $0.id == n.id }) {
            let old = items[i]
            items[i] = NotificationDTO(id: old.id, type: old.type, title: old.title,
                                       body: old.body, isRead: true, createdAt: old.createdAt)
        }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let page = try await APIClient.shared.notifications()
            items = page.notifications
            hasMore = page.hasMore ?? false
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, !loading else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await APIClient.shared.notifications(offset: items.count) else { return }
        let known = Set(items.map(\.id))
        items.append(contentsOf: page.notifications.filter { !known.contains($0.id) })
        hasMore = page.hasMore ?? false
    }
}
