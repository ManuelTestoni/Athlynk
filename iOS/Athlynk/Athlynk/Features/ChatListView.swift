//
//  ChatListView.swift
//

import SwiftUI

struct ChatListView: View {
    @State private var convos: [ConversationDTO] = []
    @State private var loading = true

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
                        ForEach(convos) { c in
                            NavigationLink(value: c) { row(c) }
                                .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 40)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { convos = (try? await APIClient.shared.conversations()) ?? []; loading = false }
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
    @FocusState private var focused: Bool

    var body: some View {
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
            }
            // Scroll to bottom only when a *newer* message arrives (the last id
            // changes). Prepending older history keeps the last id, so the view
            // stays put while we restore position in loadOlder().
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        // Composer rides the bottom safe area, so it floats above the keyboard
        // when the field is focused and the scroll content insets to match.
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.cyan, Palette.magenta]))
        .navigationTitle(conversation.coach?.fullName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Full load once, then poll only for newer messages while the screen is
        // open. SwiftUI cancels this `.task` on disappear, stopping the poll.
        .task { await reload(); await pollLoop() }
        // Drop the floating tab bar while in chat so it can't cover the composer;
        // restore it on the way out.
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
    }

    private func bubble(_ m: MessageDTO) -> some View {
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
        try? await APIClient.shared.send(conversation: conversation.id, body: text)
        // Empty chat has no "last id" to poll against — reload the first page.
        if messages.isEmpty { await reload() } else { await pollOnce() }
        sending = false
    }
}
