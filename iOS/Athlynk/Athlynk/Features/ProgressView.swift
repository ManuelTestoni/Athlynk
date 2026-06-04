//
//  ProgressView.swift
//  Stitch "Grafici Progressi" + "Comparatore Foto": the athlete's submitted
//  check history. The three charts (bodyweight trend, circumference trend,
//  before/after measurement comparison) live in a swipeable, animated carousel.
//  Below it sit the before/after photo comparator and per-check feedback.
//  Backed by GET /api/v1/progress.
//
//  Named ProgressTrackerView to avoid clashing with SwiftUI.ProgressView.
//

import SwiftUI

struct ProgressTrackerView: View {
    @State private var entries: [ProgressEntryDTO] = []
    @State private var loading = true
    @State private var error: String?

    /// Entries oldest → newest, used for the trend lines and deltas.
    private var chrono: [ProgressEntryDTO] {
        entries.sorted { ($0.submittedAt ?? "") < ($1.submittedAt ?? "") }
    }
    private var weightPoints: [DatedValue] {
        chrono.compactMap { e in
            guard let kg = e.weightKg, let iso = e.submittedAt, let d = ISO8601.parse(iso) else { return nil }
            return DatedValue(date: d, value: kg)
        }
    }
    private var measureSeries: [MeasureSeries] {
        let order = ["waist", "chest", "shoulders", "hips", "thigh_right", "arm_right"]
        let labels = ["waist": "Vita", "chest": "Petto", "shoulders": "Spalle",
                      "hips": "Fianchi", "thigh_right": "Coscia", "arm_right": "Braccio"]
        var out: [MeasureSeries] = []
        for key in order {
            let pts: [DatedValue] = chrono.compactMap { e in
                guard let iso = e.submittedAt, let d = ISO8601.parse(iso),
                      let raw = e.measurements?[key], let v = Double(raw), v > 0 else { return nil }
                return DatedValue(date: d, value: v)
            }
            guard pts.count >= 2 else { continue }
            out.append(MeasureSeries(key: key, label: labels[key] ?? key,
                                     color: Palette.accent(out.count), points: pts))
        }
        return out
    }
    private var photoEntries: [ProgressEntryDTO] { chrono.filter { !$0.photos.isEmpty } }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.magenta, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        ProgressSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.violet)
                    } else if entries.isEmpty {
                        EmptyPanel(icon: "chart.xyaxis.line",
                                   text: "Nessun check completato.\nI tuoi progressi appariranno qui.")
                    } else {
                        ChartCarousel(weight: weightPoints, series: measureSeries)
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

// MARK: - Chart data primitives

private struct DatedValue: Hashable { let date: Date; let value: Double }
private struct MeasureSeries: Identifiable, Hashable {
    let key: String; let label: String; let color: Color; let points: [DatedValue]
    var id: String { key }
    var first: Double { points.first?.value ?? 0 }
    var last: Double { points.last?.value ?? 0 }
}

// MARK: - The swipeable 3-chart carousel

private struct ChartCarousel: View {
    let weight: [DatedValue]
    let series: [MeasureSeries]

    @State private var page = 0
    @State private var appeared = false
    /// Bumped on appear and on each page change to re-run the draw animation.
    @State private var drawToken = 0

    private let titles = ["Peso corporeo", "Circonferenze", "Confronto misure"]
    private let icons  = ["scalemass.fill", "ruler.fill", "arrow.left.arrow.right"]

    var body: some View {
        VStack(spacing: 14) {
            header
            TabView(selection: $page) {
                WeightSlide(points: weight, token: drawToken).tag(0)
                TrendSlide(series: series, token: drawToken).tag(1)
                CompareSlide(series: series, token: drawToken).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 252)
            dots
        }
        .padding(18)
        .voltPanel(Palette.cyan.opacity(0.4))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
            drawToken += 1
        }
        .onChange(of: page) { _ in
            Haptics.tap()
            drawToken += 1
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: icons[page])
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Palette.bronze)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.bronze.opacity(0.12)))
                .id(page) // re-mount → fade-swap the glyph on page change
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 2) {
                Text("I MIEI PROGRESSI").voltEyebrow()
                Text(titles[page])
                    .font(Typo.display(22)).foregroundStyle(Palette.textHi)
                    .id(page)
                    .transition(.opacity)
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Palette.bronze : Palette.line)
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
                    .onTapGesture { withAnimation { page = i } }
            }
        }
    }
}

// MARK: - Slide 1 · bodyweight area + line

private struct WeightSlide: View {
    let points: [DatedValue]
    let token: Int
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            if points.count >= 2 {
                let values = points.map(\.value)
                let lo = values.min() ?? 0, hi = values.max() ?? 1
                let delta = (values.last ?? 0) - (values.first ?? 0)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", values.last ?? 0))
                                .font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                            Text("kg").font(Typo.mono(13, .bold)).foregroundStyle(Palette.textMid)
                        }
                        Spacer()
                        DeltaPill(delta: delta, unit: "kg", goodWhenDown: true)
                    }
                    LineChartBody(unit: unitPoints(values, lo: lo, hi: hi),
                                  color: Palette.cyan, progress: progress)
                        .frame(maxHeight: .infinity)
                    HStack {
                        Text(dateShort(points.first?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                        Spacer()
                        Text(dateShort(points.last?.date)).font(Typo.mono(9)).foregroundStyle(Palette.textLow)
                    }
                }
            } else {
                ChartEmpty(icon: "scalemass", text: "Servono almeno 2 check\ncon il peso registrato.")
            }
        }
        .onChange(of: token) { _ in animate() }
        .onAppear { animate() }
    }

    private func animate() {
        progress = 0
        withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
    }
}

// MARK: - Slide 2 · circumference trend (multi-series)

private struct TrendSlide: View {
    let series: [MeasureSeries]
    let token: Int
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            if !series.isEmpty {
                // Shared cm axis across every series so lines sit at true heights.
                let all = series.flatMap { $0.points.map(\.value) }
                let lo = all.min() ?? 0, hi = all.max() ?? 1
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        ForEach(series) { s in
                            LineChartBody(unit: unitPoints(s.points.map(\.value), lo: lo, hi: hi),
                                          color: s.color, progress: progress, fill: false, lineWidth: 2.2)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    legend
                }
            } else {
                ChartEmpty(icon: "ruler", text: "Servono almeno 2 check\ncon le circonferenze.")
            }
        }
        .onChange(of: token) { _ in animate() }
        .onAppear { animate() }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(series) { s in
                HStack(spacing: 5) {
                    Circle().fill(s.color).frame(width: 7, height: 7)
                    Text(s.label).font(Typo.mono(9, .semibold)).foregroundStyle(Palette.textMid)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func animate() {
        progress = 0
        withAnimation(.easeOut(duration: 1.0)) { progress = 1 }
    }
}

// MARK: - Slide 3 · first vs latest comparison bars

private struct CompareSlide: View {
    let series: [MeasureSeries]
    let token: Int
    @State private var grow: CGFloat = 0

    var body: some View {
        Group {
            if !series.isEmpty {
                let maxVal = series.map(\.last).max() ?? 1
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 11) {
                        ForEach(Array(series.enumerated()), id: \.element.id) { i, s in
                            CompareRow(series: s, maxVal: maxVal, grow: grow)
                                .opacity(grow)
                                .offset(x: grow == 0 ? -12 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.85)
                                    .delay(Double(i) * 0.06), value: grow)
                        }
                    }
                }
            } else {
                ChartEmpty(icon: "arrow.left.arrow.right", text: "Servono almeno 2 check\ncon le circonferenze.")
            }
        }
        .onChange(of: token) { _ in animate() }
        .onAppear { animate() }
    }

    private func animate() {
        grow = 0
        withAnimation(.easeOut(duration: 0.9)) { grow = 1 }
    }
}

private struct CompareRow: View {
    let series: MeasureSeries
    let maxVal: Double
    let grow: CGFloat

    var body: some View {
        let delta = series.last - series.first
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(series.color).frame(width: 7, height: 7)
                    Text(series.label).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                }
                Spacer()
                Text(String(format: "%.0f → %.0f cm", series.first, series.last))
                    .font(Typo.mono(10, .semibold)).foregroundStyle(Palette.textMid)
                DeltaPill(delta: delta, unit: "cm", goodWhenDown: true, compact: true)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let fw = CGFloat(series.first / max(maxVal, 0.0001)) * w
                let lw = CGFloat(series.last / max(maxVal, 0.0001)) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.void2).frame(height: 8)
                    // Faint "before" bar behind the live "after" bar.
                    Capsule().fill(series.color.opacity(0.25))
                        .frame(width: fw * grow, height: 8)
                    Capsule().fill(series.color)
                        .frame(width: lw * grow, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Shared chart pieces

/// Area + trimmed line, animated by `progress` (0…1).
private struct LineChartBody: View {
    let unit: [CGPoint]          // x,y in 0…1 (y already flipped: 0 = top)
    var color: Color
    var progress: CGFloat
    var fill: Bool = true
    var lineWidth: CGFloat = 2.6

    var body: some View {
        ZStack {
            if fill {
                AreaShape(unit: unit)
                    .fill(LinearGradient(colors: [color.opacity(0.28), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(Double(progress))
            }
            LineShape(unit: unit)
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            GeometryReader { geo in
                if let l = unit.last {
                    Circle().fill(color).frame(width: 9, height: 9)
                        .position(x: l.x * geo.size.width, y: l.y * geo.size.height)
                        .neonGlow(color, radius: 5)
                        .opacity(progress > 0.97 ? 1 : 0)
                }
            }
        }
    }
}

private struct LineShape: Shape {
    let unit: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = unit.first else { return p }
        func map(_ u: CGPoint) -> CGPoint { CGPoint(x: u.x * rect.width, y: u.y * rect.height) }
        p.move(to: map(f))
        unit.dropFirst().forEach { p.addLine(to: map($0)) }
        return p
    }
}

private struct AreaShape: Shape {
    let unit: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = unit.first else { return p }
        func map(_ u: CGPoint) -> CGPoint { CGPoint(x: u.x * rect.width, y: u.y * rect.height) }
        p.move(to: CGPoint(x: f.x * rect.width, y: rect.height))
        p.addLine(to: map(f))
        unit.dropFirst().forEach { p.addLine(to: map($0)) }
        if let l = unit.last { p.addLine(to: CGPoint(x: l.x * rect.width, y: rect.height)) }
        p.closeSubpath()
        return p
    }
}

private struct DeltaPill: View {
    let delta: Double
    let unit: String
    var goodWhenDown: Bool = true
    var compact: Bool = false

    var body: some View {
        let up = delta > 0.05, down = delta < -0.05
        let good = goodWhenDown ? down : up
        let color = (up || down) ? (good ? Palette.lime : Palette.amber) : Palette.textLow
        let icon = down ? "arrow.down.right" : (up ? "arrow.up.right" : "arrow.right")
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: compact ? 9 : 11, weight: .black))
            Text(String(format: "%+.1f \(unit)", delta)).font(Typo.mono(compact ? 10 : 12, .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 4 : 6)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct ChartEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.textLow)
            Text(text).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File-private helpers

/// Map raw values to unit space (x even-spaced 0…1, y flipped so 0 = top).
private func unitPoints(_ values: [Double], lo: Double, hi: Double) -> [CGPoint] {
    let span = max(hi - lo, 0.0001)
    let n = values.count
    return values.enumerated().map { i, v in
        let x = n == 1 ? 0.5 : CGFloat(i) / CGFloat(n - 1)
        let y = 1 - CGFloat((v - lo) / span)
        return CGPoint(x: x, y: y)
    }
}

private func dateShort(_ d: Date?) -> String {
    guard let d else { return "—" }
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
    return f.string(from: d)
}
