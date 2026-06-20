//
//  WorkoutPlanDetailView.swift
//  Stitch "Dettaglio Piano / Programma": full overview of one training plan —
//  goal, level, schedule, description, coach, and the day sessions to start.
//  Reuses WorkoutPlanDTO from the workouts feed (no extra request).
//

import SwiftUI

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlanDTO

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let pct = plan.progressFraction { progressBar(pct) }
                    metrics
                    if let desc = plan.description, !desc.isEmpty { descriptionCard(desc) }
                    Text("GIORNI").voltEyebrow()
                    ForEach(plan.days) { day in
                        NavigationLink(value: WorkoutDaySelection(day: day, assignmentId: plan.assignmentId)) {
                            dayRow(day)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: "Attivo", color: Palette.magenta)
                Spacer()
                if let coach = plan.coach { CoachChip(coach: coach, color: Palette.magenta) }
            }
            Text(plan.title).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let goal = plan.goal, !goal.isEmpty { tag(goal) }
                if let level = plan.level, !level.isEmpty { tag(level) }
            }
            if let range = plan.dateRangeLabel {
                Text(range).font(Typo.mono(11)).foregroundStyle(Palette.textMid)
            }
            Rectangle().fill(Palette.magenta).frame(height: 1).opacity(0.5)
        }
    }

    private func progressBar(_ pct: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Int(pct * 100))% Completato")
                .font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.magenta)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.void2)
                    Capsule().fill(Palette.magenta)
                        .frame(width: geo.size.width * pct).neonGlow(Palette.magenta, radius: 5)
                }
            }
            .frame(height: 6)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metricPill("\(plan.days.count)", "GIORNI", Palette.magenta)
            if let f = plan.frequencyPerWeek { metricPill("\(f)", "X/SETT", Palette.cyan) }
            if let d = plan.durationWeeks { metricPill("\(d)", "SETTIM", Palette.violet) }
            metricPill("\(totalExercises)", "ESERCIZI", Palette.amber)
        }
    }

    private var totalExercises: Int { plan.days.reduce(0) { $0 + $1.exercises.count } }

    private func descriptionCard(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIZIONE").voltEyebrow()
            Text(desc).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(Palette.magenta.opacity(0.3))
    }

    private func dayRow(_ day: WorkoutDayDTO) -> some View {
        HStack(spacing: 14) {
            Text("\(day.dayOrder)").font(Typo.poster(30)).foregroundStyle(Palette.magenta)
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
        .voltPanel(Palette.magenta.opacity(0.3))
    }

    private func metricPill(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Typo.mono(20, .black)).foregroundStyle(c)
            Text(l).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.magenta)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().stroke(Palette.magenta, lineWidth: 1))
    }
}
