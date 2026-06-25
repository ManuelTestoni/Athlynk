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
