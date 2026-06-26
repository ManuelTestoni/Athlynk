//
//  CoachResourcesView.swift
//  "Libreria / Gestione Risorse (Coach)" — the coach's reusable content:
//  workout & nutrition plans, check templates and supplement sheets.
//

import SwiftUI

struct CoachResourcesView: View {
    @State private var sections: [CoachResourceSection] = []
    @State private var loading = true
    @State private var expanded: Set<String> = []

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Studio", title: "Risorse",
                         subtitle: "I tuoi modelli riutilizzabili", accent: Palette.violet)
            if loading && sections.isEmpty {
                ForEach(0..<4, id: \.self) { _ in SkelLinkRow(accent: Palette.violet) }
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { i, s in
                    section(s, accent: Palette.accent(i))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func section(_ s: CoachResourceSection, accent: Color) -> some View {
        let isOpen = expanded.contains(s.key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                if isOpen { expanded.remove(s.key) } else { expanded.insert(s.key) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: s.icon).font(.system(size: 18, weight: .bold))
                        .foregroundStyle(accent).frame(width: 32)
                    Text(s.label).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                    Spacer()
                    Text("\(s.count)").font(Typo.mono(13, .bold)).foregroundStyle(accent)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textLow)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if isOpen {
                if s.items.isEmpty {
                    Text("Vuoto").font(Typo.body(13)).foregroundStyle(Palette.textLow)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(s.items) { item in
                            HStack {
                                Circle().fill(accent.opacity(0.5)).frame(width: 6, height: 6)
                                Text(item.title).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                                    .lineLimit(1)
                                Spacer()
                                if let g = item.goal ?? item.planMode ?? item.type {
                                    Text(g).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        sections = (try? await APIClient.shared.coachResources()) ?? []
    }
}

// MARK: - Integratori (coach builder)

private let kSupplementUnits = ["mg", "g", "cps"]
private let kSupplementTimings = ["Mattina", "Colazione", "Pranzo", "Pomeriggio", "Cena",
                                  "Sera", "Pre Workout", "Intra Workout", "Post Workout",
                                  "A digiuno", "Con i pasti", "Pre nanna"]

struct CoachSupplementsView: View {
    @State private var protocols: [CoachSupplementSummary] = []
    @State private var loading = true
    @State private var editing: CoachSupplementDetail?
    @State private var presentBuilder = false
    @State private var assignTarget: CoachSupplementSummary?
    @State private var deleteTarget: CoachSupplementSummary?
    @State private var error: String?

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Studio", title: "Integratori",
                         subtitle: "Protocolli di integrazione", accent: Palette.lime)

            Button { Haptics.tap(); editing = nil; presentBuilder = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18, weight: .bold))
                    Text("Nuovo protocollo").font(Typo.body(15, .semibold))
                }
                .foregroundStyle(Palette.lime)
                .frame(maxWidth: .infinity).padding(.vertical, 14).voltPanel(radius: 14)
            }
            .buttonStyle(.plain)

            if loading && protocols.isEmpty {
                ForEach(0..<3, id: \.self) { _ in SkelLinkRow(accent: Palette.lime) }
            } else if protocols.isEmpty {
                Text("Non hai ancora un protocollo, creane uno.")
                    .font(Typo.body(14)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
            } else {
                ForEach(protocols) { p in row(p) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $presentBuilder) {
            CoachSupplementBuilderView(existing: editing) { Task { await load() } }
        }
        .sheet(item: $assignTarget) { p in
            CoachSupplementAssignView(protocolId: p.id, title: p.title) { Task { await load() } }
        }
        .confirmationDialog("Eliminare il protocollo?", isPresented: .init(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { if let p = deleteTarget { Task { await remove(p) } } }
            Button("Annulla", role: .cancel) { deleteTarget = nil }
        }
        .alert("Errore", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func row(_ p: CoachSupplementSummary) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                Task { await openEdit(p) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                    Text("\(p.itemCount) integratori · \(p.assignedCount) assegnati")
                        .font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button { assignTarget = p } label: { Label("Assegna", systemImage: "person.crop.circle.badge.checkmark") }
                Button { Task { await openEdit(p) } } label: { Label("Modifica", systemImage: "pencil") }
                Button(role: .destructive) { deleteTarget = p } label: { Label("Elimina", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.textMid).frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { protocols = try await APIClient.shared.coachSupplements() }
        catch { self.error = error.localizedDescription }
    }

    private func openEdit(_ p: CoachSupplementSummary) async {
        do {
            editing = try await APIClient.shared.coachSupplementDetail(id: p.id)
            presentBuilder = true
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ p: CoachSupplementSummary) async {
        deleteTarget = nil
        do { try await APIClient.shared.coachDeleteSupplement(id: p.id); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct CoachSupplementBuilderView: View {
    let existing: CoachSupplementDetail?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var items: [CoachSupplementItem] = []
    @State private var saving = false
    @State private var error: String?
    @State private var showModels = false
    @State private var models: [CoachSupplementModel] = []

    var body: some View {
        NavigationStack {
            ScreenScroll {
                field("Titolo", $title, placeholder: "Es. Protocollo Massa")
                field("Note generali", $notes, placeholder: "Indicazioni, avvertenze…")

                ForEach($items) { $item in itemCard($item) }

                if items.isEmpty {
                    Text("Aggiungi un integratore con +.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textLow)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 16)
                }

                HStack(spacing: 12) {
                    Button { Haptics.tap(); items.append(CoachSupplementItem()) } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Palette.void0).frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.lime))
                    }
                    Button { Haptics.tap(); Task { await loadModels() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill").font(.system(size: 13, weight: .bold))
                            Text("Da modelli").font(Typo.body(14, .semibold))
                        }
                        .foregroundStyle(Palette.textHi).padding(.horizontal, 14).padding(.vertical, 10).voltPanel(radius: 12)
                    }
                    Spacer()
                }
            }
            .navigationTitle(existing == nil ? "Nuovo protocollo" : "Modifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "…" : "Salva") { Task { await save() } }.disabled(saving)
                }
            }
            .sheet(isPresented: $showModels) {
                modelsSheet
            }
            .alert("Errore", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear(perform: hydrate)
        }
    }

    private func itemCard(_ item: Binding<CoachSupplementItem>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("", text: item.name, prompt: Text("Nome integratore").foregroundStyle(Palette.textLow))
                    .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(Palette.lime)
                Menu {
                    Button("Salva come modello") { Task { await saveModel(item.wrappedValue) } }
                    Button("Elimina", role: .destructive) { items.removeAll { $0.rowId == item.wrappedValue.rowId } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.textMid)
                }
            }
            HStack(spacing: 8) {
                TextField("", text: item.quantity, prompt: Text("Quantità").foregroundStyle(Palette.textLow))
                    .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(Palette.lime)
                    .frame(maxWidth: .infinity)
                Menu {
                    ForEach(kSupplementUnits, id: \.self) { u in Button(u) { item.wrappedValue.unit = u } }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.wrappedValue.unit.isEmpty ? "g" : item.wrappedValue.unit).font(Typo.mono(13, .bold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Palette.textHi).padding(.horizontal, 12).padding(.vertical, 9).voltPanel(radius: 10)
                }
            }
            HStack(spacing: 8) {
                TextField("", text: item.timing, prompt: Text("Quando").foregroundStyle(Palette.textLow))
                    .font(Typo.body(14)).foregroundStyle(Palette.textHi).tint(Palette.lime)
                    .frame(maxWidth: .infinity)
                Menu {
                    ForEach(kSupplementTimings, id: \.self) { t in Button(t) { item.wrappedValue.timing = t } }
                } label: {
                    Image(systemName: "clock.fill").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.textMid).frame(width: 38, height: 38).voltPanel(radius: 10)
                }
            }
            TextField("", text: item.notes, prompt: Text("Note").foregroundStyle(Palette.textLow))
                .font(Typo.body(13)).foregroundStyle(Palette.textMid).tint(Palette.lime)
        }
        .padding(14).voltPanel(radius: 14)
    }

    private var modelsSheet: some View {
        NavigationStack {
            ScreenScroll {
                if models.isEmpty {
                    Text("Non hai ancora un integratore, creane uno.")
                        .font(Typo.body(14)).foregroundStyle(Palette.textLow)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
                } else {
                    ForEach(models) { m in
                        HStack {
                            Button {
                                items.append(CoachSupplementItem(name: m.name, quantity: m.quantity,
                                    unit: m.unit.isEmpty ? "g" : m.unit, timing: m.timing, notes: m.notes))
                                showModels = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                                    Text([("\(m.quantity) \(m.unit)").trimmingCharacters(in: .whitespaces), m.timing]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { Task { await deleteModel(m) } } label: {
                                Image(systemName: "trash").foregroundStyle(Palette.magenta)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).voltPanel()
                    }
                }
            }
            .navigationTitle("I tuoi modelli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { showModels = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ label: String, _ text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.textLow))
                .font(Typo.body(16)).foregroundStyle(Palette.textHi).tint(Palette.lime)
                .padding(.horizontal, 14).padding(.vertical, 13).voltPanel(radius: 12)
        }
    }

    private func hydrate() {
        guard let e = existing, items.isEmpty, title.isEmpty else { return }
        title = e.title; notes = e.notes; items = e.items
    }

    private func payloadItems() -> [[String: Any]] {
        items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            ["name": $0.name, "quantity": $0.quantity, "unit": $0.unit, "timing": $0.timing, "notes": $0.notes]
        }
    }

    private func save() async {
        let clean = payloadItems()
        if title.trimmingCharacters(in: .whitespaces).isEmpty { error = "Inserisci un titolo per il protocollo."; return }
        if clean.isEmpty { error = "Aggiungi almeno un integratore."; return }
        saving = true; defer { saving = false }
        do {
            _ = try await APIClient.shared.coachSaveSupplement(id: existing?.id, title: title, notes: notes, items: clean)
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func saveModel(_ item: CoachSupplementItem) async {
        if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Inserisci il nome dell'integratore prima di salvarlo come modello."; return
        }
        do {
            _ = try await APIClient.shared.coachSaveSupplementModel(
                ["name": item.name, "quantity": item.quantity, "unit": item.unit, "timing": item.timing, "notes": item.notes])
            Haptics.tap()
        } catch { self.error = error.localizedDescription }
    }

    private func loadModels() async {
        do { models = try await APIClient.shared.coachSupplementModels(); showModels = true }
        catch { self.error = error.localizedDescription }
    }

    private func deleteModel(_ m: CoachSupplementModel) async {
        do { try await APIClient.shared.coachDeleteSupplementModel(id: m.id); models.removeAll { $0.id == m.id } }
        catch { self.error = error.localizedDescription }
    }
}

struct CoachSupplementAssignView: View {
    let protocolId: Int
    let title: String
    let onAssigned: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clients: [CoachClientRow] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading {
                    ForEach(0..<4, id: \.self) { _ in SkelLinkRow(accent: Palette.lime) }
                } else {
                    ForEach(filtered) { c in
                        Button { Task { await assign(c) } } label: {
                            HStack {
                                Text(c.displayName).font(Typo.body(15)).foregroundStyle(Palette.textHi)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textLow)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13).voltPanel()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assegna a")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .task { await load() }
            .alert("Errore", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private var filtered: [CoachClientRow] {
        query.isEmpty ? clients : clients.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { clients = try await APIClient.shared.coachClients().clients }
        catch { self.error = error.localizedDescription }
    }

    private func assign(_ c: CoachClientRow) async {
        do { try await APIClient.shared.coachAssignSupplement(id: protocolId, clientId: c.id); onAssigned(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
