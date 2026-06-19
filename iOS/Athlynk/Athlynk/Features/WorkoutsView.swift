//
//  WorkoutsView.swift
//  Stitch "I Tuoi Programmi": training plans as summary cards (ATTIVO badge,
//  date range, elapsed progress). Tapping a card opens the full plan detail.
//

import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject var app: AppState
    @State private var plans: [WorkoutPlanDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var appear = false
    @State private var loadToken = UUID()

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Programma",
                             title: "I TUOI\nPROGRAMMI",
                             subtitle: "Sfoglia le tue schede di allenamento. Continua il tuo viaggio verso la forza e l'equilibrio.",
                             initials: initials,
                             accent: Palette.magenta)
                    .revealUp(appear, index: 0)

                NavigationLink { WorkoutHistoryView() } label: { historyLink }
                    .buttonStyle(PressableButtonStyle())
                    .revealUp(appear, index: 1)

                if loading {
                    ListCardsSkeleton(accent: Palette.magenta, count: 2)
                } else if let error {
                    EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.magenta)
                } else if plans.isEmpty {
                    EmptyPanel(icon: "dumbbell", text: "Nessuna scheda attiva.\nIl tuo coach non te ne ha ancora assegnata una.")
                } else {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { i, plan in
                        NavigationLink(value: plan) { planSummaryCard(plan) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: i + 2)
                    }
                }
            }
            .navigationDestination(for: WorkoutPlanDTO.self) { plan in
                WorkoutPlanDetailView(plan: plan)
            }
            .navigationDestination(for: ExerciseDTO.self) { ex in
                ExerciseDetailView(exercise: ex)
            }
        }
        .tint(Palette.magenta)
        .onAppear { appear = true }
        .task(id: loadToken) { await load() }
        .refreshable { await load() }
        .onRemoteChange(["WORKOUT_ASSIGNED"]) { loadToken = UUID() }
    }

    private func planSummaryCard(_ plan: WorkoutPlanDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(text: "Attivo", color: Palette.magenta)
                    Text(plan.title).font(Typo.display(24)).foregroundStyle(Palette.textHi)
                    if let range = plan.dateRangeLabel {
                        Text(range).font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                    .foregroundStyle(Palette.magenta)
            }

            if let pct = plan.progressFraction {
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
                    .frame(height: 5)
                }
            }

            HStack(spacing: 10) {
                metricPill("\(plan.days.count)", "GIORNI", Palette.magenta)
                if let f = plan.frequencyPerWeek { metricPill("\(f)", "X/SETT", Palette.cyan) }
                if let d = plan.durationWeeks { metricPill("\(d)", "SETTIM", Palette.violet) }
            }

            if let coach = plan.coach {
                HStack { Spacer(); CoachChip(coach: coach, color: Palette.magenta) }
            }
        }
        .padding(18).voltPanel(Palette.magenta.opacity(0.4))
    }

    private var historyLink: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.violet.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .black)).foregroundStyle(Palette.violet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Storico allenamenti").font(Typo.display(18)).foregroundStyle(Palette.textHi)
                Text("Le sessioni completate")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .black))
                .foregroundStyle(Palette.violet)
        }
        .padding(16).voltPanel(Palette.violet.opacity(0.35))
    }

    private func metricPill(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Typo.mono(20, .black)).foregroundStyle(c)
            Text(l).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    private var initials: String {
        let f = app.user?.firstName.first.map(String.init) ?? ""
        let l = app.user?.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func load() async {
        loading = true; error = nil
        do { plans = try await APIClient.shared.workouts() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

/// Derived schedule window + elapsed progress from start_date + duration_weeks.
extension WorkoutPlanDTO {
    var startDateParsed: Date? { startDate.flatMap(ISO8601.parse) }
    var endDateParsed: Date? {
        guard let s = startDateParsed, let w = durationWeeks else { return nil }
        return Calendar.current.date(byAdding: .day, value: w * 7, to: s)
    }
    var dateRangeLabel: String? {
        guard let s = startDateParsed else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
        guard let e = endDateParsed else { return f.string(from: s) }
        let y = DateFormatter(); y.dateFormat = "yyyy"
        return "\(f.string(from: s)) - \(f.string(from: e)) \(y.string(from: e))"
    }
    var progressFraction: CGFloat? {
        guard let s = startDateParsed, let e = endDateParsed else { return nil }
        let total = e.timeIntervalSince(s)
        guard total > 0 else { return nil }
        return CGFloat(min(max(Date().timeIntervalSince(s) / total, 0), 1))
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
