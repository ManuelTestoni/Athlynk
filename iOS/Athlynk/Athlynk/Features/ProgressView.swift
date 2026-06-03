//
//  ProgressView.swift
//  Stitch "Grafici Progressi" + "Comparatore Foto": the athlete's submitted
//  check history — a bodyweight trend line, a before/after photo comparison,
//  and per-check coach feedback. Backed by GET /api/v1/progress.
//
//  Named ProgressTrackerView to avoid clashing with SwiftUI.ProgressView.
//

import SwiftUI

struct ProgressTrackerView: View {
    @State private var entries: [ProgressEntryDTO] = []
    @State private var loading = true
    @State private var error: String?

    /// Entries oldest → newest, used for the trend line and deltas.
    private var chrono: [ProgressEntryDTO] {
        entries.sorted { ($0.submittedAt ?? "") < ($1.submittedAt ?? "") }
    }
    private var weightPoints: [(date: Date, kg: Double)] {
        chrono.compactMap { e in
            guard let kg = e.weightKg, let iso = e.submittedAt, let d = ISO8601.parse(iso) else { return nil }
            return (d, kg)
        }
    }
    private var photoEntries: [ProgressEntryDTO] { chrono.filter { !$0.photos.isEmpty } }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.magenta, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        LoadingPanel(text: "Carico i progressi…")
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.violet)
                    } else if entries.isEmpty {
                        EmptyPanel(icon: "chart.xyaxis.line",
                                   text: "Nessun check completato.\nI tuoi progressi appariranno qui.")
                    } else {
                        if weightPoints.count >= 2 { weightCard }
                        if photoEntries.count >= 2 { comparatorCard }
                        Text("STORICO CHECK").voltEyebrow().padding(.top, 4)
                        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                            entryCard(e, index: i)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Progressi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: Weight trend

    private var weightCard: some View {
        let pts = weightPoints
        let kgs = pts.map(\.kg)
        let lo = kgs.min() ?? 0, hi = kgs.max() ?? 1
        let first = kgs.first ?? 0, last = kgs.last ?? 0
        let delta = last - first
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PESO CORPOREO").voltEyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", last)).font(Typo.poster(34))
                            .foregroundStyle(Palette.textHi)
                        Text("kg").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                    }
                }
                Spacer()
                deltaPill(delta)
            }
            sparkline(kgs, lo: lo, hi: hi)
                .frame(height: 90)
            HStack {
                Text(dateShort(pts.first?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                Spacer()
                Text(dateShort(pts.last?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
            }
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.4))
    }

    private func sparkline(_ values: [Double], lo: Double, hi: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let span = max(hi - lo, 0.0001)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(values.count - 1)
                let y = h - h * CGFloat((v - lo) / span)
                return CGPoint(x: x, y: y)
            }
            ZStack {
                // Fill under the line.
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: h))
                    p.addLine(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                    if let l = pts.last { p.addLine(to: CGPoint(x: l.x, y: h)) }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Palette.cyan.opacity(0.28), .clear],
                                     startPoint: .top, endPoint: .bottom))
                // Line.
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Palette.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // Last node.
                if let l = pts.last {
                    Circle().fill(Palette.cyan).frame(width: 9, height: 9)
                        .position(l).neonGlow(Palette.cyan, radius: 5)
                }
            }
        }
    }

    private func deltaPill(_ delta: Double) -> some View {
        let up = delta > 0.05, down = delta < -0.05
        let color = down ? Palette.lime : (up ? Palette.amber : Palette.textLow)
        let icon = down ? "arrow.down.right" : (up ? "arrow.up.right" : "arrow.right")
        return HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .black))
            Text(String(format: "%+.1f kg", delta)).font(Typo.mono(12, .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: Photo comparator

    private var comparatorCard: some View {
        let before = photoEntries.first!
        let after = photoEntries.last!
        return VStack(alignment: .leading, spacing: 12) {
            Text("COMPARATORE FOTO").voltEyebrow()
            HStack(spacing: 12) {
                comparePhoto(before, label: "PRIMA")
                comparePhoto(after, label: "DOPO")
            }
        }
        .padding(18).voltPanel(Palette.magenta.opacity(0.4))
    }

    private func comparePhoto(_ e: ProgressEntryDTO, label: String) -> some View {
        VStack(spacing: 6) {
            photoThumb(e.photos.first?.url, height: 200)
            Text(label).font(Typo.mono(9, .black)).tracking(2).foregroundStyle(Palette.magenta)
            Text(dateShort(parseDate(e.submittedAt)))
                .font(Typo.mono(9)).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: History entries

    private func entryCard(_ e: ProgressEntryDTO, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateLong(parseDate(e.submittedAt)))
                    .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.violet)
                Spacer()
                if let kg = e.weightKg {
                    Text(String(format: "%.1f kg", kg))
                        .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textHi)
                }
            }
            if !e.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(e.photos) { p in photoThumb(p.url, height: 120).frame(width: 96) }
                    }
                }
            }
            if let fb = e.coachFeedback, !fb.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.cyan)
                    Text(fb).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
            } else if let notes = e.notes, !notes.isEmpty {
                Text(notes).font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
        }
        .padding(16).voltPanel(Palette.violet.opacity(0.35))
    }

    private func photoThumb(_ url: String?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Palette.void2)
            .frame(height: height)
            .overlay {
                if let url, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .empty: ProgressView().tint(Palette.cyan)
                        default: Image(systemName: "photo").foregroundStyle(Palette.textLow)
                        }
                    }
                } else {
                    Image(systemName: "photo").foregroundStyle(Palette.textLow)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Helpers

    private func parseDate(_ iso: String?) -> Date? { iso.flatMap(ISO8601.parse) }
    private func dateShort(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
        return f.string(from: d)
    }
    private func dateLong(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM yyyy"
        return f.string(from: d).uppercased()
    }

    private func load() async {
        loading = true; error = nil
        do { entries = try await APIClient.shared.progress() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
