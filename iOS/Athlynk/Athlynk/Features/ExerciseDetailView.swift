//
//  ExerciseDetailView.swift
//  Stitch "Dettaglio Esercizio": full prescription for a single exercise —
//  media/video, target muscle, sets·reps·load·rpe·recovery·tempo, equipment,
//  and the coach's technique notes. Reuses ExerciseDTO from the workouts feed.
//

import SwiftUI

struct ExerciseDetailView: View {
    let exercise: ExerciseDTO

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    titleBlock
                    statGrid
                    if let eq = exercise.equipment, !eq.isEmpty { equipmentTag(eq) }
                    if let notes = exercise.techniqueNotes, !notes.isEmpty { coachNote(notes) }
                    ExerciseTrendCard {
                        try await APIClient.shared.exerciseTrend(workoutExerciseId: exercise.id)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Palette.void2, Palette.void1],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1))
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64, weight: .black)).foregroundStyle(Palette.magenta.opacity(0.5))
            if let v = exercise.videoUrl, let url = URL(string: v) {
                Link(destination: url) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56)).foregroundStyle(Palette.magenta)
                        .background(Circle().fill(Palette.void0).padding(8))
                        .neonGlow(Palette.magenta, radius: 12)
                }
            }
        }
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

    private func equipmentTag(_ eq: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "dumbbell.fill").font(.system(size: 13, weight: .bold))
            Text(eq.uppercased()).font(Typo.mono(11, .bold)).tracking(1)
        }
        .foregroundStyle(Palette.textMid)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Palette.void2))
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
