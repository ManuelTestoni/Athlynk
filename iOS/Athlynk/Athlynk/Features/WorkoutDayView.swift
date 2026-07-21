//
//  WorkoutDayView.swift
//  Live training day: exercises shown ONE AT A TIME. Swipe or use the prev/next
//  arrows to move between them; each page shows the full prescription + media +
//  execution + coach note (ExerciseDetailView). A position indicator ("3 / 8")
//  keeps the athlete oriented.
//

import SwiftUI

struct WorkoutDayView: View {
    let day: WorkoutDayDTO
    var assignmentId: Int? = nil

    @State private var current = 0
    @State private var appear = false
    @Environment(\.dismiss) private var dismiss

    private var count: Int { day.exercises.count }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.magenta, Palette.violet, Palette.cyan, Palette.magenta])

            VStack(alignment: .leading, spacing: 16) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                if let aid = assignmentId {
                    NavigationLink { ActiveSessionView(assignmentId: aid, day: day) } label: {
                        startSessionButton
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 22)
                }

                if count == 0 {
                    Spacer()
                    Text("Nessun esercizio.").font(Typo.body(14)).foregroundStyle(Palette.textMid)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    pager
                    navBar.padding(.horizontal, 22).padding(.bottom, 8)
                }
            }
            .padding(.bottom, AppLayout.tabBarClearance)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DAY \(day.dayOrder)" + (day.focusArea.map { " · \($0.uppercased())" } ?? ""))
                .voltEyebrow()
            Text(day.label).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            if let notes = day.notes, !notes.isEmpty {
                Text(notes).font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
        }
    }

    private var pager: some View {
        TabView(selection: $current) {
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { i, ex in
                // Each page reuses the rich single-exercise layout.
                ExerciseDetailView(exercise: ex)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.25), value: current)
    }

    private var navBar: some View {
        HStack(spacing: 14) {
            navArrow("chevron.left", enabled: current > 0) {
                if current > 0 { withAnimation { current -= 1 } }
            }
            Spacer()
            Text("\(current + 1) / \(count)")
                .font(Typo.mono(14, .black)).tracking(1).foregroundStyle(Palette.textHi)
            Spacer()
            navArrow("chevron.right", enabled: current < count - 1) {
                if current < count - 1 { withAnimation { current += 1 } }
            }
        }
    }

    private func navArrow(_ icon: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.soft() }) {
            Image(systemName: icon).font(.system(size: 16, weight: .black))
                .foregroundStyle(enabled ? Palette.void0 : Palette.textLow)
                .frame(width: 48, height: 48)
                .background(Circle().fill(enabled ? Palette.magenta : Palette.void2))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
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
}
