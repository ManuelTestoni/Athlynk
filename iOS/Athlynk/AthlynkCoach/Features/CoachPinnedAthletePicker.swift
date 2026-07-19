//
//  CoachPinnedAthletePicker.swift
//  Sheet to choose which athletes appear in the dashboard's "Atleti in
//  evidenza" widget (max 6). Presented from DashboardEditSheet's "Scegli";
//  writes the selection back into the widget's config → autosaved layout.
//

import SwiftUI

struct CoachPinnedAthletePicker: View {
    let selected: [Int]
    let onSave: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var clients: [CoachClientRow] = []
    @State private var picked: [Int] = []
    @State private var loading = true
    @State private var query = ""

    private var filtered: [CoachClientRow] {
        guard !query.isEmpty else { return clients }
        return clients.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { client in
                        row(client)
                    }
                } header: {
                    Text("Selezionati: \(picked.count)/6")
                        .font(Typo.mono(10, .semibold)).tracking(2)
                        .foregroundStyle(Palette.textMid)
                }
            }
            .searchable(text: $query, prompt: "Cerca atleta")
            .overlay {
                if loading {
                    ProgressView().tint(Palette.primary)
                } else if clients.isEmpty {
                    EmptyPanel(icon: "person.2", text: "Nessun atleta attivo",
                               color: Palette.textLow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.void0)
            .navigationTitle("Atleti in evidenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .font(Typo.body(14)).tint(Palette.textMid)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Conferma") {
                        Haptics.success()
                        onSave(picked)
                        dismiss()
                    }
                    .font(Typo.body(15, .semibold)).tint(Palette.primary)
                }
            }
        }
        .task {
            picked = selected
            if let resp = try? await APIClient.shared.coachClients(status: "ACTIVE", limit: 200) {
                clients = resp.clients
            }
            loading = false
        }
    }

    private func row(_ client: CoachClientRow) -> some View {
        let isOn = picked.contains(client.id)
        return Button {
            Haptics.tap()
            if isOn {
                picked.removeAll { $0 == client.id }
            } else if picked.count < 6 {
                picked.append(client.id)
            }
        } label: {
            HStack(spacing: 12) {
                CoachClientAvatar(url: client.profileImageUrl,
                                  initials: client.initials, size: 34)
                Text(client.displayName)
                    .font(Typo.body(15, .medium)).foregroundStyle(Palette.textHi)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Palette.control : Palette.textLow.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }
}
