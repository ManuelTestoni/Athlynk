//
//  CoachMessagesView.swift
//  "Centro Messaggi (Coach)" — conversation list + a chat thread with the
//  athlete. The message thread reuses the shared MessageDTO shape.
//

import SwiftUI

struct CoachMessagesView: View {
    @State private var convos: [CoachConversation] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Conversazioni", title: "Messaggi",
                             subtitle: "Resta in contatto con i tuoi atleti", accent: Palette.violet)

                if loading && convos.isEmpty {
                    LoadingPanel()
                } else if convos.isEmpty {
                    EmptyPanel(icon: "bubble.left.and.bubble.right", text: "Nessuna conversazione.")
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
