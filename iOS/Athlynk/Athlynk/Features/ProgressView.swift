//
//  ProgressView.swift
//  "Il mio andamento": the athlete's submitted-check history. Bodyweight (weekly
//  means), circumferences and skinfolds live in the shared MeasurementTrends
//  component; below sit the before/after photo comparator and per-check feedback.
//  Backed by GET /api/v1/progress.
//
//  Named ProgressTrackerView to avoid clashing with SwiftUI.ProgressView.
//

import SwiftUI

struct ProgressTrackerView: View {
    @State private var entries: [ProgressEntryDTO] = []
    @State private var exerciseHistory: [ExerciseHistoryItemDTO] = []
    /// Sites the athlete has EVER recorded a value for — independent of the
    /// paginated `entries`, so the trend charts show every site with data
    /// (see MeasurementTrends' `everRecordedSites`), not just recently-loaded ones.
    @State private var everRecordedSites: MeasurementSitesDTO?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var appear = false
    /// Id of the last-opened history row, so popping back from the detail
    /// screen restores this scroll position instead of jumping to the top.
    @State private var lastOpenedId: Int?

    /// Entries oldest → newest.
    private var chrono: [ProgressEntryDTO] {
        entries.sorted { ($0.submittedAt ?? "") < ($1.submittedAt ?? "") }
    }

    /// Normalised samples for the trend charts.
    private var samples: [MeasurementSample] {
        chrono.compactMap { e in
            guard let iso = e.submittedAt, let d = ISO8601.parse(iso) else { return nil }
            return MeasurementSample(
                date: d,
                weightKg: e.weightKg,
                circumferences: (e.measurements ?? [:]).compactMapValues { Double($0) },
                skinfolds: (e.skinfolds ?? [:]).compactMapValues { Double($0) }
            )
        }
    }

    private var photoEntries: [ProgressEntryDTO] { chrono.filter { !$0.photos.isEmpty } }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.magenta, Palette.violet])
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if loading {
                            ProgressSkeleton()
                        } else if let error {
                            EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                        } else if entries.isEmpty {
                            EmptyPanel(icon: "chart.xyaxis.line",
                                       text: "Nessun check completato.\nI tuoi progressi appariranno qui.")
                        } else {
                            MeasurementTrends(samples: samples, everRecordedSites: everRecordedSites)
                                .revealUp(appear, index: 0)
                            if photoEntries.count >= 2 { comparatorCard.revealUp(appear, index: 1) }
                            Text("STORICO CHECK").voltEyebrow().padding(.top, 4).revealUp(appear, index: 2)
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                                NavigationLink { CheckHistoryDetailView(responseId: e.id) } label: { entryCard(e, index: i) }
                                    .buttonStyle(.plain)
                                    .id(e.id)
                                    .simultaneousGesture(TapGesture().onEnded { lastOpenedId = e.id })
                                    .revealUp(appear, index: min(i, 5) + 3)
                            }
                            if hasMore {
                                LoadMoreButton(loading: loadingMore, accent: Palette.violet) { Task { await loadMore() } }
                            }
                        }
                        if !loading, !exerciseHistory.isEmpty {
                            GreekDivider(color: Palette.control).padding(.top, 8)
                            exercisesSection.revealUp(appear, index: 4)
                        }
                    }
                    .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
                }
                .onAppear {
                    if let id = lastOpenedId { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
        .navigationTitle("Il mio andamento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Palette.violet)
                }
                .accessibilityLabel("Aggiungi misurazione")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMeasurementSheet(accent: Palette.violet) { type, key, value, date in
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                try await APIClient.shared.addMeasurement(
                    type: type, key: key, value: value, date: f.string(from: date))
                await load()
            }
            .presentationDetents([.medium, .large])
        }
        .task { if entries.isEmpty { await load() } }
        .onChange(of: loading) { _, l in if !l { appear = true } }
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

    // MARK: Exercise trends (history-based: includes substituted/added movements)

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROGRESSI PER ESERCIZIO").voltEyebrow().padding(.top, 4)
            Text("Tutti gli esercizi che hai eseguito — anche quelli sostituiti o aggiunti in sessione.")
                .font(Typo.body(12)).foregroundStyle(Palette.textMid)
            ForEach(exerciseHistory) { item in
                NavigationLink {
                    ExerciseTrendByNameView(name: item.name)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Typo.body(15, .semibold))
                                .foregroundStyle(Palette.textHi).lineLimit(1)
                            Text("\(item.sessionsCount) sessioni\(item.lastDone.map { " · ultima \($0)" } ?? "")")
                                .font(Typo.mono(10)).foregroundStyle(Palette.textMid)
                        }
                        Spacer()
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.control)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textMid)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .voltPanel(Palette.control.opacity(0.3), radius: 13)
            }
        }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let res = try await APIClient.shared.progress(offset: 0)
            entries = res.entries; hasMore = res.hasMore
        }
        catch { self.error = error.localizedDescription }
        exerciseHistory = (try? await APIClient.shared.progressExercises()) ?? []
        everRecordedSites = try? await APIClient.shared.measurementSites()
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        if let res = try? await APIClient.shared.progress(offset: entries.count) {
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: res.entries.filter { !known.contains($0.id) })
            hasMore = res.hasMore
        }
    }
}

// MARK: - Trend by exercise NAME (history-based, works for substituted/added)

struct ExerciseTrendByNameView: View {
    let name: String

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.violet, Palette.cyan, Palette.magenta, Palette.violet])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ANDAMENTO ESERCIZIO")
                            .font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(Palette.control)
                        Text(name).font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                            .fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(Palette.control).frame(height: 1).opacity(0.5)
                    }
                    ExerciseTrendCard(load: {
                        try await APIClient.shared.exerciseTrend(name: name)
                    }, accent: Palette.control)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
