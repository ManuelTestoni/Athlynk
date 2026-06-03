//
//  SettingsView.swift
//  Stitch "Impostazioni": account email + per-category email notification
//  toggles. Backed by GET/PATCH /api/v1/settings (User.email_prefs).
//

import SwiftUI

struct SettingsView: View {
    @State private var email = ""
    @State private var toggles: [SettingToggleDTO] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.bronze, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        LoadingPanel(text: "Carico le impostazioni…")
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.cyan)
                    } else {
                        accountCard
                        Text("NOTIFICHE EMAIL").voltEyebrow().padding(.top, 4)
                        ForEach(toggles) { t in toggleRow(t) }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNT").voltEyebrow()
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill").font(.system(size: 16, weight: .black))
                    .foregroundStyle(Palette.cyan)
                Text(email).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Spacer()
            }
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.3))
    }

    private func toggleRow(_ t: SettingToggleDTO) -> some View {
        let binding = Binding<Bool>(
            get: { toggles.first(where: { $0.key == t.key })?.enabled ?? t.enabled },
            set: { newValue in Task { await update(key: t.key, enabled: newValue) } }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t.label).font(Typo.display(16)).foregroundStyle(Palette.textHi)
                Text(t.desc).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.cyan)
        .padding(16).voltPanel(Palette.cyan.opacity(0.3))
    }

    private func update(key: String, enabled: Bool) async {
        // Optimistic: flip locally, then persist.
        if let i = toggles.firstIndex(where: { $0.key == key }) {
            let old = toggles[i]
            toggles[i] = SettingToggleDTO(key: old.key, label: old.label, desc: old.desc, enabled: enabled)
        }
        Haptics.tap()
        do { toggles = try await APIClient.shared.updateSetting(key: key, enabled: enabled).notifications }
        catch { /* keep optimistic value on failure */ }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let s = try await APIClient.shared.settings()
            email = s.email
            toggles = s.notifications
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
