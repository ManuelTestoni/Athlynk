//
//  ExerciseDetailView.swift
//  Stitch "Dettaglio Esercizio": full prescription for a single exercise —
//  media/video, target muscle, sets·reps·load·rpe·recovery·tempo, equipment,
//  and the coach's technique notes. Reuses ExerciseDTO from the workouts feed.
//

import SwiftUI

struct ExerciseDetailView: View {
    let exercise: ExerciseDTO
    @State private var appear = false
    @State private var stepsExpanded = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero.revealUp(appear, index: 0)
                    titleBlock.revealUp(appear, index: 1)
                    statGrid.revealUp(appear, index: 2)
                    // Single execution text: instruction_steps only (description is
                    // deduplicated away). Collapsed to the first step until expanded.
                    if let steps = exercise.executionSteps, !steps.isEmpty {
                        instructionsBlock(steps).revealUp(appear, index: 4)
                    }
                    if !exercise.equipment.isEmpty { equipmentTag(exercise.equipment).revealUp(appear, index: 5) }
                    if let notes = exercise.techniqueNotes, !notes.isEmpty { coachNote(notes).revealUp(appear, index: 6) }
                    ExerciseTrendCard {
                        try await APIClient.shared.exerciseTrend(workoutExerciseId: exercise.id)
                    }
                    .revealUp(appear, index: 7)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var hero: some View {
        ExerciseMediaHero(demoGifUrl: exercise.demoGifUrl, coverImageUrl: exercise.coverImageUrl,
                          videoUrl: exercise.videoUrl, accent: Palette.magenta)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let m = exercise.targetMuscleGroup, !m.isEmpty {
                Text("TARGET · \(m.uppercased())")
                    .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.magenta)
            }
            Text(exercise.name).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.magenta).frame(height: 1).opacity(0.5)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("square.stack.3d.up.fill", exercise.setCount.map { "\($0)" } ?? "—", "SERIE")
            stat("repeat", exercise.repRange ?? exercise.repCount.map { "\($0)" } ?? "—", "RIPETIZIONI")
            if let load = exercise.loadLabel { stat("scalemass.fill", load, "CARICO") }
            if let rec = exercise.recoverySeconds { stat("timer", "\(rec)s", "RECUPERO") }
            if let rpe = exercise.rpe { stat("flame.fill", "\(rpe)", "RPE") }
            if let rir = exercise.rir { stat("gauge.medium", "\(rir)", "RIR") }
            if let tempo = exercise.tempo, !tempo.isEmpty { stat("metronome.fill", tempo, "TEMPO") }
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .black)).foregroundStyle(Palette.magenta)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Typo.mono(18, .black)).foregroundStyle(Palette.textHi)
                Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            }
            Spacer()
        }
        .padding(14).voltPanel(Palette.magenta.opacity(0.35))
    }

    private func equipmentTag(_ eq: [String]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "dumbbell.fill").font(.system(size: 13, weight: .bold))
            Text(eq.joined(separator: " · ").uppercased()).font(Typo.mono(11, .bold)).tracking(1)
        }
        .foregroundStyle(Palette.textMid)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Palette.void2))
    }

    /// Single execution text. Shows the first step; the rest reveal on tapping
    /// "vedi esecuzione" (collapsed by default).
    private func instructionsBlock(_ steps: [String]) -> some View {
        let visible = stepsExpanded ? Array(steps.enumerated()) : Array(steps.prefix(1).enumerated())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").font(.system(size: 14, weight: .black))
                    .foregroundStyle(Palette.cyan)
                Text("ESECUZIONE").voltEyebrow()
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(visible, id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(Typo.mono(12, .black)).foregroundStyle(Palette.cyan)
                            .frame(width: 18, alignment: .leading)
                        Text(step).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                            .lineLimit(stepsExpanded ? nil : 1)
                    }
                }
            }
            if steps.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { stepsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(stepsExpanded ? "Nascondi" : "Vedi esecuzione")
                            .font(Typo.mono(11, .bold)).tracking(1)
                        Image(systemName: stepsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .black))
                    }
                    .foregroundStyle(Palette.cyan)
                }
            }
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.35))
    }

    private func coachNote(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening").font(.system(size: 14, weight: .black))
                    .foregroundStyle(Palette.cyan)
                Text("NOTA TECNICA").voltEyebrow()
            }
            Text(notes).font(Typo.body(15)).foregroundStyle(Palette.textHi).italic()
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.35))
    }
}
