//
//  BrandSettingsView.swift
//  "Aspetto" — per-user brand customization (name + primary/accent colors),
//  shared by both apps since the web settings tab is identical for CLIENT
//  and COACH. Native ColorPicker mirrors the web's <input type="color">.
//

import SwiftUI

struct BrandSettingsView: View {
    let accent: Color
    let onSave: (_ name: String, _ primary: String, _ accentHex: String) async throws -> Void
    let onReset: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var primary: Color
    @State private var accentColor: Color
    @State private var saving = false
    @State private var resetting = false
    @State private var error = ""

    init(brandName: String, brandPrimary: String, brandAccent: String, accent: Color,
         onSave: @escaping (_ name: String, _ primary: String, _ accentHex: String) async throws -> Void,
         onReset: @escaping () async throws -> Void) {
        self.accent = accent
        self.onSave = onSave
        self.onReset = onReset
        _name = State(initialValue: brandName)
        _primary = State(initialValue: Color(hexString: brandPrimary) ?? Palette.bronze)
        _accentColor = State(initialValue: Color(hexString: brandAccent) ?? Palette.control)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome brand", text: $name)
                }
                Section("Colori") {
                    ColorPicker("Primario", selection: $primary, supportsOpacity: false)
                    ColorPicker("Accento", selection: $accentColor, supportsOpacity: false)
                }
                if !error.isEmpty {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.danger)
                }
                Section {
                    Button(role: .destructive) {
                        Task { await reset() }
                    } label: {
                        HStack {
                            Text("Ripristina predefiniti")
                            if resetting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(resetting || saving)
                }
            }
            .navigationTitle("Aspetto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await save() } }
                        .disabled(saving || resetting)
                }
            }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        do {
            try await onSave(name.trimmingCharacters(in: .whitespaces), primary.hexString, accentColor.hexString)
            Haptics.success()
            dismiss()
        } catch {
            self.error = "Salvataggio non riuscito, riprova."
        }
    }

    private func reset() async {
        resetting = true; defer { resetting = false }
        do {
            try await onReset()
            Haptics.success()
            dismiss()
        } catch {
            self.error = "Ripristino non riuscito, riprova."
        }
    }
}
