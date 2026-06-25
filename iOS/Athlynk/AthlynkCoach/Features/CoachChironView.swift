//
//  CoachChironView.swift
//  Chiron AI — coach chat assistant. Full conversation history, pending-action
//  confirmation banner, and a sticky input bar. Backed by /api/v1/coach/chiron/*.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class CoachChironVM: ObservableObject {
    @Published var entries: [ChironEntry] = []
    @Published var loading = false
    @Published var sending = false
    @Published var input = ""
    @Published var pendingAction: [String: Any]?
    @Published var pendingActionLabel = ""
    @Published var errorMsg: String?
    @Published var hasMore = false
    @Published var loadingMore = false
    /// Non-nil while a reply is streaming in: the live assistant bubble text.
    @Published var streamingText: String?
    private var oldestId: Int?

    func loadHistory() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let (history, more) = try await APIClient.shared.coachChironHistory()
            entries = history
            hasMore = more
            oldestId = history.first?.id
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Reload the latest page after a send/action; keeps pagination consistent.
    private func refreshHistory() async {
        do {
            let (history, more) = try await APIClient.shared.coachChironHistory()
            entries = history
            hasMore = more
            oldestId = history.first?.id
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    /// Page in older messages when the user reaches the top.
    func loadMore() async {
        guard hasMore, !loadingMore, let before = oldestId else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let (older, more) = try await APIClient.shared.coachChironHistory(before: before)
            guard !older.isEmpty else { hasMore = false; return }
            entries.insert(contentsOf: older, at: 0)
            oldestId = older.first?.id
            hasMore = more
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    func send() async {
        let msg = input.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty, !sending else { return }
        input = ""
        let tmpId = -Int(Date().timeIntervalSince1970)
        entries.append(ChironEntry(id: tmpId, role: "user", content: msg, sources: [], actions: [], usedWebSearch: false))
        sending = true; defer { sending = false }
        streamingText = ""
        var acc = ""
        do {
            for try await event in APIClient.shared.coachChironChatStream(message: msg) {
                switch event {
                case .token(let t):
                    acc += t
                    streamingText = acc
                case .done(let result):
                    pendingAction = result.pendingAction
                    pendingActionLabel = result.pendingActionLabel
                    let finalText = result.assistantContent.isEmpty ? acc : result.assistantContent
                    entries.append(ChironEntry(id: tmpId - 1, role: "assistant", content: finalText,
                                               sources: result.sources, actions: result.actions,
                                               usedWebSearch: result.usedWebSearch))
                }
            }
            streamingText = nil
        } catch {
            streamingText = nil
            entries.removeAll { $0.id == tmpId }
            errorMsg = error.localizedDescription
        }
    }

    func executeAction() async {
        guard let action = pendingAction else { return }
        do {
            let (ok, msg) = try await APIClient.shared.coachChironExecute(action)
            pendingAction = nil; pendingActionLabel = ""
            if ok {
                await refreshHistory()
            } else {
                errorMsg = msg
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    func clearChat() async {
        do {
            try await APIClient.shared.coachChironClear()
            entries = []; pendingAction = nil; pendingActionLabel = ""
            hasMore = false; oldestId = nil
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - View

struct CoachChironView: View {
    @StateObject private var vm = CoachChironVM()
    @State private var clearConfirm = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: CoachRouter

    var body: some View {
        VStack(spacing: 0) {
            scrollArea
            if !vm.pendingActionLabel.isEmpty { actionBanner }
            inputBar
        }
        .navigationTitle("CHIRON")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textMid)
                }
                .accessibilityLabel("Chiudi")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { clearConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.bronze)
                }
                .disabled(vm.entries.isEmpty || vm.sending)
            }
        }
        .confirmationDialog("Cancella tutta la cronologia con Chiron?",
                            isPresented: $clearConfirm, titleVisibility: .visible) {
            Button("Cancella", role: .destructive) { Task { await vm.clearChat() } }
        }
        .alert("Errore", isPresented: Binding(get: { vm.errorMsg != nil }, set: { if !$0 { vm.errorMsg = nil } })) {
            Button("OK") { vm.errorMsg = nil }
        } message: {
            Text(vm.errorMsg ?? "")
        }
        .task { await vm.loadHistory() }
    }

    // MARK: Scroll area

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.loading && vm.entries.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    } else if !vm.loading && vm.entries.isEmpty {
                        welcomePrompt
                    }
                    // Reaching the top auto-loads older messages; we re-anchor to
                    // the previous first message so the view doesn't jump.
                    if vm.hasMore {
                        Color.clear.frame(height: 1)
                            .onAppear {
                                Task {
                                    let anchor = vm.entries.first?.id
                                    await vm.loadMore()
                                    if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                }
                            }
                        if vm.loadingMore {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                    }
                    ForEach(vm.entries) { entry in
                        ChironBubbleRow(entry: entry) { router.open($0); dismiss() }
                    }
                    if let streaming = vm.streamingText, !streaming.isEmpty {
                        ChironBubbleRow(entry: ChironEntry(id: -999_999, role: "assistant",
                                                           content: streaming, sources: [],
                                                           actions: [], usedWebSearch: false)) {
                            router.open($0); dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if vm.sending {
                        ChironTypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("scroll-bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            // Scroll to bottom only when a new message lands at the end — not
            // when older messages are prepended (last id unchanged then).
            .onChange(of: vm.entries.last?.id) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.sending) { _, _ in scrollToBottom(proxy) }
            .onChange(of: vm.streamingText) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("scroll-bottom") }
    }

    // MARK: Welcome

    private var welcomePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Palette.bronze)
            Text("CHIRON")
                .font(Typo.mono(12, .bold)).tracking(4).foregroundStyle(Palette.bronze)
            Text("Il tuo assistente intelligente. Chiedimi di analizzare i progressi degli atleti, suggerire piani, rispondere a domande sulla preparazione fisica e molto altro.")
                .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60).padding(.horizontal, 32)
    }

    // MARK: Action banner

    private var actionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bronze)
            VStack(alignment: .leading, spacing: 2) {
                Text("AZIONE PROPOSTA").font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.bronze)
                Text(vm.pendingActionLabel).font(Typo.body(13)).foregroundStyle(Palette.textHi).lineLimit(2)
            }
            Spacer()
            Button("Conferma") { Task { await vm.executeAction() } }
                .font(Typo.mono(11, .black)).tracking(1)
                .foregroundStyle(Palette.void0)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Palette.bronze))
            Button {
                vm.pendingAction = nil; vm.pendingActionLabel = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textLow)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.bronze.opacity(0.4)).frame(height: 1)
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Scrivi a Chiron...", text: $vm.input, axis: .vertical)
                .font(Typo.body(15))
                .foregroundStyle(Palette.textHi)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Palette.void1.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)
                .onSubmit { Task { await vm.send() } }

            let isEmpty = vm.input.trimmingCharacters(in: .whitespaces).isEmpty
            Button { Task { await vm.send() } } label: {
                Image(systemName: vm.sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(isEmpty ? Palette.textLow : Palette.void0)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(isEmpty ? Palette.line : Palette.bronze))
            }
            .disabled(isEmpty || vm.sending)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line.opacity(0.5)).frame(height: 0.5)
        }
    }
}

// MARK: - Bubble Row

private struct ChironBubbleRow: View {
    let entry: ChironEntry
    var onAction: (String) -> Void = { _ in }
    private var isUser: Bool { entry.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 56) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(entry.content)
                    .font(Typo.body(15))
                    .foregroundStyle(isUser ? Palette.void0 : Palette.textHi)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isUser ? Palette.bronze : Palette.void1.opacity(0.6))
                    )
                if entry.usedWebSearch {
                    Label("ricerca web", systemImage: "globe")
                        .font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
                if !entry.sources.isEmpty {
                    ForEach(Array(entry.sources.enumerated()), id: \.offset) { _, src in
                        if let url = URL(string: src.url) {
                            Link(destination: url) {
                                Label(src.title, systemImage: "link")
                                    .font(Typo.mono(9)).foregroundStyle(Palette.bronze).lineLimit(1)
                            }
                        }
                    }
                }
                // In-app "section" links — open the matching native screen.
                if !entry.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entry.actions) { action in
                            Button { onAction(action.url) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text(action.label).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(Typo.mono(11, .bold))
                                .foregroundStyle(Palette.bronze)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bronze.opacity(0.10)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.bronze.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            if !isUser { Spacer(minLength: 56) }
        }
    }
}

// MARK: - Typing Indicator

private struct ChironTypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Palette.textLow)
                    .frame(width: 7, height: 7)
                    .offset(y: animate ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.void1.opacity(0.6)))
        .onAppear { animate = true }
    }
}
