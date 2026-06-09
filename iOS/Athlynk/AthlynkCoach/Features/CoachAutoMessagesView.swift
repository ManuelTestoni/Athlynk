//
//  CoachAutoMessagesView.swift
//  "Messaggi automatici" — the coach edits the per-event canned replies sent to
//  athletes (welcome, goodbye, subscription expiring). Mirrors the web settings
//  page; persists via /api/v1/coach/auto-messages.
//

import SwiftUI

struct CoachAutoMessagesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var messages: [CoachAutoMessage] = []
    @State private var loading = true
    @State private var saving = false

    private func accent(_ eventType: String) -> Color {
        switch eventType {
        case "WELCOME": return Palette.lime
        case "GOODBYE": return Palette.phase
        default: return Palette.amber
        }
    }
    private func icon(_ eventType: String) -> String {
        switch eventType {
        case "WELCOME": return "hand.wave.fill"
        case "GOODBYE": return "figure.wave"
        default: return "creditcard.trianglebadge.exclamationmark"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Quando attivi, questi messaggi vengono inviati in automatico in chat all'evento corrispondente.")
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if loading {
                        FormSkeleton(accent: Palette.bronze, count: 3)
                    } else {
                        ForEach($messages) { $m in card($m) }
                        NeonButton(title: "Salva", icon: "checkmark", color: Palette.bronze, loading: saving) {
                            Task { await save() }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Risposte automatiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .task { await load() }
            .statusOverlay(flash)
        }
    }

    private func card(_ m: Binding<CoachAutoMessage>) -> some View {
        let a = accent(m.wrappedValue.eventType)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon(m.wrappedValue.eventType))
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(a).frame(width: 26)
                Text(m.wrappedValue.label).font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                Spacer()
                Toggle("", isOn: m.isEnabled).labelsHidden().tint(a)
            }
            TextEditor(text: m.body)
                .font(Typo.body(14)).foregroundStyle(Palette.textHi)
                .scrollContentBackground(.hidden).frame(minHeight: 84)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.void0))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
                .opacity(m.wrappedValue.isEnabled ? 1 : 0.5)
                .disabled(!m.wrappedValue.isEnabled)
        }
        .padding(16).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        messages = (try? await APIClient.shared.coachAutoMessages()) ?? []
    }

    private func save() async {
        saving = true; defer { saving = false }
        let payload: [[String: Any]] = messages.map {
            ["event_type": $0.eventType, "body": $0.body, "is_enabled": $0.isEnabled]
        }
        do {
            messages = try await APIClient.shared.coachUpdateAutoMessages(payload)
            flash.success("Risposte salvate")
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
