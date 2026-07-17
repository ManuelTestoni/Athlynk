//
//  AgendaView.swift
//  Stitch "Agenda" / "Dettaglio Appuntamento": the athlete's appointments with
//  their coach — upcoming first, then past. Backed by GET /api/v1/appointments.
//

import SwiftUI

struct AgendaView: View {
    @State private var items: [AppointmentDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var appear = false

    private var upcoming: [AppointmentDTO] { items.filter { isFuture($0.end ?? $0.start) } }
    private var past: [AppointmentDTO] { items.filter { !isFuture($0.end ?? $0.start) }.reversed() }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.magenta, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        DateCardsSkeleton(accent: Palette.cyan, count: 3)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if items.isEmpty {
                        EmptyPanel(icon: "calendar", text: "Nessun appuntamento in agenda.")
                    } else {
                        if !upcoming.isEmpty {
                            Text("PROSSIMI").voltEyebrow().revealUp(appear, index: 0)
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { i, appt in
                                NavigationLink { AppointmentDetailView(appointment: appt) } label: {
                                    card(appt, dimmed: false)
                                }
                                .buttonStyle(PressableButtonStyle())
                                .revealUp(appear, index: min(i, 5) + 1)
                            }
                        }
                        if !past.isEmpty {
                            SectionDivider(color: Palette.cyan).padding(.top, 8)
                                .revealUp(appear, index: 2)
                            Text("PASSATI").voltEyebrow()
                                .revealUp(appear, index: 3)
                            ForEach(Array(past.enumerated()), id: \.element.id) { i, appt in
                                NavigationLink { AppointmentDetailView(appointment: appt) } label: {
                                    card(appt, dimmed: true)
                                }
                                .buttonStyle(PressableButtonStyle())
                                .revealUp(appear, index: min(i, 5) + 4)
                            }
                        }
                        if hasMore {
                            LoadMoreButton(loading: loadingMore, accent: Palette.cyan) { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: loading) { _, l in if !l { appear = true } }
    }

    private func card(_ a: AppointmentDTO, dimmed: Bool) -> some View {
        let accent = dimmed ? Palette.textLow : Palette.cyan
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Date block
                VStack(spacing: 2) {
                    Text(dayNum(a.start)).font(Typo.poster(26)).foregroundStyle(accent)
                    Text(monthShort(a.start)).font(Typo.mono(9, .bold)).tracking(1)
                        .foregroundStyle(Palette.textLow)
                }
                .frame(width: 54).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))

                VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 11, weight: .bold))
                        Text(timeRange(a)).font(Typo.mono(11, .semibold))
                    }
                    .foregroundStyle(Palette.textMid)
                    if let type = a.type {
                        Text(type.uppercased()).font(Typo.mono(9, .bold)).tracking(1)
                            .foregroundStyle(accent)
                    }
                }
                Spacer()
                if let status = a.status {
                    StatusBadge(text: status, color: accent, filled: false)
                }
            }

            if let desc = a.description, !desc.isEmpty {
                Text(desc).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(3)
            }

            HStack(spacing: 14) {
                if let loc = a.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
                }
                if a.meetingUrl?.isEmpty == false {
                    Label("Call online", systemImage: "video.fill")
                        .font(Typo.mono(11, .semibold)).foregroundStyle(Palette.cyan)
                }
                Spacer()
            }
        }
        .padding(16).voltPanel(accent.opacity(0.4)).opacity(dimmed ? 0.7 : 1)
    }

    // MARK: Date helpers

    private func parse(_ iso: String?) -> Date? { iso.flatMap(ISO8601.parse) }
    private func isFuture(_ iso: String?) -> Bool {
        guard let d = parse(iso) else { return true }
        return d >= Date()
    }
    private func dayNum(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private func monthShort(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "MMM"
        return f.string(from: d).uppercased()
    }
    private func timeRange(_ a: AppointmentDTO) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEE d MMM · HH:mm"
        guard let s = parse(a.start) else { return "—" }
        var out = f.string(from: s)
        if let e = parse(a.end) {
            let t = DateFormatter(); t.dateFormat = "HH:mm"
            out += "–\(t.string(from: e))"
        }
        return out
    }

    private func load() async {
        loading = true; error = nil
        do {
            let res = try await APIClient.shared.appointments(offset: 0)
            items = res.appointments; hasMore = res.hasMore
        }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.appointments(offset: items.count) {
            let known = Set(items.map(\.id))
            items.append(contentsOf: res.appointments.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        }
    }
}
