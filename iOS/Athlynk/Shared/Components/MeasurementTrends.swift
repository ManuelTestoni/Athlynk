//
//  MeasurementTrends.swift
//  "Il mio andamento" — shared by athlete (own checks) and coach (per athlete).
//  Three blocks: bodyweight (weekly means, matching the website's "pesi medi"
//  logic), circumferences and skinfolds (one selectable site at a time).
//
//  Feed it `MeasurementSample`s mapped from whichever progress DTO; the component
//  sorts chronologically and aggregates per ISO week on its own.
//

import SwiftUI

/// One check's measurements, normalised to numbers. Empty sites are simply
/// absent from the dictionaries.
struct MeasurementSample {
    let date: Date
    let weightKg: Double?
    let circumferences: [String: Double]   // cm
    let skinfolds: [String: Double]        // mm
}

struct MeasurementTrends: View {
    let samples: [MeasurementSample]
    var accent: Color = Palette.cyan
    /// Sites the athlete has EVER recorded a value for, independent of which
    /// (possibly paginated) `samples` are currently loaded — so a site shows
    /// up in the picker immediately instead of only once enough history pages
    /// have been fetched. Nil falls back to whatever `samples` contains locally.
    var everRecordedSites: MeasurementSitesDTO? = nil

    @State private var selectedCirc: String?
    @State private var selectedSkin: String?

    private var chrono: [MeasurementSample] { samples.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            weightBlock
            if !circKeys.isEmpty {
                siteBlock(title: "Circonferenze", icon: "ruler.fill", unit: "cm",
                          keys: circKeys, selection: $selectedCirc, color: Palette.lime,
                          series: { circSeries($0) }, label: circLabel)
            }
            if !skinKeys.isEmpty {
                siteBlock(title: "Pliche", icon: "drop.fill", unit: "mm",
                          keys: skinKeys, selection: $selectedSkin, color: Palette.violet,
                          series: { skinSeries($0) }, label: skinLabel)
            }
        }
        .onAppear {
            if selectedCirc == nil { selectedCirc = circKeys.first }
            if selectedSkin == nil { selectedSkin = skinKeys.first }
        }
    }

    // MARK: Bodyweight (weekly means)

    private var weightBlock: some View {
        let raw = chrono.compactMap { s in s.weightKg.map { ($0, s.date) } }
        let weekly = weeklyMeans(raw)
        return VStack(alignment: .leading, spacing: 12) {
            blockHeader(icon: "scalemass.fill", title: "Peso corporeo",
                        subtitle: "Medie settimanali", color: accent)
            if weekly.count >= 2 {
                let values = weekly.map(\.mean)
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", values.last ?? 0))
                            .font(Typo.poster(34)).foregroundStyle(Palette.textHi)
                        Text("kg").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                    }
                    Spacer()
                    DeltaPill(delta: (values.last ?? 0) - (values.first ?? 0), unit: "kg")
                }
                TrendChart(mean: weekly.map { ($0.mean, $0.weekStart) }, raw: raw,
                           color: accent, unit: "kg").frame(height: 160)
            } else {
                ChartEmpty(icon: "scalemass", text: "Servono almeno 2 settimane\ncon il peso registrato.")
                    .frame(height: 140)
            }
        }
        .padding(18).voltPanel(accent.opacity(0.4))
    }

    // MARK: Selectable site block (circumferences / skinfolds)

    private func siteBlock(title: String, icon: String, unit: String,
                           keys: [String], selection: Binding<String?>, color: Color,
                           series: @escaping (String) -> [(Double, Date)],
                           label: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(icon: icon, title: title, subtitle: "Seleziona una zona", color: color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keys, id: \.self) { key in
                        let on = selection.wrappedValue == key
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selection.wrappedValue = key
                            }
                        } label: {
                            Text(label(key)).font(Typo.body(13, .semibold))
                                .foregroundStyle(on ? Palette.void0 : Palette.textHi)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(Capsule().fill(on ? color : Palette.void1))
                                .overlay(Capsule().stroke(on ? .clear : Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            let raw = series(selection.wrappedValue ?? keys.first ?? "")
            let weekly = weeklyMeans(raw)
            if weekly.count >= 2 {
                let values = weekly.map(\.mean)
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", values.last ?? 0))
                            .font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                        Text(unit).font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                    }
                    Spacer()
                    DeltaPill(delta: (values.last ?? 0) - (values.first ?? 0), unit: unit)
                }
                TrendChart(mean: weekly.map { ($0.mean, $0.weekStart) }, raw: raw,
                           color: color, unit: unit).frame(height: 150)
            } else {
                ChartEmpty(icon: icon, text: "Servono almeno 2 settimane\ncon questa misura.")
                    .frame(height: 130)
            }
        }
        .padding(18).voltPanel(color.opacity(0.4))
    }

    // MARK: Series builders

    private func circSeries(_ key: String) -> [(Double, Date)] {
        chrono.compactMap { s in s.circumferences[key].map { ($0, s.date) } }
    }
    private func skinSeries(_ key: String) -> [(Double, Date)] {
        chrono.compactMap { s in s.skinfolds[key].map { ($0, s.date) } }
    }

    /// Site keys the athlete has EVER recorded (see `everRecordedSites`; falls
    /// back to whatever's in the currently-loaded `samples`), ordered by the
    /// ISAK catalog (same vocabulary as the add-measurement dropdown) then tail.
    /// A site appearing here doesn't guarantee a drawable line yet — `siteBlock`
    /// separately requires ≥2 loaded points before it draws one.
    private var circKeys: [String] {
        let present = everRecordedSites?.measurements ?? chrono.flatMap { Array($0.circumferences.keys) }
        return orderedKeys(present: present,
                    order: ["head", "neck", "chest", "arm_relaxed_r", "arm_relaxed_l",
                            "arm_flexed_r", "arm_flexed_l", "forearm_r", "forearm_l",
                            "wrist_r", "wrist_l", "waist", "gluteal", "thigh_r", "thigh_l",
                            "calf_r", "calf_l", "ankle_r", "ankle_l"])
    }
    private var skinKeys: [String] {
        let present = everRecordedSites?.skinfolds ?? chrono.flatMap { Array($0.skinfolds.keys) }
        return orderedKeys(present: present,
                    order: ["biceps", "triceps", "subscapular", "supraspinale", "suprailiac",
                            "abdominal", "front_thigh", "medial_calf"])
    }

    private func orderedKeys(present: [String], order: [String]) -> [String] {
        let avail = Set(present)
        let head = order.filter { avail.contains($0) }
        let tail = avail.subtracting(order).sorted()
        return head + tail
    }

    // MARK: Labels

    private func circLabel(_ k: String) -> String {
        ["head": "Testa", "neck": "Collo", "chest": "Torace", "waist": "Vita", "gluteal": "Fianchi",
         "arm_relaxed_r": "Braccio ril. DX", "arm_relaxed_l": "Braccio ril. SX",
         "arm_flexed_r": "Braccio fl. DX", "arm_flexed_l": "Braccio fl. SX",
         "forearm_r": "Avambraccio DX", "forearm_l": "Avambraccio SX",
         "wrist_r": "Polso DX", "wrist_l": "Polso SX",
         "thigh_r": "Coscia DX", "thigh_l": "Coscia SX",
         "calf_r": "Polpaccio DX", "calf_l": "Polpaccio SX",
         "ankle_r": "Caviglia DX", "ankle_l": "Caviglia SX"][k] ?? k.capitalized
    }
    private func skinLabel(_ k: String) -> String {
        ["biceps": "Bicipitale", "triceps": "Tricipitale", "subscapular": "Sottoscapolare",
         "supraspinale": "Sopraspinale", "suprailiac": "Soprailiaca", "abdominal": "Addominale",
         "front_thigh": "Coscia ant.", "medial_calf": "Polpaccio mediale"][k] ?? k.capitalized
    }

    // MARK: Pieces

    private func blockHeader(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 15, weight: .black)).foregroundStyle(color)
                .frame(width: 34, height: 34).background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle.uppercased()).font(Typo.mono(9, .bold)).tracking(2)
                    .foregroundStyle(Palette.textLow)
                Text(title).font(Typo.display(20)).foregroundStyle(Palette.textHi)
            }
            Spacer()
        }
    }

}

// MARK: - Trend chart with numbered axes, raw points and a drag tooltip
//
// `mean` is the weekly-mean series that draws the line; `raw` are the individual
// measurements, plotted faintly so the athlete sees every reading behind the
// smoothed trend. Both are positioned on the x-axis by their real date so the
// faint dots line up under the curve. Drag across the chart to read any point.

struct TrendChart: View {
    let mean: [(Double, Date)]
    var raw: [(Double, Date)] = []
    var color: Color = Palette.cyan
    var unit: String = ""

    @State private var selected: Int? = nil

    private let yAxisW: CGFloat = 40
    private let labelH: CGFloat = 16

    private var loHi: (Double, Double) {
        let vals = mean.map(\.0) + raw.map(\.0)
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = hi == lo ? max(abs(hi) * 0.05, 1) : (hi - lo) * 0.14
        return (lo - pad, hi + pad)
    }
    private var dateRange: (Date, Date) {
        let ds = mean.map(\.1) + raw.map(\.1)
        return (ds.min() ?? Date(), ds.max() ?? Date())
    }

    var body: some View {
        let (lo, hi) = loHi
        let span = max(hi - lo, 0.0001)
        let (minD, maxD) = dateRange
        let dspan = max(maxD.timeIntervalSince(minD), 1)
        func xf(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(minD) / dspan) }
        func yf(_ v: Double) -> CGFloat { 1 - CGFloat((v - lo) / span) }

        return VStack(spacing: 5) {
            GeometryReader { geo in
                let pw = geo.size.width - yAxisW
                let ph = geo.size.height
                let pt: (Double, Date) -> CGPoint = { v, d in
                    CGPoint(x: yAxisW + xf(d) * pw, y: yf(v) * ph)
                }
                let meanPts = mean.map { pt($0.0, $0.1) }

                ZStack(alignment: .topLeading) {
                    // Gridlines + Y labels (max / mid / min)
                    ForEach(0..<3, id: \.self) { i in
                        let frac = CGFloat(i) / 2
                        let val = hi - Double(frac) * (hi - lo)
                        let y = frac * ph
                        Path { p in
                            p.move(to: CGPoint(x: yAxisW, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Palette.line.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        Text(String(format: "%.1f", val))
                            .font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                            .frame(width: yAxisW - 6, alignment: .trailing)
                            .position(x: (yAxisW - 6) / 2, y: max(6, min(ph - 6, y)))
                    }

                    // Mean area + line
                    Path { p in
                        guard let f = meanPts.first else { return }
                        p.move(to: CGPoint(x: f.x, y: ph)); p.addLine(to: f)
                        meanPts.dropFirst().forEach { p.addLine(to: $0) }
                        if let l = meanPts.last { p.addLine(to: CGPoint(x: l.x, y: ph)) }
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        guard let f = meanPts.first else { return }
                        p.move(to: f); meanPts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

                    // Raw individual readings, faint
                    ForEach(Array(raw.enumerated()), id: \.offset) { _, r in
                        Circle().fill(color.opacity(0.28)).frame(width: 5, height: 5)
                            .position(pt(r.0, r.1))
                    }
                    // Mean nodes
                    ForEach(Array(meanPts.enumerated()), id: \.offset) { i, pt in
                        Circle().fill(selected == i ? color : Palette.void0)
                            .overlay(Circle().stroke(color, lineWidth: 2))
                            .frame(width: selected == i ? 11 : 7, height: selected == i ? 11 : 7)
                            .position(pt)
                    }

                    // Tooltip
                    if let i = selected, i < mean.count {
                        let pt = meanPts[i]
                        Path { p in
                            p.move(to: CGPoint(x: pt.x, y: 0)); p.addLine(to: CGPoint(x: pt.x, y: ph))
                        }
                        .stroke(color.opacity(0.4), lineWidth: 1)
                        calloutView(value: mean[i].0, date: mean[i].1)
                            .position(x: min(max(pt.x, 46), geo.size.width - 46), y: 16)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard !meanPts.isEmpty else { return }
                            let nearest = meanPts.enumerated().min {
                                abs($0.element.x - g.location.x) < abs($1.element.x - g.location.x)
                            }
                            if let n = nearest { Haptics.tap(); selected = n.offset }
                        }
                        .onEnded { _ in selected = nil }
                )
            }
            // X axis date ends
            HStack {
                Text(dateShort(minD)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
                Spacer()
                Text(dateShort(maxD)).font(Typo.mono(8)).foregroundStyle(Palette.textLow)
            }
            .padding(.leading, yAxisW)
            .frame(height: labelH)
        }
    }

    private func calloutView(value: Double, date: Date) -> some View {
        VStack(spacing: 1) {
            Text("\(String(format: "%.1f", value)) \(unit)")
                .font(Typo.mono(11, .bold)).foregroundStyle(Palette.textHi)
            Text(dateShort(date)).font(Typo.mono(8)).foregroundStyle(Palette.textMid)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.void1))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Weekly aggregation (mirror of check_progress.js "media settimanale")

struct WeeklyPoint { let weekStart: Date; let mean: Double; let n: Int }

/// Group (value, date) pairs by ISO week (Monday) and average each week.
func weeklyMeans(_ points: [(Double, Date)]) -> [WeeklyPoint] {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
    var buckets: [Date: [Double]] = [:]
    for (v, d) in points {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        guard let start = cal.date(from: comps) else { continue }
        buckets[start, default: []].append(v)
    }
    return buckets
        .map { WeeklyPoint(weekStart: $0.key, mean: $0.value.reduce(0, +) / Double($0.value.count), n: $0.value.count) }
        .sorted { $0.weekStart < $1.weekStart }
}

private func dateShort(_ d: Date?) -> String {
    guard let d else { return "—" }
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "d MMM"
    return f.string(from: d)
}

// MARK: - Volt line/area chart (shared)

struct TrendLine: View {
    let values: [Double]
    var color: Color = Palette.cyan
    /// Optional per-point captions (e.g. dates) shown in the scrub bubble.
    var labels: [String]? = nil
    @State private var progress: CGFloat = 0
    @State private var scrubIndex: Int? = nil

    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let unit = unitPoints(values, lo: lo, hi: hi)
        GeometryReader { geo in
            ZStack {
                AreaShape(unit: unit)
                    .fill(LinearGradient(colors: [color.opacity(0.26), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(Double(progress))
                LineShape(unit: unit)
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                if let l = unit.last, scrubIndex == nil {
                    Circle().fill(color).frame(width: 9, height: 9)
                        .position(x: l.x * geo.size.width, y: l.y * geo.size.height)
                        .neonGlow(color, radius: 5)
                        .opacity(progress > 0.97 ? 1 : 0)
                }
                // Touch scrub: press/drag to inspect any point.
                if let i = scrubIndex, unit.indices.contains(i) {
                    let p = CGPoint(x: unit[i].x * geo.size.width, y: unit[i].y * geo.size.height)
                    Rectangle().fill(color.opacity(0.35))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: p.x, y: geo.size.height / 2)
                    Circle().fill(color).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Palette.void0, lineWidth: 2))
                        .position(p)
                    scrubBubble(i)
                        .position(x: min(max(p.x, 46), geo.size.width - 46),
                                  y: max(p.y - 30, 14))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard values.count > 1 else { return }
                        let idx = Int(round(g.location.x / max(geo.size.width, 1) * CGFloat(values.count - 1)))
                        let clamped = min(max(idx, 0), values.count - 1)
                        if clamped != scrubIndex { Haptics.soft() }
                        scrubIndex = clamped
                    }
                    .onEnded { _ in withAnimation(Motion.snappy) { scrubIndex = nil } }
            )
        }
        .onAppear { progress = 0; withAnimation(.easeOut(duration: 0.9)) { progress = 1 } }
        .id(values.count == 0 ? 0 : Int(values.reduce(0, +) * 100))   // redraw on series change
    }

    private func scrubBubble(_ i: Int) -> some View {
        VStack(spacing: 1) {
            Text(fmtScrub(values[i]))
                .font(Typo.mono(12, .bold)).foregroundStyle(Palette.void0)
            if let labels, labels.indices.contains(i) {
                Text(labels[i]).font(Typo.mono(8)).foregroundStyle(Palette.void0.opacity(0.8))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Palette.textHi))
        .allowsHitTesting(false)
    }

    private func fmtScrub(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

func unitPoints(_ values: [Double], lo: Double, hi: Double) -> [CGPoint] {
    let span = max(hi - lo, 0.0001)
    let n = values.count
    return values.enumerated().map { i, v in
        let x = n == 1 ? 0.5 : CGFloat(i) / CGFloat(n - 1)
        let y = 1 - CGFloat((v - lo) / span)
        return CGPoint(x: x, y: y)
    }
}

struct LineShape: Shape {
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

struct AreaShape: Shape {
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

struct DeltaPill: View {
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

struct ChartEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Palette.textLow)
            Text(text).font(Typo.body(13)).foregroundStyle(Palette.textMid).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
