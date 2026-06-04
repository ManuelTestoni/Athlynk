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
    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.cyan, Palette.magenta])
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { m in bubble(m).id(m.id) }
                        }
                        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                composer
            }
        }
        .navigationTitle(conversation.coach?.fullName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await reload() }
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

    private func reload() async { messages = (try? await APIClient.shared.messages(conversation: conversation.id)) ?? [] }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sending = true; draft = ""; Haptics.tap()
        try? await APIClient.shared.send(conversation: conversation.id, body: text)
        await reload()
        sending = false
    }
}
