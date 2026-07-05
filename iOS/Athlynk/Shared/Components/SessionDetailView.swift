//
//  SessionDetailView.swift
//  Shared read-only detail of a past training session: prescribed vs logged
//  sets per exercise. Used by both the athlete app and the coach app — the
//  caller passes the accent colour and a loader for the right endpoint.
//

import SwiftUI

struct SessionDetailView: View {
    let accent: Color
    let load: () async throws -> SessionDetailDTO

    @State private var data: SessionDetailDTO?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView().tint(accent).frame(maxWidth: .infinity).padding(.top, 60)
                } else if let error {
                    EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                } else if let d = data {
                    header(d)
                    if d.exercises.isEmpty {
                        EmptyPanel(icon: "dumbbell",
                                   text: "Nessuna serie registrata in questa sessione.", color: accent)
                    } else {
                        ForEach(d.exercises) { exerciseCard($0) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
        }
        .navigationTitle("Sessione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await reload() }
    }

    private func reload() async {
        loading = true; error = nil
        do { data = try await load() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    // MARK: Header

    private func header(_ d: SessionDetailDTO) -> some View {
        let statusColor = d.completed ? Palette.lime : (d.interrupted ? Palette.amber : Palette.textLow)
        return VStack(alignment: .leading, spacing: 10) {
            Text(d.dayName ?? "Sessione").font(Typo.display(22)).foregroundStyle(Palette.textHi)
            Text(prettyDate(d.startedAt)).font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
            HStack(spacing: 16) {
                if let m = d.durationMinutes { metric("timer", "\(m) min") }
                if let r = d.avgRpe { metric("flame.fill", String(format: "RPE %.1f", r)) }
                metric(d.completed ? "checkmark.seal.fill" : (d.interrupted ? "exclamationmark.triangle.fill" : "circle"),
                       d.completed ? "Completata" : (d.interrupted ? "Interrotta" : "In corso"))
                    .foregroundStyle(statusColor)
            }
            if let n = d.notes, !n.isEmpty {
                Text("« \(n) »").font(Typo.body(13)).italic().foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).voltPanel(accent.opacity(0.4))
    }

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(Typo.mono(11, .semibold))
        }
        .foregroundStyle(Palette.textMid)
    }

    // MARK: Exercise card

    private func exerciseCard(_ ex: SessionLoggedExerciseDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ex.performedName).font(Typo.display(17)).foregroundStyle(Palette.textHi)
                    if ex.added {
                        Text("AGGIUNTO").font(Typo.mono(8, .bold)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.primary))
                            .foregroundStyle(Palette.void0)
                    }
                    if ex.wasSubstituted {
                        Text("SOSTITUITO").font(Typo.mono(8, .bold)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.control))
                            .foregroundStyle(Palette.void0)
                    }
                }
                if ex.wasSubstituted {
                    Text(ex.exerciseName)
                        .font(Typo.body(11)).strikethrough().foregroundStyle(Palette.textLow)
                }
                if let p = ex.prescribedReps, !p.isEmpty {
                    Text("Prescritto: \(p)").font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(accent)
                }
            }
            if let note = ex.exerciseNote, !note.isEmpty {
                Text(note).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Column header
            HStack(spacing: 8) {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("REPS").frame(maxWidth: .infinity, alignment: .leading)
                Text("CARICO").frame(maxWidth: .infinity, alignment: .leading)
                Text("RPE").frame(width: 44, alignment: .leading)
            }
            .font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)

            ForEach(ex.sets) { s in
                HStack(spacing: 8) {
                    Text("\(s.setNumber)").font(Typo.mono(13, .black)).foregroundStyle(accent)
                        .frame(width: 34, alignment: .leading)
                    Text(s.repsDone.map { "\($0)" } ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(loadText(s)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.rpe.map { "\($0)" } ?? "—").frame(width: 44, alignment: .leading)
                }
                .font(Typo.body(14)).foregroundStyle(Palette.textHi)
                .opacity(s.completed ? 1 : 0.45)
            }
        }
        .padding(16).voltPanel(accent.opacity(0.35))
    }

    private func loadText(_ s: LoggedSetDetailDTO) -> String {
        guard let l = s.loadUsed else { return "—" }
        let num = l == l.rounded() ? String(Int(l)) : String(format: "%.1f", l)
        let unit = (s.loadUnit == "KG" || s.loadUnit == nil) ? " kg" : ""
        return num + unit
    }

    private func prettyDate(_ iso: String?) -> String {
        guard let iso, let d = Self.parseISO(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM yyyy · HH:mm"
        return f.string(from: d).capitalized
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
