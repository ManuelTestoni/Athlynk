//
//  NewCheckView.swift
//  Stitch "Nuovo Check": the athlete fills a pending check-in — bodyweight,
//  measurements and a note to the coach. Backed by POST /api/v1/checks/<id>/submit
//  (creates a QuestionnaireResponse and marks the instance completed).
//

import SwiftUI

struct NewCheckView: View {
    let check: CheckDTO
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var weight = ""
    @State private var waist = ""
    @State private var hips = ""
    @State private var arm = ""
    @State private var thigh = ""
    @State private var shoulders = ""
    @State private var chest = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.magenta, Palette.cyan, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let error {
                        Text(error).font(Typo.body(13)).foregroundStyle(Palette.magenta)
                    }

                    section("scalemass.fill", "PESO ATTUALE") {
                        field("Peso", $weight, unit: "kg", keyboard: .decimalPad)
                    }

                    section("ruler.fill", "MISURE (CM)") {
                        twoCol(field("Vita", $waist, keyboard: .decimalPad),
                               field("Fianchi", $hips, keyboard: .decimalPad))
                        twoCol(field("Braccio", $arm, keyboard: .decimalPad),
                               field("Coscia", $thigh, keyboard: .decimalPad))
                        twoCol(field("Spalle", $shoulders, keyboard: .decimalPad),
                               field("Petto", $chest, keyboard: .decimalPad))
                    }

                    section("square.and.pencil", "NOTE PER IL COACH") {
                        TextField("", text: $notes, axis: .vertical)
                            .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(Palette.violet)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
                    }

                    NeonButton(title: saving ? "Invio…" : "Invia al coach", icon: "paperplane.fill",
                               color: Palette.violet, loading: saving) {
                        Task { await submit() }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Nuovo Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

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

    private func section<Content: View>(_ icon: String, _ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .black)).foregroundStyle(Palette.violet)
                Text(title).voltEyebrow()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(Palette.violet.opacity(0.35))
    }

    private func twoCol<A: View, B: View>(_ a: A, _ b: B) -> some View {
        HStack(spacing: 12) { a; b }
    }

    private func field(_ label: String, _ text: Binding<String>, unit: String? = nil,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            HStack(spacing: 6) {
                TextField("", text: text)
                    .font(Typo.mono(16, .semibold)).foregroundStyle(Palette.textHi).tint(Palette.violet)
                    .keyboardType(keyboard)
                if let unit { Text(unit).font(Typo.mono(11, .bold)).foregroundStyle(Palette.textLow) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() async {
        saving = true; error = nil
        var measures: [String: Double] = [:]
        func add(_ key: String, _ s: String) {
            if let v = Double(s.replacingOccurrences(of: ",", with: ".")), v > 0 { measures[key] = v }
        }
        add("waist", waist); add("hips", hips); add("arm", arm)
        add("thigh", thigh); add("shoulders", shoulders); add("chest", chest)
        let w = Double(weight.replacingOccurrences(of: ",", with: "."))
        do {
            try await APIClient.shared.submitCheck(instanceId: check.id, weightKg: w,
                                                   measurements: measures, notes: notes)
            Haptics.success()
            onDone()
            dismiss()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
        saving = false
    }
}
