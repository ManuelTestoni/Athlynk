//
//  AthleteProfileView.swift
//  "Profilo & Impostazioni" dell'atleta — un'unica schermata (come il coach):
//  identità + dati di contatto, notifiche email, legale, account. Il pulsante
//  a matita in alto apre la modifica dei campi come sheet.
//  Reads GET /api/v1/profile + /api/v1/settings, saves via PATCH /api/v1/profile.
//

import SwiftUI
import PhotosUI

struct AthleteProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var profile: ClientProfileDTO?
    @State private var settings: SettingsDTO?
    @State private var loading = true
    @State private var editing = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var appear = false

    var body: some View {
        ZStack {
            ScreenScroll {
                if let p = profile {
                    header(p).revealUp(appear, index: 0)
                    detailsCard(p).revealUp(appear, index: 1)
                    if let s = settings { settingsCard(s).revealUp(appear, index: 2) }
                    LegalLinks(accent: Palette.amber).revealUp(appear, index: 3)
                    accountCard.revealUp(appear, index: 4)
                } else if loading {
                    FormSkeleton(accent: Palette.amber, count: 6)
                } else {
                    EmptyPanel(icon: "person.crop.circle.badge.exclamationmark", text: "Profilo non disponibile.")
                }
            }

            if showLogoutConfirm {
                ConfirmDialogCard(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Esci dall'account",
                    message: "Verrai disconnesso da questo dispositivo. Potrai rientrare con le tue credenziali.",
                    confirmTitle: "Esci",
                    accent: Palette.control,
                    onConfirm: { app.logout() },
                    onCancel: { dismissConfirms() }
                )
            }
            if showDeleteConfirm {
                ConfirmDialogCard(
                    icon: "trash",
                    title: "Elimina account",
                    message: "Il tuo account verrà disattivato e non potrai più accedere. Questa azione non è reversibile dall'app.",
                    confirmTitle: "Elimina definitivamente",
                    accent: Palette.danger,
                    loading: deleting,
                    onConfirm: {
                        deleting = true
                        Task { await app.deleteAccount() }
                    },
                    onCancel: { dismissConfirms() }
                )
            }
        }
        .navigationTitle("Profilo & Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "square.and.pencil") }
                    .tint(Palette.amber)
            }
        }
        .onChange(of: loading) { _, l in if !l { appear = true } }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let p = profile {
                AthleteEditProfileView(profile: p) { updated in profile = updated }
            }
        }
    }

    private func dismissConfirms() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showLogoutConfirm = false; showDeleteConfirm = false
        }
    }

    private func header(_ p: ClientProfileDTO) -> some View {
        VStack(spacing: 12) {
            AvatarView(url: p.imageUrl, initials: initials(p), size: 100, initialsSize: 34)
            Text("\(p.firstName) \(p.lastName)").font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            Text((app.user?.role ?? "ATLETA").uppercased()).font(Typo.mono(11, .bold)).tracking(3)
                .foregroundStyle(Palette.amber)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private func detailsCard(_ p: ClientProfileDTO) -> some View {
        VStack(spacing: 0) {
            detailRow("envelope.fill", "Email", app.user?.email ?? "—")
            if let phone = p.phone, !phone.isEmpty { Divider().background(Palette.line); detailRow("phone.fill", "Telefono", phone) }
            if let sport = p.sport, !sport.isEmpty { Divider().background(Palette.line); detailRow("figure.run", "Sport", sport) }
            if let w = p.weightKg { Divider().background(Palette.line); detailRow("scalemass.fill", "Peso", "\(w.formatted()) kg") }
        }
        .padding(.horizontal, 16).padding(.vertical, 4).voltPanel()
    }

    private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.amber).frame(width: 26)
            Text(label).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            Spacer()
            Text(value).font(Typo.body(14, .medium)).foregroundStyle(Palette.textHi)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.vertical, 12)
    }

    private func settingsCard(_ s: SettingsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICHE EMAIL").voltEyebrow().padding(.top, 4)
            ForEach(s.notifications) { toggle in
                SettingsToggleRow(label: toggle.label, desc: toggle.desc, isOn: Binding(
                    get: {
                        settings?.notifications.first(where: { $0.key == toggle.key })?.enabled ?? toggle.enabled
                    },
                    set: { enabled in
                        Haptics.tap()
                        Task {
                            if let updated = try? await APIClient.shared.updateSetting(key: toggle.key, enabled: enabled) {
                                settings = updated
                            }
                        }
                    }
                ))
            }
        }
    }

    private var accountCard: some View {
        AccountActions(
            onLogout: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showLogoutConfirm = true } },
            onDelete: { withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showDeleteConfirm = true } }
        )
        .padding(.top, 8)
    }

    private func initials(_ p: ClientProfileDTO) -> String {
        let f = p.firstName.first.map(String.init) ?? ""
        let l = p.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "A" : s
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let prof = APIClient.shared.profile()
        async let sett = APIClient.shared.settings()
        profile = try? await prof
        settings = try? await sett
    }
}

// MARK: - Edit profile (sheet)

struct AthleteEditProfileView: View {
    let profile: ClientProfileDTO
    var onSave: (ClientProfileDTO) -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var phone: String
    @State private var saving = false
    @State private var error: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarPreview: Data?
    @State private var uploadingPhoto = false
    @State private var photoError: String?

    init(profile: ClientProfileDTO, onSave: @escaping (ClientProfileDTO) -> Void) {
        self.profile = profile; self.onSave = onSave
        _firstName = State(initialValue: profile.firstName)
        _lastName = State(initialValue: profile.lastName)
        _phone = State(initialValue: profile.phone ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    avatarPicker
                    if let photoError {
                        Text(photoError).font(Typo.body(13)).foregroundStyle(Palette.amber)
                    }
                    if let error {
                        Text(error).font(Typo.body(13)).foregroundStyle(Palette.danger)
                    }
                    field("Nome", $firstName)
                    field("Cognome", $lastName)
                    field("Telefono", $phone, keyboard: .phonePad)
                    NeonButton(title: "Salva", icon: "checkmark", color: Palette.amber, loading: saving) {
                        Task { await save() }
                    }
                }
                .padding(20)
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Modifica profilo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
        }
    }

    private var avatarPicker: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(Palette.amber)
                        .frame(width: 104, height: 104)
                        .neonGlow(Palette.amber, radius: 10)
                    avatarImage
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                    if uploadingPhoto {
                        Circle().fill(Color(hex: 0x14110D, alpha: 0.45)).frame(width: 104, height: 104)
                        ProgressView().tint(Palette.void0)
                    }
                    Circle().fill(Palette.void0).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .black)).foregroundStyle(Palette.amber))
                        .overlay(Circle().stroke(Palette.amber, lineWidth: 2))
                        .offset(x: 36, y: 36)
                }
            }
            .buttonStyle(.plain)
            .disabled(uploadingPhoto)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await pickAndUpload(item) }
            }
            Text("Tocca per cambiare foto")
                .font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var avatarImage: some View {
        if let data = avatarPreview, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else if let url = profile.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { avatarInitials }
            }
        } else {
            avatarInitials
        }
    }

    private var avatarInitials: some View {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return Text(s.isEmpty ? "A" : s)
            .font(Typo.poster(38)).foregroundStyle(Palette.void0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickAndUpload(_ item: PhotosPickerItem) async {
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: raw),
              let jpeg = ui.jpegData(compressionQuality: 0.85) else {
            photoError = "Immagine non valida."
            return
        }
        avatarPreview = raw
        uploadingPhoto = true
        photoError = nil
        do {
            let newUrl = try await APIClient.shared.uploadProfilePhoto(jpeg)
            app.avatarUrl = newUrl
            Haptics.success()
        } catch {
            Haptics.error()
            photoError = error.localizedDescription
            avatarPreview = nil
        }
        uploadingPhoto = false
    }

    private func field(_ label: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).voltEyebrow()
            TextField("", text: text).font(Typo.body(16)).foregroundStyle(Palette.textHi)
                .tint(Palette.amber).keyboardType(keyboard)
                .padding(.horizontal, 14).padding(.vertical, 13).voltPanel(radius: 12)
        }
    }

    private func save() async {
        saving = true; error = nil
        let fields: [String: Any] = [
            "first_name": firstName, "last_name": lastName, "phone": phone,
        ]
        do {
            let updated = try await APIClient.shared.updateProfile(fields)
            Haptics.success(); onSave(updated); dismiss()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
        saving = false
    }
}
