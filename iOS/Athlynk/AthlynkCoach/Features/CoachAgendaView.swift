//
//  CoachAgendaView.swift
//  "Agenda" — the coach's upcoming appointments, grouped by day.
//

import SwiftUI

struct CoachAgendaView: View {
    @State private var items: [CoachAgendaItem] = []
    @State private var loading = true
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(eyebrow: "Calendario", title: "Agenda",
                             subtitle: "I tuoi prossimi appuntamenti", accent: Palette.amber)

                Button { Haptics.tap(); creating = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 16, weight: .bold))
                        Text("Fissa appuntamento").font(Typo.body(15, .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Palette.amber)
                    .padding(16).voltPanel()
                }
                .buttonStyle(PressableButtonStyle())

                if loading && items.isEmpty {
                    LoadingPanel()
                } else if items.isEmpty {
                    EmptyPanel(icon: "calendar.badge.exclamationmark", text: "Nessun appuntamento in programma.")
                } else {
                    ForEach(grouped, id: \.0) { day, appts in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.uppercased()).font(Typo.mono(11, .bold)).tracking(2)
                                .foregroundStyle(Palette.bronze)
                            ForEach(appts) { a in row(a) }
                        }
                    }
                }
            }
            .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) {
                CoachNewAppointmentView()
            }
            .task { await load() }
            .onRemoteChange { Task { await load() } }
            .refreshable { await load() }
        }
    }

    private var grouped: [(String, [CoachAgendaItem])] {
        let groups = Dictionary(grouping: items) { CoachDate.dayMonth($0.start) }
        return groups.sorted {
            (CoachDate.parse($0.value.first?.start) ?? .distantFuture)
                < (CoachDate.parse($1.value.first?.start) ?? .distantFuture)
        }.map { ($0.key, $0.value) }
    }

    private func row(_ a: CoachAgendaItem) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(CoachDate.time(a.start)).font(Typo.mono(15, .bold)).foregroundStyle(Palette.textHi)
                if let m = a.durationMinutes {
                    Text("\(m)′").font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                }
            }
            .frame(width: 56)
            Rectangle().fill(Palette.amber).frame(width: 2).opacity(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.client?.displayName ?? a.title).font(Typo.body(16, .semibold))
                    .foregroundStyle(Palette.textHi)
                Text(a.title).font(Typo.body(13)).foregroundStyle(Palette.textMid).lineLimit(1)
                if let loc = a.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                } else if let url = a.meetingUrl, !url.isEmpty {
                    Label("Online", systemImage: "video.fill")
                        .font(Typo.mono(10)).foregroundStyle(Palette.cyan)
                }
            }
            Spacer()
        }
        .padding(14).voltPanel()
    }

    private func load() async {
        loading = true; defer { loading = false }
        items = (try? await APIClient.shared.coachAgenda()) ?? []
    }
}

// MARK: - Book a new appointment

private enum CoachApptType: String, CaseIterable, Identifiable {
    case visita, prima_visita, check, consulenza
    var id: String { rawValue }
    var label: String {
        switch self {
        case .visita: return "Visita"
        case .prima_visita: return "Prima visita"
        case .check: return "Check"
        case .consulenza: return "Consulenza"
        }
    }
    var isOnline: Bool { self == .consulenza }
}

struct CoachNewAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flash = StatusFlash()

    @State private var clients: [CoachClientRow] = []
    @State private var loading = true
    @State private var clientId: Int?
    @State private var title = ""
    @State private var type: CoachApptType = .visita
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
                                                     of: Date().addingTimeInterval(86400)) ?? Date()
    @State private var duration = 60
    @State private var meetingUrl = ""
    @State private var note = ""
    @State private var saving = false

    private var selectedClient: CoachClientRow? { clients.first { $0.id == clientId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    clientField
                    field("Titolo", $title, placeholder: type == .check ? "Es. Check settimanale" : "Es. Visita di controllo")

                    section("TIPO") {
                        Picker("", selection: $type) {
                            ForEach(CoachApptType.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    section("QUANDO") {
                        DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact).tint(Palette.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    section("DURATA") {
                        HStack {
                            Text("\(duration) minuti").font(Typo.body(16, .semibold)).foregroundStyle(Palette.textHi)
                            Spacer()
                            Stepper("", value: $duration, in: 15...240, step: 15).labelsHidden().tint(Palette.amber)
                        }
                    }

                    if type.isOnline {
                        field("Link riunione", $meetingUrl, placeholder: "https://…", keyboard: .URL)
                    }

                    section("NOTE (FACOLTATIVO)") {
                        TextEditor(text: $note)
                            .font(Typo.body(15)).foregroundStyle(Palette.textHi)
                            .scrollContentBackground(.hidden).frame(minHeight: 90)
                    }

                    NeonButton(title: "Fissa appuntamento", icon: "calendar.badge.plus",
                               color: Palette.amber, loading: saving) { Task { await save() } }
                }
                .padding(20)
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Nuovo appuntamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Chiudi") { dismiss() }.tint(Palette.textMid)
            } }
            .task { await load() }
            .statusOverlay(flash)
        }
    }

    private var clientField: some View {
        section("ATLETA") {
            if loading {
                ProgressView().tint(Palette.amber).frame(maxWidth: .infinity)
            } else if clients.isEmpty {
                Text("Nessun atleta disponibile.").font(Typo.body(13)).foregroundStyle(Palette.textMid)
            } else {
                Menu {
                    ForEach(clients) { c in
                        Button(c.displayName) { clientId = c.id }
                    }
                } label: {
                    HStack {
                        Text(selectedClient?.displayName ?? "Scegli atleta")
                            .font(Typo.body(16, selectedClient == nil ? .regular : .semibold))
                            .foregroundStyle(selectedClient == nil ? Palette.textLow : Palette.textHi)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.amber)
                    }
                }
            }
        }
    }

    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(Typo.mono(10, .semibold)).tracking(2).foregroundStyle(Palette.textMid)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12).voltPanel(radius: 12)
        }
    }

    private func field(_ label: String, _ text: Binding<String>, placeholder: String = "",
                       keyboard: UIKeyboardType = .default) -> some View {
        section(label.uppercased()) {
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.textLow))
                .font(Typo.body(16)).foregroundStyle(Palette.textHi).tint(Palette.amber)
                .keyboardType(keyboard).autocorrectionDisabled(keyboard == .URL)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        clients = ((try? await APIClient.shared.coachClients())?.clients) ?? []
        if clientId == nil { clientId = clients.first?.id }
    }

    private func save() async {
        guard let cid = clientId else { flash.failure("Scegli un atleta"); return }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            flash.failure("Inserisci un titolo"); return
        }
        saving = true; defer { saving = false }
        let iso = ISO8601DateFormatter().string(from: start)
        do {
            _ = try await APIClient.shared.coachCreateAppointment(
                clientId: cid, title: title, type: type.rawValue, startISO: iso,
                durationMinutes: duration,
                description: note.isEmpty ? nil : note,
                meetingUrl: type.isOnline && !meetingUrl.isEmpty ? meetingUrl : nil)
            flash.success("Appuntamento fissato")
            try? await Task.sleep(for: .seconds(1.1))
            dismiss()
        } catch {
            flash.failure(error.localizedDescription)
        }
    }
}
