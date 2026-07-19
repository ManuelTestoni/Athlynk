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
    @EnvironmentObject private var confirmCenter: ConfirmCenter
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
    // Real backend progress (PDF jobs expose phase+percent via the status endpoint).
    @State private var importPhase: String?
    @State private var importPercent: Double?

    private static let phaseLabels: [String: String] = [
        "analyze": "Analisi del documento…",
        "classify": "Identificazione pagine rilevanti…",
        "ocr": "OCR delle pagine necessarie…",
        "extract": "Estrazione AI in corso…",
        "finalize": "Preparazione revisione…",
    ]

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
            .confirmDialogHost(confirmCenter)
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
                CoachImportReviewView(kind: kind, extracted: ex, title: $title,
                                      flash: flash) {
                    onSaved()
                    dismiss()
                }
            }

            if fileData != nil && extracted == nil && !analyzing {
                NeonButton(title: "Analizza con Chiron", icon: "wand.and.stars",
                           color: kind.accent, loading: busy) { Task { await analyze() } }
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
            // Real backend phase when available (PDF jobs); rotating phrases otherwise.
            Text(importPhase.flatMap { Self.phaseLabels[$0] }
                 ?? importPhrases[phraseIdx % importPhrases.count])
                .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
                .transition(.opacity)
                .id(importPhase ?? "\(phraseIdx)")
            if let pct = importPercent {
                Capsule().fill(kind.accent.opacity(0.18)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(kind.accent)
                                .frame(width: geo.size.width * max(0.04, min(1, pct / 100)))
                                .animation(.easeInOut(duration: 0.5), value: pct)
                        }
                    }
            } else {
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
        importPhase = nil; importPercent = nil
        withAnimation { analyzing = true }
        defer { busy = false; withAnimation { analyzing = false } }
        do {
            let result: [String: Any]
            if isPDF {
                let api = APIClient.shared
                let jobId = kind == .workout
                    ? try await api.coachImportWorkoutPDF(file: data, filename: name, title: title)
                    : try await api.coachImportDietPDF(file: data, filename: name, title: title)
                result = try await pollPDF(jobId: jobId)
            } else {
                result = kind == .workout
                    ? try await APIClient.shared.coachImportWorkoutExcel(file: data, filename: name, title: title)
                    : try await APIClient.shared.coachImportDietExcel(file: data, filename: name, title: title)
            }
            let payload = (result["result"] as? [String: Any]) ?? result
            extracted = (payload["extracted"] as? [String: Any]) ?? payload
            summary = buildSummary(extracted ?? [:])
            flash.success("Documento analizzato")
        } catch {
            // 403 here means the coach's plan doesn't include the Chiron add-on
            // (server message is already the exact upsell copy) — surface it
            // verbatim instead of the generic "Si è verificato un errore".
            if case APIError.http(403, let detail) = error {
                flash.failure(detail)
            } else {
                flash.failure(error.localizedDescription)
            }
        }
    }

    /// Poll the async PDF job until done/error, driving the real progress UI.
    private func pollPDF(jobId: String) async throws -> [String: Any] {
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            let status = kind == .workout
                ? try await APIClient.shared.coachWorkoutImportStatus(jobId: jobId)
                : try await APIClient.shared.coachDietImportStatus(jobId: jobId)
            withAnimation {
                importPhase = status["phase"] as? String
                if let p = status["percent"] as? Int { importPercent = Double(p) }
                else if let p = status["percent"] as? Double { importPercent = p }
            }
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

}
