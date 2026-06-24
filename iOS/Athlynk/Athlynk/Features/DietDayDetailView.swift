//
//  DietDayDetailView.swift
//  One day of a FOOD-mode nutrition plan: the day's meals (each opens
//  MealDetailView) plus the day total. Used by NutritionView's weekly carousel
//  and as the single-day detail for DAILY plans.
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
}

struct DietDayDetailView: View {
    let day: DietDayDTO

    private var totalKcal: Int { Int(day.meals.reduce(0) { $0 + $1.kcal }) }

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
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 44)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((DietWeekday.long[day.dayOfWeek] ?? day.dayOfWeek).uppercased())
                .font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("TOTALE GIORNO").font(Typo.mono(9, .bold)).tracking(1).foregroundStyle(Palette.textLow)
                Spacer()
                Text("\(totalKcal)").font(Typo.poster(28)).foregroundStyle(Palette.lime)
                Text("kcal").font(Typo.mono(11, .bold)).foregroundStyle(Palette.lime.opacity(0.7))
            }
            Rectangle().fill(Palette.lime).frame(height: 1).opacity(0.5)
        }
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
