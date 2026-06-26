//
//  SupplementsView.swift
//  Stitch "Integratori" / "Il Tuo Protocollo": the athlete's active supplement
//  protocol — each item with dose, timing and the coach's note.
//  Backed by GET /api/v1/supplements (SupplementAssignment → sheet → items).
//

import SwiftUI

struct SupplementsView: View {
    @State private var sheets: [SupplementSheetDTO] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            VoltBackground(palette: [Palette.amber, Palette.lime, Palette.magenta, Palette.amber])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if loading {
                        SupplementsSkeleton(count: 3)
                    } else if let error {
                        EmptyPanel(icon: "wifi.exclamationmark", text: error, color: Palette.amber)
                    } else if sheets.isEmpty {
                        EmptyPanel(icon: "pills", text: "Nessun integratore assegnato.")
                    } else {
                        ForEach(sheets) { sheet in
                            if sheets.count > 1 || !(sheet.title.isEmpty) {
                                HStack {
                                    Text(sheet.title).font(Typo.display(20)).foregroundStyle(Palette.textHi)
                                    Spacer()
                                    if let c = sheet.coach { CoachChip(coach: c, color: Palette.amber) }
                                }
                            }
                            if let n = sheet.notes, !n.isEmpty {
                                Text(n).font(Typo.body(13)).foregroundStyle(Palette.textMid)
                            }
                            ForEach(Array(sheet.items.enumerated()), id: \.element.id) { i, item in
                                itemCard(item, index: i)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 40)
            }
        }
        .navigationTitle("Integratori")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTEGRAZIONE").font(Typo.mono(10, .bold)).tracking(3).foregroundStyle(Palette.amber)
            Text("Il Tuo Protocollo").font(Typo.poster(34)).foregroundStyle(Palette.textHi)
            Text("Mantieni la costanza. Segui le indicazioni del coach per massimizzare recupero e prestazioni.")
                .font(Typo.body(14)).foregroundStyle(Palette.textMid)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Palette.amber).frame(height: 1).opacity(0.5)
        }
    }

    private func itemCard(_ item: SupplementItemDTO, index: Int) -> some View {
        let accent = Palette.accent(index)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .black)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(Typo.display(19)).foregroundStyle(Palette.textHi)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if !item.dose.isEmpty { tag("scalemass.fill", item.dose) }
                if let t = item.timing, !t.isEmpty { tag("clock.fill", t) }
            }
            if let n = item.notes, !n.isEmpty {
                Text(n).font(Typo.body(13)).foregroundStyle(Palette.textMid)
            }
        }
        .padding(16).voltPanel(accent.opacity(0.4))
    }

    private func tag(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(Typo.mono(11, .bold))
        }
        .foregroundStyle(Palette.textHi)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Palette.void2))
    }

    private func load() async {
        loading = true; error = nil
        do { sheets = try await APIClient.shared.supplements() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
