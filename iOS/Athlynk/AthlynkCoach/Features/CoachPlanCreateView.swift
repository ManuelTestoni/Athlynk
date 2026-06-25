//
//  CoachPlanCreateView.swift
//  Create a workout / nutrition plan on mobile — two routes:
//   • Builder: the full wizard (CoachPlanWizards) — same phases as the web:
//     workout kind (settimanale/programmazione) + days/exercises/progressione,
//     or nutrition mode (alimenti/macro) × kind (giornaliero/settimanale).
//   • Chiron AI import: upload the same PDF / Excel formats the web supports,
//     let Chiron parse them, review the summary, then save a draft plan.
//

import SwiftUI
import UniformTypeIdentifiers

enum CoachPlanKind { case workout, nutrition
    var label: String { self == .workout ? "Allenamento" : "Piano alimentare" }
    var accent: Color { self == .workout ? Palette.cyan : Palette.lime }
}

struct CoachPlanCreateView: View {
    let kind: CoachPlanKind
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var mode = 0            // 0 = builder, 1 = Chiron import
    @State private var title = ""
    @State private var busy = false

    // Import state
    @State private var picking = false
    @State private var fileName: String?
    @State private var fileData: Data?
    @State private var extracted: [String: Any]?
    @State private var summary: String?
    @State private var analyzing = false   // drives the progress overlay
    @State private var phraseIdx = 0

    // Rotating status phrases shown during analysis (mirrors the web importer).
    private var importPhrases: [String] {
        kind == .workout
        ? ["Sto leggendo il documento…", "Sto identificando le sessioni…",
           "Sto riconoscendo gli esercizi…", "Sto calcolando serie e ripetizioni…",
           "Sto cercando i match nel database…"]
        : ["Sto leggendo il documento…", "Sto identificando i giorni della dieta…",
           "Sto riconoscendo gli alimenti…", "Sto normalizzando le unità di misura…",
           "Sto cercando i match nel database…"]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text("Builder").tag(0)
                    Text("Chiron AI").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)

                if mode == 0 {
                    if kind == .workout {
                        CoachWorkoutWizardView(onSaved: onSaved, embedded: true)
                    } else {
                        CoachNutritionWizardView(onSaved: onSaved, embedded: true)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            field("Titolo", $title,
                                  placeholder: kind == .workout ? "Es. Upper/Lower" : "Es. Definizione 2000 kcal")
                            importSection
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Nuovo \(kind.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .fileImporter(isPresented: $picking, allowedContentTypes: allowedTypes) { result in
                handlePicked(result)
            }
            .statusOverlay(flash)
        }
    }

    private var allowedTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "xlsx") ?? .spreadsheet,
         UTType(filenameExtension: "xls") ?? .spreadsheet, .spreadsheet]
    }

    // MARK: Chiron import

    private var importSection: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 22, weight: .bold)).foregroundStyle(kind.accent)
                Text("Importa da PDF o Excel")
                    .font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text("Chiron legge il documento ed estrae \(kind == .workout ? "sessioni ed esercizi" : "giorni, pasti e alimenti").")
                    .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(18).voltPanel()

            Button { picking = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: fileName == nil ? "doc.badge.plus" : "doc.fill")
                    Text(fileName ?? "Scegli file").lineLimit(1)
                }
                .font(Typo.body(15, .semibold)).foregroundStyle(kind.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(kind.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            }
            .buttonStyle(.plain)

            if analyzing {
                importProgress
            }

            if let ex = extracted, !analyzing {
                if let summary {
                    Text(summary).font(Typo.mono(11, .semibold)).tracking(1)
                        .foregroundStyle(kind.accent).frame(maxWidth: .infinity)
                }
                importReview(ex)
            }

            if fileData != nil && extracted == nil && !analyzing {
                NeonButton(title: "Analizza con Chiron", icon: "wand.and.stars",
                           color: kind.accent, loading: busy) { Task { await analyze() } }
            }
            if extracted != nil && !analyzing {
                NeonButton(title: "Salva bozza", icon: "tray.and.arrow.down.fill",
                           color: kind.accent, loading: busy) { Task { await confirmImport() } }
            }
        }
    }

    // Progress overlay: animated bar + rotating status phrase (web-style UX).
    private var importProgress: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars").font(.system(size: 24, weight: .bold))
                .foregroundStyle(kind.accent)
                .symbolEffect(.pulse, options: .repeating)
            ProgressView().tint(kind.accent).scaleEffect(1.1)
            Text(importPhrases[phraseIdx % importPhrases.count])
                .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .id(phraseIdx)
            Capsule().fill(kind.accent.opacity(0.18)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(kind.accent)
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: analyzing ? geo.size.width * 0.65 : -geo.size.width * 0.1)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: analyzing)
                    }
                }
        }
        .frame(maxWidth: .infinity).padding(20).voltPanel()
        .task(id: analyzing) {
            guard analyzing else { return }
            while analyzing && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                if analyzing { withAnimation { phraseIdx += 1 } }
            }
        }
    }

    // Structured review of the parsed plan before saving the draft.
    @ViewBuilder
    private func importReview(_ ex: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REVISIONE").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            if kind == .workout {
                let sessions = (ex["sessions"] as? [[String: Any]]) ?? []
                if sessions.isEmpty {
                    Text("Nessuna sessione rilevata. Controlla il file o riprova.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                }
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    reviewGroup(
                        title: (s["name"] as? String) ?? (s["day_name"] as? String) ?? "Sessione",
                        items: ((s["blocks"] as? [[String: Any]]) ?? []).flatMap { b in
                            ((b["exercises"] as? [[String: Any]]) ?? []).map { e in
                                let name = (e["name"] as? String) ?? (e["exercise_name"] as? String) ?? "Esercizio"
                                let sets = (e["sets"] as? Int).map { "\($0)×" } ?? ""
                                let reps = (e["reps"] as? Int).map { "\($0)" } ?? (e["rep_range"] as? String ?? "")
                                return "\(name) — \(sets)\(reps)".trimmingCharacters(in: .whitespaces)
                            }
                        })
                }
            } else {
                let days = (ex["days"] as? [[String: Any]]) ?? []
                if days.isEmpty {
                    Text("Nessun giorno rilevato. Controlla il file o riprova.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    reviewGroup(
                        title: (d["name"] as? String) ?? (d["day_name"] as? String) ?? "Giorno",
                        items: ((d["meals"] as? [[String: Any]]) ?? []).flatMap { m in
                            let mealName = (m["name"] as? String) ?? "Pasto"
                            let foods = ((m["items"] as? [[String: Any]]) ?? (m["foods"] as? [[String: Any]]) ?? [])
                            return ["· \(mealName)"] + foods.map { f in
                                let fn = (f["name"] as? String) ?? (f["food_name"] as? String) ?? "Alimento"
                                let qty = (f["quantity"] as? Double).map { "  \(Int($0)) g" }
                                    ?? (f["grams"] as? Double).map { "  \(Int($0)) g" } ?? ""
                                return "   \(fn)\(qty)"
                            }
                        })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }

    private func reviewGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
            ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                Text(line).font(Typo.body(12)).foregroundStyle(Palette.textMid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: Field helper

    private func field(_ label: String, _ text: Binding<String>, placeholder: String = "",
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.textLow))
                .font(Typo.body(16)).foregroundStyle(Palette.textHi).tint(kind.accent)
                .keyboardType(keyboard)
                .padding(.horizontal, 14).padding(.vertical, 13).voltPanel(radius: 12)
        }
    }

    // MARK: Actions

    private func handlePicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url) {
            fileData = data
            fileName = url.lastPathComponent
            extracted = nil; summary = nil
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        }
    }

    private var isPDF: Bool { (fileName ?? "").lowercased().hasSuffix(".pdf") }

    private func analyze() async {
        guard let data = fileData, let name = fileName else { return }
        busy = true; phraseIdx = 0
        withAnimation { analyzing = true }
        defer { busy = false; withAnimation { analyzing = false } }
        do {
            let result: [String: Any]
            if isPDF {
                let api = APIClient.shared
                let jobId = kind == .workout
                    ? try await api.coachImportWorkoutPDF(file: data, filename: name, title: title, clientId: nil)
                    : try await api.coachImportDietPDF(file: data, filename: name, title: title, clientId: nil)
                result = try await pollPDF(jobId: jobId)
            } else {
                result = kind == .workout
                    ? try await APIClient.shared.coachImportWorkoutExcel(file: data, filename: name, title: title, clientId: nil)
                    : try await APIClient.shared.coachImportDietExcel(file: data, filename: name, title: title, clientId: nil)
            }
            let payload = (result["result"] as? [String: Any]) ?? result
            extracted = (payload["extracted"] as? [String: Any]) ?? payload
            summary = buildSummary(extracted ?? [:])
            flash.success("Documento analizzato")
        } catch {
            flash.failure(error.localizedDescription)
        }
    }

    /// Poll the async PDF job until done/error.
    private func pollPDF(jobId: String) async throws -> [String: Any] {
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            let status = kind == .workout
                ? try await APIClient.shared.coachWorkoutImportStatus(jobId: jobId)
                : try await APIClient.shared.coachDietImportStatus(jobId: jobId)
            switch status["status"] as? String {
            case "done": return status
            case "error": throw APIError.http(500, (status["detail"] as? String) ?? "Analisi non riuscita")
            default: continue
            }
        }
        throw APIError.transport("Analisi troppo lunga, riprova.")
    }

    private func buildSummary(_ ex: [String: Any]) -> String {
        if kind == .workout {
            let sessions = (ex["sessions"] as? [[String: Any]]) ?? []
            let exCount = sessions.reduce(0) { acc, s in
                acc + ((s["blocks"] as? [[String: Any]]) ?? []).reduce(0) { $0 + (($1["exercises"] as? [Any])?.count ?? 0) }
            }
            return "\(sessions.count) sessioni · \(exCount) esercizi rilevati."
        } else {
            let days = (ex["days"] as? [[String: Any]]) ?? []
            let meals = days.reduce(0) { $0 + (($1["meals"] as? [Any])?.count ?? 0) }
            return "\(days.count) giorni · \(meals) pasti rilevati."
        }
    }

    private func confirmImport() async {
        guard let ex = extracted else { return }
        busy = true; defer { busy = false }
        do {
            if kind == .workout {
                try await APIClient.shared.coachConfirmWorkout(workoutJson: ex, title: title, clientId: nil, assignNow: false)
            } else {
                try await APIClient.shared.coachConfirmDiet(dietJson: ex, title: title, clientId: nil, assignNow: false)
            }
            flash.success("Bozza salvata")
            try? await Task.sleep(for: .seconds(1.2))
            onSaved()
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
