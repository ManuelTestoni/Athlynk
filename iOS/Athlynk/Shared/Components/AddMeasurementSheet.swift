//
//  AddMeasurementSheet.swift
//  Inserisce una singola misurazione (pesata / circonferenza / plica) fatta il
//  giorno X. La misura viene salvata come check leggero e compare nel grafico di
//  andamento, nello storico e ne "Il mio percorso". Condivisa fra atleta e coach:
//  l'invio è delegato a `onSubmit` così la stessa UI serve entrambe le app.
//

import SwiftUI

struct AddMeasurementSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case weight = "weight", circumference = "circumference", skinfold = "skinfold"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .weight: return "Peso"
            case .circumference: return "Circonf."
            case .skinfold: return "Plica"
            }
        }
        var unit: String {
            switch self {
            case .weight: return "kg"
            case .circumference: return "cm"
            case .skinfold: return "mm"
            }
        }
    }

    var accent: Color = Palette.violet
    /// (type, key, value, date) → throws on failure (message shown to the user).
    let onSubmit: (_ type: String, _ key: String?, _ value: Double, _ date: Date) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .weight
    @State private var siteKey: String = ""
    @State private var valueText: String = ""
    @State private var date = Date()
    @State private var catalog: MeasurementCatalog?
    @State private var saving = false
    @State private var error: String?

    private var sites: [MeasurementOption] {
        switch kind {
        case .weight: return []
        case .circumference: return catalog?.circumferences ?? []
        case .skinfold: return catalog?.skinfolds ?? []
        }
    }

    private var selectedSiteLabel: String {
        sites.first { $0.key == siteKey }?.label ?? "Seleziona…"
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Andamento", title: "Nuova misura",
                             subtitle: "Registra una rilevazione del giorno scelto", accent: accent)

                field("Tipo") {
                    Picker("", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, _ in resetSite() }
                }

                if kind != .weight {
                    field("Punto di misura") {
                        if sites.isEmpty {
                            // Catalogo non ancora caricato: un Menu vuoto non si apre
                            // ("clicco e non esce nulla"). Mostra un retry esplicito.
                            Button { Task { await loadCatalog() } } label: {
                                HStack {
                                    Text("Caricamento punti… tocca per riprovare")
                                        .font(Typo.body(14)).foregroundStyle(Palette.textLow)
                                    Spacer()
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        } else {
                        Menu {
                            // Native dropdown: a tap-to-open list with a checkmark on
                            // the current site. A plain Picker(.menu) rendered as an
                            // empty box here, so drive the menu ourselves.
                            ForEach(sites) { s in
                                Button {
                                    siteKey = s.key
                                } label: {
                                    if s.key == siteKey {
                                        Label(s.label, systemImage: "checkmark")
                                    } else {
                                        Text(s.label)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedSiteLabel)
                                    .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        }
                    }
                }

                field("Valore (\(kind.unit))") {
                    TextField("", text: $valueText,
                              prompt: Text("0.0").foregroundStyle(Palette.textLow))
                        .font(Typo.mono(18, .bold)).tint(accent)
                        .keyboardType(.decimalPad)
                }

                field("Data") {
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                        .labelsHidden().tint(accent)
                }

                if let error {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber)
                }

                NeonButton(title: saving ? "Salvataggio…" : "Salva misura",
                           icon: "ruler.fill", color: accent) {
                    Task { await save() }
                }
                .disabled(saving)
                .padding(.top, 6)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .task { if catalog == nil { await loadCatalog() } }
        }
    }

    private func loadCatalog() async {
        catalog = try? await APIClient.shared.measurementCatalog()
        resetSite()
    }

    private func resetSite() {
        siteKey = sites.first?.key ?? ""
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .voltPanel(radius: 14)
        }
    }

    private func save() async {
        error = nil
        let normalized = valueText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            error = "Inserisci un valore valido."
            return
        }
        if kind != .weight && siteKey.isEmpty {
            error = "Seleziona il punto di misura."
            return
        }
        saving = true; defer { saving = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        do {
            try await onSubmit(kind.rawValue, kind == .weight ? nil : siteKey, value, date)
            Haptics.success()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Impossibile salvare. Riprova."
        }
    }
}
