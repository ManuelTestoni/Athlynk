//
//  JourneyView.swift
//  "Il mio percorso": the athlete's timeline of assigned plans, diets and
//  completed checks, newest first, as a scrollable animated vertical rail with
//  type filters. Backed by GET /api/v1/journey.
//

import SwiftUI

struct JourneyView: View {
    @State private var events: [JourneyEventDTO] = []
    @State private var phases: [JourneyPhaseDTO] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var filter: String?      // nil = all
    @State private var appear = false

    /// A timeline row is either an assigned event or a coach phase. Phases are
    /// placed on the rail at their start date.
    private enum Item: Identifiable {
        case event(JourneyEventDTO)
        case phase(JourneyPhaseDTO)
        var id: String {
            switch self {
            case .event(let e): return "e-\(e.id)"
            case .phase(let p): return "p-\(p.id)"
            }
        }
        var date: String {
            switch self {
            case .event(let e): return e.date
            case .phase(let p): return p.start
            }
        }
    }

    private struct Meta { let icon: String; let label: String; let color: Color }
    private func meta(_ type: String) -> Meta {
        switch type {
        case "allenamento": return Meta(icon: "dumbbell.fill", label: "Allenamento", color: Palette.magenta)
        case "nutrizione":  return Meta(icon: "leaf.fill", label: "Nutrizione", color: Palette.lime)
        case "check":       return Meta(icon: "chart.xyaxis.line", label: "Check", color: Palette.cyan)
        default:            return Meta(icon: "circle.fill", label: type.capitalized, color: Palette.bronze)
        }
    }

    /// Newest first, filtered. Events and phases merged onto one rail.
    private var shown: [Item] {
        var items: [Item] = []
        if filter == nil || filter == "fase" {
            items += phases.map { Item.phase($0) }
        }
        if filter == nil {
            items += events.map { Item.event($0) }
        } else if filter != "fase" {
            items += events.filter { $0.type == filter }.map { Item.event($0) }
        }
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.bronze, Palette.violet, Palette.cyan, Palette.bronze])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !events.isEmpty || !phases.isEmpty { filters }

                    if loading {
                        TimelineSkeleton(accent: Palette.bronze, count: 4, railWidth: 44)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if shown.isEmpty {
                        EmptyPanel(icon: "map", text: filter == nil
                                   ? "Il tuo percorso apparirà qui.\nPiani, diete e check assegnati."
                                   : "Nessun evento di questo tipo.", color: Palette.bronze)
                    } else {
                        timeline
                        if hasMore && filter != "fase" {
                            LoadMoreButton(loading: loadingMore, accent: Palette.bronze) { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 44)
            }
        }
        .navigationTitle("Il mio percorso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appear = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PANORAMICA").voltEyebrow()
            Text("Il tuo\npercorso").font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, "Tutto", "square.grid.2x2.fill", Palette.bronze)
                filterChip("allenamento", "Allenamento", "dumbbell.fill", Palette.magenta)
                filterChip("nutrizione", "Nutrizione", "leaf.fill", Palette.lime)
                filterChip("check", "Check", "chart.xyaxis.line", Palette.cyan)
                if !phases.isEmpty {
                    filterChip("fase", "Fasi", "flag.fill", Palette.phase)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ value: String?, _ label: String, _ icon: String, _ color: Color) -> some View {
        let on = filter == value
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .black))
                Text(label).font(Typo.body(13, .semibold))
            }
            .foregroundStyle(on ? Palette.void0 : Palette.textHi)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(on ? color : Palette.void1))
            .overlay(Capsule().stroke(on ? .clear : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var timeline: some View {
        let items = shown
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let prevMonth = i > 0 ? monthKey(items[i - 1].date) : ""
                let showMonth = i == 0 || monthKey(item.date) != prevMonth
                if showMonth {
                    monthLabel(item.date).revealUp(appear, index: min(i, 8))
                }
                Group {
                    switch item {
                    case .event(let ev):
                        row(ev, isFirst: i == 0, isLast: i == items.count - 1)
                    case .phase(let ph):
                        phaseRow(ph, isFirst: i == 0, isLast: i == items.count - 1)
                    }
                }
                .revealUp(appear, index: min(i + 1, 9))
            }
        }
    }

    private func monthLabel(_ iso: String) -> some View {
        HStack(spacing: 10) {
            Text(monthTitle(iso)).font(Typo.mono(11, .bold)).tracking(2).foregroundStyle(Palette.bronze)
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        .padding(.leading, 56).padding(.top, 14).padding(.bottom, 6)
    }

    private func row(_ ev: JourneyEventDTO, isFirst: Bool, isLast: Bool) -> some View {
        let m = meta(ev.type)
        return HStack(alignment: .top, spacing: 0) {
            // Rail + node
            ZStack(alignment: .top) {
                Rectangle().fill(Palette.line).frame(width: 2)
                    .padding(.top, isFirst ? 26 : 0)
                    .padding(.bottom, isLast ? 0 : -100)   // bleed into next row
                Circle().fill(m.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Palette.void0, lineWidth: 3))
                    .overlay(Circle().fill(m.color).frame(width: 14, height: 14).blur(radius: 6).opacity(0.5))
                    .padding(.top, 20)
            }
            .frame(width: 44)

            // Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: m.icon).font(.system(size: 11, weight: .black)).foregroundStyle(m.color)
                    Text(m.label.uppercased()).font(Typo.mono(9, .bold)).tracking(1.5).foregroundStyle(m.color)
                    Spacer()
                    Text(dayTitle(ev.date)).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                }
                Text(ev.title).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let sub = ev.subtitle, !sub.isEmpty {
                        Text(sub).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                    }
                    Spacer()
                    if let st = ev.statusLabel, !st.isEmpty {
                        Text(st).font(Typo.mono(9, .bold)).foregroundStyle(m.color)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(m.color.opacity(0.14)))
                    }
                }
            }
            .padding(15).voltPanel(m.color.opacity(0.32))
            .padding(.bottom, 12)
        }
    }

    private func phaseRow(_ ph: JourneyPhaseDTO, isFirst: Bool, isLast: Bool) -> some View {
        let c = Palette.phase
        return HStack(alignment: .top, spacing: 0) {
            // Rail + flag node
            ZStack(alignment: .top) {
                Rectangle().fill(Palette.line).frame(width: 2)
                    .padding(.top, isFirst ? 26 : 0)
                    .padding(.bottom, isLast ? 0 : -100)
                Image(systemName: "flag.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.void0)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(c))
                    .overlay(Circle().stroke(Palette.void0, lineWidth: 3))
                    .overlay(Circle().fill(c).frame(width: 22, height: 22).blur(radius: 6).opacity(0.5))
                    .padding(.top, 16)
            }
            .frame(width: 44)

            // Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "flag.fill").font(.system(size: 11, weight: .black)).foregroundStyle(c)
                    Text("FASE").font(Typo.mono(9, .bold)).tracking(1.5).foregroundStyle(c)
                    Spacer()
                    Text(durationLabel(ph).uppercased()).font(Typo.mono(9, .bold)).foregroundStyle(c)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(c.opacity(0.14)))
                }
                Text(ph.title).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(dayTitle(ph.start)) → \(dayTitle(ph.end))")
                    .font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
                if !ph.note.isEmpty {
                    Text(ph.note).font(Typo.body(12)).foregroundStyle(Palette.textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .voltPanel(c.opacity(0.32))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(c.opacity(0.5), lineWidth: 1.5)
            )
            .padding(.bottom, 12)
        }
    }

    private func durationLabel(_ ph: JourneyPhaseDTO) -> String {
        if ph.durationUnit == "MONTHS" {
            return "\(ph.durationValue) \(ph.durationValue == 1 ? "mese" : "mesi")"
        }
        return "\(ph.durationValue) \(ph.durationValue == 1 ? "settimana" : "settimane")"
    }

    // MARK: Dates

    private func parse(_ iso: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: iso)
    }
    private func monthKey(_ iso: String) -> String { String(iso.prefix(7)) }
    private func monthTitle(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "MMMM yyyy"
        return f.string(from: d).uppercased()
    }
    private func dayTitle(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
        return f.string(from: d).uppercased()
    }

    private func load() async {
        loading = true; error = nil
        do {
            let r = try await APIClient.shared.journey(offset: 0)
            events = r.events; phases = r.phases; hasMore = r.hasMore
        }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let r = try await APIClient.shared.journey(offset: events.count)
            let known = Set(events.map(\.id))
            events.append(contentsOf: r.events.filter { !known.contains($0.id) })
            hasMore = r.hasMore
        } catch {
            print("JourneyView.loadMore failed: \(error.localizedDescription)")
        }
    }
}
