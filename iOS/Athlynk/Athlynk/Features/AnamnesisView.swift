//
//  AnamnesisView.swift
//  Read-only summary of the athlete's «Prima Valutazione» check response.
//  Backed by GET /api/v1/prima-valutazione (QuestionnaireResponse preset_key=prima_valutazione).
//

import SwiftUI

struct AnamnesisView: View {
    @State private var dto: PrimaValutazioneDTO?
    @State private var loading = true
    @State private var error: String?

    private var isStale: Bool {
        guard let iso = dto?.submittedAt,
              let d = ISO8601.parse(iso) else { return false }
        return Date().timeIntervalSince(d) > 90 * 86_400
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.bronze, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.lime)
                    } else if let d = dto, d.hasData {
                        header(d)
                        if let antrop = d.data?.antropometria { vitals(antrop) }
                        if let storia = d.data?.storia { storiaSection(storia) }
                        if let all = d.data?.allenamento { allenamSection(all) }
                        if let fab = d.data?.fabbisogni { fabbisogniSection(fab) }
                        if let ob = d.data?.obiettivi { obiettiviSection(ob) }
                    } else {
                        EmptyPanel(icon: "doc.text.magnifyingglass",
                                   text: "Prima valutazione non ancora completata.\nChiedi al tuo coach di assegnare il check.")
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Prima Valutazione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - Header

    private func header(_ d: PrimaValutazioneDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIMA VISITA").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.bronze)
            Text("Valutazione\nIniziale").font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            HStack(spacing: 10) {
                if let iso = d.submittedAt, let date = dateLabel(iso) {
                    Text(date).font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                }
                if isStale {
                    Label("Aggiornamento consigliato", systemImage: "clock.badge.exclamationmark")
                        .font(Typo.mono(10, .semibold)).foregroundStyle(Palette.amber)
                }
            }
            Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
        }
    }

    // MARK: - Anthropometry vitals row

    private func vitals(_ a: PrimaValutazioneDTO.Antropometria) -> some View {
        HStack(spacing: 12) {
            if let h = a.altezzaCm   { vital(String(format: "%.0f", h), "CM", Palette.lime)    }
            if let w = a.pesoKg      { vital(String(format: "%.1f", w), "KG", Palette.magenta)  }
        }
    }

    private func vital(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Typo.poster(26)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).voltPanel(color.opacity(0.35))
    }

    // MARK: - Storia clinica

    private func storiaSection(_ s: PrimaValutazioneDTO.Storia) -> some View {
        Group {
            textBlock("STORIA CLINICA", s.patologie)
            textBlock("ALLERGIE", s.allergie)
            textBlock("FARMACI", s.farmaci)
            textBlock("INTERVENTI", s.interventi)
            textBlock("FAMILIARITÀ", s.familiarita)
            if let profs = s.professionistiSeguiti, !profs.isEmpty {
                tagBlock("ALTRI PROFESSIONISTI", profs)
            }
        }
    }

    // MARK: - Allenamento

    @ViewBuilder
    private func allenamSection(_ a: PrimaValutazioneDTO.Allenamento) -> some View {
        let hasStats = a.anniEsperienza != nil || a.seduteSettimana != nil || a.durataMedMin != nil
        if hasStats || !(a.discipline ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ALLENAMENTO").voltEyebrow()
                if let disc = a.discipline, !disc.isEmpty {
                    tagBlock(nil, disc)
                }
                HStack(spacing: 12) {
                    if let v = a.anniEsperienza { kv("Esperienza", "\(v) anni") }
                    if let v = a.seduteSettimana { kv("Sedute/sett.", "\(v)") }
                    if let v = a.durataMedMin { kv("Durata media", "\(v) min") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).voltPanel(Palette.cyan.opacity(0.3))
        }
    }

    // MARK: - Fabbisogni

    @ViewBuilder
    private func fabbisogniSection(_ f: PrimaValutazioneDTO.Fabbisogni) -> some View {
        if f.detKcal != nil || f.proteineG != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("FABBISOGNI CALCOLATI").voltEyebrow()
                HStack(spacing: 12) {
                    if let v = f.detKcal      { macroBox("\(v)", "KCAL",  Palette.bronze) }
                    if let v = f.proteineG    { macroBox("\(v)g", "PRO",   Palette.cyan) }
                    if let v = f.carboidratiG { macroBox("\(v)g", "CARB",  Palette.lime) }
                    if let v = f.lipidiG      { macroBox("\(v)g", "FAT",   Palette.magenta) }
                }
                if f.fibraG != nil || f.idricoMl != nil {
                    HStack(spacing: 12) {
                        if let v = f.fibraG   { macroBox("\(v)g",  "FIBRA", Palette.violet) }
                        if let v = f.idricoMl { macroBox("\(v)ml", "H₂O",  Palette.cyan.opacity(0.7)) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).voltPanel(Palette.bronze.opacity(0.3))
        }
    }

    // MARK: - Obiettivi

    @ViewBuilder
    private func obiettiviSection(_ o: PrimaValutazioneDTO.Obiettivi) -> some View {
        if o.obiettivoPrincipale != nil || o.motivazione != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("OBIETTIVI").voltEyebrow()
                if let v = o.obiettivoPrincipale { kv("Obiettivo", v) }
                if let v = o.motivazione { kv("Motivazione", v) }
                if let v = o.scadenza { kv("Scadenza", v) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).voltPanel(Palette.lime.opacity(0.3))
        }
    }

    // MARK: - Primitives

    @ViewBuilder
    private func textBlock(_ title: String, _ body: String?) -> some View {
        if let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).voltEyebrow()
                Text(body).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).voltPanel(Palette.bronze.opacity(0.3))
        }
    }

    @ViewBuilder
    private func tagBlock(_ title: String?, _ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).voltEyebrow() }
            FlowLayout(tags.map { $0 }, accent: Palette.cyan)
        }
    }

    private func macroBox(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(Typo.mono(14, .bold)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .semibold)).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).voltPanel(color.opacity(0.2))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k.uppercased()).font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            Spacer()
            Text(v).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
        }
    }

    private func dateLabel(_ iso: String) -> String? {
        guard let d = ISO8601.parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: d)
    }

    private func load() async {
        loading = true; error = nil
        do { dto = try await APIClient.shared.primaValutazione() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

// MARK: - Simple tag flow layout (wrapping HStack)

private struct FlowLayout: View {
    let tags: [String]
    let accent: Color
    init(_ tags: [String], accent: Color = .blue) {
        self.tags = tags; self.accent = accent
    }
    var body: some View {
        // ponytail: simple wrapping via LazyVGrid columns — no custom layout needed
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 200), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(Typo.mono(10, .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(accent.opacity(0.15), in: Capsule())
            }
        }
    }
}
