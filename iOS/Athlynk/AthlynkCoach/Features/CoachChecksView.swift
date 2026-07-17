//
//  CoachChecksView.swift
//  "Revisione Check-in (Coach)" — list of submitted checks + a detail/review
//  screen where the coach reads measurements/photos and writes feedback.
//

import SwiftUI

struct CoachChecksView: View {
    @Binding var path: NavigationPath
    @State private var checks: [CoachCheckRow] = []
    @State private var pendingCount = 0
    @State private var filter = "pending"     // pending | all
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var loadToken = UUID()
    @State private var appear = false

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Da revisionare", title: "Check-in",
                             subtitle: "\(pendingCount) in attesa di feedback", accent: Palette.bronze)
                    .revealUp(appear, index: 0)

                CoachCheckTemplatesSection()
                    .revealUp(appear, index: 1)

                SectionDivider().padding(.vertical, 4)

                Picker("", selection: $filter) {
                    Text("In attesa").tag("pending")
                    Text("Tutti").tag("all")
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { _, _ in checks = []; loadToken = UUID() }
                .revealUp(appear, index: 2)

                if filter == "all" {
                    CoachCheckAthleteListView()
                        .revealUp(appear, index: 3)
                } else if loading && checks.isEmpty {
                    AvatarRowsSkeleton(accent: Palette.bronze)
                } else if checks.isEmpty {
                    EmptyPanel(icon: "checkmark.seal", text: "Nessun check da revisionare. Ottimo lavoro!",
                               color: Palette.lime)
                } else {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                        NavigationLink(value: CheckRoute(id: c.id)) { coachCheckCard(c) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: min(i, 6) + 3)
                    }
                    if hasMore {
                        LoadMoreButton(loading: loadingMore, accent: Palette.bronze) {
                            Task { await loadMore() }
                        }
                    }
                }
            }
            .onChange(of: loading) { _, l in if !l { appear = true } }
            .onAppear { if !checks.isEmpty { appear = true } }
            .navigationDestination(for: CheckRoute.self) {
                CoachCheckDetailView(responseId: $0.id) { id in markFeedbackSent(id) }
            }
            .navigationDestination(for: CheckTemplateRoute.self) {
                CoachCheckTemplateDetailView(templateId: $0.id)
            }
            .navigationDestination(for: CheckAthleteRoute.self) {
                CoachAthleteChecksListView(route: $0)
            }
            .task(id: loadToken) {
                guard filter == "pending" else { return }
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await load()
            }
            .onRemoteChange(["CHECK_SUBMITTED"]) { checks = []; loadToken = UUID() }
            .refreshable { if filter == "pending" { await load(force: true) } }
        }
    }

    private func markFeedbackSent(_ id: Int) {
        // Feedback can be (re)written from any check detail, including ones opened
        // from "Tutti" that were never pending — only decrement/remove if this id
        // was actually part of the currently loaded "in attesa" list.
        guard checks.contains(where: { $0.id == id }) else { return }
        checks.removeAll { $0.id == id }
        pendingCount = max(0, pendingCount - 1)
    }

    private func load(force: Bool = false) async {
        if !force, !checks.isEmpty { return }
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachChecks(filter: filter, offset: 0) {
            checks = res.checks; pendingCount = res.pendingCount; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachChecks(filter: filter, offset: checks.count) {
            let known = Set(checks.map(\.id))
            checks.append(contentsOf: res.checks.filter { !known.contains($0.id) })
            hasMore = res.hasMore
            pendingCount = res.pendingCount
        }
    }
}

/// Shared check-row card, reused by `CoachChecksView`'s "In attesa" list and
/// `CoachAthleteChecksListView`'s per-athlete "Tutti" list.
func coachCheckCard(_ c: CoachCheckRow) -> some View {
    HStack(spacing: 14) {
        CoachClientAvatar(url: c.client?.profileImageUrl, initials: c.client?.initials ?? "A", size: 48)
        VStack(alignment: .leading, spacing: 4) {
            Text(c.client?.displayName ?? "Atleta").font(Typo.body(16, .semibold))
                .foregroundStyle(Palette.textHi)
            Text(c.title).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
            Text(CoachDate.relative(c.submittedAt)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
        }
        Spacer()
        if c.isQuickMeasurement {
            StatusBadge(text: "Misurazione", color: Palette.cyan, filled: false)
        } else if c.filledByCoach {
            StatusBadge(text: "Compilato", color: Palette.violet, filled: false)
        } else if c.reviewed {
            StatusBadge(text: "Fatto", color: Palette.lime)
        } else {
            StatusBadge(text: "Nuovo", color: Palette.bronze)
        }
    }
    .padding(14).voltPanel()
}

struct CoachCheckDetailView: View {
    let responseId: Int
    var onFeedbackSent: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @StateObject private var flash = StatusFlash()
    @State private var data: CoachCheckDetailDTO?
    @State private var loading = true
    @State private var feedback = ""
    @State private var privateNotes = ""
    @State private var sending = false
    @State private var sent = false
    @State private var editForm: CoachCheckPrefill?
    @State private var loadingEdit = false

    var body: some View {
        ScreenScroll {
            if let d = data {
                clientHeader(d)
                if !d.measurements.isEmpty || d.weightKg != nil { measurements(d) }
                if let fb = fabbisogniSummary(d) { fabbisogniCard(fb) }
                if !d.photos.isEmpty { photos(d) }
                if hasNotes(d) { notes(d) }
                editValuesButton
                feedbackComposer(d)
            } else if loading {
                CoachCheckDetailSkeleton()
            } else {
                EmptyPanel(icon: "doc.questionmark", text: "Check non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .statusOverlay(flash)
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
        .sheet(item: $editForm) { pf in
            CoachCheckFormView(mode: .edit(responseId: responseId),
                               title: data?.title ?? "Check",
                               questions: pf.questions, steps: pf.steps, prefill: pf.prefill) {
                flash.success("Valori aggiornati"); Task { await load() }
            }
        }
        .task {
            Analytics.shared.capture(.checkinOpened, ["check_id": responseId])
            Analytics.shared.capture(.checkinReviewStarted, ["check_id": responseId])
            await load()
        }
    }

    private var editValuesButton: some View {
        Button {
            Task {
                loadingEdit = true; defer { loadingEdit = false }
                editForm = try? await APIClient.shared.coachCheckPrefill(responseId: responseId)
                if editForm == nil { flash.failure("Modifica non disponibile") }
            }
        } label: {
            Label(loadingEdit ? "Apertura…" : "Correggi valori", systemImage: "slider.horizontal.3")
                .font(Typo.body(13, .semibold)).foregroundStyle(Palette.cyan)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.cyan.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func clientHeader(_ d: CoachCheckDetailDTO) -> some View {
        VStack(spacing: 10) {
            CoachClientAvatar(url: d.client.profileImageUrl, initials: d.client.initials, size: 72)
            Text(d.client.displayName).font(Typo.poster(28)).foregroundStyle(Palette.textHi)
            Text("\(d.title) · \(CoachDate.dayMonth(d.submittedAt))")
                .font(Typo.mono(11)).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private func measurements(_ d: CoachCheckDetailDTO) -> some View {
        var rows: [(String, String)] = []
        if let w = d.weightKg { rows.append(("Peso", "\(String(format: "%.1f", w)) kg")) }
        for (k, v) in d.measurements.sorted(by: { $0.key < $1.key }) { rows.append((label(k), "\(v) cm")) }
        for (k, v) in d.skinfolds.sorted(by: { $0.key < $1.key }) { rows.append((label(k), "\(v) mm")) }
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Antropometria", title: "Misurazioni", accent: Palette.cyan)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Text(r.0).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        Spacer()
                        Text(r.1).font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
                }
            }
        }
    }

    // MARK: - Calcolo Fabbisogni summary (mirrors WebApp check/detail.html)

    private struct FBSummaryMacro { let label: String; let gkg: String?; let g: Int?; let kcal: Int?; let note: String? }
    private struct FBSummary {
        let altezza: String?, peso: String?, eta: String?, sesso: String?
        let formula: String?, mb: Int?
        let pal: String?, palDesc: String?
        let detBase: Int?, detAdjust: Int, detFinale: Int?, detNote: String?
        let macros: [FBSummaryMacro]
        let fibra: String?, idrico: String?
        let micro: String?, noteOp: String?
    }

    private func fabbisogniSummary(_ d: CoachCheckDetailDTO) -> FBSummary? {
        func s(_ k: String) -> String? {
            let v = d.answers[k]?.asString
            return (v?.isEmpty ?? true) ? nil : v
        }
        func i(_ k: String) -> Int? {
            guard let v = s(k), let d = Double(v) else { return nil }
            return Int(d.rounded())
        }
        let detBase = i("det_kcal")
        let detAdjust = i("det_adjust_kcal") ?? 0
        let detFinale = i("det_finale_kcal") ?? detBase.map { $0 + detAdjust }
        let macroDefs: [(String, String, String, String, Double)] = [
            ("Proteine", "proteine_gkg", "proteine_g_totale", "proteine_note", 4),
            ("Carboidrati", "carboidrati_gkg", "carboidrati_g_totale", "carboidrati_note", 4),
            ("Lipidi", "lipidi_target", "lipidi_g_totale", "lipidi_note", 9),
        ]
        let macros: [FBSummaryMacro] = macroDefs.compactMap { entry -> FBSummaryMacro? in
            let (label, gkgKey, gKey, noteKey, factor) = entry
            let g = i(gKey), gkg = s(gkgKey), note = s(noteKey)
            guard g != nil || gkg != nil || note != nil else { return nil }
            let kcal = g.map { Int((Double($0) * factor).rounded()) }
            return FBSummaryMacro(label: label, gkg: gkg, g: g, kcal: kcal, note: note)
        }
        let fb = FBSummary(
            altezza: s("altezza_cm"), peso: s("peso_kg"), eta: s("eta_anni"), sesso: s("sesso"),
            formula: s("formula_mb"), mb: i("mb_stimata_kcal"),
            pal: s("pal_valore"), palDesc: s("pal_descrizione"),
            detBase: detBase, detAdjust: detAdjust, detFinale: detFinale, detNote: s("det_note"),
            macros: macros,
            fibra: s("fibra_gdie"), idrico: s("idrico_mldie"),
            micro: s("micronutrienti_critici"), noteOp: s("note_operative"))
        let hasData = !macros.isEmpty || fb.altezza != nil || fb.peso != nil || fb.mb != nil
            || fb.detFinale != nil || fb.fibra != nil || fb.idrico != nil || fb.micro != nil || fb.noteOp != nil
        return hasData ? fb : nil
    }

    private func fabbisogniCard(_ fb: FBSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Strumento", title: "Calcolo Fabbisogni", accent: Palette.bronze)

            if let det = fb.detFinale {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DET FINALE").font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                        (Text("\(det)").font(Typo.poster(26)) + Text(" kcal/die").font(Typo.body(12)))
                            .foregroundStyle(Palette.textHi)
                    }
                    Spacer()
                    if fb.detAdjust != 0, let base = fb.detBase {
                        StatusBadge(text: "base \(base) · \(fb.detAdjust > 0 ? "+" : "")\(fb.detAdjust) kcal", color: Palette.bronze)
                    }
                }
                .padding(14).voltPanel(radius: 12)
            }

            let stats: [(String, String)] = [
                fb.peso.map { ("Peso", "\($0) kg") },
                fb.altezza.map { ("Altezza", "\($0) cm") },
                fb.eta.map { ("Età", $0) },
                fb.sesso.map { ("Sesso", $0) },
                fb.mb.map { ("MB", "\($0) kcal") },
                fb.pal.map { ("PAL", "\($0)×") },
                fb.formula.map { ("Formula", $0) },
            ].compactMap { $0 }
            if !stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(stats, id: \.0) { r in
                        HStack {
                            Text(r.0).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                            Spacer()
                            Text(r.1).font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
                    }
                }
            }

            if !fb.macros.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(fb.macros.enumerated()), id: \.offset) { idx, m in
                        HStack {
                            Text(m.label).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                            Spacer()
                            let parts = [m.gkg.map { "\($0) g/kg" }, m.g.map { "\($0) g" }, m.kcal.map { "\($0) kcal" }]
                                .compactMap { $0 }.joined(separator: " · ")
                            Text(parts).font(Typo.mono(13)).foregroundStyle(Palette.textMid)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if idx < fb.macros.count - 1 { Divider().opacity(0.3) }
                    }
                }
                .voltPanel(radius: 12)
            }

            let extras: [(String, String)] = [
                fb.fibra.map { ("Fibra", "\($0) g/die") },
                fb.idrico.map { ("Idratazione", "\($0) ml/die") },
            ].compactMap { $0 }
            if !extras.isEmpty {
                HStack(spacing: 16) {
                    ForEach(extras, id: \.0) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0.uppercased()).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                            Text(r.1).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                        }
                    }
                }
            }
            noteRow("Attività", fb.palDesc)
            noteRow("Note DET", fb.detNote)
            noteRow("Micronutrienti", fb.micro)
            noteRow("Note operative", fb.noteOp)
        }
    }

    private func photos(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Visivo", title: "Foto", accent: Palette.violet)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(d.photos) { p in
                        AsyncImage(url: URL(string: p.url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Rectangle().fill(Palette.void2)
                            }
                        }
                        .frame(width: 150, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func notes(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Note atleta", title: "Diario", accent: Palette.amber)
            VStack(alignment: .leading, spacing: 10) {
                noteRow("Messaggio", d.notes)
                noteRow("Infortuni", d.injuries)
                noteRow("Limitazioni", d.limitations)
            }
        }
    }

    @ViewBuilder private func noteRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).voltEyebrow()
                Text(value).font(Typo.body(14)).foregroundStyle(Palette.textHi)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).voltPanel()
        }
    }

    private func feedbackComposer(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: sent || !d.coachFeedback.isEmpty ? "Inviato" : "La tua revisione",
                              title: "Feedback", accent: Palette.bronze)
            ZStack(alignment: .topLeading) {
                if feedback.isEmpty {
                    Text("Scrivi un feedback per l'atleta…")
                        .font(Typo.body(15)).foregroundStyle(Palette.textLow)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                }
                TextEditor(text: $feedback)
                    .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .voltPanel(radius: 14)

            NeonButton(title: sent ? "Feedback inviato" : "Invia feedback",
                       icon: sent ? "checkmark" : "paperplane.fill",
                       color: sent ? Palette.lime : Palette.bronze, loading: sending) {
                Task { await send() }
            }
            .disabled(feedback.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
    }

    private func hasNotes(_ d: CoachCheckDetailDTO) -> Bool {
        [d.notes, d.injuries, d.limitations].contains { ($0 ?? "").isEmpty == false }
    }

    private func label(_ key: String) -> String {
        key.replacingOccurrences(of: "circ::", with: "")
           .replacingOccurrences(of: "pl::", with: "")
           .replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let d = try? await APIClient.shared.coachCheck(id: responseId) {
            data = d
            feedback = d.coachFeedback
            privateNotes = d.coachPrivateNotes
            sent = !d.coachFeedback.isEmpty
        }
    }

    private func send() async {
        sending = true; defer { sending = false }
        do {
            try await APIClient.shared.coachSendFeedback(
                checkId: responseId, feedback: feedback, privateNotes: privateNotes)
            Haptics.success(); sent = true
            onFeedbackSent?(responseId)
            Analytics.shared.capture(.checkinReviewCompleted, ["check_id": responseId])
            flash.success("Feedback inviato")
        } catch {
            Haptics.error()
            flash.failure("Invio non riuscito")
        }
    }
}
