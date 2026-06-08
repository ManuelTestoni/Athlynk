//
//  CoachPlansView.swift
//  "Gestione Allenamenti (Coach)" + "Gestione Nutrizione (Coach)".
//  Read-only management overview: the plan library + who has what assigned.
//

import SwiftUI

struct CoachWorkoutsView: View {
    @State private var data: CoachWorkoutsResponse?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Programmazione", title: "Allenamenti",
                         subtitle: "Le tue schede e assegnazioni", accent: Palette.cyan)
            if loading && data == nil {
                LoadingPanel()
            } else if let d = data {
                CoachSectionTitle(eyebrow: "Libreria", title: "Schede (\(d.plans.count))", accent: Palette.cyan)
                if d.plans.isEmpty {
                    EmptyPanel(icon: "dumbbell", text: "Nessuna scheda creata.")
                } else {
                    ForEach(d.plans) { p in
                        planCard(title: p.title,
                                 subtitle: [p.goal, p.level].compactMap { $0 }.joined(separator: " · "),
                                 meta: p.durationWeeks.map { "\($0) sett." },
                                 assigned: p.assignedCount, accent: Palette.cyan)
                    }
                }
                if !d.assignments.isEmpty {
                    CoachSectionTitle(eyebrow: "In corso", title: "Assegnazioni", accent: Palette.bronze)
                    ForEach(d.assignments) { a in assignmentCard(a, accent: Palette.cyan) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async { loading = true; defer { loading = false }
        data = try? await APIClient.shared.coachWorkouts() }
}

struct CoachNutritionView: View {
    @State private var data: CoachNutritionResponse?
    @State private var loading = true

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Programmazione", title: "Nutrizione",
                         subtitle: "I tuoi piani alimentari", accent: Palette.lime)
            if loading && data == nil {
                LoadingPanel()
            } else if let d = data {
                CoachSectionTitle(eyebrow: "Libreria", title: "Piani (\(d.plans.count))", accent: Palette.lime)
                if d.plans.isEmpty {
                    EmptyPanel(icon: "flame", text: "Nessun piano creato.")
                } else {
                    ForEach(d.plans) { p in
                        planCard(title: p.title,
                                 subtitle: [p.planMode, p.planKind].compactMap { $0 }.joined(separator: " · "),
                                 meta: p.dailyKcal.map { "\($0) kcal" },
                                 assigned: p.assignedCount, accent: Palette.lime)
                    }
                }
                if !d.assignments.isEmpty {
                    CoachSectionTitle(eyebrow: "In corso", title: "Assegnazioni", accent: Palette.bronze)
                    ForEach(d.assignments) { a in assignmentCard(a, accent: Palette.lime) }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async { loading = true; defer { loading = false }
        data = try? await APIClient.shared.coachNutrition() }
}

// MARK: - Shared cards (file-private helpers usable by both views above)

private func planCard(title: String, subtitle: String, meta: String?, assigned: Int, accent: Color) -> some View {
    HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            if let meta { Text(meta).font(Typo.mono(10)).foregroundStyle(Palette.textLow) }
        }
        Spacer()
        VStack(spacing: 2) {
            Text("\(assigned)").font(Typo.poster(24)).foregroundStyle(accent)
            Text("attivi").font(Typo.mono(8, .semibold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Palette.textLow)
        }
    }
    .padding(14).voltPanel()
}

private func assignmentCard(_ a: CoachAssignmentRow, accent: Color) -> some View {
    HStack(spacing: 12) {
        CoachClientAvatar(url: a.client.profileImageUrl, initials: a.client.initials, size: 40)
        VStack(alignment: .leading, spacing: 2) {
            Text(a.client.displayName).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            Text(a.title).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
        }
        Spacer()
        Circle().fill(accent).frame(width: 8, height: 8)
    }
    .padding(14).voltPanel()
}
