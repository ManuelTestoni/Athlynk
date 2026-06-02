//
//  WorkoutsView.swift
//  Active training plans → day cards → push into a live day.
//

import SwiftUI

struct WorkoutsView: View {
    @State private var plans: [WorkoutPlanDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROGRAMMA").voltEyebrow()
                    GlitchText(text: "TRAIN", size: 56)
                }
                .revealUp(appear, index: 0)

                if loading {
                    LoadingPanel(text: "Carico le schede…")
                } else if let error {
                    EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.magenta)
                } else if plans.isEmpty {
                    EmptyPanel(icon: "dumbbell", text: "Nessuna scheda attiva.\nIl tuo coach non te ne ha ancora assegnata una.")
                } else {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { i, plan in
                        planCard(plan).revealUp(appear, index: i + 1)
                    }
                }
            }
            .navigationDestination(for: WorkoutDayDTO.self) { day in
                WorkoutDayView(day: day)
            }
        }
        .tint(Palette.magenta)
        .onAppear { appear = true }
        .task { await load() }
        .refreshable { await load() }
    }

    private func planCard(_ plan: WorkoutPlanDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(Typo.display(24)).foregroundStyle(Palette.textHi)
                    if let goal = plan.goal {
                        Text(goal.uppercased())
                            .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.magenta)
                    }
                }
                Spacer()
                if let coach = plan.coach {
                    CoachChip(coach: coach, color: Palette.magenta)
                }
            }

            HStack(spacing: 10) {
                metricPill("\(plan.days.count)", "GIORNI", Palette.magenta)
                if let f = plan.frequencyPerWeek { metricPill("\(f)", "X/SETT", Palette.cyan) }
                if let d = plan.durationWeeks { metricPill("\(d)", "SETTIM", Palette.violet) }
            }

            VStack(spacing: 10) {
                ForEach(plan.days) { day in
                    NavigationLink(value: day) { dayRow(day) }
                        .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(18)
        .voltPanel(Palette.magenta.opacity(0.4))
    }

    private func dayRow(_ day: WorkoutDayDTO) -> some View {
        HStack(spacing: 14) {
            Text("\(day.dayOrder)")
                .font(Typo.poster(30)).foregroundStyle(Palette.magenta)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.label).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Text("\(day.exercises.count) esercizi" + (day.focusArea.map { " · \($0)" } ?? ""))
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "play.fill").font(.system(size: 14, weight: .black))
                .foregroundStyle(Palette.magenta)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.void2))
    }

    private func metricPill(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Typo.mono(20, .black)).foregroundStyle(c)
            Text(l).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    private func load() async {
        loading = true; error = nil
        do { plans = try await APIClient.shared.workouts() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct CoachChip: View {
    let coach: Coach
    var color: Color = Palette.cyan
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).neonGlow(color, radius: 4)
            Text(coach.fullName).font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Palette.void2))
    }
}
