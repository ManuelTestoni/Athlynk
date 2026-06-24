//
//  EditProfileView.swift
//  Stitch "Modifica Profilo": edit the athlete's own profile fields.
//  Reads GET /api/v1/profile and saves with PATCH /api/v1/profile.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""

    @State private var imageUrl: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarPreview: Data?
    @State private var uploadingPhoto = false

    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.amber, Palette.magenta, Palette.violet, Palette.amber])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        FormSkeleton(accent: Palette.amber, count: 6)
                    } else {
                        avatarPicker
                        if let error {
                            Text(error).font(Typo.body(13)).foregroundStyle(Palette.magenta)
                        }
                        field("Nome", text: $firstName)
                        field("Cognome", text: $lastName)
                        field("Telefono", text: $phone, keyboard: .phonePad)

                        NeonButton(title: saving ? "Salvataggio…" : "Salva modifiche",
                                   icon: "checkmark", color: Palette.amber, loading: saving) {
                            Task { await save() }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Modifica profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Palette.amber, Palette.magenta],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 104, height: 104)
                        .neonGlow(Palette.amber, radius: 10)
                    avatarImage
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                    if uploadingPhoto {
                        Circle().fill(Color(hex: 0x14110D, alpha: 0.45)).frame(width: 104, height: 104)
                        ProgressView().tint(Palette.void0)
                    }
                    // Camera badge
                    Circle().fill(Palette.void0).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .black)).foregroundStyle(Palette.amber))
                        .overlay(Circle().stroke(Palette.amber, lineWidth: 2))
                        .offset(x: 36, y: 36)
                }
            }
            .buttonStyle(.plain)
            .disabled(uploadingPhoto)

            Text("Tocca per cambiare foto")
                .font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await pickAndUpload(item) }
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let data = avatarPreview, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else if let imageUrl, let url = URL(string: imageUrl) {
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
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        avatarPreview = data
        uploadingPhoto = true
        error = nil
        do {
            let newUrl = try await APIClient.shared.uploadProfilePhoto(data)
            imageUrl = newUrl
            app.avatarUrl = newUrl
            Haptics.success()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
            avatarPreview = nil
        }
        uploadingPhoto = false
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            TextField("", text: text)
                .font(Typo.body(16)).foregroundStyle(Palette.textHi).tint(Palette.amber)
                .keyboardType(keyboard)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
        }
    }

    private func load() async {
        loading = true
        do {
            let p = try await APIClient.shared.profile()
            firstName = p.firstName
            lastName = p.lastName
            phone = p.phone ?? ""
            imageUrl = p.imageUrl
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true; error = nil
        let fields: [String: Any] = [
            "first_name": firstName,
            "last_name": lastName,
            "phone": phone,
        ]
        do {
            _ = try await APIClient.shared.updateProfile(fields)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
        saving = false
    }
}
