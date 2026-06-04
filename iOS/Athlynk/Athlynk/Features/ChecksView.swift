//
//  ChecksView.swift
//  Stitch "Timeline dei Check": a vertical progress timeline. The current API
//  exposes only pending check-ins (id/title/due_date/coach); the historical
//  weight/photo/commentary entries shown in the mockup need a dedicated
//  endpoint (to be wired later). "Nuovo Check" is a placeholder until then.
//

import SwiftUI

struct ChecksView: View {
    @EnvironmentObject var app: AppState
    @State private var checks: [CheckDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: ChecksRoute.self) { route in
                    switch route {
                    case .progress: ProgressTrackerView()
                    }
                }
        }
        .tint(Palette.violet)
    }

    private var content: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Monitoraggio Progressi",
                         title: "I TUOI\nCHECK",
                         subtitle: "I check-in che il tuo coach sta aspettando.",
                         initials: initials,
                         accent: Palette.violet)
                .revealUp(appear, index: 0)

            NavigationLink(value: ChecksRoute.progress) {
                progressLink
            }
            .buttonStyle(PressableButtonStyle())
            .revealUp(appear, index: 1)

            if loading {
                TimelineSkeleton(accent: Palette.violet, count: 3)
            } else if let error {
                EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.violet)
            } else if checks.isEmpty {
                EmptyPanel(icon: "checkmark.seal.fill",
                           text: "Tutto in regola.\nNessun check-in da compilare.",
                           color: Palette.lime)
                    .revealUp(appear, index: 1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                        timelineRow(c, index: i, isLast: i == checks.count - 1)
                            .revealUp(appear, index: i + 1)
                    }
                }
            }

            newCheckButton.revealUp(appear, index: checks.count + 1)
        }
        .onAppear { appear = true }
        .task { await load() }
        .refreshable { await load() }
        .onRemoteChange(["CHECK_REVIEWED"]) { Task { await load() } }
    }

    private func timelineRow(_ c: CheckDTO, index: Int, isLast: Bool) -> some View {
        let accent = Palette.accent(index)
        return HStack(alignment: .top, spacing: 14) {
            // Timeline rail: node + connector.
            VStack(spacing: 0) {
                Circle().fill(accent).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Palette.void0, lineWidth: 3))
                    .neonGlow(accent, radius: 5)
                if !isLast {
                    Rectangle().fill(Palette.line).frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            NavigationLink { NewCheckView(check: c) { Task { await load() } } } label: {
                checkCard(c, accent: accent)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private func checkCard(_ c: CheckDTO, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateLabel(c.dueDate))
                        .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(accent)
                    Text(c.title).font(Typo.display(19)).foregroundStyle(Palette.textHi)
                    if let coach = c.coach {
                        Text("da \(coach.fullName)").font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    }
                }
                Spacer()
                StatusBadge(text: "Da compilare", color: accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voltPanel(accent.opacity(0.45))
    }

    private var progressLink: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.cyan.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.cyan)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Andamento progressi").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                Text("Peso, foto e feedback del coach")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                .foregroundStyle(Palette.cyan)
        }
        .padding(16).voltPanel(Palette.cyan.opacity(0.35))
    }

    private var newCheckButton: some View {
        NeonButton(title: "Nuovo Check", icon: "plus", color: Palette.violet) {
            // Compose flow (Stitch "Nuovo Check") — needs a create endpoint.
        }
        .padding(.top, 6)
    }

    private func dateLabel(_ iso: String?) -> String {
        guard let iso, let d = ISO8601.parse(iso) else { return "IN ATTESA" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: d).uppercased()
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func load() async {
        loading = true; error = nil
        do { checks = try await APIClient.shared.checks() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

enum ChecksRoute: Hashable {
    case progress
}

enum ISO8601 {
    /// Django returns dates like "2026-06-01" and datetimes like "2026-06-01T10:00:00+00:00".
    nonisolated static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
}
