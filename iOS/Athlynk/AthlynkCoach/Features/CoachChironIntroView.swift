//
//  CoachChironIntroView.swift
//  First-login profile setup wizard for coaches. Chiron collects professional
//  info (type, specialization, experience, certifications, bio, photo) and
//  saves it via PATCH /api/v1/coach/profile + POST /api/v1/coach/profile/photo.
//  Shown once, gated by AppStorage("athlynk.coach.chiron.done").
//

import SwiftUI
import PhotosUI

struct CoachChironIntroView: View {
    var onFinish: () -> Void

    @State private var professionalType: String?
    @State private var specialization = ""
    @State private var yearsExperience: Double = 5
    @State private var selectedCerts: Set<String> = []
    @State private var bio = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?

    @State private var step = 0
    @State private var speak = 0
    @State private var burst = 0
    @State private var entered = false
    @State private var saving = false

    private let professionalTypes: [(code: String, label: String)] = [
        ("COACH", "Coach"),
        ("ALLENATORE", "Allenatore"),
        ("NUTRIZIONISTA", "Nutrizionista"),
    ]
    private let certOptions = ["ISSA", "CONI", "ACE", "NASM", "EREPS", "FIF", "FIPE", "Altra"]

    private var stepCount: Int { 8 }
    private var isLast: Bool { step == stepCount - 1 }

    private var prompt: String {
        switch step {
        case 0: return "Bentornato. Sono Chiron — aiuto i migliori coach a fare la loro miglior lavoro. Prima di tutto, parliamo di te."
        case 1: return "Qual è la tua figura professionale?"
        case 2: return "Qual è la tua specializzazione o disciplina principale?"
        case 3: return "Quanti anni di esperienza hai?"
        case 4: return "Hai certificazioni? Seleziona quelle che possiedi."
        case 5: return "Scrivi una breve bio per presentarti ai tuoi atleti."
        case 6: return "Aggiungi una foto profilo professionale. È la prima cosa che vedono i tuoi atleti."
        default: return "Perfetto. Il tuo profilo è pronto. Inizia a guidare i tuoi atleti."
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return professionalType != nil
        default: return true
        }
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.amber, Palette.cyan, Palette.bronze])

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)

                ZStack {
                    ParticleBurst(trigger: burst, colors: [Palette.bronze, Palette.amber, Palette.cyan])
                    ChironMascot(speak: speak, reduceMotion: false, size: 150)
                }
                .frame(height: 168)

                speechBubble
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
        .onChange(of: step) { speak += 1 }
        .onChange(of: photoItem) {
            Task {
                guard let item = photoItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let compressed = ImageCompressor.jpeg(data, maxDim: 1200, quality: 0.75)
                    photoData = compressed
                    if let ui = UIImage(data: compressed) {
                        photoPreview = Image(uiImage: ui)
                    }
                }
            }
        }
    }

    // MARK: - Top bar

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
        }
        .padding(.horizontal, 24).padding(.top, 16)
    }

    // MARK: - Speech bubble

    private var speechBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Palette.bronze)
            Text(prompt)
                .font(Typo.display(20))
                .foregroundStyle(Palette.textHi)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .voltPanel(Palette.bronze.opacity(0.4))
        .id("speech-\(step)")
        .transition(.opacity)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            introBadges
        case 1:
            CoachChipGrid(options: professionalTypes, selection: $professionalType, accent: Palette.bronze)
        case 2:
            VoltField(icon: "figure.run", placeholder: "Es. Powerlifting, Nuoto, Nutrizione sportiva…",
                      text: $specialization, accent: Palette.amber)
        case 3:
            experienceSlider
        case 4:
            certGrid
        case 5:
            bioEditor
        case 6:
            photoStep
        default:
            recap
        }
    }

    private var introBadges: some View {
        VStack(spacing: 12) {
            introRow("person.2.fill",    "Clienti",    "Gestisci il roster dei tuoi atleti",    Palette.cyan)
            introRow("doc.richtext.fill","Piani",      "Costruisci piani workout e nutrizione",  Palette.magenta)
            introRow("sparkles",         "Chiron AI",  "Il tuo assistente di coaching IA",       Palette.amber)
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
        .padding(12).voltPanel(Palette.bronze.opacity(0.3))
    }

    private var experienceSlider: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(yearsExperience))")
                    .font(Typo.poster(52)).foregroundStyle(Palette.bronze)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: yearsExperience)
                Text("anni").font(Typo.mono(15, .bold)).foregroundStyle(Palette.textMid)
            }
            Slider(value: $yearsExperience, in: 0...30, step: 1) { _ in Haptics.soft() }
                .tint(Palette.bronze)
        }
        .padding(20).voltPanel(Palette.bronze.opacity(0.35))
    }

    private var certGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(certOptions, id: \.self) { cert in
                let on = selectedCerts.contains(cert)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if on { selectedCerts.remove(cert) } else { selectedCerts.insert(cert) }
                    }
                } label: {
                    Text(cert)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(on ? Palette.void0 : Palette.textHi)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(on ? Palette.amber : Palette.void1))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(on ? .clear : Palette.line, lineWidth: 1))
                        .scaleEffect(on ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bioEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $bio)
                .font(Typo.body(15))
                .foregroundStyle(Palette.textHi)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(14)
                .voltPanel(Palette.bronze.opacity(0.3))
            Text("\(bio.count)/300")
                .font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: bio) { if bio.count > 300 { bio = String(bio.prefix(300)) } }
    }

    private var photoStep: some View {
        VStack(spacing: 16) {
            if let preview = photoPreview {
                preview
                    .resizable().scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Palette.bronze, lineWidth: 2))
                    .shadow(color: Palette.bronze.opacity(0.4), radius: 14)
                    .frame(maxWidth: .infinity)
            } else {
                Circle()
                    .fill(Palette.void1)
                    .frame(width: 120, height: 120)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Palette.textLow))
                    .frame(maxWidth: .infinity)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text(photoPreview == nil ? "Scegli foto" : "Cambia foto")
                }
                .font(Typo.body(15, .semibold))
                .foregroundStyle(Palette.bronze)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .voltPanel(Palette.bronze.opacity(0.3))
            }
        }
    }

    private var recap: some View {
        VStack(spacing: 9) {
            recapRow("Tipo",     professionalTypes.first(where: { $0.code == professionalType })?.label ?? "—")
            if !specialization.isEmpty { recapRow("Disciplina", specialization) }
            recapRow("Esperienza", "\(Int(yearsExperience)) anni")
            if !selectedCerts.isEmpty { recapRow("Certificazioni", selectedCerts.sorted().joined(separator: ", ")) }
            if !bio.isEmpty { recapRow("Bio", String(bio.prefix(60)) + (bio.count > 60 ? "…" : "")) }
        }
        .padding(16).voltPanel(Palette.bronze.opacity(0.4))
    }

    private func recapRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k.uppercased()).font(Typo.mono(10, .bold)).tracking(1.5).foregroundStyle(Palette.textLow)
            Spacer()
            Text(v).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 && !isLast {
                Button { back() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 16, weight: .black))
                        .foregroundStyle(Palette.textHi)
                        .frame(width: 54, height: 54)
                        .background(Circle().stroke(Palette.line, lineWidth: 1))
                }
            }
            NeonButton(
                title: isLast ? "Inizia a fare coaching" : "Avanti",
                icon: isLast ? "arrow.right.circle.fill" : "arrow.right",
                color: Palette.bronze, loading: saving
            ) { advance() }
            .opacity(canAdvance ? 1 : 0.5)
            .disabled(!canAdvance || saving)
        }
    }

    // MARK: - Behaviour

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
        var fields: [String: Any] = [
            "years_experience": Int(yearsExperience),
        ]
        if let t = professionalType { fields["professional_type"] = t }
        if !specialization.isEmpty { fields["specialization"] = specialization }
        if !selectedCerts.isEmpty { fields["certifications"] = selectedCerts.sorted().joined(separator: ", ") }
        if !bio.isEmpty { fields["bio"] = bio }

        _ = try? await APIClient.shared.coachUpdateProfile(fields)
        if let photoData {
           _ = try? await APIClient.shared.coachUploadProfilePhoto(photoData)
        }

        saving = false
        burst += 1
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { finish() }
    }

    private func finish() { onFinish() }
}

// MARK: - Single-select chip grid (mirrors athlete ChipGrid)

private struct CoachChipGrid: View {
    let options: [(code: String, label: String)]
    @Binding var selection: String?
    var accent: Color

    private let cols = [GridItem(.adaptive(minimum: 130), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(options, id: \.code) { opt in
                let on = selection == opt.code
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = opt.code }
                } label: {
                    Text(opt.label)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(on ? Palette.void0 : Palette.textHi)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(on ? accent : Palette.void1))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(on ? .clear : Palette.line, lineWidth: 1))
                        .scaleEffect(on ? 1.03 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
