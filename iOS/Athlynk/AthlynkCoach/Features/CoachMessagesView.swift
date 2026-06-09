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

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Conversazioni", title: "Messaggi",
                             subtitle: "Resta in contatto con i tuoi atleti", accent: Palette.violet)

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

                if loading && convos.isEmpty {
                    LoadingPanel()
                } else if convos.isEmpty {
                    EmptyPanel(icon: "bubble.left.and.bubble.right",
                               text: "Nessuna conversazione attiva.\nUsa “Nuovo messaggio” per scrivere a un atleta.")
                } else {
                    ForEach(convos) { c in
                        NavigationLink(value: c) { row(c) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .navigationDestination(for: CoachConversation.self) { c in
                CoachThreadView(conversation: c)
            }
            .sheet(isPresented: $composingNew, onDismiss: { Task { await load() } }) {
                CoachNewMessageView()
            }
            .task { await load() }
            .onRemoteChange(["MESSAGE"]) { Task { await load() } }
            .refreshable { await load() }
        }
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
    @State private var draft = ""
    @State private var loading = true
    @State private var pollTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if loading { LoadingPanel().padding(.top, 40) }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                    }
                    .padding(.horizontal, 18).padding(.top, 70).padding(.bottom, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .background(VoltBackground(palette: [Palette.violet, Palette.bronze, Palette.cyan, Palette.violet]).ignoresSafeArea())
        .navigationTitle(conversation.client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad(); startPolling() }
        .onDisappear { pollTask?.cancel(); app.tabBarHidden = false }
        .onAppear { app.tabBarHidden = true }
    }

    private func bubble(_ m: MessageDTO) -> some View {
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
            Haptics.tap()
        } catch { Haptics.error(); draft = body }
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
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return clients }
        return clients.filter { $0.displayName.lowercased().contains(q) }
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
                    LoadingPanel()
                } else if filtered.isEmpty {
                    EmptyPanel(icon: "person.2", text: "Nessun atleta disponibile.")
                } else {
                    ForEach(filtered) { c in
                        Button { Haptics.tap(); selected = c } label: {
                            HStack(spacing: 14) {
                                CoachClientAvatar(url: c.profileImageUrl, initials: c.initials, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.displayName).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                                    if let g = c.primaryGoal {
                                        Text(g).font(Typo.body(12)).foregroundStyle(Palette.textMid).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if c.hasConversation {
                                    Text("In corso").font(Typo.mono(8, .semibold)).tracking(1)
                                        .foregroundStyle(Palette.textLow)
                                }
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
