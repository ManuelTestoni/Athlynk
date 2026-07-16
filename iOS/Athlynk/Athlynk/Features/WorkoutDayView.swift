//
//  WorkoutDayView.swift
//  Live training day: tick off exercises, watch the completion ring fill,
//  and get a neon confetti blast when the whole session is done.
//

import SwiftUI

struct WorkoutDayView: View {
    let day: WorkoutDayDTO
    var assignmentId: Int? = nil

    @State private var done: Set<Int> = []
    @State private var burst = 0
    @State private var appear = false
    @Environment(\.dismiss) private var dismiss

    private var progress: Double {
        day.exercises.isEmpty ? 0 : Double(done.count) / Double(day.exercises.count)
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let aid = assignmentId {
                        NavigationLink { ActiveSessionView(assignmentId: aid, day: day) } label: {
                            startSessionButton
                        }
                        .buttonStyle(PressableButtonStyle())
                    }

                    ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                        exerciseCard(ex, index: i)
                            .revealUp(appear, index: i)
                    }

                    if done.count == day.exercises.count && !day.exercises.isEmpty {
                        completeBanner.transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, AppLayout.tabBarClearance)
            }

            ParticleBurst(trigger: burst)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DAY \(day.dayOrder)" + (day.focusArea.map { " · \($0.uppercased())" } ?? ""))
                .voltEyebrow()
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading) {
                    Text(day.label).font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                    Text("\(done.count)/\(day.exercises.count) completati")
                        .font(Typo.mono(13, .bold)).foregroundStyle(Palette.magenta)
                }
                Spacer()
                RingGauge(progress: progress, color: Palette.magenta, lineWidth: 10,
                          value: "\(Int(progress * 100))")
                    .frame(width: 84, height: 84)
            }
            if let notes = day.notes, !notes.isEmpty {
                Text(notes).font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
        }
    }

    private var startSessionButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill").font(.system(size: 16, weight: .black))
            Text("AVVIA SESSIONE").font(Typo.mono(13, .black)).tracking(2)
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .black))
        }
        .foregroundStyle(Palette.void0)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Capsule().fill(Palette.magenta))
        .neonGlow(Palette.magenta, radius: 10)
    }

    private func exerciseCard(_ ex: ExerciseDTO, index: Int) -> some View {
        let isDone = done.contains(ex.id)
        let accent = Palette.accent(index)
        // Card body opens the exercise detail; the check circle (overlaid) ticks
        // it off without triggering navigation.
        return ZStack(alignment: .topTrailing) {
            NavigationLink(value: ex) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(Typo.mono(15, .black)).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ex.name)
                                .font(Typo.display(19)).foregroundStyle(Palette.textHi)
                                .strikethrough(isDone, color: Palette.textLow)
                            if let m = ex.targetMuscleGroup {
                                Text(m.uppercased()).font(Typo.mono(9, .bold)).tracking(1)
                                    .foregroundStyle(Palette.textLow)
                            }
                        }
                        Spacer()
                        Color.clear.frame(width: 28, height: 28)
                    }

                    HStack(spacing: 8) {
                        spec(ex.setsReps, "SET×REP", accent)
                        if let load = ex.loadLabel { spec(load, "CARICO", accent) }
                        if let rec = ex.recoverySeconds { spec("\(rec)s", "REC", accent) }
                        if let rpe = ex.rpe { spec("\(rpe)", "RPE", accent) }
                    }

                    if let notes = ex.techniqueNotes, !notes.isEmpty {
                        Text(notes).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(2)
                    }
                }
                .padding(16)
                .voltPanel(accent.opacity(isDone ? 0.2 : 0.5))
                .opacity(isDone ? 0.6 : 1)
            }
            .buttonStyle(PressableButtonStyle())

            Button { toggle(ex) } label: {
                ZStack {
                    Circle().stroke(accent, lineWidth: 2).frame(width: 28, height: 28)
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .black))
                            .foregroundStyle(accent)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func spec(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Typo.mono(14, .bold)).foregroundStyle(Palette.textHi)
            Text(l).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.void2))
    }

    private var completeBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40, weight: .black))
                .foregroundStyle(Palette.lime).neonGlow(Palette.lime, radius: 14)
            Text("SESSIONE COMPLETA").font(Typo.poster(30)).foregroundStyle(Palette.textHi)
            Text("Distrutto. Recupera e idratati.")
                .font(Typo.body(13)).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .voltPanel(Palette.lime.opacity(0.5))
    }

    private func toggle(_ ex: ExerciseDTO) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if done.contains(ex.id) { done.remove(ex.id); Haptics.soft() }
            else {
                done.insert(ex.id); Haptics.thud()
                if done.count == day.exercises.count { burst += 1 }
            }
        }
    }
}
