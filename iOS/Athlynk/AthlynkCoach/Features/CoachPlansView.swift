//
//  CoachPlansView.swift
//  "Gestione Allenamenti (Coach)" + "Gestione Nutrizione (Coach)".
//  Read-only management overview: the plan library + who has what assigned.
//

import SwiftUI

struct CoachWorkoutsView: View {
    @Binding var path: NavigationPath
    @State private var plans: [CoachPlanRow] = []
    @State private var assignments: [CoachAssignmentRow] = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var query = ""
    @State private var creating = false
    @State private var loadToken = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Programmazione", title: "Allenamenti",
                             subtitle: "Le tue schede e assegnazioni", accent: Palette.cyan)
                workoutSearchBar
                if loading && plans.isEmpty {
                    CoachPlanLibrarySkeleton(accent: Palette.cyan)
                } else {
                    CoachSectionTitle(eyebrow: "Libreria", title: "Schede (\(plans.count))", accent: Palette.cyan)
                    if plans.isEmpty {
                        EmptyPanel(icon: "dumbbell", text: "Nessuna scheda ancora creata.",
                                   color: Palette.cyan,
                                   actionTitle: "Creane una ora") { creating = true }
                    } else {
                        ForEach(plans) { p in
                            NavigationLink(value: CoachPlanRoute.workout(p.id)) {
                                planCard(title: p.title,
                                         subtitle: [p.goal, p.level].compactMap { $0 }.joined(separator: " · "),
                                         meta: p.durationWeeks.map { "\($0) sett." },
                                         assigned: p.assignedCount, accent: Palette.cyan)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        if hasMore {
                            LoadMoreButton(loading: loadingMore, accent: Palette.cyan) { Task { await loadMore() } }
                        }
                    }
                    if !assignments.isEmpty {
                        CoachSectionTitle(eyebrow: "In corso", title: "Assegnazioni", accent: Palette.bronze)
                        ForEach(assignments) { a in assignmentCard(a, accent: Palette.cyan) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus.circle.fill") }.tint(Palette.cyan)
            } }
            .navigationDestination(for: CoachPlanRoute.self) { route in
                switch route {
                case .workout(let id): CoachWorkoutDetailView(planId: id)
                case .nutrition(let id): CoachNutritionDetailView(planId: id)
                }
            }
            .sheet(isPresented: $creating, onDismiss: { plans = []; loadToken = UUID() }) {
                CoachPlanCreateView(kind: .workout)
            }
            .task(id: loadToken) {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await load()
            }
            .refreshable { await load(force: true) }
        }
    }

    private var workoutSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.cyan)
            TextField("", text: $query, prompt: Text("Cerca scheda…").foregroundStyle(Palette.textLow))
                .font(Typo.body(15)).tint(Palette.cyan)
                .onSubmit { Task { await load(force: true) } }
            if !query.isEmpty {
                Button { query = ""; Task { await load(force: true) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textLow)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).voltPanel(radius: 14)
    }

    private func load(force: Bool = false) async {
        if !force, !plans.isEmpty, query.isEmpty { return }
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachWorkouts(q: query, offset: 0) {
            plans = res.plans; assignments = res.assignments; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachWorkouts(q: query, offset: plans.count) {
            plans.append(contentsOf: res.plans); hasMore = res.hasMore
        }
    }
}

struct CoachNutritionView: View {
    @Binding var path: NavigationPath
    @State private var plans: [CoachPlanRow] = []
    @State private var assignments: [CoachAssignmentRow] = []
    @State private var hasMore = false
    @State private var loading = true
    @State private var loadingMore = false
    @State private var query = ""
    @State private var creating = false
    @State private var loadToken = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Programmazione", title: "Nutrizione",
                             subtitle: "I tuoi piani alimentari", accent: Palette.lime)
                nutritionSearchBar
                if loading && plans.isEmpty {
                    CoachPlanLibrarySkeleton(accent: Palette.lime)
                } else {
                    CoachSectionTitle(eyebrow: "Libreria", title: "Piani (\(plans.count))", accent: Palette.lime)
                    if plans.isEmpty {
                        EmptyPanel(icon: "flame", text: "Nessun piano ancora creato.",
                                   color: Palette.lime,
                                   actionTitle: "Creane uno ora") { creating = true }
                    } else {
                        ForEach(plans) { p in
                            NavigationLink(value: CoachPlanRoute.nutrition(p.id)) {
                                planCard(title: p.title,
                                         subtitle: [p.planMode, p.planKind].compactMap { $0 }.joined(separator: " · "),
                                         meta: p.dailyKcal.map { "\($0) kcal" },
                                         assigned: p.assignedCount, accent: Palette.lime)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        if hasMore {
                            LoadMoreButton(loading: loadingMore, accent: Palette.lime) { Task { await loadMore() } }
                        }
                    }
                    if !assignments.isEmpty {
                        CoachSectionTitle(eyebrow: "In corso", title: "Assegnazioni", accent: Palette.bronze)
                        ForEach(assignments) { a in assignmentCard(a, accent: Palette.lime) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus.circle.fill") }.tint(Palette.lime)
            } }
            .navigationDestination(for: CoachPlanRoute.self) { route in
                switch route {
                case .workout(let id): CoachWorkoutDetailView(planId: id)
                case .nutrition(let id): CoachNutritionDetailView(planId: id)
                }
            }
            .sheet(isPresented: $creating, onDismiss: { plans = []; loadToken = UUID() }) {
                CoachPlanCreateView(kind: .nutrition)
            }
            .task(id: loadToken) {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await load()
            }
            .refreshable { await load(force: true) }
        }
    }

    private var nutritionSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.lime)
            TextField("", text: $query, prompt: Text("Cerca piano…").foregroundStyle(Palette.textLow))
                .font(Typo.body(15)).tint(Palette.lime)
                .onSubmit { Task { await load(force: true) } }
            if !query.isEmpty {
                Button { query = ""; Task { await load(force: true) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textLow)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).voltPanel(radius: 14)
    }

    private func load(force: Bool = false) async {
        if !force, !plans.isEmpty, query.isEmpty { return }
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachNutrition(q: query, offset: 0) {
            plans = res.plans; assignments = res.assignments; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachNutrition(q: query, offset: plans.count) {
            plans.append(contentsOf: res.plans); hasMore = res.hasMore
        }
    }
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
