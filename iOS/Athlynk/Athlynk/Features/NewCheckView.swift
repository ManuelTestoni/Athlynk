//
//  NewCheckView.swift
//  Multi-step check compiler. The questionnaire (steps + questions) is sent by
//  the backend with each pending check; the athlete must fill every step before
//  submitting. Backed by POST /api/v1/checks/<id>/submit.
//  Numeric answers are range-checked; `allegato` questions accept photos which
//  are downscaled/compressed before a multipart upload. Validation errors render
//  inline above the offending field and scroll it to centre.
//

import SwiftUI
import PhotosUI

struct NewCheckView: View {
    let check: CheckDTO
    var onDone: () -> Void = {}

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var stepIdx = 0
    /// Scalar answers (metrica / aperta / radio / si_no / media), keyed by question id.
    @State private var text: [String: String] = [:]
    /// Multi-select answers (checkbox).
    @State private var multi: [String: [String]] = [:]
    /// Picked-and-compressed images for `allegato` questions.
    @State private var attachments: [String: [Data]] = [:]
    @State private var pickerItems: [String: [PhotosPickerItem]] = [:]
    @State private var loadingPhotos = false
    @State private var saving = false
    /// Once true, the form is replaced by the success confirmation screen.
    @State private var submitted = false
    /// Per-question validation messages, shown above each field.
    @State private var fieldErrors: [String: String] = [:]
    /// Submit/network failure, shown once at the top.
    @State private var submitError: String?
    @FocusState private var focused: String?
    @State private var scrollTarget: String?
    @State private var scrollNonce = 0

    /// Plausible ranges (cm / kg / mm) for known measurements — mirrors the server.
    private static let bounds: [String: ClosedRange<Double>] = [
        "peso_corporeo": 20...400,
        "circ_spalle": 40...200, "circ_petto": 40...200, "circ_vita": 30...200,
        "circ_fianchi": 40...200, "circ_coscia": 20...120, "circ_braccio": 10...80,
        "pl_petto": 1...100, "pl_addome": 1...100, "pl_coscia": 1...100, "pl_tricipite": 1...100,
    ]

    private var steps: [CheckStep] {
        check.steps.isEmpty ? [CheckStep(id: "__solo", label: "Check")] : check.steps
    }
    private func questions(in step: CheckStep) -> [CheckQuestion] {
        check.questions.filter { ($0.stepId ?? steps.first?.id) == step.id }
    }
    private var isLast: Bool { stepIdx >= steps.count - 1 }

    var body: some View {
        if submitted {
            CheckSuccessView(title: check.title) { dismiss() }
        } else {
            form
        }
    }

    private var form: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header.id("__top")
                    progress
                    if let submitError {
                        Text(submitError).font(Typo.body(13)).foregroundStyle(Palette.magenta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let step = steps[stepIdx]
                    let qs = questions(in: step)
                    if qs.isEmpty {
                        Text("Nessuna domanda in questa sezione.")
                            .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                    } else {
                        ForEach(qs) { q in
                            if q.type == "antropometria" {
                                antropometriaCards(q).id(q.id)
                            } else {
                                questionCard(q).id(q.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 28)
            }
            // Centre the field we want the athlete to look at: tapped (keyboard)
            // or flagged by validation.
            .onChange(of: focused) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: scrollNonce) { _, _ in
                guard let t = scrollTarget else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { proxy.scrollTo(t, anchor: .center) }
            }
            // Step change → jump back above the first question.
            .onChange(of: stepIdx) { _, _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { proxy.scrollTo("__top", anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { nav }
        .background(VoltBackground(palette: [Palette.violet, Palette.magenta, Palette.cyan, Palette.violet]))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(check.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Drop the floating tab bar so it can't cover the form / nav buttons.
        .onAppear { app.tabBarHidden = true; seedDefaults() }
        .onDisappear { app.tabBarHidden = false }
    }

    // MARK: Header / progress

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHECK").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.violet)
            Text(check.title).font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            if let coach = check.coach {
                Text("per \(coach.fullName)").font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
            Rectangle().fill(Palette.violet).frame(height: 1).opacity(0.5)
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, _ in
                Capsule()
                    .fill(i <= stepIdx ? Palette.violet : Palette.line)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Text("\(stepIdx + 1) / \(steps.count)")
                .font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                .offset(y: -16)
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stepIdx)
    }

    // MARK: Question rendering

    @ViewBuilder
    private func questionCard(_ q: CheckQuestion) -> some View {
        let invalid = fieldErrors[q.id] != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(q.label.uppercased()).voltEyebrow()
                if q.required { Text("*").font(Typo.mono(10, .black)).foregroundStyle(Palette.magenta) }
            }
            if let msg = fieldErrors[q.id] {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(msg).font(Typo.body(12, .semibold))
                }
                .foregroundStyle(Palette.magenta)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
            input(for: q)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .voltPanel(invalid ? Palette.magenta.opacity(0.6) : Palette.violet.opacity(0.35))
        .animation(.easeOut(duration: 0.2), value: invalid)
    }

    // MARK: Antropometria — peso / circonferenze / pliche as distinct cells

    @ViewBuilder
    private func antropometriaCards(_ q: CheckQuestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if q.weight {
                antroPhaseCard(icon: "scalemass.fill", title: "Peso corporeo") {
                    antroField(label: "Peso", key: "peso_corporeo", unit: "kg")
                }
            }
            if !q.circumferences.isEmpty {
                antroPhaseCard(icon: "ruler.fill", title: "Circonferenze") {
                    antroGrid(q.circumferences, prefix: "circ::", unit: "cm")
                }
            }
            if !q.skinfolds.isEmpty {
                antroPhaseCard(icon: "circle.dashed", title: "Pliche cutanee") {
                    antroGrid(q.skinfolds, prefix: "pl::", unit: "mm")
                }
            }
        }
    }

    private func antroPhaseCard<Content: View>(icon: String, title: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.bronze)
                Text(title).voltEyebrow()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .voltPanel(Palette.violet.opacity(0.35))
    }

    private func antroGrid(_ items: [AntroItem], prefix: String, unit: String) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 12) {
            ForEach(items) { item in
                antroField(label: item.label, key: prefix + item.key, unit: unit)
            }
        }
    }

    private func antroField(label: String, key: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                .lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 6) {
                TextField("", text: bind(key), prompt: Text("0.0").foregroundStyle(Palette.textLow))
                    .font(Typo.mono(15, .semibold)).foregroundStyle(Palette.textHi).tint(Palette.violet)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: key)
                Text(unit).font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.void2))
        }
    }

    @ViewBuilder
    private func input(for q: CheckQuestion) -> some View {
        switch q.type {
        case "metrica":
            HStack(spacing: 6) {
                TextField("", text: bind(q.id), prompt: Text("0.0").foregroundStyle(Palette.textLow))
                    .font(Typo.mono(16, .semibold)).foregroundStyle(Palette.textHi).tint(Palette.violet)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: q.id)
                if let unit = q.unit { Text(unit).font(Typo.mono(11, .bold)).foregroundStyle(Palette.textLow) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))

        case "media":
            mediaSlider(q)

        case "si_no":
            HStack(spacing: 10) {
                choiceChip("Sì", selected: text[q.id] == "si") { setChoice(q.id, "si") }
                choiceChip("No", selected: text[q.id] == "no") { setChoice(q.id, "no") }
            }

        case "radio":
            Menu {
                ForEach(q.options, id: \.self) { opt in
                    Button(opt) { setChoice(q.id, opt) }
                }
            } label: {
                let chosen = text[q.id] ?? ""
                HStack(spacing: 8) {
                    Text(chosen.isEmpty ? "Seleziona…" : chosen)
                        .font(Typo.body(15))
                        .foregroundStyle(chosen.isEmpty ? Palette.textLow : Palette.textHi)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textLow)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
            }

        case "checkbox":
            VStack(spacing: 8) {
                ForEach(q.options, id: \.self) { opt in
                    choiceRow(opt, selected: (multi[q.id] ?? []).contains(opt)) { toggle(q.id, opt) }
                }
            }

        case "allegato":
            allegato(q)

        default: // aperta
            TextField("", text: bind(q.id),
                      prompt: Text(q.placeholder ?? "Scrivi qui…").foregroundStyle(Palette.textLow),
                      axis: .vertical)
                .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(Palette.violet)
                .lineLimit(3...6)
                .focused($focused, equals: q.id)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
        }
    }

    private func mediaSlider(_ q: CheckQuestion) -> some View {
        let lo = q.min ?? 1, hi = max(q.max ?? 10, (q.min ?? 1) + 1)
        let current = Double(text[q.id] ?? "") ?? ((lo + hi) / 2).rounded()
        return VStack(spacing: 8) {
            HStack {
                Text(q.minLabel ?? "\(Int(lo))").font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
                Spacer()
                Text("\(Int(current)) / \(Int(hi))")
                    .font(Typo.mono(13, .bold)).foregroundStyle(Palette.violet)
                Spacer()
                Text(q.maxLabel ?? "\(Int(hi))").font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
            }
            Slider(value: Binding(
                get: { Double(text[q.id] ?? "") ?? current },
                set: { text[q.id] = String(Int($0.rounded())) }
            ), in: lo...hi, step: 1).tint(Palette.violet)
        }
    }

    @ViewBuilder
    private func allegato(_ q: CheckQuestion) -> some View {
        let count = attachments[q.id]?.count ?? 0
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: itemsBinding(q.id), maxSelectionCount: 6, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.violet)
                    Text(count == 0 ? "Carica foto" : "\(count) foto selezionate")
                        .font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                    Spacer()
                    if loadingPhotos { ProgressView().tint(Palette.violet) }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(count > 0 ? Palette.violet.opacity(0.5) : Palette.line, lineWidth: 1))
            }
            if count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array((attachments[q.id] ?? []).enumerated()), id: \.offset) { _, data in
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: pickerItems[q.id] ?? []) { _, items in loadPhotos(q.id, items) }
    }

    private func choiceRow(_ label: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); tap() } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected ? Palette.violet : Palette.textLow)
                Text(label).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Palette.violet.opacity(0.12) : Palette.void2))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Palette.violet.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func choiceChip(_ label: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); tap() } label: {
            Text(label).font(Typo.body(15, .semibold))
                .foregroundStyle(selected ? Palette.void0 : Palette.textHi)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Capsule().fill(selected ? Palette.violet : Palette.void2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Nav

    private var nav: some View {
        HStack(spacing: 12) {
            if stepIdx > 0 {
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { stepIdx -= 1 } } label: {
                    Image(systemName: "arrow.left").font(.system(size: 16, weight: .black))
                        .foregroundStyle(Palette.textHi)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Palette.void2))
                }
                .buttonStyle(.plain)
            }
            NeonButton(title: isLast ? (saving ? "Invio…" : "Invia al coach") : "Avanti",
                       icon: isLast ? "paperplane.fill" : "arrow.right",
                       color: Palette.violet, loading: saving || loadingPhotos) {
                advance()
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Logic

    private func bind(_ id: String) -> Binding<String> {
        Binding(get: { text[id] ?? "" }, set: { text[id] = $0; fieldErrors[id] = nil })
    }

    private func itemsBinding(_ id: String) -> Binding<[PhotosPickerItem]> {
        Binding(get: { pickerItems[id] ?? [] }, set: { pickerItems[id] = $0 })
    }

    private func setChoice(_ id: String, _ value: String) {
        text[id] = value; fieldErrors[id] = nil
    }

    private func toggle(_ id: String, _ opt: String) {
        var cur = multi[id] ?? []
        if let i = cur.firstIndex(of: opt) { cur.remove(at: i) } else { cur.append(opt) }
        multi[id] = cur
        fieldErrors[id] = nil
    }

    private func loadPhotos(_ qid: String, _ items: [PhotosPickerItem]) {
        loadingPhotos = true
        Task {
            var out: [Data] = []
            for it in items {
                if let raw = try? await it.loadTransferable(type: Data.self) {
                    out.append(ImageCompressor.jpeg(raw))
                }
            }
            attachments[qid] = out
            if !out.isEmpty { fieldErrors[qid] = nil }
            loadingPhotos = false
        }
    }

    /// Media questions start at their midpoint, matching the web builder.
    private func seedDefaults() {
        for q in check.questions where q.type == "media" && text[q.id] == nil {
            let lo = q.min ?? 1, hi = max(q.max ?? 10, (q.min ?? 1) + 1)
            text[q.id] = String(Int(((lo + hi) / 2).rounded()))
        }
    }

    /// Validate one question; returns a user-facing message or nil if it passes.
    private func problem(_ q: CheckQuestion) -> String? {
        switch q.type {
        case "antropometria":
            return nil   // composite — individual fields are optional
        case "checkbox":
            return q.required && (multi[q.id] ?? []).isEmpty ? "Seleziona almeno un'opzione." : nil
        case "allegato":
            return q.required && (attachments[q.id] ?? []).isEmpty ? "Carica almeno una foto." : nil
        case "media":
            return nil
        case "metrica":
            let raw = (text[q.id] ?? "").trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { return q.required ? "Campo obbligatorio." : nil }
            guard let v = Double(raw.replacingOccurrences(of: ",", with: ".")) else {
                return "Inserisci solo un numero (es. 82,5)."
            }
            if v <= 0 { return "Dev'essere un numero maggiore di 0." }
            if let r = Self.bounds[q.id], !r.contains(v) {
                let unit = q.unit ?? ""
                return "Valore non plausibile: usa un numero tra \(Int(r.lowerBound)) e \(Int(r.upperBound)) \(unit)."
            }
            return nil
        default: // aperta / radio / si_no
            return q.required && (text[q.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                ? "Campo obbligatorio." : nil
        }
    }

    private func advance() {
        focused = nil
        let qs = questions(in: steps[stepIdx])
        var firstBad: String?
        for q in qs {
            let p = problem(q)
            fieldErrors[q.id] = p
            if p != nil && firstBad == nil { firstBad = q.id }
        }
        if let firstBad {
            Haptics.error()
            scrollTarget = firstBad
            scrollNonce += 1   // re-fire even if the same field failed twice
            return
        }
        submitError = nil
        if isLast {
            Task { await submit() }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { stepIdx += 1 }
        }
    }

    private func submit() async {
        saving = true; submitError = nil
        var answers: [String: Any] = [:]
        for q in check.questions {
            if q.type == "checkbox" {
                let v = multi[q.id] ?? []
                if !v.isEmpty { answers[q.id] = v }
            } else if q.type == "antropometria" {
                // Sub-fields live in `text` under peso_corporeo / circ::* / pl::*.
                var keys = q.weight ? ["peso_corporeo"] : []
                keys += q.circumferences.map { "circ::" + $0.key }
                keys += q.skinfolds.map { "pl::" + $0.key }
                for k in keys {
                    let v = (text[k] ?? "").trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { answers[k] = v }
                }
            } else if q.type != "allegato" {
                let v = (text[q.id] ?? "").trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { answers[q.id] = v }
            }
        }
        let files = attachments.filter { !$0.value.isEmpty }
        do {
            try await APIClient.shared.submitCheck(instanceId: check.id, answers: answers, attachments: files)
            onDone()   // refresh the timeline underneath while we show the confirmation
            withAnimation(.easeOut(duration: 0.25)) { submitted = true }
        } catch {
            Haptics.error()
            self.submitError = error.localizedDescription
        }
        saving = false
    }
}
