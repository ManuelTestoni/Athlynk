//
//  DietDayDetailView.swift
//  One day of a FOOD-mode nutrition plan: the day's meals (each opens
//  MealDetailView) plus the day total. Used by NutritionView's weekly carousel
//  and as the single-day detail for DAILY plans. When opened from a WEEKLY
//  plan, shows visible prev/next-day chevrons + swipe across the other days.
//

import SwiftUI

/// Italian weekday labels keyed by the backend `day_of_week` codes.
enum DietWeekday {
    static let long: [String: String] = [
        "MONDAY": "Lunedì", "TUESDAY": "Martedì", "WEDNESDAY": "Mercoledì",
        "THURSDAY": "Giovedì", "FRIDAY": "Venerdì", "SATURDAY": "Sabato", "SUNDAY": "Domenica",
    ]
    static let short: [String: String] = [
        "MONDAY": "LUN", "TUESDAY": "MAR", "WEDNESDAY": "MER",
        "THURSDAY": "GIO", "FRIDAY": "VEN", "SATURDAY": "SAB", "SUNDAY": "DOM",
    ]
    static let order = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]

    static func sorted(_ days: [DietDayDTO]) -> [DietDayDTO] {
        days.sorted { (order.firstIndex(of: $0.dayOfWeek) ?? 99) < (order.firstIndex(of: $1.dayOfWeek) ?? 99) }
    }

    /// Today's backend day code (MONDAY…SUNDAY).
    static func todayCode() -> String {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1=Sun...7=Sat
        return order[(weekday + 5) % 7] // Mon=0...Sun=6
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    /// ISO date (yyyy-MM-dd) of `dayCode` within the current calendar week (Mon→Sun).
    static func isoDate(for dayCode: String) -> String? {
        guard let idx = order.firstIndex(of: dayCode) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayIdx = (cal.component(.weekday, from: today) + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -todayIdx, to: today),
              let target = cal.date(byAdding: .day, value: idx, to: monday) else { return nil }
        return isoFormatter.string(from: target)
    }

    /// The current week's 7 ISO dates, Mon→Sun.
    static func thisWeekISODates() -> [String] { order.compactMap(isoDate(for:)) }
}

/// Navigation payload for `DietDayDetailView`: the full week so the detail
/// screen can page prev/next without re-fetching.
struct DietDayNavContext: Hashable {
    let days: [DietDayDTO]
    let startId: Int
}

struct DietDayDetailView: View {
    let days: [DietDayDTO]
    @State private var currentIndex: Int
    /// +1 paging to next day (content slides in from the right), -1 to
    /// previous (slides in from the left) — drives the asymmetric transition.
    @State private var direction: Int = 1

    init(days: [DietDayDTO], startId: Int) {
        self.days = days
        _currentIndex = State(initialValue: days.firstIndex(where: { $0.id == startId }) ?? 0)
    }

    private var day: DietDayDTO { days[currentIndex] }
    private var totalKcal: Int { Int(day.meals.reduce(0) { $0 + $1.kcal }) }
    private var canPage: Bool { days.count > 1 }

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if day.meals.isEmpty {
                        EmptyPanel(icon: "fork.knife", text: "Nessun pasto previsto per questo giorno.",
                                   color: Palette.lime)
                    } else {
                        Text("PASTI").voltEyebrow().padding(.top, 4)
                        ForEach(Array(day.meals.enumerated()), id: \.element.id) { i, meal in
                            NavigationLink(value: meal) { mealCard(meal, index: i) }
                                .buttonStyle(PressableButtonStyle())
                                .revealUp(true, index: i)
                        }
                    }
                }
                .id(currentIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: direction >= 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction >= 0 ? .leading : .trailing).combined(with: .opacity)))
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, AppLayout.tabBarClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // simultaneousGesture (not .gesture) so this never blocks the system's
        // edge-swipe-back recognizer. A swipe that STARTS at the extreme left
        // edge is left alone (system pops the screen); everywhere else, a
        // rightward swipe pages to the previous day instead of exiting.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard canPage, v.startLocation.x > 24 else { return }
                    if v.translation.width < -40 { goNext() }
                    else if v.translation.width > 40 { goPrev() }
                }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if canPage {
                    Button { goPrev() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .black))
                            .foregroundStyle(currentIndex > 0 ? Palette.lime : Palette.textLow)
                            .frame(width: 36, height: 36).background(Circle().fill(Palette.void2))
                    }
                    .disabled(currentIndex == 0)
                }
                Spacer()
                Text((DietWeekday.long[day.dayOfWeek] ?? day.dayOfWeek).uppercased())
                    .font(Typo.poster(30)).foregroundStyle(Palette.textHi)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if canPage {
                    Button { goNext() } label: {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .black))
                            .foregroundStyle(currentIndex < days.count - 1 ? Palette.lime : Palette.textLow)
                            .frame(width: 36, height: 36).background(Circle().fill(Palette.void2))
                    }
                    .disabled(currentIndex == days.count - 1)
                }
            }
            if canPage {
                Text("Scorri per cambiare giorno")
                    .font(Typo.mono(9, .bold)).foregroundStyle(Palette.textLow)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("TOTALE GIORNO").font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                Spacer()
                Text("\(totalKcal)").font(Typo.poster(28)).foregroundStyle(Palette.lime)
                Text("kcal").font(Typo.mono(11, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            }
            Rectangle().fill(Palette.lime).frame(height: 1).opacity(0.5)
        }
    }

    private func goPrev() {
        guard currentIndex > 0 else { return }
        Haptics.tap()
        direction = -1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { currentIndex -= 1 }
    }
    private func goNext() {
        guard currentIndex < days.count - 1 else { return }
        Haptics.tap()
        direction = 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { currentIndex += 1 }
    }

    private func mealCard(_ meal: MealDTO, index: Int) -> some View {
        let accent = Palette.accent(index)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meal.name).font(Typo.display(18)).foregroundStyle(Palette.textHi)
                if let t = meal.timeOfDay, !t.isEmpty {
                    Text(t).font(Typo.mono(11)).foregroundStyle(Palette.textLow)
                }
                Spacer()
                Text("\(Int(meal.kcal)) kcal").font(Typo.mono(13, .bold)).foregroundStyle(accent)
            }
            ForEach(meal.items) { item in
                HStack {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text(item.name ?? "—").font(Typo.body(14)).foregroundStyle(Palette.textHi)
                    Spacer()
                    Text("\(Int(item.quantityG))g").font(Typo.mono(12)).foregroundStyle(Palette.textMid)
                }
            }
        }
        .padding(16).voltPanel(accent.opacity(0.35))
    }
}
