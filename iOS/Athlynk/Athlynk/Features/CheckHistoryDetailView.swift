//
//  CheckHistoryDetailView.swift
//  Read-only detail of one past submitted check: every answered question,
//  section by section — including the coach-only «Calcolo Fabbisogni» tool,
//  which the athlete never fills but can review. Mirrors WebApp check/detail.html.
//  Backed by GET /api/v1/checks/<id>.
//

import SwiftUI

struct CheckHistoryDetailView: View {
    let responseId: Int

    @State private var data: CheckDetailDTO?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.magenta, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        ProgressSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if let d = data {
                        header(d)
                        ForEach(d.sections) { section(for: $0) }
                        if !d.photos.isEmpty { photos(d) }
                        if hasNotes(d) { notes(d) }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle(data?.title ?? "Check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func header(_ d: CheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CHECK COMPILATO").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.violet)
            Text(dateLong(parseDate(d.submittedAt))).font(Typo.body(14)).foregroundStyle(Palette.textMid)
        }
    }

    // MARK: Sections

    @ViewBuilder private func section(for s: CheckSection) -> some View {
        if !s.questions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(s.label.uppercased()).voltEyebrow()
                ForEach(s.questions) { q in questionRow(q) }
            }
        }
    }

    @ViewBuilder private func questionRow(_ q: CheckSectionQuestion) -> some View {
        switch q.type {
        case "strumento_fabbisogni":
            if let fb = q.fb { fabbisogniCard(fb) }
        case "allegato":
            if let files = q.files, !files.isEmpty { attachmentRow(q.label, files) }
        case "metrica_pair":
            if let sides = q.sides { pairRow(q.label, sides) }
        default:
            if let display = q.value?.display {
                simpleRow(q.label, display, unit: q.unit, previous: q.previous?.display, delta: q.delta)
            }
        }
    }

    private func simpleRow(_ label: String, _ value: String, unit: String?, previous: String?, delta: Double?) -> some View {
        HStack(alignment: .top) {
            Text(label).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(value).font(Typo.mono(14, .bold)).foregroundStyle(Palette.textHi)
                    if let unit { Text(unit).font(Typo.mono(10)).foregroundStyle(Palette.textLow) }
                }
                if let delta, delta != 0 {
                    Text("\(delta > 0 ? "+" : "")\(String(format: "%.1f", delta))")
                        .font(Typo.mono(10, .semibold)).foregroundStyle(delta > 0 ? Palette.lime : Palette.magenta)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
    }

    private func pairRow(_ label: String, _ sides: [CheckMeasureSide]) -> some View {
        HStack {
            Text(label).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            Spacer()
            HStack(spacing: 14) {
                ForEach(Array(sides.enumerated()), id: \.offset) { _, side in
                    VStack(alignment: .trailing, spacing: 1) {
                        if let tag = side.tag { Text(tag).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow) }
                        HStack(spacing: 3) {
                            Text(side.value?.display ?? "—").font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                            if let unit = side.unit { Text(unit).font(Typo.mono(9)).foregroundStyle(Palette.textLow) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
    }

    private func attachmentRow(_ label: String, _ files: [CheckAttachmentFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Typo.body(13)).foregroundStyle(Palette.textMid)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(files) { f in attachmentThumb(f) }
                }
            }
        }
        .padding(14).voltPanel(radius: 12)
    }

    private func attachmentThumb(_ f: CheckAttachmentFile) -> some View {
        let isImage = (f.mimeType ?? "").hasPrefix("image") || f.url.lowercased().hasSuffix(".jpg")
            || f.url.lowercased().hasSuffix(".jpeg") || f.url.lowercased().hasSuffix(".png")
        return Link(destination: URL(string: f.url) ?? URL(string: "about:blank")!) {
            if isImage {
                AsyncImage(url: URL(string: f.url)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Rectangle().fill(Palette.void2)
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc.fill").font(.system(size: 22)).foregroundStyle(Palette.violet)
                    Text(f.fileName).font(Typo.mono(8)).foregroundStyle(Palette.textLow).lineLimit(1)
                }
                .frame(width: 88, height: 88)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
            }
        }
    }

    // MARK: Calcolo Fabbisogni (read-only — mirrors WebApp check/detail.html)

    private func fabbisogniCard(_ fb: CheckFabbisogni) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "function").foregroundStyle(Palette.bronze)
                Text("Calcolo Fabbisogni").font(Typo.body(13, .semibold)).foregroundStyle(Palette.bronze)
            }

            if let det = fb.detFinale {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DET FINALE").font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                        (Text("\(det)").font(Typo.poster(24)) + Text(" kcal/die").font(Typo.body(12)))
                            .foregroundStyle(Palette.textHi)
                    }
                    Spacer()
                    if fb.detAdjust != 0, let base = fb.detBase {
                        StatusBadge(text: "base \(base) · \(fb.detAdjust > 0 ? "+" : "")\(fb.detAdjust) kcal", color: Palette.bronze)
                    }
                }
                .padding(14).voltPanel(radius: 12)
            }

            let stats: [(String, String)] = [
                fb.peso?.display.map { ("Peso", "\($0) kg") },
                fb.altezza?.display.map { ("Altezza", "\($0) cm") },
                fb.eta?.display.map { ("Età", $0) },
                fb.sesso?.display.map { ("Sesso", $0) },
                fb.mb.map { ("MB", "\($0) kcal") },
                fb.pal?.display.map { ("PAL", "\($0)×") },
                fb.formula?.display.map { ("Formula", $0) },
            ].compactMap { $0 }
            if !stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(stats, id: \.0) { r in
                        HStack {
                            Text(r.0).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                            Spacer()
                            Text(r.1).font(Typo.mono(12, .bold)).foregroundStyle(Palette.textHi)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10).voltPanel(radius: 10)
                    }
                }
            }

            if !fb.macros.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(fb.macros.enumerated()), id: \.offset) { idx, m in
                        HStack {
                            Text(m.label).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                            Spacer()
                            let parts = [m.gkg?.display.map { "\($0) g/kg" }, m.g.map { "\($0) g" }, m.kcal.map { "\($0) kcal" }]
                                .compactMap { $0 }.joined(separator: " · ")
                            Text(parts).font(Typo.mono(12)).foregroundStyle(Palette.textMid)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        if idx < fb.macros.count - 1 { Divider().opacity(0.3) }
                    }
                }
                .voltPanel(radius: 12)
            }

            let extras: [(String, String)] = [
                fb.fibra?.display.map { ("Fibra", "\($0) g/die") },
                fb.idrico?.display.map { ("Idratazione", "\($0) ml/die") },
            ].compactMap { $0 }
            if !extras.isEmpty {
                HStack(spacing: 16) {
                    ForEach(extras, id: \.0) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0.uppercased()).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                            Text(r.1).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                        }
                    }
                }
            }
            fbNote("Attività", fb.palDesc?.display)
            fbNote("Note DET", fb.detNote?.display)
            fbNote("Micronutrienti", fb.micro?.display)
            fbNote("Note operative", fb.noteOp?.display)
        }
        .padding(14).voltPanel(Palette.bronze.opacity(0.3), radius: 14)
    }

    @ViewBuilder private func fbNote(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                Text(value).font(Typo.body(13)).foregroundStyle(Palette.textHi)
            }
        }
    }

    // MARK: Photos / notes

    private func photos(_ d: CheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOTO PROGRESSI").voltEyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(d.photos) { p in
                        AsyncImage(url: URL(string: p.url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Rectangle().fill(Palette.void2)
                            }
                        }
                        .frame(width: 130, height: 175)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func notes(_ d: CheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTE & FEEDBACK").voltEyebrow()
            if let fb = d.coachFeedback.isEmpty ? nil : d.coachFeedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").font(.system(size: 12, weight: .black)).foregroundStyle(Palette.cyan)
                    Text(fb).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
            }
            fbNote("Messaggio", d.notes)
            fbNote("Infortuni", d.injuries)
            fbNote("Limitazioni", d.limitations)
        }
    }

    private func hasNotes(_ d: CheckDetailDTO) -> Bool {
        !d.coachFeedback.isEmpty || [d.notes, d.injuries, d.limitations].contains { ($0 ?? "").isEmpty == false }
    }

    // MARK: Load / helpers

    private func load() async {
        loading = true; defer { loading = false }
        do { data = try await APIClient.shared.checkDetail(responseId: responseId) }
        catch { self.error = "Impossibile caricare il check." }
    }

    private func parseDate(_ iso: String?) -> Date? { iso.flatMap(ISO8601.parse) }
    private func dateLong(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }
}
