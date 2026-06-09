//
//  CoachProfileView.swift
//  "Profilo Coach" + "Impostazioni Coach" + "Modifica Profilo".
//  Reuses the shared settings/account endpoints (role-agnostic on the backend).
//

import SwiftUI

struct CoachProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var profile: CoachProfileDTO?
    @State private var settings: SettingsDTO?
    @State private var loading = true
    @State private var editing = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showAutoReplies = false
    @State private var deleting = false

    var body: some View {
        ScreenScroll {
            if let p = profile {
                header(p)
                if let bio = p.bio, !bio.isEmpty { bioCard(bio) }
                detailsCard(p)
                if hasSocials(p) { socialsCard(p) }
                if let s = settings { settingsCard(s) }
                accountCard
            } else if loading {
                CoachProfileSkeleton()
            } else {
                EmptyPanel(icon: "person.crop.circle.badge.exclamationmark", text: "Profilo non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "square.and.pencil") }
                    .tint(Palette.bronze)
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let p = profile {
                CoachEditProfileView(profile: p) { updated in profile = updated }
            }
        }
        .confirmationDialog("Vuoi uscire?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Esci", role: .destructive) { app.logout() }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Eliminare l'account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina definitivamente", role: .destructive) {
                deleting = true
                Task { await app.deleteAccount() }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il tuo account verrà disattivato e verrai disconnesso da tutti i dispositivi. Questa azione non è reversibile.")
        }
        .sheet(isPresented: $showAutoReplies) { CoachAutoMessagesView() }
    }

    private func header(_ p: CoachProfileDTO) -> some View {
        VStack(spacing: 12) {
            CoachClientAvatar(url: p.profileImageUrl, initials: p.initials, size: 100)
            Text(p.fullName).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            Text(p.roleLabel.uppercased()).font(Typo.mono(11, .bold)).tracking(3)
                .foregroundStyle(Palette.bronze)
            if let spec = p.specialization, !spec.isEmpty {
                Text(spec).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private func bioCard(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BIO").voltEyebrow()
            Text(bio).font(Typo.body(15)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }

    private func detailsCard(_ p: CoachProfileDTO) -> some View {
        VStack(spacing: 0) {
            detailRow("envelope.fill", "Email", p.email ?? "—")
            if let phone = p.phone, !phone.isEmpty { Divider().background(Palette.line); detailRow("phone.fill", "Telefono", phone) }
            if let city = p.city, !city.isEmpty { Divider().background(Palette.line); detailRow("mappin.circle.fill", "Città", city) }
            if let y = p.yearsExperience { Divider().background(Palette.line); detailRow("clock.fill", "Esperienza", "\(y) anni") }
            if let c = p.certifications, !c.isEmpty { Divider().background(Palette.line); detailRow("rosette", "Certificazioni", c) }
        }
        .padding(.horizontal, 16).padding(.vertical, 4).voltPanel()
    }

    private func detailRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.bronze).frame(width: 26)
            Text(label).font(Typo.body(14)).foregroundStyle(Palette.textMid)
            Spacer()
            Text(value).font(Typo.body(14, .medium)).foregroundStyle(Palette.textHi)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.vertical, 12)
    }

    private func socialsCard(_ p: CoachProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOCIAL").voltEyebrow()
            HStack(spacing: 12) {
                socialChip("Instagram", p.socialInstagram, Palette.phase)
                socialChip("YouTube", p.socialYoutube, Palette.bronze)
                socialChip("Web", p.socialWebsite, Palette.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).voltPanel()
    }

    @ViewBuilder private func socialChip(_ label: String, _ url: String?, _ accent: Color) -> some View {
        if let url, !url.isEmpty, let u = URL(string: url) {
            Link(destination: u) {
                Text(label).font(Typo.mono(11, .semibold)).foregroundStyle(accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(Capsule().stroke(accent, lineWidth: 1))
            }
        }
    }

    private func settingsCard(_ s: SettingsDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachSectionTitle(eyebrow: "Preferenze", title: "Notifiche email", accent: Palette.cyan)
            ForEach(s.notifications) { toggle in
                CoachToggleRow(toggle: toggle) { enabled in
                    Task {
                        if let updated = try? await APIClient.shared.updateSetting(key: toggle.key, enabled: enabled) {
                            settings = updated
                        }
                    }
                }
            }
        }
    }

    private var accountCard: some View {
        VStack(spacing: 12) {
            Button { Haptics.tap(); showAutoReplies = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.violet).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Risposte automatiche").font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                        Text("Messaggi inviati in automatico").font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textLow)
                }
                .padding(14).voltPanel()
            }
            .buttonStyle(PressableButtonStyle())

            NeonButton(title: "Esci", icon: "rectangle.portrait.and.arrow.right",
                       color: Palette.bronze, filled: false) { showLogoutConfirm = true }

            Button(role: .destructive) { Haptics.tap(); showDeleteConfirm = true } label: {
                HStack(spacing: 8) {
                    if deleting { ProgressView().tint(Palette.crimson) }
                    Image(systemName: "trash")
                    Text("Elimina account").font(Typo.body(14, .semibold))
                }
                .foregroundStyle(Palette.crimson)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.crimson.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(deleting)
        }
        .padding(.top, 8)
    }

    private func hasSocials(_ p: CoachProfileDTO) -> Bool {
        [p.socialInstagram, p.socialYoutube, p.socialWebsite].contains { ($0 ?? "").isEmpty == false }
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let prof = APIClient.shared.coachProfile()
        async let sett = APIClient.shared.settings()
        profile = try? await prof
        settings = try? await sett
    }
}

private struct CoachToggleRow: View {
    let toggle: SettingToggleDTO
    var onChange: (Bool) -> Void
    @State private var on: Bool

    init(toggle: SettingToggleDTO, onChange: @escaping (Bool) -> Void) {
        self.toggle = toggle; self.onChange = onChange
        _on = State(initialValue: toggle.enabled)
    }

    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toggle.label).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi)
                Text(toggle.desc).font(Typo.body(12)).foregroundStyle(Palette.textMid)
            }
        }
        .tint(Palette.bronze)
        .onChange(of: on) { _, v in Haptics.tap(); onChange(v) }
        .padding(14).voltPanel()
    }
}

// MARK: - Edit profile

struct CoachEditProfileView: View {
    let profile: CoachProfileDTO
    var onSave: (CoachProfileDTO) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var specialization: String
    @State private var city: String
    @State private var phone: String
    @State private var bio: String
    @State private var saving = false

    init(profile: CoachProfileDTO, onSave: @escaping (CoachProfileDTO) -> Void) {
        self.profile = profile; self.onSave = onSave
        _firstName = State(initialValue: profile.firstName)
        _lastName = State(initialValue: profile.lastName)
        _specialization = State(initialValue: profile.specialization ?? "")
        _city = State(initialValue: profile.city ?? "")
        _phone = State(initialValue: profile.phone ?? "")
        _bio = State(initialValue: profile.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    field("Nome", $firstName)
                    field("Cognome", $lastName)
                    field("Specializzazione", $specialization)
                    field("Città", $city)
                    field("Telefono", $phone)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BIO").voltEyebrow()
                        TextEditor(text: $bio)
                            .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                            .scrollContentBackground(.hidden).frame(minHeight: 100)
                            .padding(10).voltPanel(radius: 14)
                    }
                    NeonButton(title: "Salva", icon: "checkmark", color: Palette.bronze, loading: saving) {
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

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).voltEyebrow()
            TextField("", text: text).font(Typo.body(16)).foregroundStyle(Palette.textHi)
                .tint(Palette.bronze)
                .padding(.horizontal, 14).padding(.vertical, 13).voltPanel(radius: 12)
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let fields: [String: Any] = [
            "first_name": firstName, "last_name": lastName,
            "specialization": specialization, "city": city,
            "phone": phone, "bio": bio,
        ]
        if let updated = try? await APIClient.shared.coachUpdateProfile(fields) {
            Haptics.success(); onSave(updated); dismiss()
        } else { Haptics.error() }
    }
}
