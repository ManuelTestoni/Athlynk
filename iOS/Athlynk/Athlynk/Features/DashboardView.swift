//
//  DashboardView.swift
//  The "Hub": hero greeting, live stat rings, and quick jumps to each domain.
//

import SwiftUI
import Combine

@MainActor
final class DashboardVM: ObservableObject {
    @Published var workouts: [WorkoutPlanDTO] = []
    @Published var nutrition: [NutritionPlanDTO] = []
    @Published var checks: [CheckDTO] = []
    @Published var loading = true

    func load() async {
        loading = true
        workouts = (try? await APIClient.shared.workouts()) ?? []
        nutrition = (try? await APIClient.shared.nutrition()) ?? []
        checks = (try? await APIClient.shared.checks()) ?? []
        loading = false
    }

    var sessionsPerWeek: Int { workouts.first?.frequencyPerWeek ?? workouts.first?.days.count ?? 0 }
    var totalExercises: Int { workouts.flatMap { $0.days }.reduce(0) { $0 + $1.exercises.count } }
    var dailyKcal: Int { nutrition.first?.dailyKcal ?? 0 }
}

struct DashboardView: View {
    @Binding var tab: AppTab
    @EnvironmentObject var app: AppState
    @StateObject private var vm = DashboardVM()
    @State private var appear = false

    var body: some View {
        ScreenScroll {
            // Hero
            VStack(alignment: .leading, spacing: 6) {
                Text("\(greeting), ATLETA").voltEyebrow()
                GlitchText(text: app.greetingName.uppercased(), size: 52)
                if let goal = app.me?.profile?.primaryGoal, !goal.isEmpty {
                    Text(goal.uppercased())
                        .font(Typo.mono(12, .bold)).tracking(2)
                        .foregroundStyle(Palette.lime)
                }
            }
            .revealUp(appear, index: 0)

            // Stat rings
            HStack(spacing: 14) {
                statRing(value: vm.sessionsPerWeek, max: 7, label: "Sessioni/sett", color: Palette.magenta)
                statRing(value: vm.checks.count, max: 5, label: "Check aperti", color: Palette.violet)
                statRing(value: vm.dailyKcal / 100, max: 35, label: "Kcal ÷100", color: Palette.lime)
            }
            .revealUp(appear, index: 1)

            // Quick jumps
            Text("ACCESSO RAPIDO").voltEyebrow().padding(.top, 6)
                .revealUp(appear, index: 2)

            VStack(spacing: 12) {
                jump(.train, title: "La tua scheda",
                     subtitle: workoutSubtitle, icon: "dumbbell.fill", index: 3)
                jump(.fuel, title: "Piano nutrizionale",
                     subtitle: nutritionSubtitle, icon: "flame.fill", index: 4)
                jump(.check, title: "Check-in",
                     subtitle: vm.checks.isEmpty ? "Nessun check in attesa" : "\(vm.checks.count) da compilare",
                     icon: "checkmark.seal.fill", index: 5)
            }

            if vm.loading { LoadingPanel() }
        }
        .onAppear { appear = true }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "BUONGIORNO" : (h < 18 ? "BUON POMERIGGIO" : "BUONASERA")
    }
    private var workoutSubtitle: String {
        guard let w = vm.workouts.first else { return "Nessuna scheda attiva" }
        return "\(w.title) · \(w.days.count) giorni"
    }
    private var nutritionSubtitle: String {
        guard let n = vm.nutrition.first else { return "Nessun piano attivo" }
        return n.planMode == "MACRO" ? "Macro: \(n.dailyKcal ?? 0) kcal" : n.title
    }

    private func statRing(value: Int, max: Int, label: String, color: Color) -> some View {
        VStack(spacing: 10) {
            RingGauge(progress: max > 0 ? Double(value) / Double(max) : 0,
                      color: color, lineWidth: 9,
                      value: "\(value)")
                .frame(width: 92, height: 92)
            Text(label)
                .font(Typo.mono(9, .bold)).tracking(1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .voltPanel(color.opacity(0.4))
    }

    private func jump(_ dest: AppTab, title: String, subtitle: String, icon: String, index: Int) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { tab = dest }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(dest.color.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(dest.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typo.display(19)).foregroundStyle(Palette.textHi)
                    Text(subtitle).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(dest.color)
            }
            .padding(16)
            .voltPanel(dest.color.opacity(0.35))
        }
        .buttonStyle(PressableButtonStyle())
        .revealUp(appear, index: index)
    }
}
