//
//  ExercisePickerSheet.swift
//  Catalog exercise picker: search by name or browse by muscle group —
//  same UX as the food picker. Used by the athlete's active session to
//  add an exercise or substitute one (session-only, the plan never changes).
//
//  `SubstitutePickerSheet` shows same-primary-muscle suggestions first, with a
//  "Non trovi il tuo esercizio? Esplora tutti" escape hatch into the full picker.
//

import SwiftUI

struct SessionExercisePickerSheet: View {
    var title = "Aggiungi esercizio"
    var accent: Color = Palette.primary
    var onPick: (ExerciseSearchItemDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ExerciseSearchItemDTO] = []
    @State private var groups: [MuscleGroupDTO] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var filter = "all"   // all | cat
    @State private var activeGroup: MuscleGroupDTO?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VoltField(icon: "magnifyingglass", placeholder: "Cerca un esercizio…",
                          text: $query, accent: accent)
                    .padding(.horizontal, 16).padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach([("all", "Tutti"), ("cat", "Gruppi muscolari")], id: \.0) { key, label in
                        Button {
                            Haptics.tap()
                            filter = key; activeGroup = nil; results = []
                            scheduleSearch(immediate: true)
                        } label: {
                            Text(label)
                                .font(Typo.body(12, .semibold))
                                .foregroundStyle(filter == key ? Palette.void0 : Palette.textMid)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(filter == key ? accent : Palette.void2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                if filter == "cat", let g = activeGroup {
                    Button {
                        Haptics.tap()
                        activeGroup = nil; results = []
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text(g.name).font(Typo.body(13, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }

                if filter == "cat" && activeGroup == nil {
                    if filteredGroups.isEmpty {
                        Spacer()
                        Text(groups.isEmpty ? "Caricamento gruppi…" : "Nessun gruppo trovato.")
                            .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredGroups) { g in groupRow(g) }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 24)
                        }
                    }
                } else if loading && results.isEmpty {
                    Spacer(); ProgressView().tint(accent); Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(emptyText)
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { item in
                                Button {
                                    Haptics.tap()
                                    onPick(item)
                                    dismiss()
                                } label: { ExerciseResultRow(item: item, accent: accent) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }.tint(accent)
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .task { if results.isEmpty { await search() } }
        }
        .presentationDetents([.large])
    }

    private var filteredGroups: [MuscleGroupDTO] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? groups : groups.filter { $0.name.lowercased().contains(q) }
    }

    private func groupRow(_ g: MuscleGroupDTO) -> some View {
        Button {
            Haptics.tap()
            activeGroup = g
            scheduleSearch(immediate: true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                Text(g.name).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textMid)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voltPanel(Palette.line, radius: 13)
    }

    private var emptyText: String {
        if filter == "cat" && activeGroup == nil { return "Scegli un gruppo muscolare." }
        return query.isEmpty ? "Cerca nel catalogo o filtra per gruppo muscolare." : "Nessun esercizio trovato."
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        if filter == "cat" && activeGroup == nil && !groups.isEmpty {
            results = []; return
        }
        loading = true; defer { loading = false }
        let resp = try? await APIClient.shared.searchExercises(
            q: query,
            muscleGroup: activeGroup?.slug ?? "",
            includeGroups: groups.isEmpty)
        guard !Task.isCancelled else { return }
        if let g = resp?.muscleGroups { groups = g }
        if filter == "cat" && activeGroup == nil {
            results = []
        } else {
            results = resp?.results ?? []
        }
    }
}

/// Substitute flow: same-primary-muscle suggestions first, full catalog on demand.
struct SubstitutePickerSheet: View {
    let forExercise: SessionExerciseDTO
    /// Catalog id used for the "same primary muscle" lookup.
    let catalogExerciseId: Int?
    var accent: Color = Palette.control
    var onPick: (ExerciseSearchItemDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var similar: [ExerciseSearchItemDTO] = []
    @State private var loading = true
    @State private var exploreAll = false

    var body: some View {
        Group {
            if exploreAll {
                SessionExercisePickerSheet(title: "Sostituisci esercizio", accent: accent, onPick: onPick)
            } else {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STESSO GRUPPO MUSCOLARE")
                            .font(Typo.mono(10, .bold)).tracking(2)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 16).padding(.top, 14)

                        if loading {
                            Spacer(); HStack { Spacer(); ProgressView().tint(accent); Spacer() }; Spacer()
                        } else if similar.isEmpty {
                            Spacer()
                            Text("Nessun esercizio simile trovato.")
                                .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                                .frame(maxWidth: .infinity)
                            Spacer()
                        } else {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 8) {
                                    ForEach(similar) { item in
                                        Button {
                                            Haptics.tap()
                                            onPick(item)
                                            dismiss()
                                        } label: { ExerciseResultRow(item: item, accent: accent) }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        Button {
                            Haptics.tap()
                            exploreAll = true
                        } label: {
                            (Text("Non trovi il tuo esercizio? ") + Text("Esplora tutti").bold())
                                .font(Typo.body(13))
                                .foregroundStyle(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16).padding(.bottom, 20)
                    }
                    .background(Palette.void0.ignoresSafeArea())
                    .navigationTitle("Sostituisci \(forExercise.name)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { dismiss() }.tint(accent)
                        }
                    }
                    .task {
                        guard let catId = catalogExerciseId else { loading = false; return }
                        let resp = try? await APIClient.shared.searchExercises(similarTo: catId)
                        similar = resp?.results ?? []
                        loading = false
                    }
                }
                .presentationDetents([.large])
            }
        }
    }
}

private struct ExerciseResultRow: View {
    let item: ExerciseSearchItemDTO
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Typo.mono(10)).foregroundStyle(Palette.textMid)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
        }
        .padding(14).voltPanel(accent.opacity(0.3))
    }

    private var subtitle: String {
        ([item.primaryMuscle] + item.equipment).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
