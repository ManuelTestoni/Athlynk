//
//  AnamnesisView.swift
//  Stitch "Questionario Anamnesi": read-only view of the intake form the coach
//  compiled for the athlete. Backed by GET /api/v1/anamnesis (ClientAnamnesis).
//  (The athlete can't author it — only the coach creates the anamnesis.)
//

import SwiftUI

struct AnamnesisView: View {
    @State private var anamnesis: AnamnesisDTO?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.bronze, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        LoadingPanel(text: "Carico l'anamnesi…")
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.lime)
                    } else if let a = anamnesis {
                        header(a)
                        vitals(a)
                        textSection("STORIA CLINICA", a.medicalHistory)
                        textSection("FARMACI", a.medications)
                        textSection("INFORTUNI", a.injuries)
                        textSection("ALLERGIE", a.allergies)
                        textSection("INTOLLERANZE", a.intolerances)
                        textSection("STILE DI VITA", a.lifestyleNotes)
                        textSection("ABITUDINI ALIMENTARI", a.foodHabits)
                        textSection("STORIA DEL PESO", a.weightHistory)
                        textSection("OBIETTIVO", a.pathGoal)
                        if hasWellness(a) { wellness(a) }
                    } else {
                        EmptyPanel(icon: "doc.text.magnifyingglass",
                                   text: "Nessuna anamnesi disponibile.\nIl tuo coach non l'ha ancora compilata.")
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Anamnesi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func header(_ a: AnamnesisDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIMA VISITA").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.bronze)
            Text("Anamnesi").font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            HStack(spacing: 10) {
                if let d = dateLabel(a.date) {
                    Text(d).font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                }
                if let coach = a.coach {
                    Text("· \(coach.fullName)").font(Typo.mono(11)).foregroundStyle(Palette.textMid)
                }
            }
            Rectangle().fill(Palette.bronze).frame(height: 1).opacity(0.5)
        }
    }

    private func vitals(_ a: AnamnesisDTO) -> some View {
        HStack(spacing: 12) {
            if let age = a.age { vital("\(age)", "ETÀ", Palette.cyan) }
            if let w = a.weightKg { vital(String(format: "%.0f", w), "PESO KG", Palette.magenta) }
            if let h = a.heightCm { vital(String(format: "%.0f", h), "ALTEZZA CM", Palette.lime) }
        }
    }

    private func vital(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(Typo.poster(26)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).voltPanel(color.opacity(0.35))
    }

    @ViewBuilder
    private func textSection(_ title: String, _ body: String?) -> some View {
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

    private func hasWellness(_ a: AnamnesisDTO) -> Bool {
        [a.sleepQuality, a.stressLevel].contains { ($0 ?? "").isEmpty == false }
    }

    private func wellness(_ a: AnamnesisDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BENESSERE").voltEyebrow()
            if let s = a.sleepQuality, !s.isEmpty { kv("Sonno", s) }
            if let s = a.stressLevel, !s.isEmpty { kv("Stress", s) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(Palette.cyan.opacity(0.3))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k.uppercased()).font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            Spacer()
            Text(v.capitalized).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
        }
    }

    private func dateLabel(_ iso: String?) -> String? {
        guard let iso, let d = ISO8601.parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: d)
    }

    private func load() async {
        loading = true; error = nil
        do { anamnesis = try await APIClient.shared.anamnesis() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
