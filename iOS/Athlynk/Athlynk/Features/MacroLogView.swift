//
//  MacroLogView.swift
//  MACRO-mode food diary. The coach sets only macro targets; here the athlete
//  logs what they actually eat today and watches calories/macros fill up.
//  Backed by /api/v1/nutrition/assignments/<id>/macro-day (+ log create/delete).
//

import SwiftUI

struct MacroLogView: View {
    let assignmentId: Int
    let planTitle: String
    /// ISO yyyy-MM-dd of a past day to review/edit; nil = today's diary.
    var logDate: String? = nil
    /// The week's 7 ISO dates (Mon→Sun) this day belongs to. When set, shows
    /// visible prev/next-day chevrons + swipe (opened from the MACRO weekly
    /// day-strip in NutritionView). Nil when opened as a standalone diary.
    var weekDates: [String]? = nil

    @State private var pagedDate: String?
    @State private var day: MacroDayDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var showSearch = false
    @State private var barFill = false

    private var effectiveDate: String? { pagedDate ?? logDate }
    private var weekIndex: Int? {
        guard let weekDates, let effectiveDate else { return nil }
        return weekDates.firstIndex(of: effectiveDate)
    }
    private var isToday: Bool { effectiveDate == nil || effectiveDate == todayISO() }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if weekDates != nil { dayPagerHeader }
                    if loading {
                        MacroLogSkeleton()
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.danger)
                    } else if let day {
                        ringCard(day)
                        macrosCard(day)
                        NeonButton(title: "Aggiungi alimento", icon: "plus.circle.fill", color: Palette.lime) {
                            showSearch = true
                        }
                        entriesSection(day)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle(weekDates != nil ? "" : (isToday ? "Diario di oggi" : "Giorno passato"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(Palette.lime)
        .task(id: effectiveDate) { await load() }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard weekDates != nil else { return }
                    if v.translation.width < -40 { goNext() }
                    else if v.translation.width > 40 { goPrev() }
                }
        )
        .sheet(isPresented: $showSearch) {
            FoodSearchSheet(assignmentId: assignmentId, logDate: effectiveDate) {
                Task { await load(animated: true) }
            }
        }
    }

    // MARK: Day pager (weekly context only)

    private var dayPagerHeader: some View {
        HStack {
            Button { goPrev() } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .black))
                    .foregroundStyle(canGoPrev ? Palette.lime : Palette.textLow)
                    .frame(width: 36, height: 36).background(Circle().fill(Palette.void2))
            }
            .disabled(!canGoPrev)
            Spacer()
            VStack(spacing: 2) {
                Text(prettyDate(effectiveDate ?? todayISO())).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                Text("Scorri per cambiare giorno").font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
            }
            Spacer()
            Button { goNext() } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .black))
                    .foregroundStyle(canGoNext ? Palette.lime : Palette.textLow)
                    .frame(width: 36, height: 36).background(Circle().fill(Palette.void2))
            }
            .disabled(!canGoNext)
        }
    }

    private var canGoPrev: Bool { guard let i = weekIndex else { return false }; return i > 0 }
    private var canGoNext: Bool {
        guard let i = weekIndex, let weekDates else { return false }
        return i < weekDates.count - 1
    }
    private func goPrev() {
        guard canGoPrev, let i = weekIndex, let weekDates else { return }
        Haptics.tap(); pagedDate = weekDates[i - 1]
    }
    private func goNext() {
        guard canGoNext, let i = weekIndex, let weekDates else { return }
        Haptics.tap(); pagedDate = weekDates[i + 1]
    }
    private func todayISO() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar(identifier: .gregorian)
        return f.string(from: Date())
    }

    // MARK: Calorie ring

    private func ringCard(_ day: MacroDayDTO) -> some View {
        let target = max(day.target.kcal, 1)
        let consumed = day.consumed.kcal
        let remaining = max(target - consumed, 0)
        let over = consumed > target
        return VStack(spacing: 14) {
            HStack {
                Text(planTitle).font(Typo.mono(10, .bold)).tracking(1.5)
                    .foregroundStyle(Palette.textLow).lineLimit(1)
                Spacer()
                Text(prettyDate(day.date)).font(Typo.mono(10, .bold)).foregroundStyle(Palette.textLow)
            }
            ZStack {
                RingGauge(progress: consumed / target, color: over ? Palette.amber : Palette.lime, lineWidth: 14)
                    .frame(width: 188, height: 188)
                VStack(spacing: 2) {
                    Text("\(Int(consumed))").font(Typo.poster(46)).foregroundStyle(Palette.textHi)
                        .contentTransition(.numericText())
                    Text("/ \(Int(target)) kcal").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                    Text(over ? "+\(Int(consumed - target)) oltre" : "\(Int(remaining)) rimaste")
                        .font(Typo.mono(11, .bold))
                        .foregroundStyle(over ? Palette.amber : Palette.lime)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: consumed)
        }
        .padding(20).voltPanel(Palette.lime.opacity(0.4))
    }

    // MARK: Macro bars

    private func macrosCard(_ day: MacroDayDTO) -> some View {
        VStack(spacing: 14) {
            macroBar("Proteine", day.consumed.protein, day.target.protein, Palette.magenta)
            macroBar("Carboidrati", day.consumed.carb, day.target.carb, Palette.cyan)
            macroBar("Grassi", day.consumed.fat, day.target.fat, Palette.amber)
        }
        .padding(18).voltPanel(Palette.cyan.opacity(0.35))
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { barFill = true } }
    }

    private func macroBar(_ label: String, _ consumed: Double, _ target: Double, _ color: Color) -> some View {
        let pct = target > 0 ? min(consumed / target, 1) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Typo.body(13, .semibold)).foregroundStyle(Palette.textHi)
                Spacer()
                Text("\(Int(consumed)) / \(Int(target)) g")
                    .font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.void2).frame(height: 9)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * (barFill ? pct : 0), height: 9)
                }
            }
            .frame(height: 9)
        }
    }

    // MARK: Entries

    @ViewBuilder
    private func entriesSection(_ day: MacroDayDTO) -> some View {
        Text(isToday ? "ALIMENTI DI OGGI" : "ALIMENTI DEL GIORNO").voltEyebrow().padding(.top, 6)
        if day.entries.isEmpty {
            EmptyPanel(icon: "fork.knife", text: "Nessun alimento registrato.\nTocca «Aggiungi alimento».",
                       color: Palette.lime)
        } else {
            ForEach(Array(day.entries.enumerated()), id: \.element.id) { i, e in
                entryRow(e).revealUp(true, index: i)
            }
        }
    }

    private func entryRow(_ e: MacroEntryDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                Text("\(Int(e.quantityG))g · P \(Int(e.protein)) · C \(Int(e.carbs)) · G \(Int(e.fat))")
                    .font(Typo.mono(10)).foregroundStyle(Palette.textMid)
            }
            Spacer()
            Text("\(Int(e.kcal))").font(Typo.mono(15, .bold)).foregroundStyle(Palette.lime)
            Text("kcal").font(Typo.mono(9, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            Button { Task { await delete(e) } } label: {
                Image(systemName: "trash.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.danger.opacity(0.12)))
            }
            .accessibilityLabel("Elimina \(e.name)")
        }
        .padding(14).voltPanel(Palette.lime.opacity(0.3))
    }

    // MARK: Data

    private func load(animated: Bool = false) async {
        if !animated { loading = true }
        error = nil
        do {
            let d = try await APIClient.shared.macroDay(assignment: assignmentId, date: effectiveDate)
            if animated { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { day = d } }
            else { day = d }
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func delete(_ e: MacroEntryDTO) async {
        Haptics.tap()
        do {
            try await APIClient.shared.deleteMacroLog(entryId: e.id)
            await load(animated: true)
        } catch { /* keep current state on failure */ }
    }

    private func prettyDate(_ iso: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: iso) else { return iso }
        let out = DateFormatter(); out.locale = Locale(identifier: "it_IT"); out.dateFormat = "EEE d MMM"
        return out.string(from: d).uppercased()
    }
}

// MARK: - Food search + quantity sheet

private struct FoodSearchSheet: View {
    let assignmentId: Int
    var logDate: String? = nil
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FoodDTO] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var filter = "all"   // all | cat | recent
    @State private var categories: [String] = []
    @State private var activeCat = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VoltField(icon: "magnifyingglass", placeholder: "Cerca un alimento…",
                          text: $query, accent: Palette.lime)
                    .padding(.horizontal, 16).padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach([("all", "Tutti"), ("cat", "Categorie"), ("recent", "Recenti")], id: \.0) { key, label in
                        Button {
                            Haptics.tap()
                            filter = key; activeCat = ""; results = []
                            scheduleSearch(immediate: true)
                        } label: {
                            Text(label)
                                .font(Typo.body(12, .semibold))
                                .foregroundStyle(filter == key ? Palette.void0 : Palette.textMid)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(filter == key ? Palette.lime : Palette.void2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                if filter == "cat" && !activeCat.isEmpty {
                    Button {
                        Haptics.tap()
                        activeCat = ""; results = []
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                            Text(activeCat).font(Typo.body(13, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Palette.lime)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }

                if filter == "cat" && activeCat.isEmpty {
                    if filteredCategories.isEmpty {
                        Spacer()
                        Text(categories.isEmpty ? "Caricamento categorie…" : "Nessuna categoria trovata.")
                            .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredCategories, id: \.self) { cat in
                                    categoryRow(cat)
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 24)
                        }
                    }
                } else if loading && results.isEmpty {
                    Spacer(); ProgressView().tint(Palette.lime); Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(emptyText)
                        .font(Typo.body(13)).foregroundStyle(Palette.textMid)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { food in
                                NavigationLink {
                                    QuantityView(assignmentId: assignmentId, food: food, logDate: logDate) {
                                        onAdded(); dismiss()
                                    }
                                } label: { resultRow(food) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                    }
                }
            }
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle("Aggiungi alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }.tint(Palette.lime)
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .task { if results.isEmpty { await search() } }
        }
        .presentationDetents([.large])
    }

    private var filteredCategories: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? categories : categories.filter { $0.lowercased().contains(q) }
        return base.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func categoryRow(_ cat: String) -> some View {
        Button {
            Haptics.tap()
            activeCat = cat
            scheduleSearch(immediate: true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.lime)
                Text(cat).font(Typo.body(14, .semibold)).foregroundStyle(Palette.textHi)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textMid)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voltPanel(Palette.line, radius: 13)
    }

    private func resultRow(_ f: FoodDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                Text("\(Int(f.kcal)) kcal · P \(Int(f.protein)) · C \(Int(f.carb)) · G \(Int(f.fat))  /100g")
                    .font(Typo.mono(10)).foregroundStyle(Palette.textMid)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.lime)
        }
        .padding(14).voltPanel(Palette.lime.opacity(0.3))
    }

    private var emptyText: String {
        if filter == "recent" { return "Nessun alimento recente." }
        if filter == "cat" && activeCat.isEmpty { return "Scegli una categoria." }
        return query.isEmpty ? "Cerca nella banca dati o scegli un filtro." : "Nessun alimento trovato."
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        if filter == "cat" && activeCat.isEmpty && categories.isEmpty {
            // first load → fetch categories, don't show results yet
        } else if filter == "cat" && activeCat.isEmpty {
            results = []; return
        }
        loading = true; defer { loading = false }
        let resp = try? await APIClient.shared.searchFoods(
            query,
            filter: filter == "recent" ? "recent" : nil,
            cat: filter == "cat" ? activeCat : nil,
            includeCats: filter == "cat" && categories.isEmpty)
        guard !Task.isCancelled else { return }
        if let cats = resp?.categories { categories = cats }
        if filter == "cat" && activeCat.isEmpty {
            results = []
        } else {
            results = resp?.results ?? []
        }
    }
}

private struct QuantityView: View {
    let assignmentId: Int
    let food: FoodDTO
    var logDate: String? = nil
    var onConfirm: () -> Void

    @State private var grams: Double = 100
    @State private var saving = false
    @StateObject private var flash = StatusFlash()

    private var factor: Double { grams / 100 }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(food.name).font(Typo.display(24)).foregroundStyle(Palette.textHi)
                        .multilineTextAlignment(.center)
                    Text("Valori per la quantità scelta").voltEyebrow()
                }
                .padding(.top, 10)

                ZStack {
                    RingGauge(progress: 1, color: Palette.lime, lineWidth: 12).frame(width: 150, height: 150)
                    VStack(spacing: 0) {
                        Text("\(Int(food.kcal * factor))").font(Typo.poster(40)).foregroundStyle(Palette.textHi)
                            .contentTransition(.numericText())
                        Text("kcal").font(Typo.mono(12, .bold)).foregroundStyle(Palette.textMid)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: grams)

                HStack(spacing: 10) {
                    macroChip("P", food.protein * factor, Palette.magenta)
                    macroChip("C", food.carb * factor, Palette.cyan)
                    macroChip("G", food.fat * factor, Palette.amber)
                }

                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(grams))").font(Typo.poster(36)).foregroundStyle(Palette.lime)
                        Text("grammi").font(Typo.mono(13, .bold)).foregroundStyle(Palette.textMid)
                    }
                    Slider(value: $grams, in: 5...600, step: 5) { editing in
                        if editing { Haptics.soft() }
                    }
                    .tint(Palette.lime)
                }
                .padding(18).voltPanel(Palette.lime.opacity(0.35))

                NeonButton(title: saving ? "Aggiungo…" : "Aggiungi al diario", icon: "checkmark.circle.fill",
                           color: Palette.lime, loading: saving) {
                    Task { await add() }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .statusOverlay(flash)
        .navigationTitle("Quantità")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func macroChip(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(grams))g").font(Typo.mono(16, .black)).foregroundStyle(color)
            Text(label).font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    private func add() async {
        saving = true
        do {
            try await APIClient.shared.addMacroLog(assignment: assignmentId, foodId: food.id,
                                                    quantityG: grams, mealName: nil, date: logDate)
            Haptics.success()
            onConfirm()
        } catch { flash.failure("Aggiunta non riuscita") }
        saving = false
    }
}
