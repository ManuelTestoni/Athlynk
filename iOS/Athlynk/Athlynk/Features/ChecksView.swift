//
//  ChecksView.swift
//  Pending check-ins the coach is waiting on.
//

import SwiftUI

struct ChecksView: View {
    @State private var checks: [CheckDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 6) {
                Text("MONITORAGGIO").voltEyebrow()
                GlitchText(text: "CHECK", size: 56)
            }
            .revealUp(appear, index: 0)

            if loading {
                LoadingPanel()
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.violet)
            } else if checks.isEmpty {
                EmptyPanel(icon: "checkmark.seal.fill",
                           text: "Tutto in regola.\nNessun check-in da compilare.",
                           color: Palette.lime)
            } else {
                ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                    checkCard(c, index: i).revealUp(appear, index: i + 1)
                }
            }
        }
        .onAppear { appear = true }
        .task { await load() }
        .refreshable { await load() }
    }

    private func checkCard(_ c: CheckDTO, index: Int) -> some View {
        let accent = Palette.accent(index)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                    if let coach = c.coach {
                        Text("da \(coach.fullName)").font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Label(dateLabel(c.dueDate), systemImage: "calendar")
                    .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textMid)
                Spacer()
                Text("DA COMPILARE")
                    .font(Typo.mono(9, .black)).tracking(1).foregroundStyle(Palette.void0)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(accent))
            }
        }
        .padding(18)
        .voltPanel(accent.opacity(0.45))
    }

    private func dateLabel(_ iso: String?) -> String {
        guard let iso, let d = ISO8601.parse(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "d MMM"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: d)
    }

    private func load() async {
        loading = true; error = nil
        do { checks = try await APIClient.shared.checks() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

enum ISO8601 {
    /// Django returns dates like "2026-06-01" and datetimes like "2026-06-01T10:00:00+00:00".
    static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
}
