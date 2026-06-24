//
//  ChironTutorialView.swift
//  First-login onboarding. Chiron — the Greek archer-centaur who tutored heroes —
//  guides the athlete through filling in the profile shown in the "You" section:
//  gender, birth date, height, weight, sport, goal and activity level. Saved via
//  PATCH /api/v1/profile. Shown only on the client's first login
//  (AppState.showChiron / server chiron_intro_seen). Pure Athlynk: parchment,
//  Didot, bronze seal — pushed hard on motion.
//

import SwiftUI

struct ChironTutorialView: View {
    let userName: String
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Collected profile
    @State private var gender: String?
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var hasBirth = false
    @State private var weightKg: Double = 70
    @State private var sport = ""

    // Flow
    @State private var step = 0
    @State private var speak = 0
    @State private var burst = 0
    @State private var entered = false
    @State private var saving = false

    private let genders = ["Uomo", "Donna", "Altro"]

    private var stepCount: Int { 6 }
    private var isLast: Bool { step == stepCount - 1 }
    private var name: String { userName.isEmpty ? "atleta" : userName }

    private var prompt: String {
        switch step {
        case 0: return "Χαῖρε, \(name). Sono Chiron: ho forgiato eroi. Prima di partire, lascia che ti conosca."
        case 1: return "Dimmi chi sei. Come ti identifichi?"
        case 2: return "Quando sei nato? Il tempo è parte della forza."
        case 3: return "E il tuo peso di oggi? È solo il punto di partenza."
        case 4: return "Qual è la disciplina che vuoi dominare?"
        default: return "Tutto pronto, \(name). Ora il percorso è inciso nel marmo. Andiamo."
        }
    }

    /// Whether the current step lets the athlete advance.
    private var canAdvance: Bool {
        switch step {
        case 1: return gender != nil
        default: return true
        }
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.amber, Palette.magenta, Palette.bronze])

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)

                ZStack {
                    ParticleBurst(trigger: burst, colors: [Palette.bronze, Palette.amber, Palette.cyan])
                    ChironMascot(speak: speak, reduceMotion: reduceMotion, size: 150)
                }
                .frame(height: 168)

                speech
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                ScrollView(showsIndicators: false) {
                    stepContent
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .frame(maxHeight: .infinity)

                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 18)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { entered = true }
        }
        .onChange(of: step) { _ in speak += 1 }
    }

    // MARK: Progress + skip

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Palette.bronze : Palette.line)
                        .frame(height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
                }
            }
            Button(action: finish) {
                Text("Salta").font(Typo.mono(12, .bold)).tracking(1).foregroundStyle(Palette.textMid)
            }
            .accessibilityLabel("Salta il tutorial")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: Chiron's line

    private var speech: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "laurel.leading").font(.system(size: 13, weight: .black))
                .foregroundStyle(Palette.bronze)
            Text(prompt)
                .font(Typo.display(20)).foregroundStyle(Palette.textHi)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .voltPanel(Palette.bronze.opacity(0.4))
        .id("speech-\(step)")
        .transition(.opacity)
    }

    // MARK: Step inputs

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            introBadges
        case 1:
            ChipGrid(options: genders, selection: $gender, accent: Palette.bronze)
        case 2:
            VStack(spacing: 12) {
                DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.locale, Locale(identifier: "it_IT"))
                    .onChange(of: birthDate) { _ in hasBirth = true }
                if !hasBirth {
                    Text("Scorri per impostare la data").font(Typo.body(12)).foregroundStyle(Palette.textLow)
                }
            }
            .padding(8).voltPanel(Palette.bronze.opacity(0.3))
        case 3:
            MeasureSlider(value: $weightKg, range: 35...200, step: 0.5, unit: "kg",
                          format: "%.1f", accent: Palette.magenta)
        case 4:
            VoltField(icon: "figure.run", placeholder: "Es. Calcio, Powerlifting, Running…",
                      text: $sport, accent: Palette.amber)
        default:
            recap
        }
    }

    private var introBadges: some View {
        VStack(spacing: 12) {
            introRow("dumbbell.fill", "Schede", "I tuoi allenamenti, sempre con te", Palette.magenta)
            introRow("leaf.fill", "Nutrizione", "Piani e diario alimentare", Palette.lime)
            introRow("chart.xyaxis.line", "Progressi", "Peso, misure e foto", Palette.cyan)
        }
    }

    private func introRow(_ icon: String, _ title: String, _ sub: String, _ color: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 17, weight: .black)).foregroundStyle(color)
                .frame(width: 42, height: 42).background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Text(sub).font(Typo.body(12)).foregroundStyle(Palette.textMid)
            }
            Spacer()
        }
        .padding(12).voltPanel(color.opacity(0.3))
    }

    private var recap: some View {
        VStack(spacing: 9) {
            recapRow("Sesso", gender ?? "—")
            recapRow("Peso", String(format: "%.1f kg", weightKg))
            if !sport.isEmpty { recapRow("Sport", sport) }
        }
        .padding(16).voltPanel(Palette.bronze.opacity(0.4))
    }

    private func recapRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k.uppercased()).font(Typo.mono(10, .bold)).tracking(1.5).foregroundStyle(Palette.textLow)
            Spacer()
            Text(v).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 && !isLast {
                Button { back() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 16, weight: .black))
                        .foregroundStyle(Palette.textHi)
                        .frame(width: 54, height: 54)
                        .background(Circle().stroke(Palette.line, lineWidth: 1))
                }
                .accessibilityLabel("Indietro")
            }
            NeonButton(title: isLast ? "Inizia il percorso" : "Avanti",
                       icon: isLast ? "arrow.right.circle.fill" : "arrow.right",
                       color: Palette.bronze, loading: saving) {
                advance()
            }
            .opacity(canAdvance ? 1 : 0.5)
            .disabled(!canAdvance || saving)
        }
    }

    // MARK: Behaviour

    private func advance() {
        Haptics.tap()
        if isLast { Task { await save() }; return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
    }

    private func back() {
        Haptics.tap()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = max(0, step - 1) }
    }

    private func save() async {
        saving = true
        var fields: [String: Any] = ["weight_kg": weightKg]
        if let gender { fields["gender"] = gender }
        if hasBirth {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            fields["birth_date"] = f.string(from: birthDate)
        }
        if !sport.isEmpty { fields["sport"] = sport }
        try? await APIClient.shared.updateProfile(fields)
        saving = false
        burst += 1
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { finish() }
    }

    private func finish() { onFinish() }
}

// MARK: - Reusable inputs

/// Wrapping selectable chips. Single selection bound to `selection`.
private struct ChipGrid: View {
    let options: [String]
    @Binding var selection: String?
    var accent: Color

    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(options, id: \.self) { opt in
                let on = selection == opt
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = opt }
                } label: {
                    Text(opt)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(on ? Palette.void0 : Palette.textHi)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? accent : Palette.void1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(on ? .clear : Palette.line, lineWidth: 1))
                        .scaleEffect(on ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Big animated number with a slider underneath.
private struct MeasureSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let format: String
    var accent: Color

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: format, value))
                    .font(Typo.poster(52)).foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
                Text(unit).font(Typo.mono(15, .bold)).foregroundStyle(Palette.textMid)
            }
            Slider(value: $value, in: range, step: step) { editing in
                if editing { Haptics.soft() }
            }
            .tint(accent)
        }
        .padding(20).voltPanel(accent.opacity(0.35))
    }
}
