//
//  AppointmentDetailView.swift
//  Stitch "Dettaglio Appuntamento": full detail of a single appointment —
//  when, how long, where / meeting link, coach, status and notes.
//  Reuses AppointmentDTO from the agenda feed (no extra request).
//

import SwiftUI

struct AppointmentDetailView: View {
    let appointment: AppointmentDTO

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.cyan, Palette.violet, Palette.magenta, Palette.cyan])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    whenCard
                    infoCard
                    if let url = appointment.meetingUrl, let link = URL(string: url) { joinButton(link) }
                    if let desc = appointment.description, !desc.isEmpty { notesCard(desc) }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let t = appointment.type {
                    Text(t.uppercased()).font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.cyan)
                }
                Spacer()
                if let s = appointment.status { StatusBadge(text: s, color: Palette.cyan, filled: false) }
            }
            Text(appointment.title).font(Typo.poster(34)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.cyan).frame(height: 1).opacity(0.5)
        }
    }

    private var whenCard: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(dayNum(appointment.start)).font(Typo.poster(40)).foregroundStyle(Palette.cyan)
                Text(monthShort(appointment.start)).font(Typo.mono(10, .bold)).tracking(1)
                    .foregroundStyle(Palette.textLow)
            }
            .frame(width: 76).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.void2))
            VStack(alignment: .leading, spacing: 4) {
                Text(weekday(appointment.start)).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                Text(timeRange).font(Typo.mono(13, .semibold)).foregroundStyle(Palette.textMid)
            }
            Spacer()
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.4))
    }

    private var infoCard: some View {
        VStack(spacing: 10) {
            if let d = appointment.durationMinutes { infoRow("Durata", "\(d) min", "clock") }
            if let loc = appointment.location, !loc.isEmpty { infoRow("Luogo", loc, "mappin.and.ellipse") }
            if let coach = appointment.coach { infoRow("Coach", coach.fullName, "person.fill") }
        }
        .padding(18).voltPanel(Palette.violet.opacity(0.3))
    }

    private func infoRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .black)).foregroundStyle(Palette.cyan)
                .frame(width: 24)
            Text(label.uppercased()).font(Typo.mono(10, .bold)).tracking(1).foregroundStyle(Palette.textLow)
            Spacer()
            Text(value).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                .multilineTextAlignment(.trailing)
        }
    }

    private func joinButton(_ link: URL) -> some View {
        Link(destination: link) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                Text("Partecipa alla call").font(Typo.body(16, .semibold))
            }
            .foregroundStyle(Palette.void0)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Capsule().fill(Palette.cyan))
        }
    }

    private func notesCard(_ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE").voltEyebrow()
            Text(desc).font(Typo.body(14)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).voltPanel(Palette.cyan.opacity(0.3))
    }

    // MARK: Date helpers
    private func parse(_ iso: String?) -> Date? { iso.flatMap(ISO8601.parse) }
    private func dayNum(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private func monthShort(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "MMM"
        return f.string(from: d).uppercased()
    }
    private func weekday(_ iso: String?) -> String {
        guard let d = parse(iso) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
    }
    private var timeRange: String {
        guard let s = parse(appointment.start) else { return "—" }
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        var out = t.string(from: s)
        if let e = parse(appointment.end) { out += " – \(t.string(from: e))" }
        return out
    }
}
