//
//  CoachCheckForm.swift
//  Compilazione di un modello per un atleta + modifica dei valori di un check
//  già compilato. Rende le domande risolte (CheckQuestion) e raccoglie le
//  risposte nelle stesse chiavi della web app (peso_corporeo, circ::, pl::, id).
//

import SwiftUI

struct CoachCheckFormView: View {
    enum Mode: Hashable {
        case fill(templateId: Int)
        case edit(responseId: Int)
    }

    let mode: Mode
    let title: String
    let questions: [CheckQuestion]
    let steps: [CheckStep]
    var prefill: [String: AnyCodable] = [:]
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var multi: [String: [String]] = [:]
    @State private var clients: [CoachClientRow] = []
    @State private var clientId: Int?
    @State private var saving = false
    @State private var error: String?

    private var needsClient: Bool { if case .fill = mode { return true } else { return false } }

    private var orderedSteps: [CheckStep] {
        steps.isEmpty ? [CheckStep(id: "__solo", label: "Check")] : steps
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if needsClient { clientPicker }

                    ForEach(orderedSteps) { step in
                        let qs = questions.filter { ($0.stepId ?? orderedSteps.first?.id) == step.id }
                        if !qs.isEmpty {
                            if orderedSteps.count > 1 {
                                CoachSectionTitle(eyebrow: "Step", title: step.label, accent: Palette.cyan)
                            }
                            ForEach(Array(qs.enumerated()), id: \.offset) { _, q in
                                questionCard(q)
                            }
                        }
                    }

                    if let error { Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber) }

                    NeonButton(title: saving ? "Salvataggio…" : "Salva", icon: "checkmark.seal.fill",
                               color: Palette.lime) { Task { await save() } }
                        .disabled(saving || (needsClient && clientId == nil))
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .task { await setup() }
        }
    }

    private var clientPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATLETA").font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            Picker("", selection: $clientId) {
                Text("Seleziona…").tag(Optional<Int>.none)
                ForEach(clients) { Text($0.displayName).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu).tint(Palette.lime)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 14)
        }
    }

    // MARK: Question rendering

    @ViewBuilder private func questionCard(_ q: CheckQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(q.label + (q.required ? " *" : "")).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
            switch q.type {
            case "antropometria": antroFields(q)
            case "strumento_fabbisogni": fabbisogniTool()
            case "media": scaleField(q)
            case "si_no": siNoField(q)
            case "radio": radioField(q)
            case "checkbox": checkboxField(q)
            case "aperta":
                TextField("", text: bind(q.id), prompt: Text(q.placeholder ?? "Scrivi…").foregroundStyle(Palette.textLow),
                          axis: .vertical)
                    .font(Typo.body(14)).tint(Palette.lime).lineLimit(2...5)
            case "metrica":
                numField(q.id, unit: q.unit)
            case "allegato":
                Text("Allegati: gestiscili dal web.").font(Typo.body(12)).foregroundStyle(Palette.textLow)
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).voltPanel()
    }

    // MARK: - Strumento Calcolo Fabbisogni (mirrors WebApp check/builder.html)

    private let fbFormulas = ["Mifflin-St Jeor", "Harris-Benedict", "Cunningham"]
    private let fbPalPresets: [(Double, String)] = [
        (1.2, "Sedentario"), (1.375, "Leggero"), (1.55, "Moderato"), (1.725, "Attivo"), (1.9, "Molto attivo"),
    ]
    private struct FBMacro { let label: String, gkgKey: String, gKey: String, noteKey: String, factor: Double }
    private let fbMacros: [FBMacro] = [
        FBMacro(label: "Proteine",    gkgKey: "proteine_gkg",    gKey: "proteine_g_totale",    noteKey: "proteine_note",    factor: 4),
        FBMacro(label: "Carboidrati", gkgKey: "carboidrati_gkg", gKey: "carboidrati_g_totale", noteKey: "carboidrati_note", factor: 4),
        FBMacro(label: "Lipidi",      gkgKey: "lipidi_target",   gKey: "lipidi_g_totale",      noteKey: "lipidi_note",      factor: 9),
    ]

    @ViewBuilder private func fabbisogniTool() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            fbCard(n: 1, title: "Dati base", subtitle: "Antropometria e formula del metabolismo basale") {
                HStack(spacing: 10) { numField("altezza_cm", label: "Altezza", unit: "cm"); numField("peso_kg", label: "Peso", unit: "kg") }
                HStack(spacing: 10) { numField("eta_anni", label: "Età", unit: "anni"); fbSessoField }
                fbFormulaField
                numField("mb_stimata_kcal", label: "MB stimata (auto · modificabile)", unit: "kcal")
            }
            .onChange(of: values["altezza_cm"]) { _, _ in fbCalcBMR() }
            .onChange(of: values["peso_kg"]) { _, _ in fbCalcBMR(); fbRescaleMacros() }
            .onChange(of: values["eta_anni"]) { _, _ in fbCalcBMR() }

            fbCard(n: 2, title: "Fabbisogni energetici", subtitle: "Livello di attività, DET e modulazione calorica") {
                numField("pal_valore", label: "LAF / PAL", unit: "×")
                fbPalPresetRow
                TextField("Descrizione livello di attività", text: bind("pal_descrizione"), axis: .vertical)
                    .font(Typo.body(14)).tint(Palette.lime).lineLimit(2...4)
                numField("det_kcal", label: "DET base (MB × PAL)", unit: "kcal")
                numField("det_adjust_kcal", label: "Aggiusta ± (deficit/surplus)", unit: "kcal")
                HStack {
                    Text("DET finale").font(Typo.body(13)).foregroundStyle(Palette.textMid)
                    Spacer()
                    Text("\(fbDetFinal) kcal/die").font(Typo.mono(16, .bold)).foregroundStyle(Palette.lime)
                }
                .padding(.horizontal, 12).padding(.vertical, 10).voltPanel(radius: 10)
                TextField("Note DET", text: bind("det_note"), axis: .vertical)
                    .font(Typo.body(14)).tint(Palette.lime).lineLimit(2...4)
            }
            .onChange(of: values["mb_stimata_kcal"]) { _, _ in fbCalcDET() }
            .onChange(of: values["pal_valore"]) { _, _ in fbCalcDET() }
            .onChange(of: values["det_kcal"]) { _, _ in fbSyncDetFinal() }
            .onChange(of: values["det_adjust_kcal"]) { _, _ in fbSyncDetFinal() }

            fbCard(n: 3, title: "Macronutrienti", subtitle: "Target g/kg ⇄ grammi totali") {
                ForEach(fbMacros, id: \.label) { m in fbMacroRow(m) }
            }

            fbCard(n: 4, title: "Altri fabbisogni", subtitle: "Fibra, idratazione e micronutrienti") {
                HStack(spacing: 10) { numField("fibra_gdie", label: "Fibra", unit: "g/die") }
                TextField("Nota fibra", text: bind("fibra_note"), axis: .vertical).font(Typo.body(14)).tint(Palette.lime).lineLimit(1...3)
                HStack(spacing: 10) { numField("idrico_mldie", label: "Idratazione", unit: "ml/die") }
                TextField("Nota idratazione", text: bind("idrico_criterio"), axis: .vertical).font(Typo.body(14)).tint(Palette.lime).lineLimit(1...3)
                TextField("Micronutrienti da monitorare", text: bind("micronutrienti_critici"), axis: .vertical)
                    .font(Typo.body(14)).tint(Palette.lime).lineLimit(2...4)
            }

            fbCard(n: 5, title: "Note operative", subtitle: "Sintesi, vincoli e priorità") {
                TextField("Vincoli, priorità, strategie…", text: bind("note_operative"), axis: .vertical)
                    .font(Typo.body(14)).tint(Palette.lime).lineLimit(3...6)
            }
        }
        .task { fbCalcBMR(); fbCalcDET(); fbSyncDetFinal() }
    }

    @ViewBuilder private func fbCard<Content: View>(n: Int, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(n)").font(Typo.mono(11, .bold)).foregroundStyle(Palette.void0)
                    .frame(width: 20, height: 20).background(Circle().fill(Palette.bronze))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                    Text(subtitle).font(Typo.body(11)).foregroundStyle(Palette.textLow)
                }
            }
            content()
        }
        .padding(14).voltPanel()
    }

    private var fbSessoField: some View {
        HStack(spacing: 8) {
            ForEach(["Maschio", "Femmina"], id: \.self) { opt in
                let on = values["sesso"] == opt
                Button { values["sesso"] = opt; fbCalcBMR() } label: {
                    Text(opt).font(Typo.body(13, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Palette.lime : Palette.void2))
                        .foregroundStyle(on ? Palette.void0 : Palette.textMid)
                }.buttonStyle(.plain)
            }
        }
    }

    private var fbFormulaField: some View {
        Menu {
            ForEach(fbFormulas, id: \.self) { f in Button(f) { values["formula_mb"] = f; fbCalcBMR() } }
        } label: {
            let chosen = values["formula_mb"] ?? ""
            HStack {
                Text(chosen.isEmpty ? "Formula MB…" : chosen).font(Typo.body(14))
                    .foregroundStyle(chosen.isEmpty ? Palette.textLow : Palette.textHi)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, 12).padding(.vertical, 11).voltPanel(radius: 10)
        }
    }

    private var fbPalPresetRow: some View {
        HStack(spacing: 6) {
            ForEach(fbPalPresets, id: \.1) { v, l in
                let on = values["pal_valore"] == String(v)
                Button { values["pal_valore"] = String(v) } label: {
                    Text(l).font(Typo.body(11, .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.lime : Palette.void2))
                        .foregroundStyle(on ? Palette.void0 : Palette.textMid)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func fbMacroRow(_ m: FBMacro) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                numField(m.gkgKey, label: m.label, unit: "g/kg")
                numField(m.gKey, label: "Grammi totali", unit: "g")
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((Double(values[m.gKey] ?? "") ?? 0) * m.factor)) kcal")
                        .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textMid)
                }
            }
            TextField("Nota \(m.label.lowercased())", text: bind(m.noteKey), axis: .vertical)
                .font(Typo.body(13)).tint(Palette.lime).lineLimit(1...3)
        }
        .onChange(of: values[m.gkgKey]) { _, _ in fbMacroFromGkg(m) }
        .onChange(of: values[m.gKey]) { _, _ in fbMacroFromGrams(m) }
    }

    private func fbCalcBMR() {
        guard let peso = Double(values["peso_kg"] ?? ""), peso > 0,
              let formula = values["formula_mb"], !formula.isEmpty else { return }
        let h = Double(values["altezza_cm"] ?? "") ?? 0
        let a = Double(values["eta_anni"] ?? "") ?? 0
        let sesso = values["sesso"] ?? ""
        let male = sesso == "Maschio"
        var bmr = 0.0
        switch formula {
        case "Mifflin-St Jeor":
            guard h > 0, a > 0, !sesso.isEmpty else { return }
            bmr = male ? (10 * peso + 6.25 * h - 5 * a + 5) : (10 * peso + 6.25 * h - 5 * a - 161)
        case "Harris-Benedict":
            guard h > 0, a > 0, !sesso.isEmpty else { return }
            bmr = male ? (88.36 + 13.4 * peso + 4.8 * h - 5.7 * a) : (447.6 + 9.25 * peso + 3.1 * h - 4.3 * a)
        case "Cunningham":
            guard !sesso.isEmpty else { return }
            bmr = 500 + 22 * peso * (male ? 0.80 : 0.75)
        default: return
        }
        if bmr > 0 { values["mb_stimata_kcal"] = String(Int(bmr.rounded())) }
    }

    private func fbCalcDET() {
        guard let mb = Double(values["mb_stimata_kcal"] ?? ""), mb > 0,
              let pal = Double(values["pal_valore"] ?? ""), pal > 0 else { return }
        values["det_kcal"] = String(Int((mb * pal).rounded()))
    }

    private var fbDetFinal: Int {
        let base = Int(Double(values["det_kcal"] ?? "") ?? 0)
        guard base > 0 else { return 0 }
        return base + Int(Double(values["det_adjust_kcal"] ?? "") ?? 0)
    }

    private func fbSyncDetFinal() {
        values["det_finale_kcal"] = fbDetFinal > 0 ? String(fbDetFinal) : ""
    }

    /// Su cambio peso: i grammi totali si ricalcolano dal target g/kg (sorgente di verità).
    private func fbRescaleMacros() {
        guard let p = Double(values["peso_kg"] ?? ""), p > 0 else { return }
        for m in fbMacros {
            guard let gkg = Double(values[m.gkgKey] ?? ""), gkg > 0 else { continue }
            values[m.gKey] = String(Int((gkg * p).rounded()))
        }
    }

    private func fbMacroFromGkg(_ m: FBMacro) {
        let p = Double(values["peso_kg"] ?? "") ?? 0
        guard let gkg = Double(values[m.gkgKey] ?? ""), gkg > 0 else {
            if !(values[m.gkgKey] ?? "").isEmpty { values[m.gKey] = "0" }
            return
        }
        if p > 0 { values[m.gKey] = String(Int((gkg * p).rounded())) }
    }

    private func fbMacroFromGrams(_ m: FBMacro) {
        let p = Double(values["peso_kg"] ?? "") ?? 0
        guard let g = Double(values[m.gKey] ?? ""), g > 0 else {
            if !(values[m.gKey] ?? "").isEmpty { values[m.gkgKey] = "0" }
            return
        }
        if p > 0 { values[m.gkgKey] = String((g / p * 100).rounded() / 100) }
    }

    @ViewBuilder private func antroFields(_ q: CheckQuestion) -> some View {
        if q.weight { numField("peso_corporeo", label: "Peso", unit: "kg") }
        ForEach(q.circumferences) { c in numField("circ::" + c.key, label: c.label, unit: "cm") }
        ForEach(q.skinfolds) { s in numField("pl::" + s.key, label: s.label, unit: "mm") }
    }

    private func numField(_ key: String, label: String? = nil, unit: String?) -> some View {
        HStack {
            if let label { Text(label).font(Typo.body(13)).foregroundStyle(Palette.textMid) }
            Spacer()
            TextField("0", text: bind(key)).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).font(Typo.mono(15, .bold)).tint(Palette.lime)
                .frame(maxWidth: 90)
            if let unit { Text(unit).font(Typo.mono(11)).foregroundStyle(Palette.textLow) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).voltPanel(radius: 10)
    }

    @ViewBuilder private func scaleField(_ q: CheckQuestion) -> some View {
        let lo = Int(q.min ?? 1), hi = Int(q.max ?? 5)
        let current = Int(values[q.id] ?? "") ?? lo
        VStack(spacing: 6) {
            // Flexible cells so any range (1–5, 1–10, …) fits the screen width
            // instead of overflowing a fixed-diameter HStack. ponytail: even
            // split; a 1–20 scale would get cramped — wrap to a grid if that ever ships.
            HStack(spacing: 6) {
                ForEach(lo...hi, id: \.self) { n in
                    Button { values[q.id] = String(n) } label: {
                        Text("\(n)").font(Typo.mono(14, .bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 9)
                                .fill(current == n ? Palette.lime : Palette.void2))
                            .foregroundStyle(current == n ? Palette.void0 : Palette.textMid)
                    }.buttonStyle(.plain)
                }
            }
            if let mn = q.minLabel, let mx = q.maxLabel, !mn.isEmpty || !mx.isEmpty {
                HStack { Text(mn).font(Typo.mono(9)); Spacer(); Text(mx).font(Typo.mono(9)) }
                    .foregroundStyle(Palette.textLow)
            }
        }
    }

    private func siNoField(_ q: CheckQuestion) -> some View {
        HStack(spacing: 10) {
            ForEach(["Sì", "No"], id: \.self) { opt in
                let on = values[q.id] == opt
                Button { values[q.id] = opt } label: {
                    Text(opt).font(Typo.body(14, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Palette.lime : Palette.void2))
                        .foregroundStyle(on ? Palette.void0 : Palette.textMid)
                }.buttonStyle(.plain)
            }
        }
    }

    private func radioField(_ q: CheckQuestion) -> some View {
        Menu {
            ForEach(q.options, id: \.self) { opt in
                Button(opt) { values[q.id] = opt }
            }
        } label: {
            let chosen = values[q.id] ?? ""
            HStack {
                Text(chosen.isEmpty ? "Seleziona…" : chosen)
                    .font(Typo.body(14))
                    .foregroundStyle(chosen.isEmpty ? Palette.textLow : Palette.textHi)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, 12).padding(.vertical, 12).voltPanel(radius: 10)
        }
    }

    private func checkboxField(_ q: CheckQuestion) -> some View {
        VStack(spacing: 8) {
            ForEach(q.options, id: \.self) { opt in
                let on = (multi[q.id] ?? []).contains(opt)
                Button {
                    var sel = multi[q.id] ?? []
                    if on { sel.removeAll { $0 == opt } } else { sel.append(opt) }
                    multi[q.id] = sel
                } label: { choiceRow(opt, on: on, multi: true) }.buttonStyle(.plain)
            }
        }
    }

    private func choiceRow(_ opt: String, on: Bool, multi: Bool = false) -> some View {
        HStack {
            Image(systemName: on ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle") : (multi ? "square" : "circle"))
                .foregroundStyle(on ? Palette.lime : Palette.textLow)
            Text(opt).font(Typo.body(14)).foregroundStyle(Palette.textHi)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10).voltPanel(radius: 10)
    }

    private func bind(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    // MARK: Setup + submit

    private func setup() async {
        if needsClient {
            clients = (try? await APIClient.shared.coachClients(query: "", status: "ACTIVE", limit: 500).clients) ?? []
        }
        // Seed from prefill (edit mode).
        for q in questions where q.type == "checkbox" {
            multi[q.id] = prefill[q.id]?.asStringArray ?? []
        }
        for (k, v) in prefill {
            if multi[k] != nil { continue }
            values[k] = v.asString
        }
    }

    private func answersPayload() -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in values where !v.trimmingCharacters(in: .whitespaces).isEmpty { out[k] = v }
        for (k, v) in multi where !v.isEmpty { out[k] = v }
        return out
    }

    private func save() async {
        saving = true; defer { saving = false }
        error = nil
        do {
            switch mode {
            case .fill(let templateId):
                guard let clientId else { error = "Seleziona un atleta."; return }
                try await APIClient.shared.coachFillCheck(
                    templateId: templateId, clientId: clientId, answers: answersPayload(), date: nil)
            case .edit(let responseId):
                try await APIClient.shared.coachUpdateCheckValues(
                    responseId: responseId, answers: answersPayload())
            }
            Haptics.success(); onDone(); dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Salvataggio non riuscito."
        }
    }
}
