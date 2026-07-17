//
//  CoachPlanFormView.swift
//  Create/edit a subscription plan from the coach app — mirrors the web's
//  SubscriptionPlanForm (plan_form.html) via /api/v1/coach/subscription-plans.
//

import SwiftUI

struct CoachPlanFormView: View {
    /// nil = create a new plan; non-nil = edit this one.
    let existingPlan: CoachPlanSummary?
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var price: String
    @State private var currency: String
    @State private var planType: String
    @State private var kind: String
    @State private var durationDays: String
    @State private var billingInterval: String
    @State private var isActive: Bool
    @State private var saving = false
    @State private var deleting = false
    @State private var error: String?

    private static let planTypes = [
        ("mensile", "Mensile"), ("trimestrale", "Trimestrale"), ("semestrale", "Semestrale"),
        ("annuale", "Annuale"), ("una_tantum", "Una Tantum"),
    ]
    private static let kinds = [
        ("subscription", "Abbonamento ricorrente"), ("one_time", "Servizio/Add-on (pagamento singolo)"),
    ]
    private static let currencies = [("EUR", "Euro (€)"), ("GBP", "Sterlina (£)"), ("USD", "Dollaro USA ($)"), ("JPY", "Yen (¥)")]
    private static let billingIntervals = [
        ("mensile", "Mensile"), ("trimestrale", "Trimestrale"), ("semestrale", "Semestrale"), ("annuale", "Annuale"),
    ]

    init(existingPlan: CoachPlanSummary?, onSaved: @escaping () async -> Void) {
        self.existingPlan = existingPlan
        self.onSaved = onSaved
        _name = State(initialValue: existingPlan?.name ?? "")
        _description = State(initialValue: existingPlan?.description ?? "")
        _price = State(initialValue: existingPlan.map { String(format: "%.2f", $0.price) } ?? "")
        _currency = State(initialValue: existingPlan?.currency ?? "EUR")
        _planType = State(initialValue: existingPlan?.planType ?? "mensile")
        _kind = State(initialValue: existingPlan?.kind ?? "subscription")
        _durationDays = State(initialValue: existingPlan?.durationDays.map(String.init) ?? "")
        _billingInterval = State(initialValue: existingPlan?.billingInterval ?? "mensile")
        _isActive = State(initialValue: existingPlan?.isActive ?? true)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Double(price.replacingOccurrences(of: ",", with: ".")) != nil && !saving
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Offerta", title: existingPlan == nil ? "Crea piano" : "Modifica piano",
                             subtitle: "Visibile ai tuoi atleti nella sezione abbonamenti", accent: Palette.cyan)

                field("Nome") {
                    TextField("", text: $name, prompt: Text("Es. Piano Base").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan)
                }
                field("Descrizione") {
                    TextField("", text: $description, prompt: Text("Opzionale").foregroundStyle(Palette.textLow), axis: .vertical)
                        .font(Typo.body(15)).tint(Palette.cyan).lineLimit(3...6)
                }
                HStack(spacing: 12) {
                    field("Prezzo") {
                        TextField("", text: $price, prompt: Text("29.99").foregroundStyle(Palette.textLow))
                            .font(Typo.body(15)).tint(Palette.cyan).keyboardType(.decimalPad)
                    }
                    field("Valuta") {
                        Picker("", selection: $currency) {
                            ForEach(Self.currencies, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.menu).tint(Palette.cyan)
                    }
                }
                field("Tipo") {
                    Picker("", selection: $kind) {
                        ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.menu).tint(Palette.cyan).frame(maxWidth: .infinity, alignment: .leading)
                }
                field("Durata") {
                    Picker("", selection: $planType) {
                        ForEach(Self.planTypes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.menu).tint(Palette.cyan).frame(maxWidth: .infinity, alignment: .leading)
                }
                field("Durata in giorni") {
                    TextField("", text: $durationDays, prompt: Text("Es. 30 per mensile, 90 per trimestrale").foregroundStyle(Palette.textLow))
                        .font(Typo.body(15)).tint(Palette.cyan).keyboardType(.numberPad)
                }
                if kind == "subscription" {
                    field("Intervallo di rinnovo") {
                        Picker("", selection: $billingInterval) {
                            ForEach(Self.billingIntervals, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .pickerStyle(.menu).tint(Palette.cyan).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                field("Visibile") {
                    Toggle(isActive ? "Attivo" : "Disattivato", isOn: $isActive)
                        .font(Typo.body(14)).tint(Palette.cyan)
                }

                if let error {
                    Text(error).font(Typo.body(13)).foregroundStyle(Palette.amber)
                }

                NeonButton(title: saving ? "Salvataggio…" : "Salva piano", icon: "checkmark.circle.fill",
                           color: Palette.cyan) {
                    Task { await save() }
                }
                .disabled(!canSave)
                .padding(.top, 6)

                if existingPlan != nil {
                    NeonButton(title: deleting ? "Eliminazione…" : "Elimina piano", icon: "trash",
                               color: Palette.danger) {
                        Task { await delete() }
                    }
                    .disabled(deleting || saving)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
            content()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .voltPanel(radius: 14)
        }
    }

    private func save() async {
        guard let priceValue = Double(price.replacingOccurrences(of: ",", with: ".")) else { return }
        saving = true; defer { saving = false }
        error = nil
        let body: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "description": description,
            "price": priceValue,
            "currency": currency,
            "plan_type": planType,
            "kind": kind,
            "billing_interval": kind == "subscription" ? billingInterval : NSNull(),
            "duration_days": Int(durationDays) ?? NSNull(),
            "is_active": isActive,
        ]
        do {
            if let existingPlan {
                _ = try await APIClient.shared.coachUpdatePlan(id: existingPlan.id, body)
            } else {
                _ = try await APIClient.shared.coachCreatePlan(body)
            }
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Impossibile salvare il piano. Riprova."
        }
    }

    private func delete() async {
        guard let existingPlan else { return }
        deleting = true; defer { deleting = false }
        error = nil
        do {
            try await APIClient.shared.coachDeletePlan(id: existingPlan.id)
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Impossibile eliminare il piano."
        }
    }
}
