//
//  DashboardEditSheet.swift
//  Role-agnostic editor for the customizable dashboard (athlete + coach apps).
//
//  Native reorder (.onMove) over the active widgets, remove, and an "add"
//  section listing the remaining catalog. Every mutation normalizes the
//  canonical order (y = index) and calls `onChanged` — the owning VM
//  debounces the PUT, so edits autosave like the web grid.
//

import SwiftUI

struct DashboardEditSheet: View {
    @Binding var widgets: [DashboardWidgetDTO]
    let catalog: [WidgetCatalogItemDTO]
    /// Called after any mutation; owner debounces + PUTs the layout.
    var onChanged: () -> Void
    /// Reset to the server's role default (DELETE), then refresh.
    var onReset: () -> Void
    /// Coach app hooks the pinned-athletes picker here (widget index).
    var onConfigure: ((Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var available: [WidgetCatalogItemDTO] {
        let placed = Set(widgets.map(\.type))
        return catalog.filter { !placed.contains($0.type) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                        row(widget, index: index)
                    }
                    .onMove { from, to in
                        widgets.move(fromOffsets: from, toOffset: to)
                        normalizeAndNotify()
                    }
                    .onDelete { offsets in
                        widgets.remove(atOffsets: offsets)
                        normalizeAndNotify()
                    }
                } header: {
                    Text("WIDGET ATTIVI")
                        .font(Typo.mono(10, .semibold)).tracking(2)
                        .foregroundStyle(Palette.textMid)
                } footer: {
                    Text("Trascina per riordinare. L'ordine si sincronizza con la web app.")
                        .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                }

                if !available.isEmpty {
                    Section {
                        ForEach(available) { entry in
                            addRow(entry)
                        }
                    } header: {
                        Text("AGGIUNGI WIDGET")
                            .font(Typo.mono(10, .semibold)).tracking(2)
                            .foregroundStyle(Palette.textMid)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Palette.void0)
            .navigationTitle("Personalizza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ripristina") {
                        Haptics.soft()
                        onReset()
                    }
                    .font(Typo.body(14)).tint(Palette.danger)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fatto") { dismiss() }
                        .font(Typo.body(15, .semibold)).tint(Palette.primary)
                }
            }
        }
    }

    private func row(_ widget: DashboardWidgetDTO, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: catalogEntry(widget.type)?.sfSymbol ?? "square.grid.2x2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.control)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(catalogEntry(widget.type)?.title ?? widget.type)
                    .font(Typo.body(15, .medium)).foregroundStyle(Palette.textHi)
                if widget.type == "pinned_athletes" {
                    Text(pinnedSubtitle(widget))
                        .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            if widget.type == "pinned_athletes", let onConfigure {
                Button {
                    Haptics.tap()
                    onConfigure(index)
                } label: {
                    Text("Scegli")
                        .font(Typo.mono(11, .bold)).tracking(1)
                        .foregroundStyle(Palette.control)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addRow(_ entry: WidgetCatalogItemDTO) -> some View {
        Button {
            Haptics.tap()
            widgets.append(DashboardWidgetDTO(
                id: "wg_\(entry.type)", type: entry.type,
                x: 0, y: widgets.count, size: "M", config: nil))
            normalizeAndNotify()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.success)
                Image(systemName: entry.sfSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textMid)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(Typo.body(15, .medium)).foregroundStyle(Palette.textHi)
                    Text(entry.desc)
                        .font(Typo.body(12)).foregroundStyle(Palette.textLow)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func catalogEntry(_ type: String) -> WidgetCatalogItemDTO? {
        catalog.first { $0.type == type }
    }

    private func pinnedSubtitle(_ widget: DashboardWidgetDTO) -> String {
        let n = widget.config?.clientIds?.count ?? 0
        return n == 0 ? "Nessun atleta scelto" : "\(n) atleti in evidenza"
    }

    /// Canonical cross-platform order lives in the array; rewrite y = index so
    /// the web grid re-flows to the mobile ordering on next load.
    private func normalizeAndNotify() {
        for i in widgets.indices {
            widgets[i].y = i
            widgets[i].x = 0
        }
        onChanged()
    }
}
