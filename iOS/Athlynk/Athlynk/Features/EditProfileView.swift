//
//  EditProfileView.swift
//  Stitch "Modifica Profilo": edit the athlete's own profile fields.
//  Reads GET /api/v1/profile and saves with PATCH /api/v1/profile.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var heightCm = ""
    @State private var goal = ""
    @State private var activity = ""

    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.amber, Palette.magenta, Palette.violet, Palette.amber])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        LoadingPanel(text: "Carico il profilo…")
                    } else {
                        if let error {
                            Text(error).font(Typo.body(13)).foregroundStyle(Palette.magenta)
                        }
                        field("Nome", text: $firstName)
                        field("Cognome", text: $lastName)
                        field("Telefono", text: $phone, keyboard: .phonePad)
                        field("Altezza (cm)", text: $heightCm, keyboard: .numberPad)
                        field("Obiettivo", text: $goal)
                        field("Livello attività", text: $activity)

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
            heightCm = p.heightCm.map { "\($0)" } ?? ""
            goal = p.primaryGoal ?? ""
            activity = p.activityLevel ?? ""
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true; error = nil
        var fields: [String: Any] = [
            "first_name": firstName,
            "last_name": lastName,
            "phone": phone,
            "primary_goal": goal,
            "activity_level": activity,
        ]
        fields["height_cm"] = Int(heightCm.trimmingCharacters(in: .whitespaces)) ?? ""
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
