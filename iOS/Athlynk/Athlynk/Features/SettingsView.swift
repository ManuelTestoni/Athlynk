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
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.cyan)
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
        VStack(spacing: 12) {
            NeonButton(title: "Esci", icon: "power", color: Palette.cyan, filled: false) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirm = .logout }
            }
            NeonButton(title: "Elimina account", icon: "trash.fill", color: Palette.magenta, filled: false) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirm = .delete }
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func confirmOverlay(_ kind: ConfirmKind) -> some View {
        let isDelete = kind == .delete
        let accent = isDelete ? Palette.magenta : Palette.cyan

        ZStack {
            Color(hex: 0x14110D, alpha: 0.45)
                .ignoresSafeArea()
                .onTapGesture { dismissConfirm() }

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: isDelete ? "trash.fill" : "power")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(accent)
                Text(isDelete ? "Elimina account" : "Esci dall'account")
                    .font(Typo.display(22)).foregroundStyle(Palette.textHi)
                Text(isDelete
                     ? "Il tuo account verrà disattivato e non potrai più accedere. Questa azione non è reversibile dall'app."
                     : "Verrai disconnesso da questo dispositivo. Potrai rientrare con le tue credenziali.")
                    .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    NeonButton(title: isDelete ? "Elimina definitivamente" : "Esci",
                               icon: isDelete ? "trash.fill" : "power",
                               color: accent, filled: true, loading: deleting) {
                        Task { await performConfirm(kind) }
                    }
                    NeonButton(title: "Annulla", color: Palette.cyan, filled: false) {
                        dismissConfirm()
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .voltPanel(accent.opacity(0.35))
            .padding(.horizontal, 28)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .zIndex(1)
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
