//
//  CoachCheckBuilder.swift
//  Composer a blocchi per creare/modificare un modello check, foglio di
//  assegnazione e form di compilazione/modifica valori. Compatibile col formato
//  questions_config/steps_config della web app.
//

import SwiftUI

// MARK: - Modello blocco

/// Mutable step used only by the builder (CheckStep from the API is immutable).
struct EditStep: Identifiable, Hashable {
    let id: String
    var label: String
}

struct CheckBlock: Identifiable, Hashable {
    let id = UUID()
    var qid: String
    var type: String          // antropometria | media | si_no | radio | checkbox | aperta | allegato
    var label: String
    var required: Bool
    var stepId: String
    // antropometria
    var weight: Bool = true
    var circKeys: [String] = []
    var skinKeys: [String] = []
    // media (scala)
    var minVal: Int = 1
    var maxVal: Int = 5
    var minLabel: String = ""
    var maxLabel: String = ""
    // radio / checkbox
    var options: [String] = []
    // aperta
    var placeholder: String = ""

    static func make(_ type: String, stepId: String) -> CheckBlock {
        CheckBlock(
            qid: type == "antropometria" ? "antropometria" : "q_\(UUID().uuidString.prefix(8))",
            type: type, label: Self.defaultLabel(type), required: false, stepId: stepId,
            options: (type == "radio" || type == "checkbox") ? ["Opzione 1", "Opzione 2"] : [])
    }

    init(qid: String, type: String, label: String, required: Bool, stepId: String,
         weight: Bool = true, circKeys: [String] = [], skinKeys: [String] = [],
         minVal: Int = 1, maxVal: Int = 5, minLabel: String = "", maxLabel: String = "",
         options: [String] = [], placeholder: String = "") {
        self.qid = qid; self.type = type; self.label = label; self.required = required
        self.stepId = stepId; self.weight = weight; self.circKeys = circKeys; self.skinKeys = skinKeys
        self.minVal = minVal; self.maxVal = maxVal; self.minLabel = minLabel; self.maxLabel = maxLabel
        self.options = options; self.placeholder = placeholder
    }

    init(from q: CheckQuestion, defaultStep: String) {
        qid = q.id; type = q.type; label = q.label; required = q.required
        stepId = q.stepId ?? defaultStep
        weight = q.weight
        circKeys = q.circumferences.map { $0.key }
        skinKeys = q.skinfolds.map { $0.key }
        minVal = Int(q.min ?? 1); maxVal = Int(q.max ?? 5)
        minLabel = q.minLabel ?? ""; maxLabel = q.maxLabel ?? ""
        options = q.options
        placeholder = q.placeholder ?? ""
    }

    static func defaultLabel(_ type: String) -> String {
        switch type {
        case "antropometria": return "Misure corporee"
        case "media": return "Come ti senti?"
        case "si_no": return "Domanda sì/no"
        case "radio": return "Scelta singola"
        case "checkbox": return "Scelta multipla"
        case "aperta": return "Domanda aperta"
        case "allegato": return "Carica una foto"
        default: return "Domanda"
        }
    }

    func config() -> [String: Any] {
        var d: [String: Any] = ["id": qid, "type": type, "label": label,
                                "required": required, "step_id": stepId]
        switch type {
        case "antropometria":
            d["weight"] = weight; d["circumferences"] = circKeys; d["skinfolds"] = skinKeys
        case "media":
            d["min"] = minVal; d["max"] = maxVal; d["minLabel"] = minLabel; d["maxLabel"] = maxLabel
        case "radio", "checkbox":
            d["options"] = options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case "aperta":
            d["placeholder"] = placeholder
        default: break
        }
        return d
    }
}

// MARK: - Builder

struct CoachCheckBuilderView: View {
    /// nil → creazione; altrimenti modifica del modello indicato.
    let templateId: Int?
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var steps: [EditStep] = [EditStep(id: "s_main", label: "Check")]
    @State private var blocks: [CheckBlock] = []
    @State private var catalog: CheckCatalog?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    private var defaultStep: String { steps.first?.id ?? "s_main" }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: templateId == nil ? "Nuovo modello" : "Modifica modello",
                             title: "Builder", subtitle: "Componi il check a blocchi", accent: Palette.violet)

                fieldBox("Titolo") {
                    TextField("", text: $title, prompt: Text("Es. Check settimanale").foregroundStyle(Palette.textLow))
                        .font(Typo.body(16, .semibold)).tint(Palette.violet)
                }

                stepsEditor

                CoachSectionTitle(eyebrow: "Domande", title: "Blocchi", accent: Palette.cyan)
                if blocks.isEmpty {
                    Text("Aggiungi un blocco per iniziare.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textLow)
                }
                ForEach($blocks) { $block in
                    blockCard($block)
                }

                addMenu

                if let error {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber)
                }

                NeonButton(title: saving ? "Salvataggio…" : "Salva modello", icon: "checkmark.seal.fill",
                           color: Palette.violet) { Task { await save() } }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 4)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .task { await loadInitial() }
        }
    }

    // MARK: Steps

    private var stepsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STEP").font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.2)) { addStep() } } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Palette.violet)
                }
            }
            if steps.count > 1 {
                Text("Tocca il nome per rinominare · frecce per riordinare")
                    .font(Typo.mono(8)).foregroundStyle(Palette.textLow)
            }
            ForEach($steps) { $s in
                HStack(spacing: 8) {
                    editableField("Nome step…", text: $s.label)
                    if steps.count > 1 {
                        Button { moveStep(s.id, by: -1) } label: { Image(systemName: "arrow.up") }
                            .foregroundStyle(Palette.textLow)
                        Button { moveStep(s.id, by: 1) } label: { Image(systemName: "arrow.down") }
                            .foregroundStyle(Palette.textLow)
                        Button { removeStep(s.id) } label: {
                            Image(systemName: "trash").foregroundStyle(Palette.amber)
                        }
                    }
                }
            }
        }
    }

    // MARK: Block card

    @ViewBuilder private func blockCard(_ block: Binding<CheckBlock>) -> some View {
        let b = block.wrappedValue
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(blockLabel(b.type)).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.violet)
                Spacer()
                Button { move(b.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .foregroundStyle(Palette.textLow)
                Button { move(b.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .foregroundStyle(Palette.textLow)
                Button { removeBlock(b.id) } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Palette.amber)
            }
            Text("TESTO DOMANDA (modificabile)").font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            editableField("Scrivi la domanda…", text: block.label)
            Toggle("Obbligatoria", isOn: block.required).font(Typo.body(13)).tint(Palette.violet)

            if steps.count > 1 {
                Picker("Step", selection: block.stepId) {
                    ForEach(steps) { Text($0.label).tag($0.id) }
                }.pickerStyle(.menu).tint(Palette.violet)
            }

            switch b.type {
            case "antropometria": antroEditor(block)
            case "media": scaleEditor(block)
            case "radio", "checkbox": optionsEditor(block)
            case "aperta":
                editableField("Testo guida (placeholder)…", text: block.placeholder)
            default: EmptyView()
            }
        }
        .padding(14).voltPanel()
    }

    @ViewBuilder private func antroEditor(_ block: Binding<CheckBlock>) -> some View {
        Toggle("Peso corporeo", isOn: block.weight).font(Typo.body(13)).tint(Palette.lime)
        if catalog == nil {
            // Senza catalogo le circonferenze/pliche restano vuote: dà un appiglio
            // per ricaricarlo invece di mostrare due gruppi vuoti.
            Button { Task { catalog = try? await APIClient.shared.coachCheckCatalog() } } label: {
                Label("Catalogo misure non caricato · tocca per riprovare", systemImage: "arrow.clockwise")
                    .font(Typo.body(12)).foregroundStyle(Palette.cyan)
            }
        } else {
            DisclosureGroup("Circonferenze (\(block.wrappedValue.circKeys.count))") {
                ForEach(flatCirc(), id: \.key) { item in
                    toggleRow(item.label, on: block.wrappedValue.circKeys.contains(item.key)) { on in
                        toggleKey(block.circKeys, item.key, on)
                    }
                }
            }.font(Typo.body(13)).tint(Palette.cyan)
            DisclosureGroup("Pliche (\(block.wrappedValue.skinKeys.count))") {
                ForEach(catalog?.skinfolds ?? []) { item in
                    toggleRow(item.label, on: block.wrappedValue.skinKeys.contains(item.key)) { on in
                        toggleKey(block.skinKeys, item.key, on)
                    }
                }
            }.font(Typo.body(13)).tint(Palette.cyan)
        }
    }

    @ViewBuilder private func scaleEditor(_ block: Binding<CheckBlock>) -> some View {
        HStack(spacing: 12) {
            Stepper("Min \(block.wrappedValue.minVal)", value: block.minVal, in: 0...9).font(Typo.body(12))
            Stepper("Max \(block.wrappedValue.maxVal)", value: block.maxVal, in: 1...10).font(Typo.body(12))
        }
        editableField("Etichetta min (es. Male)", text: block.minLabel)
        editableField("Etichetta max (es. Benissimo)", text: block.maxLabel)
    }

    @ViewBuilder private func optionsEditor(_ block: Binding<CheckBlock>) -> some View {
        ForEach(block.options.indices, id: \.self) { i in
            HStack(spacing: 8) {
                editableField("Testo opzione…", text: block.options[i])
                Button {
                    DispatchQueue.main.async { block.wrappedValue.options.remove(at: i) }
                } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Palette.textLow)
                }
            }
        }
        Button { block.wrappedValue.options.append("") } label: {
            Label("Aggiungi opzione", systemImage: "plus").font(Typo.body(12)).foregroundStyle(Palette.violet)
        }
    }

    private func toggleRow(_ label: String, on: Bool, _ action: @escaping (Bool) -> Void) -> some View {
        Button { action(!on) } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Palette.cyan : Palette.textLow)
                Text(label).font(Typo.body(13)).foregroundStyle(Palette.textHi)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var addMenu: some View {
        Menu {
             for_block("Antropometria", "antropometria")
            for_block("Scala benessere", "media")
            for_block("Domanda aperta", "aperta")
            for_block("Scelta singola", "radio")
            for_block("Scelta multipla", "checkbox")
            for_block("Sì / No", "si_no")
            for_block("Allegato foto", "allegato")
        } label: {
            Label("Aggiungi blocco", systemImage: "plus.app.fill")
                .font(Typo.body(15, .semibold)).foregroundStyle(Palette.violet)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).stroke(Palette.violet.opacity(0.5), lineWidth: 1))
        }
    }

    private func for_block(_ title: String, _ type: String) -> some View {
        Button(title) { withAnimation(.easeOut(duration: 0.2)) { blocks.append(.make(type, stepId: defaultStep)) } }
    }

    /// Boxed text input with a pencil cue — makes clear the field is editable,
    /// vs. a bare TextField that reads as static text.
    private func editableField(_ placeholder: String, text: Binding<String>,
                               accent: Color = Palette.violet) -> some View {
        HStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.textLow))
                .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(accent)
            Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.35), lineWidth: 1))
    }

    // MARK: Helpers

    private func flatCirc() -> [(key: String, label: String)] {
        var out: [(String, String)] = []
        for c in catalog?.circumferences ?? [] {
            if c.isLimb {
                out.append((c.key + "_r", c.label + " (DX)"))
                out.append((c.key + "_l", c.label + " (SX)"))
            } else {
                out.append((c.key, c.label))
            }
        }
        return out
    }

    private func toggleKey(_ binding: Binding<[String]>, _ key: String, _ on: Bool) {
        var set = binding.wrappedValue
        if on { if !set.contains(key) { set.append(key) } }
        else { set.removeAll { $0 == key } }
        binding.wrappedValue = set
    }

    // ForEach($blocks) holds a binding into each element; removing the element
    // synchronously inside its own row crashes (index out of range). Defer one
    // runloop tick so the current render pass finishes first.
    private func removeBlock(_ id: UUID) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { blocks.removeAll { $0.id == id } }
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < blocks.count else { return }
        withAnimation(.easeOut(duration: 0.2)) { blocks.swapAt(i, j) }
    }

    private func moveStep(_ id: String, by delta: Int) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < steps.count else { return }
        withAnimation(.easeOut(duration: 0.2)) { steps.swapAt(i, j) }
    }

    private func addStep() {
        steps.append(EditStep(id: "s_\(UUID().uuidString.prefix(6))", label: "Step \(steps.count + 1)"))
    }
    private func removeStep(_ id: String) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                steps.removeAll { $0.id == id }
                for i in blocks.indices where blocks[i].stepId == id { blocks[i].stepId = defaultStep }
            }
        }
    }

    private func loadInitial() async {
        loading = true; defer { loading = false }
        catalog = try? await APIClient.shared.coachCheckCatalog()
        if let templateId, let d = try? await APIClient.shared.coachCheckTemplate(id: templateId) {
            title = d.title
            if !d.steps.isEmpty { steps = d.steps.map { EditStep(id: $0.id, label: $0.label) } }
            blocks = d.questions.map { CheckBlock(from: $0, defaultStep: defaultStep) }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        error = nil
        let stepDicts = steps.map { ["id": $0.id, "label": $0.label, "icon": "ph-list"] as [String: Any] }
        let qDicts = blocks.map { $0.config() }
        do {
            if let templateId {
                try await APIClient.shared.coachUpdateCheckTemplate(
                    id: templateId, title: title, steps: stepDicts, questions: qDicts)
            } else {
                try await APIClient.shared.coachCreateCheckTemplate(
                    title: title, steps: stepDicts, questions: qDicts)
            }
            Haptics.success(); onSaved(); dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Salvataggio non riuscito."
        }
    }

    private func fieldBox<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            content().padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading).voltPanel(radius: 14)
        }
    }
}

// MARK: - Assegnazione

struct CoachAssignCheckView: View {
    let template: CoachCheckTemplateDetail
    var onAssigned: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var clients: [CoachClientRow] = []
    @State private var selected: Set<Int> = []
    @State private var recurrence = "once"
    @State private var weeklyDay = 0
    @State private var monthlyDay = 1
    @State private var durationHours = 72
    @State private var saving = false
    @State private var error: String?

    private let weekdays = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Assegna", title: template.title,
                             subtitle: "Scegli atleti e frequenza", accent: Palette.cyan)

                CoachSectionTitle(eyebrow: "Atleti", title: "Destinatari", accent: Palette.cyan)
                ForEach(clients) { c in
                    Button { toggle(c.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(c.id) ? Palette.cyan : Palette.textLow)
                            Text(c.displayName).font(Typo.body(15)).foregroundStyle(Palette.textHi)
                            Spacer()
                        }
                        .padding(14).voltPanel(radius: 12)
                    }
                    .buttonStyle(.plain)
                }

                CoachSectionTitle(eyebrow: "Frequenza", title: "Ricorrenza", accent: Palette.violet)
                Picker("", selection: $recurrence) {
                    Text("Una volta").tag("once")
                    Text("Settimanale").tag("weekly")
                    Text("Mensile").tag("monthly")
                }.pickerStyle(.segmented)

                if recurrence == "weekly" {
                    Picker("Giorno", selection: $weeklyDay) {
                        ForEach(0..<7, id: \.self) { Text(weekdays[$0]).tag($0) }
                    }.pickerStyle(.segmented)
                } else if recurrence == "monthly" {
                    Stepper("Giorno del mese: \(monthlyDay)", value: $monthlyDay, in: 1...28)
                        .font(Typo.body(14)).foregroundStyle(Palette.textHi)
                }

                if let error { Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber) }

                NeonButton(title: saving ? "Invio…" : "Assegna check", icon: "paperplane.fill",
                           color: Palette.cyan) { Task { await assign() } }
                    .disabled(saving || selected.isEmpty)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .task { clients = (try? await APIClient.shared.coachClients(query: "", status: "ACTIVE").clients) ?? [] }
        }
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func assign() async {
        saving = true; defer { saving = false }
        error = nil
        do {
            try await APIClient.shared.coachAssignCheck(
                templateId: template.id, clientIds: Array(selected), recurrence: recurrence,
                weeklyDay: recurrence == "weekly" ? weeklyDay : nil,
                monthlyDay: recurrence == "monthly" ? monthlyDay : nil,
                durationHours: durationHours, notes: "")
            Haptics.success(); onAssigned(); dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Assegnazione non riuscita."
        }
    }
}
