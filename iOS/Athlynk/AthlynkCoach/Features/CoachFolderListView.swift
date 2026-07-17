//
//  CoachFolderListView.swift
//  Folder management for workout schede, nutrition piani and check templates —
//  the coach-side taxonomy the web app has had for a while (WorkoutFolder /
//  NutritionFolder / CheckFolder), previously entirely missing on iOS. One
//  generic screen reused for all three domains: same CRUD shape server-side,
//  same "Non archiviati" + folder list + paginated content UI.
//

import SwiftUI

extension CoachFolderDomain {
    var accent: Color {
        switch self {
        case .workout: return Palette.cyan
        case .nutrition: return Palette.lime
        case .check: return Palette.violet
        }
    }
    var title: String {
        switch self {
        case .workout: return "Cartelle allenamento"
        case .nutrition: return "Cartelle nutrizione"
        case .check: return "Cartelle check"
        }
    }
    var itemNounPlural: String {
        switch self {
        case .workout: return "schede"
        case .nutrition: return "piani"
        case .check: return "modelli"
        }
    }
}

/// Display-only row shape a folder's contents are mapped into, so one content
/// view works for CoachPlanRow (workout/nutrition) and CoachFolderedCheckTemplate
/// (check) alike without forcing them into a shared network model.
struct FolderRowItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
}

// MARK: - Folder list

struct CoachFolderListView: View {
    let domain: CoachFolderDomain
    /// One page of a folder's contents, mapped to display rows. `folderId` is
    /// "unfiled" or a numeric id as a string.
    let loadPage: (_ folderId: String, _ offset: Int) async throws -> (rows: [FolderRowItem], hasMore: Bool)
    let destination: (Int) -> AnyView

    @EnvironmentObject private var confirmCenter: ConfirmCenter
    @State private var folders: [CoachFolder] = []
    @State private var loading = true
    @State private var creating = false
    @State private var editingFolder: CoachFolder?
    @State private var folderTitle = ""
    @State private var saving = false
    @StateObject private var flash = StatusFlash()

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: "Organizzazione", title: domain.title, accent: domain.accent)

            if loading {
                AvatarRowsSkeleton(accent: domain.accent)
            } else {
                NavigationLink {
                    CoachFolderContentView(domain: domain, folderId: "unfiled", folderTitle: "Non archiviati",
                                           accent: domain.accent, loadPage: loadPage, destination: destination)
                } label: {
                    folderRow(icon: "tray", title: "Non archiviati", subtitle: nil)
                }
                .buttonStyle(PressableButtonStyle())

                ForEach(folders) { f in
                    NavigationLink {
                        CoachFolderContentView(domain: domain, folderId: "\(f.id)", folderTitle: f.title,
                                               accent: domain.accent, loadPage: loadPage, destination: destination)
                    } label: {
                        folderRow(icon: f.isDefaultTemplates ? "square.on.square" : "folder.fill", title: f.title,
                                  subtitle: "\(f.count) \(domain.itemNounPlural)")
                    }
                    .buttonStyle(PressableButtonStyle())
                    .contextMenu {
                        if !f.isDefaultTemplates {
                            Button { startRename(f) } label: { Label("Rinomina", systemImage: "pencil") }
                            Button(role: .destructive) { delete(f) } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                }

                Button { startCreate() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Nuova cartella")
                    }
                    .font(Typo.body(15, .semibold)).foregroundStyle(domain.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(domain.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .statusOverlay(flash)
        .sheet(isPresented: $creating) { editorSheet(isNew: true) }
        .sheet(item: $editingFolder) { _ in editorSheet(isNew: false) }
    }

    private func folderRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(domain.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.body(15, .semibold)).foregroundStyle(Palette.textHi).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.textLow)
        }
        .padding(14).voltPanel()
    }

    @ViewBuilder
    private func editorSheet(isNew: Bool) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                VoltField(icon: "folder", placeholder: "Nome cartella", text: $folderTitle, accent: domain.accent)
                NeonButton(title: isNew ? "Crea cartella" : "Salva", color: domain.accent, loading: saving) {
                    Task { await save(isNew: isNew) }
                }
                Spacer()
            }
            .padding(20)
            .background(Palette.void0.ignoresSafeArea())
            .navigationTitle(isNew ? "Nuova cartella" : "Rinomina cartella")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Annulla") { creating = false; editingFolder = nil }.tint(Palette.textMid)
            } }
        }
        .presentationDetents([.height(260)])
    }

    private func startCreate() {
        Haptics.tap(); folderTitle = ""; creating = true
    }

    private func startRename(_ f: CoachFolder) {
        Haptics.tap(); folderTitle = f.title; editingFolder = f
    }

    private func save(isNew: Bool) async {
        let title = folderTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        saving = true; defer { saving = false }
        do {
            if isNew {
                _ = try await APIClient.shared.coachCreateFolder(domain, title: title)
            } else if let f = editingFolder {
                _ = try await APIClient.shared.coachRenameFolder(domain, folderId: f.id, title: title)
            }
            Haptics.success()
            creating = false; editingFolder = nil
            await load()
        } catch {
            flash.failure("Salvataggio non riuscito")
        }
    }

    private func delete(_ f: CoachFolder) {
        Task {
            guard await confirmCenter.confirm(.init(
                title: "Eliminare la cartella?",
                subtitle: f.count > 0
                    ? "\"\(f.title)\" contiene \(f.count) \(domain.itemNounPlural)."
                    : "\"\(f.title)\" verrà eliminata.",
                icon: "trash")) else { return }

            var action = "move_to_unfiled"
            if f.count > 0 {
                let deleteContentsToo = await confirmCenter.confirm(.init(
                    title: "Cosa fare del contenuto?",
                    subtitle: "Puoi spostare \(domain.itemNounPlural) in \"Non archiviati\" oppure eliminarli insieme alla cartella.",
                    icon: "tray.and.arrow.down",
                    variant: .danger,
                    confirmLabel: "Elimina anche il contenuto",
                    cancelLabel: "Sposta in Non archiviati"))
                action = deleteContentsToo ? "delete_plans" : "move_to_unfiled"
            }
            do {
                try await APIClient.shared.coachDeleteFolder(domain, folderId: f.id, action: action)
                Haptics.success()
                await load()
            } catch {
                flash.failure("Eliminazione non riuscita")
            }
        }
    }

    private func load() async {
        loading = folders.isEmpty
        defer { loading = false }
        let fetched = (try? await APIClient.shared.coachFolders(domain)) ?? []
        // The default "Template" folder is always pinned first.
        folders = fetched.sorted { $0.isDefaultTemplates && !$1.isDefaultTemplates }
    }
}

// MARK: - Folder content (paginated)

private struct CoachFolderContentView: View {
    let domain: CoachFolderDomain
    let folderId: String
    let folderTitle: String
    let accent: Color
    let loadPage: (_ folderId: String, _ offset: Int) async throws -> (rows: [FolderRowItem], hasMore: Bool)
    let destination: (Int) -> AnyView

    @State private var rows: [FolderRowItem] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false

    var body: some View {
        ScreenScroll {
            ScreenHeader(eyebrow: domain.itemNounPlural.uppercased(), title: folderTitle, accent: accent)

            if loading {
                AvatarRowsSkeleton(accent: accent)
            } else if rows.isEmpty {
                EmptyPanel(icon: "tray", text: "Nessun elemento in questa cartella.")
            } else {
                ForEach(rows) { row in
                    NavigationLink { destination(row.id) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(Typo.body(15, .semibold))
                                    .foregroundStyle(Palette.textHi).lineLimit(1)
                                if !row.subtitle.isEmpty {
                                    Text(row.subtitle).font(Typo.mono(10)).foregroundStyle(Palette.textLow)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.textLow)
                        }
                        .padding(14).voltPanel()
                    }
                    .buttonStyle(PressableButtonStyle())
                    .swipeActions(edge: .trailing) {
                        if folderId != "unfiled" {
                            Button {
                                Task { await unfile(row) }
                            } label: { Label("Rimuovi da cartella", systemImage: "tray") }
                            .tint(Palette.textMid)
                        }
                    }
                }
                if hasMore {
                    LoadMoreButton(loading: loadingMore, accent: accent) { Task { await loadMore() } }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        guard let page = try? await loadPage(folderId, 0) else { return }
        rows = page.rows; hasMore = page.hasMore
    }

    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        guard let page = try? await loadPage(folderId, rows.count) else { return }
        rows.append(contentsOf: page.rows); hasMore = page.hasMore
    }

    private func unfile(_ row: FolderRowItem) async {
        Haptics.tap()
        _ = try? await APIClient.shared.coachMoveItemToFolder(domain, itemId: row.id, folderId: nil)
        rows.removeAll { $0.id == row.id }
    }
}
