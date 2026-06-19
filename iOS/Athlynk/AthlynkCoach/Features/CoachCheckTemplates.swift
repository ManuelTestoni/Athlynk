//
//  CoachCheckTemplates.swift
//  Gestione modelli check lato coach (parità con la web app): lista modelli,
//  builder a blocchi, assegnazione, compilazione per atleta e modifica valori.
//

import SwiftUI

struct CheckTemplateRoute: Hashable { let id: Int }

// MARK: - Sezione "I tuoi modelli" (mostrata in CoachChecksView)

struct CoachCheckTemplatesSection: View {
    @State private var presets: [CoachCheckTemplate] = []
    @State private var customs: [CoachCheckTemplate] = []
    @State private var loading = true
    @State private var showBuilder = false
    @State private var reloadToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CoachSectionTitle(eyebrow: "Libreria", title: "I tuoi modelli", accent: Palette.violet)
                Spacer()
                Button { showBuilder = true } label: {
                    Label("Nuovo", systemImage: "plus")
                        .font(Typo.mono(10, .bold)).tracking(1)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Palette.violet))
                        .foregroundStyle(Palette.void0)
                }
                .buttonStyle(.plain)
            }

            if loading && presets.isEmpty && customs.isEmpty {
                AvatarRowsSkeleton(accent: Palette.violet)
            } else {
                if !presets.isEmpty {
                    Text("PRESET").font(Typo.mono(9, .bold)).tracking(2).foregroundStyle(Palette.textLow)
                    ForEach(presets) { t in row(t) }
                }
                if !customs.isEmpty {
                    Text("PERSONALIZZATI").font(Typo.mono(9, .bold)).tracking(2)
                        .foregroundStyle(Palette.textLow).padding(.top, 4)
                    ForEach(customs) { t in row(t) }
                } else if !loading {
                    Text("Nessun modello personalizzato. Creane uno nuovo.")
                        .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                }
            }
        }
        .task(id: reloadToken) {
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await load()
        }
        .sheet(isPresented: $showBuilder) {
            CoachCheckBuilderView(templateId: nil) { presets = []; customs = []; reloadToken += 1 }
        }
    }

    private func row(_ t: CoachCheckTemplate) -> some View {
        NavigationLink(value: CheckTemplateRoute(id: t.id)) {
            HStack(spacing: 12) {
                Image(systemName: t.isPreset ? "square.stack.3d.up.fill" : "doc.text.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.violet).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                    Text("\(t.questionsCount) domande · \(t.stepsCount) step")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                }
                Spacer()
                if t.isPreset && t.isModifiedPreset {
                    StatusBadge(text: "Modificato", color: Palette.amber, filled: false)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textLow)
            }
            .padding(14).voltPanel()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func load() async {
        guard presets.isEmpty && customs.isEmpty else { return }
        loading = true; defer { loading = false }
        if let res = try? await APIClient.shared.coachCheckTemplates() {
            presets = res.presets; customs = res.customs
        }
    }
}

// MARK: - Dettaglio modello + azioni

struct CoachCheckTemplateDetailView: View {
    let templateId: Int
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()
    @State private var detail: CoachCheckTemplateDetail?
    @State private var loading = true
    @State private var showBuilder = false
    @State private var showAssign = false
    @State private var showFill = false

    var body: some View {
        ScreenScroll {
            if let d = detail {
                ScreenHeader(eyebrow: d.isPreset ? "Preset" : "Modello", title: d.title,
                             subtitle: "\(d.questions.count) domande · \(d.steps.count) step", accent: Palette.violet)

                actions(d)

                CoachSectionTitle(eyebrow: "Anteprima", title: "Domande", accent: Palette.cyan)
                ForEach(Array(d.questions.enumerated()), id: \.offset) { _, q in
                    previewRow(q)
                }
            } else if loading {
                CoachClientDetailSkeleton()
            } else {
                EmptyPanel(icon: "doc.questionmark", text: "Modello non disponibile.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .statusOverlay(flash)
        .onAppear { app.tabBarHidden = true }
        .onDisappear { app.tabBarHidden = false }
        .task { await load() }
        .sheet(isPresented: $showBuilder) {
            CoachCheckBuilderView(templateId: templateId) { Task { await load() } }
        }
        .sheet(isPresented: $showAssign) {
            if let d = detail { CoachAssignCheckView(template: d) { flash.success("Check assegnato") } }
        }
        .sheet(isPresented: $showFill) {
            if let d = detail {
                CoachCheckFormView(mode: .fill(templateId: d.id), title: d.title,
                                   questions: d.questions, steps: d.steps) {
                    flash.success("Check compilato")
                }
            }
        }
    }

    @ViewBuilder private func actions(_ d: CoachCheckTemplateDetail) -> some View {
        VStack(spacing: 10) {
            NeonButton(title: "Assegna a un atleta", icon: "paperplane.fill", color: Palette.cyan) {
                showAssign = true
            }
            NeonButton(title: "Compila per un atleta", icon: "square.and.pencil", color: Palette.lime) {
                showFill = true
            }
            HStack(spacing: 10) {
                secondary("Modifica", "slider.horizontal.3") { showBuilder = true }
                secondary("Duplica", "doc.on.doc") { Task { await duplicate() } }
            }
            HStack(spacing: 10) {
                if d.isPreset {
                    secondary("Ripristina", "arrow.counterclockwise") { Task { await restore() } }
                } else {
                    secondary("Elimina", "trash", tint: Palette.amber) { Task { await remove() } }
                }
            }
        }
    }

    private func secondary(_ title: String, _ icon: String, tint: Color = Palette.textMid,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Typo.body(13, .semibold)).foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func previewRow(_ q: CheckQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(blockLabel(q.type)).font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.violet)
            Text(q.label).font(Typo.body(14)).foregroundStyle(Palette.textHi)
            if q.type == "antropometria" {
                Text(antroSummary(q)).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).voltPanel(radius: 12)
    }

    private func antroSummary(_ q: CheckQuestion) -> String {
        var parts: [String] = []
        if q.weight { parts.append("Peso") }
        if !q.circumferences.isEmpty { parts.append("\(q.circumferences.count) circ.") }
        if !q.skinfolds.isEmpty { parts.append("\(q.skinfolds.count) pliche") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        loading = true; defer { loading = false }
        detail = try? await APIClient.shared.coachCheckTemplate(id: templateId)
    }

    private func duplicate() async {
        do { try await APIClient.shared.coachDuplicateCheckTemplate(id: templateId)
            Haptics.success(); flash.success("Modello duplicato") }
        catch { flash.failure("Duplica non riuscita") }
    }
    private func restore() async {
        do { try await APIClient.shared.coachRestoreCheckTemplate(id: templateId)
            Haptics.success(); flash.success("Preset ripristinato"); await load() }
        catch { flash.failure("Ripristino non riuscito") }
    }
    private func remove() async {
        do { try await APIClient.shared.coachDeleteCheckTemplate(id: templateId)
            Haptics.success(); dismiss() }
        catch { flash.failure("Eliminazione non riuscita") }
    }
}

func blockLabel(_ type: String) -> String {
    switch type {
    case "antropometria": return "ANTROPOMETRIA"
    case "media": return "SCALA"
    case "si_no": return "SÌ / NO"
    case "radio": return "SCELTA SINGOLA"
    case "checkbox": return "SCELTA MULTIPLA"
    case "aperta": return "DOMANDA APERTA"
    case "allegato": return "ALLEGATO"
    case "metrica": return "METRICA"
    default: return type.uppercased()
    }
}
