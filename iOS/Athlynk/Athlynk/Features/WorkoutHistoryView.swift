//
//  WorkoutHistoryView.swift
//  Stitch "Storico Allenamenti": past training sessions grouped by month, each
//  with date, day, duration, RPE, set count and completion status.
//  Backed by GET /api/v1/workout-history (WorkoutSession).
//

import SwiftUI

struct WorkoutHistoryView: View {
    @State private var sessions: [WorkoutSessionDTO] = []
    @State private var loading = true
    @State private var error: String?

    private var groups: [(title: String, sessions: [WorkoutSessionDTO])] {
        var order: [String] = []
        var map: [String: [WorkoutSessionDTO]] = [:]
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "LLLL yyyy"
        for s in sessions {
            let key: String
            if let iso = s.startedAt, let d = ISO8601.parse(iso) { key = f.string(from: d).capitalized }
            else { key = "—" }
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key, default: []].append(s)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.magenta, Palette.cyan, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        LoadingPanel(text: "Carico lo storico…")
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.violet)
                    } else if sessions.isEmpty {
                        EmptyPanel(icon: "clock.arrow.circlepath",
                                   text: "Nessuna sessione registrata.\nIl tuo storico apparirà qui.")
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                            HStack(spacing: 8) {
                                Image(systemName: "calendar").font(.system(size: 12, weight: .bold))
                                Text(g.title.uppercased()).font(Typo.mono(10, .bold)).tracking(2)
                            }
                            .foregroundStyle(Palette.violet).padding(.top, 6)
                            ForEach(g.sessions) { card($0) }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Storico")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func card(_ s: WorkoutSessionDTO) -> some View {
        let statusColor = s.completed ? Palette.lime : (s.interrupted ? Palette.amber : Palette.textLow)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(dayNum(s.startedAt)).font(Typo.poster(24)).foregroundStyle(Palette.violet)
                Text(monthShort(s.startedAt)).font(Typo.mono(9, .bold)).tracking(1)
                    .foregroundStyle(Palette.textLow)
            }
            .frame(width: 52).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))

            VStack(alignment: .leading, spacing: 6) {
                Text(s.dayLabel).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                if let f = s.focusArea, !f.isEmpty {
                    Text(f.uppercased()).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.violet)
                }
                HStack(spacing: 14) {
                    if let d = s.durationMinutes { metric("timer", "\(d) min") }
                    if let r = s.avgRpe { metric("flame.fill", String(format: "RPE %.1f", r)) }
                    metric("square.stack.3d.up.fill", "\(s.setCount) serie")
                }
            }
            Spacer()
            Image(systemName: s.completed ? "checkmark.seal.fill" : (s.interrupted ? "exclamationmark.triangle.fill" : "circle"))
                .font(.system(size: 20, weight: .black)).foregroundStyle(statusColor)
        }
        .padding(16).voltPanel(statusColor.opacity(0.4))
    }

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(Typo.mono(11, .semibold))
        }
        .foregroundStyle(Palette.textMid)
    }

    private func parse(_ iso: String?) -> Date? { iso.flatMap(ISO8601.parse) }
    private func dayNum(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private func monthShort(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "MMM"
        return f.string(from: d).uppercased()
    }

    private func load() async {
        loading = true; error = nil
        do { sessions = try await APIClient.shared.workoutHistory() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
