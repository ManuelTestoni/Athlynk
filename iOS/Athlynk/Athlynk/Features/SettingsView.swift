//
//  SettingsView.swift
//  Stitch "Impostazioni": account email + per-category email notification
//  toggles. Backed by GET/PATCH /api/v1/settings (User.email_prefs).
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var toggles: [SettingToggleDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var confirm: ConfirmKind?
    @State private var deleting = false

    /// Which destructive action the confirm popup is asking about.
    private enum ConfirmKind { case logout, delete }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.bronze, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        SettingsSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else {
                        accountCard
                        Text("NOTIFICHE EMAIL").voltEyebrow().padding(.top, 4)
                        ForEach(toggles) { t in toggleRow(t) }
                        LegalLinks(accent: Palette.cyan)
                        accountActions
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }

            if let confirm { confirmOverlay(confirm) }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var accountActions: some View {
        AccountActions(
            onLogout: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirm = .logout } },
            onDelete: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirm = .delete } }
        )
    }

    @ViewBuilder
    private func confirmOverlay(_ kind: ConfirmKind) -> some View {
        let isDelete = kind == .delete
        ConfirmDialogCard(
            icon: isDelete ? "trash" : "rectangle.portrait.and.arrow.right",
            title: isDelete ? "Elimina account" : "Esci dall'account",
            message: isDelete
                ? "Il tuo account verrà disattivato e non potrai più accedere. Questa azione non è reversibile dall'app."
                : "Verrai disconnesso da questo dispositivo. Potrai rientrare con le tue credenziali.",
            confirmTitle: isDelete ? "Elimina definitivamente" : "Esci",
            accent: isDelete ? Palette.danger : Palette.control,
            loading: deleting,
            onConfirm: { Task { await performConfirm(kind) } },
            onCancel: { dismissConfirm() }
        )
    }

    private func dismissConfirm() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { confirm = nil }
    }

    private func performConfirm(_ kind: ConfirmKind) async {
        switch kind {
        case .logout:
            app.logout()
        case .delete:
            deleting = true
            await app.deleteAccount()
            deleting = false
        }
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
        return SettingsToggleRow(label: t.label, desc: t.desc, isOn: binding)
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
