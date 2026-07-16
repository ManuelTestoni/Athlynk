//
//  ChatListView.swift
//

import SwiftUI

struct ChatListView: View {
    @State private var convos: [ConversationDTO] = []
    @State private var loading = true
    @State private var appear = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.magenta, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    GlitchText(text: "CHAT", size: 48).padding(.top, 8)
                    if loading {
                        AvatarRowsSkeleton(accent: Palette.cyan, count: 5)
                    } else if convos.isEmpty {
                        EmptyPanel(icon: "bubble.left", text: "Nessuna conversazione.")
                    } else {
                        ForEach(Array(convos.enumerated()), id: \.element.id) { i, c in
                            NavigationLink(value: c) { row(c) }
                                .buttonStyle(PressableButtonStyle())
                                .revealUp(appear, index: min(i, 8))
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { convos = (try? await APIClient.shared.conversations()) ?? []; loading = false; appear = true }
        .onRemoteChange(["MESSAGE"]) { Task { convos = (try? await APIClient.shared.conversations()) ?? [] } }
    }

    private func row(_ c: ConversationDTO) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.cyan.opacity(0.18)).frame(width: 48, height: 48)
                Text(String(c.coach?.firstName.first ?? "?"))
                    .font(Typo.poster(20)).foregroundStyle(Palette.cyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.coach?.fullName ?? "Coach").font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Text(c.lastMessage ?? "Nessun messaggio")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                .foregroundStyle(Palette.cyan)
        }
        .padding(14).voltPanel(Palette.cyan.opacity(0.35))
    }
}

struct ChatDetailView: View {
    let conversation: ConversationDTO
    @EnvironmentObject private var app: AppState
    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @State private var showRequestSheet = false
    @State private var confirmTarget: MessageDTO?
    @State private var rejectTarget: MessageDTO?
    @FocusState private var focused: Bool
    @StateObject private var flash = StatusFlash()

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if hasOlder {
                            Button { Task { await loadOlder(proxy) } } label: {
                                HStack(spacing: 8) {
                                    if loadingOlder {
                                        ProgressView().tint(Palette.cyan)
                                    } else {
                                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                                        Text("Carica precedenti").font(Typo.mono(11, .semibold))
                                    }
                                }
                                .foregroundStyle(Palette.cyan)
                                .padding(.vertical, 8).padding(.horizontal, 16)
                                .background(Capsule().stroke(Palette.cyan.opacity(0.4), lineWidth: 1))
                            }
                            .disabled(loadingOlder)
                            .padding(.bottom, 4)
                        }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
                    // Few (or zero) messages must still sit at the bottom of the
                    // screen, not float at the top of an otherwise-empty ScrollView.
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                }
                // Scroll to bottom only when a *newer* message arrives (the last id
                // changes). Prepending older history keeps the last id, so the view
                // stays put while we restore position in loadOlder().
                .onChange(of: messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
                // Full load once, then poll only for newer messages while the screen is
                // open. SwiftUI cancels this `.task` on disappear, stopping the poll.
                .task {
                    await reload()
                    if let id = messages.last?.id {
                        // The bulk of the initial page lands in one shot; give SwiftUI a
                        // beat to lay the rows out before the very first scrollTo, or it's
                        // unreliable and the view is left showing the top of the thread.
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    await pollLoop()
                }
            }
        }
        // Composer rides the bottom safe area, so it floats above the keyboard
        // when the field is focused and the scroll content insets to match.
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.cyan, Palette.magenta]))
        .navigationTitle(conversation.coach?.fullName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showRequestSheet = true } label: {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Palette.cyan)
                }
            }
        }
        // Drop the floating tab bar while in chat so it can't cover the composer;
        // restore it on the way out.
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
        .statusOverlay(flash)
        .sheet(isPresented: $showRequestSheet) {
            AppointmentRequestSheet(conversationId: conversation.id) { msg in
                messages.append(msg)
            }
        }
        .sheet(item: $confirmTarget) { target in
            AppointmentConfirmSheet(conversationId: conversation.id, appointmentId: target.appointmentId ?? 0,
                                     title: target.appointmentTitle ?? "Appuntamento",
                                     when: formatAppointmentWhen(target.appointmentStart)) { msg in
                applyResponse(msg, to: target)
            }
        }
        .sheet(item: $rejectTarget) { target in
            AppointmentRejectSheet(conversationId: conversation.id, appointmentId: target.appointmentId ?? 0,
                                    title: target.appointmentTitle ?? "Appuntamento",
                                    when: formatAppointmentWhen(target.appointmentStart)) { msg in
                applyResponse(msg, to: target)
            }
        }
    }

    private func applyResponse(_ msg: MessageDTO, to target: MessageDTO) {
        if let i = messages.firstIndex(where: { $0.id == target.id }) {
            messages[i] = replacing(messages[i], appointmentStatus: msg.appointmentStatus)
        }
        messages.append(msg)
    }

    private func replacing(_ m: MessageDTO, appointmentStatus: String?) -> MessageDTO {
        MessageDTO(id: m.id, body: m.body, messageType: m.messageType, isMine: m.isMine, sentAt: m.sentAt,
                   attachmentUrl: m.attachmentUrl, appointmentId: m.appointmentId, appointmentStatus: appointmentStatus,
                   appointmentTitle: m.appointmentTitle, appointmentStart: m.appointmentStart,
                   appointmentExpired: false, readAt: m.readAt)
    }

    @ViewBuilder
    private func bubble(_ m: MessageDTO) -> some View {
        if m.messageType == "APPOINTMENT_REQUEST" {
            appointmentBubble(m)
        } else if m.messageType == "APPOINTMENT_RESPONSE" {
            HStack {
                if m.isMine { Spacer(minLength: 50) }
                Label(m.body, systemImage: "calendar.badge.checkmark")
                    .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                if !m.isMine { Spacer(minLength: 50) }
            }
        } else {
            HStack {
                if m.isMine { Spacer(minLength: 50) }
                Text(m.body)
                    .font(Typo.body(15))
                    .foregroundStyle(m.isMine ? Palette.void0 : Palette.textHi)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background {
                        if m.isMine {
                            LinearGradient(colors: [Palette.cyan, Palette.cyan.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                        } else { Palette.void2 }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                        m.isMine ? .clear : Palette.line, lineWidth: 1))
                if !m.isMine { Spacer(minLength: 50) }
            }
        }
    }

    private func appointmentBubble(_ m: MessageDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Richiesta appuntamento", systemImage: "calendar")
                .font(Typo.body(13, .semibold)).foregroundStyle(Palette.cyan)
            Text(m.body).font(Typo.body(14)).foregroundStyle(Palette.textHi)

            switch m.appointmentStatus {
            case "PENDING" where m.appointmentExpired == true:
                StatusBadge(text: "Scaduta", color: Palette.textLow, filled: false)
            case "PENDING" where !m.isMine:
                HStack(spacing: 8) {
                    Button { confirmTarget = m } label: {
                        Text("Conferma").font(Typo.mono(11, .black)).tracking(1)
                            .foregroundStyle(Palette.void0)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Palette.success))
                    }
                    Button { rejectTarget = m } label: {
                        Text("Rifiuta").font(Typo.mono(11, .black)).tracking(1)
                            .foregroundStyle(Palette.void0)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Palette.danger))
                    }
                }
            case "SCHEDULED":
                StatusBadge(text: "Confermato", color: Palette.success)
            case "CANCELLED":
                StatusBadge(text: "Rifiutato", color: Palette.danger)
            default:
                EmptyView()
            }
        }
        .padding(14).voltPanel(Palette.cyan.opacity(0.35))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft, prompt: Text("Messaggio…").foregroundStyle(Palette.textLow))
                .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(Palette.cyan)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Capsule().fill(Palette.void2))
                .focused($focused)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .black)).foregroundStyle(Palette.void0)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.cyan)).neonGlow(Palette.cyan, radius: 8)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Load the most recent page; `hasOlder` drives the "Carica precedenti" button.
    private func reload() async {
        guard let page = try? await APIClient.shared.messages(conversation: conversation.id) else { return }
        messages = page.messages
        hasOlder = page.hasMore ?? false
    }

    /// Prepend the previous page (older than the oldest held), restoring scroll
    /// position to the message that was at the top so the view doesn't jump.
    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard !loadingOlder, let anchor = messages.first?.id else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let page = try? await APIClient.shared.messages(conversation: conversation.id, before: anchor) else { return }
        let known = Set(messages.map(\.id))
        let older = page.messages.filter { !known.contains($0.id) }
        guard !older.isEmpty else { hasOlder = false; return }
        messages.insert(contentsOf: older, at: 0)
        hasOlder = page.hasMore ?? false
        proxy.scrollTo(anchor, anchor: .top)
    }

    /// Fetch only messages newer than the last one held; append the unseen ones.
    private func pollOnce() async {
        guard let last = messages.last?.id,
              let new = try? await APIClient.shared.newMessages(conversation: conversation.id, since: last),
              !new.isEmpty else { return }
        let known = Set(messages.map(\.id))
        messages.append(contentsOf: new.filter { !known.contains($0.id) })
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { return }
            await pollOnce()
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sending = true; draft = ""; Haptics.tap()
        do {
            try await APIClient.shared.send(conversation: conversation.id, body: text)
            // Empty chat has no "last id" to poll against — reload the first page.
            if messages.isEmpty { await reload() } else { await pollOnce() }
        } catch { flash.failure("Invio non riuscito"); draft = text }
        sending = false
    }
}

private let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
private let clockFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

private func formatAppointmentWhen(_ iso: String?) -> String {
    guard let iso, let d = ISO8601.parse(iso) else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "EEEE d MMMM · HH:mm"
    return f.string(from: d)
}

/// "Richiedi appuntamento" — athlete proposes a day + time range to the coach.
struct AppointmentRequestSheet: View {
    let conversationId: Int
    let onSent: (MessageDTO) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var timeFrom = Date()
    @State private var timeTo = Date().addingTimeInterval(3600)
    @State private var notes = ""
    @State private var error = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Titolo") {
                    TextField("Es. Consulenza progressi", text: $title)
                }
                Section("Data e orario") {
                    DatePicker("Giorno", selection: $date, displayedComponents: .date)
                    DatePicker("Dalle", selection: $timeFrom, displayedComponents: .hourAndMinute)
                    DatePicker("Alle", selection: $timeTo, displayedComponents: .hourAndMinute)
                }
                Section("Note (opzionale)") {
                    TextField("", text: $notes, axis: .vertical)
                }
                if !error.isEmpty {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.danger)
                }
            }
            .navigationTitle("Richiedi appuntamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invia") { Task { await submit() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
        }
    }

    private func submit() async {
        sending = true
        do {
            let msg = try await APIClient.shared.requestAppointment(
                conversation: conversationId, title: title,
                preferredDate: dayFmt.string(from: date),
                timeFrom: clockFmt.string(from: timeFrom), timeTo: clockFmt.string(from: timeTo),
                notes: notes.isEmpty ? nil : notes)
            onSent(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}

/// Coach's appointment request accepted by picking a confirmed day/time.
/// Accepts the slot the requester already proposed, as-is — no date/time re-entry.
struct AppointmentConfirmSheet: View {
    let conversationId: Int
    let appointmentId: Int
    let title: String
    let when: String
    let onDone: (MessageDTO) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.success.opacity(0.18)).frame(width: 46, height: 46)
                        Image(systemName: "calendar.badge.checkmark").foregroundStyle(Palette.success)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                        Text(when).font(Typo.body(13)).foregroundStyle(Palette.textMid).textCase(.none)
                    }
                    Spacer()
                }
                .padding(14).voltPanel(Palette.success.opacity(0.3))

                Text("Confermando accetti l'orario proposto dalla controparte — non serve reinserirlo.")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid)

                if !error.isEmpty {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.danger)
                }
                Spacer()
                NeonButton(title: "Conferma", icon: "checkmark", color: Palette.success, loading: sending) {
                    Task { await submit() }
                }
            }
            .padding(20)
            .navigationTitle("Confermi l'appuntamento?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func submit() async {
        sending = true
        do {
            let msg = try await APIClient.shared.respondAppointment(
                conversation: conversationId, appointmentId: appointmentId, action: "accept")
            onDone(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}

/// Reject a pending appointment request, optionally proposing a different day/time.
struct AppointmentRejectSheet: View {
    let conversationId: Int
    let appointmentId: Int
    let title: String
    let when: String
    let onDone: (MessageDTO) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var withCounter = false
    @State private var counterDate = Date()
    @State private var counterTime = Date()
    @State private var error = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.danger.opacity(0.18)).frame(width: 46, height: 46)
                        Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(Palette.danger)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                        Text(when).font(Typo.body(13)).foregroundStyle(Palette.textMid).textCase(.none)
                    }
                    Spacer()
                }
                .padding(14).voltPanel(Palette.danger.opacity(0.3))

                Toggle("Proponi un altro orario", isOn: $withCounter.animation())
                    .font(Typo.body(15, .medium)).tint(Palette.danger)

                if withCounter {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Giorno alternativo", selection: $counterDate, displayedComponents: .date)
                        DatePicker("Orario alternativo", selection: $counterTime, displayedComponents: .hourAndMinute)
                    }
                    .padding(14).voltPanel()
                }

                if !error.isEmpty {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.danger)
                }
                Spacer()
                NeonButton(title: withCounter ? "Rifiuta e proponi" : "Rifiuta", icon: "xmark",
                           color: Palette.danger, loading: sending) {
                    Task { await submit() }
                }
            }
            .padding(20)
            .navigationTitle("Rifiuta appuntamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func submit() async {
        sending = true
        do {
            let msg = try await APIClient.shared.respondAppointment(
                conversation: conversationId, appointmentId: appointmentId, action: "reject",
                counterDate: withCounter ? dayFmt.string(from: counterDate) : nil,
                counterTime: withCounter ? clockFmt.string(from: counterTime) : nil)
            onDone(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}
