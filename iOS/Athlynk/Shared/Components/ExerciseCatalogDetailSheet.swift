//
//  ExerciseCatalogDetailSheet.swift
//  Catalog-only exercise detail — gif, description, muscles, instructions —
//  for contexts that don't have a full prescription in hand yet: picker rows
//  (builder, add/substitute), and read-only scheda/session list rows.
//  Fetches on demand by catalog id via the shared dual-auth
//  `GET /api/exercises/<id>/` endpoint. Contexts that already hold a full
//  prescription (the athlete's workout-day view) keep using the full-page
//  `ExerciseDetailView` instead — this sheet is deliberately lighter.
//

import SwiftUI

struct ExerciseCatalogDetailSheet: View {
    let exerciseId: Int
    var fallbackName: String = "Esercizio"
    var accent: Color = Palette.textMid

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ExerciseCatalogDetailDTO?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ExerciseMediaHero(demoGifUrl: detail?.demoGifUrl, coverImageUrl: detail?.coverImageUrl,
                                      accent: accent)

                    Text(detail?.name ?? fallbackName)
                        .font(Typo.display(24)).foregroundStyle(Palette.textHi)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail, hasTags(detail) {
                        tagsRow(detail)
                    }

                    if loading {
                        ProgressView().tint(accent)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    } else if failed {
                        Text("Impossibile caricare il dettaglio. Riprova.")
                            .font(Typo.body(13)).foregroundStyle(Palette.textLow)
                    } else {
                        if let desc = detail?.description, !desc.isEmpty {
                            descriptionBlock(desc)
                        }
                        if let steps = detail?.instructionSteps, !steps.isEmpty {
                            instructionsBlock(steps)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 32)
            }
            .background(Palette.void0)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func hasTags(_ d: ExerciseCatalogDetailDTO) -> Bool {
        d.category != nil || !d.primaryMuscles.isEmpty || !d.secondaryMuscles.isEmpty || !d.equipment.isEmpty
    }

    private func tagsRow(_ d: ExerciseCatalogDetailDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let cat = d.category { chip(cat.name, filled: true) }
                ForEach(d.primaryMuscles) { m in chip(m.name, filled: true) }
                ForEach(d.secondaryMuscles) { m in chip(m.name, filled: false) }
                ForEach(d.equipment) { eq in chip(eq.name, filled: false) }
            }
        }
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text.uppercased())
            .font(Typo.mono(10, .bold)).tracking(0.6)
            .foregroundStyle(filled ? Palette.void0 : Palette.textMid)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(filled ? accent : Palette.void2))
    }

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").font(.system(size: 14, weight: .black))
                    .foregroundStyle(accent)
                Text("ESERCIZIO").voltEyebrow()
            }
            Text(text).font(Typo.body(15)).foregroundStyle(Palette.textHi)
        }
        .padding(18).voltPanel(accent.opacity(0.35))
    }

    private func instructionsBlock(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").font(.system(size: 14, weight: .black))
                    .foregroundStyle(accent)
                Text("ESECUZIONE").voltEyebrow()
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(Typo.mono(12, .black)).foregroundStyle(accent)
                            .frame(width: 18, alignment: .leading)
                        Text(step).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    }
                }
            }
        }
        .padding(18).voltPanel(accent.opacity(0.35))
    }

    private func load() async {
        loading = true
        failed = false
        do {
            detail = try await APIClient.shared.exerciseCatalogDetail(id: exerciseId)
        } catch {
            failed = true
        }
        loading = false
    }
}
