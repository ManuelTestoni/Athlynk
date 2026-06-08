//
//  CoachChecksView.swift
//  "Revisione Check-in (Coach)" — list of submitted checks + a detail/review
//  screen where the coach reads measurements/photos and writes feedback.
//

import SwiftUI

struct CoachChecksView: View {
    @State private var checks: [CoachCheckRow] = []
    @State private var pendingCount = 0
    @State private var filter = "pending"     // pending | all
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Da revisionare", title: "Check-in",
                             subtitle: "\(pendingCount) in attesa di feedback", accent: Palette.bronze)

                Picker("", selection: $filter) {
                    Text("In attesa").tag("pending")
                    Text("Tutti").tag("all")
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { _, _ in Task { await load() } }

                if loading && checks.isEmpty {
                    LoadingPanel()
                } else if checks.isEmpty {
                    EmptyPanel(icon: "checkmark.seal", text: filter == "pending"
                               ? "Nessun check da revisionare. Ottimo lavoro!"
                               : "Nessun check ricevuto.", color: Palette.lime)
                } else {
                    ForEach(checks) { c in
                        NavigationLink(value: CheckRoute(id: c.id)) { card(c) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationDestination(for: CheckRoute.self) { CoachCheckDetailView(responseId: $0.id) }
            .task { await load() }
            .onRemoteChange(["CHECK_SUBMITTED"]) { Task { await load() } }
            .refreshable { await load() }
        }
    }

    private func card(_ c: CoachCheckRow) -> some View {
        HStack(spacing: 14) {
            CoachClientAvatar(url: c.client?.profileImageUrl, initials: c.client?.initials ?? "A", size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.client?.displayName ?? "Atleta").font(Typo.body(16, .semibold))
                    .foregroundStyle(Palette.textHi)
                Text(c.title).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
                Text(CoachDate.relative(c.submittedAt)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
            }
            Spacer()
            if c.reviewed {
                StatusBadge(text: "Fatto", color: Palette.lime)
            } else {
                StatusBadge(text: "Nuovo", color: Palette.bronze)
            }
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachChecks(filter: filter) {
            checks = res.checks; pendingCount = res.pendingCount
        }
    }
}

struct CoachCheckDetailView: View {
    let responseId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var data: CoachCheckDetailDTO?
    @State private var loading = true
    @State private var feedback = ""
    @State private var privateNotes = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        ScreenScroll {
            if let d = data {
                clientHeader(d)
                if !d.measurements.isEmpty || d.weightKg != nil { measurements(d) }
                if !d.photos.isEmpty { photos(d) }
                if hasNotes(d) { notes(d) }
                feedbackComposer(d)
            } else if loading {
                LoadingPanel()
            } else {
                EmptyPanel(icon: "doc.questionmark", text: "Check non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func clientHeader(_ d: CoachCheckDetailDTO) -> some View {
        VStack(spacing: 10) {
            CoachClientAvatar(url: d.client.profileImageUrl, initials: d.client.initials, size: 72)
            Text(d.client.displayName).font(Typo.poster(28)).foregroundStyle(Palette.textHi)
            Text("\(d.title) · \(CoachDate.dayMonth(d.submittedAt))")
                .font(Typo.mono(11)).foregroundStyle(Palette.textMid)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private func measurements(_ d: CoachCheckDetailDTO) -> some View {
        var rows: [(String, String)] = []
        if let w = d.weightKg { rows.append(("Peso", "\(String(format: "%.1f", w)) kg")) }
        for (k, v) in d.measurements.sorted(by: { $0.key < $1.key }) { rows.append((label(k), "\(v) cm")) }
        for (k, v) in d.skinfolds.sorted(by: { $0.key < $1.key }) { rows.append((label(k), "\(v) mm")) }
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Antropometria", title: "Misurazioni", accent: Palette.cyan)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Text(r.0).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        Spacer()
                        Text(r.1).font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
                }
            }
        }
    }

    private func photos(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Visivo", title: "Foto", accent: Palette.violet)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(d.photos) { p in
                        AsyncImage(url: URL(string: p.url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Rectangle().fill(Palette.void2)
                            }
                        }
                        .frame(width: 150, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func notes(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachSectionTitle(eyebrow: "Note atleta", title: "Diario", accent: Palette.amber)
            VStack(alignment: .leading, spacing: 10) {
                noteRow("Messaggio", d.notes)
                noteRow("Infortuni", d.injuries)
                noteRow("Limitazioni", d.limitations)
            }
        }
    }

    @ViewBuilder private func noteRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).voltEyebrow()
                Text(value).font(Typo.body(14)).foregroundStyle(Palette.textHi)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).voltPanel()
        }
    }

    private func feedbackComposer(_ d: CoachCheckDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: sent || !d.coachFeedback.isEmpty ? "Inviato" : "La tua revisione",
                              title: "Feedback", accent: Palette.bronze)
            ZStack(alignment: .topLeading) {
                if feedback.isEmpty {
                    Text("Scrivi un feedback per l'atleta…")
                        .font(Typo.body(15)).foregroundStyle(Palette.textLow)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                }
                TextEditor(text: $feedback)
                    .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .voltPanel(radius: 14)

            NeonButton(title: sent ? "Feedback inviato" : "Invia feedback",
                       icon: sent ? "checkmark" : "paperplane.fill",
                       color: sent ? Palette.lime : Palette.bronze, loading: sending) {
                Task { await send() }
            }
            .disabled(feedback.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
    }

    private func hasNotes(_ d: CoachCheckDetailDTO) -> Bool {
        [d.notes, d.injuries, d.limitations].contains { ($0 ?? "").isEmpty == false }
    }

    private func label(_ key: String) -> String {
        key.replacingOccurrences(of: "circ::", with: "")
           .replacingOccurrences(of: "pl::", with: "")
           .replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func load() async {
        loading = true; defer { loading = false }
        if let d = try? await APIClient.shared.coachCheck(id: responseId) {
            data = d
            feedback = d.coachFeedback
            privateNotes = d.coachPrivateNotes
            sent = !d.coachFeedback.isEmpty
        }
    }

    private func send() async {
        sending = true; defer { sending = false }
        do {
            try await APIClient.shared.coachSendFeedback(
                checkId: responseId, feedback: feedback, privateNotes: privateNotes)
            Haptics.success(); sent = true
        } catch { Haptics.error() }
    }
}
