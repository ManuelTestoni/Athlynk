//
//  CoachPlanCreateView.swift
//  Create a workout / nutrition plan on mobile — two routes:
//   • Chiron AI import: upload the same PDF / Excel formats the web supports,
//     let Chiron parse them, review the summary, then save a draft plan.
//   • Manual: a lightweight quick-create (title + essentials) that lands a draft
//     in the library; the full structure is edited from the plan detail / web.
//

import SwiftUI
import UniformTypeIdentifiers

enum CoachPlanKind { case workout, nutrition
    var label: String { self == .workout ? "Allenamento" : "Piano alimentare" }
    var accent: Color { self == .workout ? Palette.cyan : Palette.lime }
}

struct CoachPlanCreateView: View {
    let kind: CoachPlanKind
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var mode = 0            // 0 = Chiron import, 1 = manuale
    @State private var title = ""
    @State private var goal = ""
    @State private var kcal = ""
    @State private var busy = false

    // Import state
    @State private var picking = false
    @State private var fileName: String?
    @State private var fileData: Data?
    @State private var extracted: [String: Any]?
    @State private var summary: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $mode) {
                        Text("Chiron AI").tag(0)
                        Text("Manuale").tag(1)
                    }
                    .pickerStyle(.segmented)

                    field("Titolo", $title, placeholder: kind == .workout ? "Es. Upper/Lower" : "Es. Definizione 2000 kcal")

                    if mode == 0 { importSection } else { manualSection }
                }
                .padding(20)
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

            if let summary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ANTEPRIMA").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                    Text(summary).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
            }

            if fileData != nil && extracted == nil {
                NeonButton(title: "Analizza con Chiron", icon: "wand.and.stars",
                           color: kind.accent, loading: busy) { Task { await analyze() } }
            }
            if extracted != nil {
                NeonButton(title: "Salva bozza", icon: "tray.and.arrow.down.fill",
                           color: kind.accent, loading: busy) { Task { await confirmImport() } }
            }
        }
    }

    // MARK: Manual quick-create

    private var manualSection: some View {
        VStack(spacing: 14) {
            if kind == .workout {
                field("Obiettivo (facoltativo)", $goal, placeholder: "Es. Ipertrofia")
            } else {
                field("Kcal giornaliere (facoltativo)", $kcal, placeholder: "Es. 2000", keyboard: .numberPad)
            }
            Text("Crea una bozza con i dati essenziali. Aggiungi \(kind == .workout ? "giorni ed esercizi" : "pasti e alimenti") dal dettaglio del piano.")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
                .frame(maxWidth: .infinity, alignment: .leading)
            NeonButton(title: "Crea bozza", icon: "plus", color: kind.accent, loading: busy) {
                Task { await createManual() }
            }
        }
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
        busy = true; defer { busy = false }
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
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }

    private func createManual() async {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            flash.failure("Inserisci un titolo"); return
        }
        busy = true; defer { busy = false }
        do {
            if kind == .workout {
                var payload: [String: Any] = ["title": title]
                if !goal.isEmpty { payload["goal"] = goal }
                _ = try await APIClient.shared.coachCreateWorkout(payload)
            } else {
                var payload: [String: Any] = ["title": title]
                if let k = Int(kcal) { payload["daily_kcal"] = k }
                _ = try await APIClient.shared.coachCreateNutrition(payload)
            }
            Analytics.shared.capture(.planUpdated, ["kind": kind == .workout ? "workout" : "nutrition"])
            flash.success("Bozza creata")
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
