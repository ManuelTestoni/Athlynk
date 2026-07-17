//
//  CoachMessagesView.swift
//  "Centro Messaggi (Coach)" — conversation list + a chat thread with the
//  athlete. The message thread reuses the shared MessageDTO shape.
//

import SwiftUI

struct CoachMessagesView: View {
    @State private var convos: [CoachConversation] = []
    @State private var loading = true
    @State private var composingNew = false
    @State private var appear = false

    var body: some View {
        ScreenScroll {
                ScreenHeader(eyebrow: "Conversazioni", title: "Messaggi",
                             subtitle: "Resta in contatto con i tuoi atleti", accent: Palette.violet)
                    .revealUp(appear, index: 0)

                Button { Haptics.tap(); composingNew = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .bold))
                        Text("Nuovo messaggio").font(Typo.body(15, .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.textLow)
                    }
                    .foregroundStyle(Palette.violet)
                    .padding(16).voltPanel()
                }
                .buttonStyle(PressableButtonStyle())
                .revealUp(appear, index: 1)

                if loading && convos.isEmpty {
                    AvatarRowsSkeleton(accent: Palette.violet)
                } else if convos.isEmpty {
                    EmptyPanel(icon: "bubble.left.and.bubble.right",
                               text: "Nessuna conversazione attiva.\nUsa “Nuovo messaggio” per scrivere a un atleta.")
                } else {
                    ForEach(Array(convos.enumerated()), id: \.element.id) { i, c in
                        NavigationLink(value: c) { row(c) }
                            .buttonStyle(PressableButtonStyle())
                            .revealUp(appear, index: min(i, 6) + 2)
                    }
                }
            }
        .navigationDestination(for: CoachConversation.self) { c in
            CoachThreadView(conversation: c)
        }
        .sheet(isPresented: $composingNew, onDismiss: { Task { await load() } }) {
            CoachNewMessageView()
        }
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .task { await load() }
        .onRemoteChange(["MESSAGE"]) { Task { await load() } }
        .refreshable { await load() }
    }

    private func row(_ c: CoachConversation) -> some View {
        HStack(spacing: 14) {
            CoachClientAvatar(url: c.client.profileImageUrl, initials: c.client.initials, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.client.displayName).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                Text(c.lastMessage ?? "Nessun messaggio")
                    .font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(CoachDate.relative(c.lastMessageAt)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                if c.unread > 0 {
                    Text("\(c.unread)").font(Typo.mono(10, .black))
                        .foregroundStyle(Palette.void0)
                        .frame(width: 20, height: 20).background(Circle().fill(Palette.violet))
                }
            }
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        convos = (try? await APIClient.shared.coachConversations()) ?? []
    }
}

struct CoachThreadView: View {
    let conversation: CoachConversation
    @EnvironmentObject private var app: AppState
    @State private var messages: [MessageDTO] = []
    @State private var loading = true
    @State private var pollTask: Task<Void, Never>?
    @State private var draft = ""
    @State private var confirmTarget: MessageDTO?
    @State private var rejectTarget: MessageDTO?
    @State private var showRequestSheet = false
    @FocusState private var composerFocused: Bool
    @StateObject private var flash = StatusFlash()

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if loading { LoadingPanel().padding(.top, 40) }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                        }
                        .padding(.horizontal, 18).padding(.top, 70).padding(.bottom, 12)
                        // Few (or zero) messages must still sit at the bottom of the
                        // screen, not float at the top of an otherwise-empty ScrollView.
                        .frame(minHeight: geo.size.height, alignment: .bottom)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                    .task {
                        await initialLoad()
                        if let last = messages.last {
                            // Bulk-inserted rows from the initial load need a beat to lay
                            // out before scrollTo is reliable — the count-driven onChange
                            // above alone isn't enough for the very first page.
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        startPolling()
                    }
                }
            }
            composer
        }
        .background(VoltBackground(palette: [Palette.violet, Palette.bronze, Palette.cyan, Palette.violet]).ignoresSafeArea())
        .navigationTitle(conversation.client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.tabBarHidden = true; app.chironHidden = true }
        .onDisappear { pollTask?.cancel(); app.tabBarHidden = false; app.chironHidden = false }
        .statusOverlay(flash)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showRequestSheet = true } label: {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Palette.bronze)
                }
            }
        }
        .sheet(isPresented: $showRequestSheet) {
            CoachAppointmentRequestSheet(conversationId: conversation.id) { msg in
                messages.append(msg)
            }
        }
        .sheet(item: $confirmTarget) { target in
            CoachAppointmentConfirmSheet(conversationId: conversation.id, appointmentId: target.appointmentId ?? 0,
                                          title: target.appointmentTitle ?? "Appuntamento",
                                          when: formatCoachAppointmentWhen(target.appointmentStart)) { msg in
                applyResponse(msg, to: target)
            }
        }
        .sheet(item: $rejectTarget) { target in
            CoachAppointmentRejectSheet(conversationId: conversation.id, appointmentId: target.appointmentId ?? 0,
                                         title: target.appointmentTitle ?? "Appuntamento",
                                         when: formatCoachAppointmentWhen(target.appointmentStart)) { msg in
                applyResponse(msg, to: target)
            }
        }
    }

    private func applyResponse(_ msg: MessageDTO, to target: MessageDTO) {
        if let i = messages.firstIndex(where: { $0.id == target.id }) {
            messages[i] = MessageDTO(id: target.id, body: target.body, messageType: target.messageType,
                                      isMine: target.isMine, sentAt: target.sentAt, attachmentUrl: target.attachmentUrl,
                                      appointmentId: target.appointmentId, appointmentStatus: msg.appointmentStatus,
                                      appointmentTitle: target.appointmentTitle, appointmentStart: target.appointmentStart,
                                      appointmentExpired: false, readAt: target.readAt)
        }
        messages.append(msg)
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
                    .font(Typo.body(15)).foregroundStyle(m.isMine ? Palette.void0 : Palette.textHi)
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(m.isMine ? Palette.bronze : Palette.void1)
                    }
                    .overlay {
                        if !m.isMine {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1)
                        }
                    }
                if !m.isMine { Spacer(minLength: 50) }
            }
        }
    }

    private func appointmentBubble(_ m: MessageDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Richiesta appuntamento", systemImage: "calendar")
                .font(Typo.body(13, .semibold)).foregroundStyle(Palette.violet)
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
        .padding(14).voltPanel(Palette.violet.opacity(0.35))
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("", text: $draft, prompt: Text("Messaggio…").foregroundStyle(Palette.textLow), axis: .vertical)
                .font(Typo.body(15)).foregroundStyle(Palette.textHi).tint(Palette.bronze)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .voltPanel(radius: 22)
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.void0)
                    .frame(width: 46, height: 46).background(Circle().fill(Palette.bronze))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func initialLoad() async {
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachMessages(conversation: conversation.id) {
            messages = res.messages
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let since = messages.last?.id else { continue }
                if let fresh = try? await APIClient.shared.coachNewMessages(conversation: conversation.id, since: since),
                   !fresh.isEmpty {
                    messages.append(contentsOf: fresh)
                }
            }
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        draft = ""
        do {
            try await APIClient.shared.coachSend(conversation: conversation.id, body: body)
            if let since = messages.last?.id,
               let fresh = try? await APIClient.shared.coachNewMessages(conversation: conversation.id, since: since) {
                messages.append(contentsOf: fresh)
            } else if let res = try? await APIClient.shared.coachMessages(conversation: conversation.id) {
                messages = res.messages
            }
            Analytics.shared.capture(.messageSent, ["conversation_id": conversation.id])
            Haptics.tap()
        } catch { flash.failure("Invio non riuscito"); draft = body }
    }
}

private let coachDayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
private let coachClockFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

private func formatCoachAppointmentWhen(_ iso: String?) -> String {
    guard let d = CoachDate.parse(iso) else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "EEEE d MMMM · HH:mm"
    return f.string(from: d)
}

/// "Fissa appuntamento" — coach proposes a day + time range to the athlete from chat.
struct CoachAppointmentRequestSheet: View {
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
                    TextField("Es. Check-in mensile", text: $title)
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
            .navigationTitle("Fissa appuntamento")
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
            let msg = try await APIClient.shared.coachRequestAppointment(
                conversation: conversationId, title: title,
                preferredDate: coachDayFmt.string(from: date),
                timeFrom: coachClockFmt.string(from: timeFrom), timeTo: coachClockFmt.string(from: timeTo),
                notes: notes.isEmpty ? nil : notes)
            onSent(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}

/// Accepts the slot the athlete already proposed, as-is — no date/time re-entry.
struct CoachAppointmentConfirmSheet: View {
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

                Text("Confermando accetti l'orario proposto dall'atleta — non serve reinserirlo.")
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
            let msg = try await APIClient.shared.coachRespondAppointment(
                conversation: conversationId, appointmentId: appointmentId, action: "accept")
            onDone(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}

/// Reject a pending appointment request, optionally proposing a different day/time.
struct CoachAppointmentRejectSheet: View {
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
            let msg = try await APIClient.shared.coachRespondAppointment(
                conversation: conversationId, appointmentId: appointmentId, action: "reject",
                counterDate: withCounter ? coachDayFmt.string(from: counterDate) : nil,
                counterTime: withCounter ? coachClockFmt.string(from: counterTime) : nil)
            onDone(msg)
            dismiss()
        } catch { self.error = "Errore, riprova" }
        sending = false
    }
}

// MARK: - New message (start a conversation with an athlete)

struct CoachNewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var clients: [CoachMessageableClient] = []
    @State private var loading = true
    @State private var selected: CoachMessageableClient?
    @State private var draft = ""
    @State private var sending = false
    @State private var query = ""

    private var filtered: [CoachMessageableClient] {
        // Only athletes the coach has never written to — existing chats live in
        // the conversation list, not here.
        let fresh = clients.filter { !$0.hasConversation }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return fresh }
        return fresh.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let c = selected { composer(c) } else { picker }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle(selected == nil ? "Nuovo messaggio" : selected!.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selected == nil {
                        Button("Chiudi") { dismiss() }.tint(Palette.textMid)
                    } else {
                        Button { selected = nil } label: { Image(systemName: "chevron.left") }.tint(Palette.textMid)
                    }
                }
            }
            .task { await load() }
            .statusOverlay(flash)
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.violet)
                    TextField("", text: $query, prompt: Text("Cerca atleta…").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.violet)
                }
                .padding(.horizontal, 16).padding(.vertical, 13).voltPanel(radius: 14)

                if loading {
                    AvatarRowsSkeleton(accent: Palette.violet, count: 4)
                } else if filtered.isEmpty {
                    EmptyPanel(icon: "person.2", text: "Nessun atleta disponibile.")
                } else {
                    ForEach(filtered) { c in
                        Button { Haptics.tap(); selected = c } label: {
                            HStack(spacing: 14) {
                                CoachClientAvatar(url: c.profileImageUrl, initials: c.initials, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.displayName).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                                    if let sport = c.sport {
                                        Text(sport).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.textLow)
                            }
                            .padding(14).voltPanel()
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(20)
        }
    }

    private func composer(_ c: CoachMessageableClient) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MESSAGGIO").font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
                TextEditor(text: $draft)
                    .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                    .scrollContentBackground(.hidden).frame(minHeight: 140)
                    .padding(10).voltPanel(radius: 14)
            }
            NeonButton(title: "Invia", icon: "paperplane.fill", color: Palette.violet, loading: sending) {
                Task { await start(c) }
            }
            Spacer()
        }
        .padding(20)
    }

    private func load() async {
        loading = true; defer { loading = false }
        clients = (try? await APIClient.shared.coachMessageableClients()) ?? []
    }

    private func start(_ c: CoachMessageableClient) async {
        let body = draft.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { flash.failure("Scrivi un messaggio"); return }
        sending = true; defer { sending = false }
        do {
            _ = try await APIClient.shared.coachStartConversation(clientId: c.id, body: body)
            flash.success("Messaggio inviato")
            try? await Task.sleep(for: .seconds(1.1))
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
