//
//  CoachChecksView.swift
//  "Revisione Check-in (Coach)" — list of submitted checks + a detail/review
//  screen where the coach reads measurements/photos and writes feedback.
//

import SwiftUI

struct CoachChecksView: View {
    @Binding var path: NavigationPath
    @State private var checks: [CoachCheckRow] = []
    @State private var pendingCount = 0
    @State private var filter = "pending"     // pending | all
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var loadToken = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScroll {
                ScreenHeader(eyebrow: "Da revisionare", title: "Check-in",
                             subtitle: "\(pendingCount) in attesa di feedback", accent: Palette.bronze)

                Picker("", selection: $filter) {
                    Text("In attesa").tag("pending")
                    Text("Tutti").tag("all")
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { _, _ in checks = []; loadToken = UUID() }

                if loading && checks.isEmpty {
                    AvatarRowsSkeleton(accent: Palette.bronze)
                } else if checks.isEmpty {
                    EmptyPanel(icon: "checkmark.seal", text: filter == "pending"
                               ? "Nessun check da revisionare. Ottimo lavoro!"
                               : "Nessun check ricevuto.", color: Palette.lime)
                } else {
                    ForEach(checks) { c in
                        NavigationLink(value: CheckRoute(id: c.id)) { card(c) }
                            .buttonStyle(PressableButtonStyle())
                    }
                    if hasMore {
                        LoadMoreButton(loading: loadingMore, accent: Palette.bronze) {
                            Task { await loadMore() }
                        }
                    }
                }

                CoachCheckTemplatesSection()
                    .padding(.top, 8)
            }
            .navigationDestination(for: CheckRoute.self) {
                CoachCheckDetailView(responseId: $0.id)
            }
            .navigationDestination(for: CheckTemplateRoute.self) {
                CoachCheckTemplateDetailView(templateId: $0.id)
            }
            .task(id: loadToken) {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await load()
            }
            .onRemoteChange(["CHECK_SUBMITTED"]) { checks = []; loadToken = UUID() }
            .refreshable { await load(force: true) }
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

    private func load(force: Bool = false) async {
        if !force, !checks.isEmpty { return }
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachChecks(filter: filter, offset: 0) {
            checks = res.checks; pendingCount = res.pendingCount; hasMore = res.hasMore
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.coachChecks(filter: filter, offset: checks.count) {
            checks.append(contentsOf: res.checks)
            hasMore = res.hasMore
            pendingCount = res.pendingCount
        }
    }
}

struct CoachCheckDetailView: View {
    let responseId: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @StateObject private var flash = StatusFlash()
    @State private var data: CoachCheckDetailDTO?
    @State private var loading = true
    @State private var feedback = ""
    @State private var privateNotes = ""
    @State private var sending = false
    @State private var sent = false
    @State private var editForm: CoachCheckPrefill?
    @State private var loadingEdit = false

    var body: some View {
        ScreenScroll {
            if let d = data {
                clientHeader(d)
                if !d.measurements.isEmpty || d.weightKg != nil { measurements(d) }
                if !d.photos.isEmpty { photos(d) }
                if hasNotes(d) { notes(d) }
                editValuesButton
                feedbackComposer(d)
            } else if loading {
                CoachCheckDetailSkeleton()
            } else {
                EmptyPanel(icon: "doc.questionmark", text: "Check non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .statusOverlay(flash)
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
        .sheet(item: $editForm) { pf in
            CoachCheckFormView(mode: .edit(responseId: responseId),
                               title: data?.title ?? "Check",
                               questions: pf.questions, steps: pf.steps, prefill: pf.prefill) {
                flash.success("Valori aggiornati"); Task { await load() }
            }
        }
        .task {
            Analytics.shared.capture(.checkinOpened, ["check_id": responseId])
            Analytics.shared.capture(.checkinReviewStarted, ["check_id": responseId])
            await load()
        }
    }

    private var editValuesButton: some View {
        Button {
            Task {
                loadingEdit = true; defer { loadingEdit = false }
                editForm = try? await APIClient.shared.coachCheckPrefill(responseId: responseId)
                if editForm == nil { flash.failure("Modifica non disponibile") }
            }
        } label: {
            Label(loadingEdit ? "Apertura…" : "Correggi valori", systemImage: "slider.horizontal.3")
                .font(Typo.body(13, .semibold)).foregroundStyle(Palette.cyan)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.cyan.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            Analytics.shared.capture(.checkinReviewCompleted, ["check_id": responseId])
            flash.success("Feedback inviato")
        } catch {
            Haptics.error()
            flash.failure("Invio non riuscito")
        }
    }
}
