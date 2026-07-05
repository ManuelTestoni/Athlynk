//
//  MealDetailView.swift
//  Stitch "Dettaglio Pasto": a single meal's total calories + macro summary and
//  the per-food breakdown. Reuses MealDTO from the nutrition feed.
//

import SwiftUI

struct MealDetailView: View {
    let meal: MealDTO
    var accent: Color = Palette.lime

    private var protein: Double { meal.items.reduce(0) { $0 + $1.protein } }
    private var carbs: Double { meal.items.reduce(0) { $0 + $1.carbs } }
    private var fat: Double { meal.items.reduce(0) { $0 + $1.fat } }

    @State private var appear = false

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.lime, Palette.cyan, Palette.amber, Palette.lime])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header.revealUp(appear, index: 0)
                    totalsCard.revealUp(appear, index: 1)
                    Text("ALIMENTI").voltEyebrow().revealUp(appear, index: 2)
                    ForEach(Array(meal.items.enumerated()), id: \.element.id) { i, item in
                        itemRow(item).revealUp(appear, index: min(i, 6) + 3)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = meal.timeOfDay, !t.isEmpty {
                Text(t.uppercased()).font(Typo.mono(10, .bold)).tracking(2).foregroundStyle(accent)
            }
            Text(meal.name).font(Typo.poster(36)).foregroundStyle(Palette.textHi)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(accent).frame(height: 1).opacity(0.5)
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TOTALE PASTO").voltEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(meal.kcal))").font(Typo.poster(44)).foregroundStyle(accent)
                Text("kcal").font(Typo.mono(14, .bold)).foregroundStyle(Palette.textMid)
            }
            HStack(spacing: 10) {
                macroCol("PRO", protein, Palette.magenta)
                macroCol("CAR", carbs, Palette.cyan)
                macroCol("FAT", fat, Palette.amber)
            }
        }
        .padding(18).voltPanel(accent.opacity(0.4))
    }

    private func macroCol(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(grams))g").font(Typo.mono(18, .black)).foregroundStyle(color)
            Text(label).font(Typo.mono(8, .bold)).tracking(1).foregroundStyle(Palette.textLow)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.void2))
    }

    private func itemRow(_ item: MealItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name ?? "—").font(Typo.display(17)).foregroundStyle(Palette.textHi)
                Spacer()
                Text("\(Int(item.quantityG))g")
                    .font(Typo.mono(13, .bold)).foregroundStyle(Palette.textMid)
                Text("· \(Int(item.kcal)) kcal")
                    .font(Typo.mono(13, .bold)).foregroundStyle(accent)
            }
            HStack(spacing: 16) {
                miniMacro("P", item.protein, Palette.magenta)
                miniMacro("C", item.carbs, Palette.cyan)
                miniMacro("F", item.fat, Palette.amber)
                Spacer()
            }
        }
        .padding(16).voltPanel(accent.opacity(0.3))
    }

    private func miniMacro(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(letter).font(Typo.mono(10, .black)).foregroundStyle(color)
            Text("\(Int(grams))g").font(Typo.mono(11, .semibold)).foregroundStyle(Palette.textMid)
        }
    }
}
