//
//  CoachAgendaView.swift
//  "Agenda" — the coach's upcoming appointments, grouped by day.
//

import SwiftUI

struct CoachAgendaView: View {
    @State private var items: [CoachAgendaItem] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Calendario", title: "Agenda",
                             subtitle: "I tuoi prossimi appuntamenti", accent: Palette.amber)

                if loading && items.isEmpty {
                    LoadingPanel()
                } else if items.isEmpty {
                    EmptyPanel(icon: "calendar.badge.exclamationmark", text: "Nessun appuntamento in programma.")
                } else {
                    ForEach(grouped, id: \.0) { day, appts in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.uppercased()).font(Typo.mono(11, .bold)).tracking(2)
                                .foregroundStyle(Palette.bronze)
                            ForEach(appts) { a in row(a) }
                        }
                    }
                }
            }
            .task { await load() }
            .onRemoteChange { Task { await load() } }
            .refreshable { await load() }
        }
    }

    private var grouped: [(String, [CoachAgendaItem])] {
        let groups = Dictionary(grouping: items) { CoachDate.dayMonth($0.start) }
        return groups.sorted {
            (CoachDate.parse($0.value.first?.start) ?? .distantFuture)
                < (CoachDate.parse($1.value.first?.start) ?? .distantFuture)
        }.map { ($0.key, $0.value) }
    }

    private func row(_ a: CoachAgendaItem) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(CoachDate.time(a.start)).font(Typo.mono(15, .bold)).foregroundStyle(Palette.textHi)
                if let m = a.durationMinutes {
                    Text("\(m)′").font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
            }
            .frame(width: 56)
            Rectangle().fill(Palette.amber).frame(width: 2).opacity(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.client?.displayName ?? a.title).font(Typo.body(16, .semibold))
                    .foregroundStyle(Palette.textHi)
                Text(a.title).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
                if let loc = a.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                } else if let url = a.meetingUrl, !url.isEmpty {
                    Label("Online", systemImage: "video.fill")
                        .font(Typo.mono(10)).foregroundStyle(Palette.cyan)
                }
            }
            Spacer()
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        items = (try? await APIClient.shared.coachAgenda()) ?? []
    }
}
