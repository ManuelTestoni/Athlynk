//
//  CoachCheckAthleteListView.swift
//  "Tutti" tab inside Check-in: athletes who have at least one check, then
//  drill into one athlete's paginated check list.
//

import SwiftUI

struct CheckAthleteRoute: Hashable {
    let clientId: Int
    let displayName: String
    let profileImageUrl: String?
    let initials: String
}

struct CoachCheckAthleteListView: View {
    @State private var rows: [CoachClientRow] = []
    @State private var query = ""
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar

            if loading && rows.isEmpty {
                AvatarRowsSkeleton(accent: Palette.bronze)
            } else if rows.isEmpty {
                EmptyPanel(icon: "checkmark.seal", text: "Nessun atleta con check ricevuti.", color: Palette.lime)
            } else {
                ForEach(rows) { r in
                    NavigationLink(value: CheckAthleteRoute(clientId: r.id, displayName: r.displayName,
                                                             profileImageUrl: r.profileImageUrl, initials: r.initials)) {
                        athleteCard(r)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                if hasMore {
                    LoadMoreButton(loading: loadingMore, accent: Palette.bronze) {
                        Task { await loadMore() }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.bronze)
            TextField("", text: $query, prompt: Text("Cerca atleta…").foregroundStyle(Palette.textLow))
                .font(Typo.body(15)).tint(Palette.bronze)
                .textInputAutocapitalization(.words)
                .onSubmit { Task { await load() } }
            if !query.isEmpty {
                Button { query = ""; Task { await load() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textLow)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .voltPanel(radius: 14)
    }

    private func athleteCard(_ r: CoachClientRow) -> some View {
        HStack(spacing: 14) {
            CoachClientAvatar(url: r.profileImageUrl, initials: r.initials, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(r.displayName).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                if let last = r.lastCheckAt {
                    Text("Ultimo check \(CoachDate.relative(last))")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachClients(query: query, hasChecks: true) {
            rows = res.clients; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachClients(query: query, offset: rows.count, hasChecks: true) {
            let known = Set(rows.map(\.id))
            rows.append(contentsOf: res.clients.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        }
    }
}

struct CoachAthleteChecksListView: View {
    let route: CheckAthleteRoute
    @State private var checks: [CoachCheckRow] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false

    var body: some View {
        ScreenScroll {
            HStack(spacing: 14) {
                CoachClientAvatar(url: route.profileImageUrl, initials: route.initials, size: 60)
                Text(route.displayName).font(Typo.poster(24)).foregroundStyle(Palette.textHi)
                Spacer()
            }

            if loading && checks.isEmpty {
                AvatarRowsSkeleton(accent: Palette.bronze)
            } else if checks.isEmpty {
                EmptyPanel(icon: "checkmark.seal", text: "Nessun check per questo atleta.", color: Palette.lime)
            } else {
                ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                    NavigationLink(value: CheckRoute(id: c.id)) { coachCheckCard(c) }
                        .buttonStyle(PressableButtonStyle())
                }
                if hasMore {
                    LoadMoreButton(loading: loadingMore, accent: Palette.bronze) {
                        Task { await loadMore() }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachClientChecks(clientId: route.clientId) {
            checks = res.checks; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachClientChecks(clientId: route.clientId, offset: checks.count) {
            let known = Set(checks.map(\.id))
            checks.append(contentsOf: res.checks.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        }
    }
}
