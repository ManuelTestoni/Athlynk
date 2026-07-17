//
//  CalendarFeedView.swift
//  Google/Apple Calendar subscription screen — shared by both apps (athlete's
//  own agenda and the coach's agenda are the same UI, different endpoint).
//

import SwiftUI

struct CalendarFeedView: View {
    let load: () async throws -> CalendarFeedDTO
    let rotate: () async throws -> CalendarFeedDTO

    @Environment(\.dismiss) private var dismiss
    @State private var feed: CalendarFeedDTO?
    @State private var loading = true
    @State private var rotating = false

    var body: some View {
        NavigationStack {
            Form {
                if let feed {
                    Section("Google Calendar") {
                        Link(destination: URL(string: feed.googleSubscribeUrl)!) {
                            Label("Aggiungi a Google Calendar", systemImage: "arrow.up.right.square")
                        }
                    }
                    Section("Apple Calendar") {
                        Link(destination: URL(string: feed.webcalUrl)!) {
                            Label("Aggiungi a Apple Calendar", systemImage: "arrow.up.right.square")
                        }
                    }
                    Section {
                        Button {
                            UIPasteboard.general.string = feed.feedUrl
                            Haptics.success()
                        } label: {
                            Label("Copia link feed", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            Task { await rotateFeed() }
                        } label: {
                            HStack {
                                Text("Rigenera link")
                                if rotating { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(rotating)
                    } footer: {
                        Text("Rigenerando il link, quello precedente smette di funzionare nei calendari già collegati.")
                    }
                } else if loading {
                    ProgressView()
                }
            }
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .task { await loadFeed() }
        }
    }

    private func loadFeed() async {
        loading = true; defer { loading = false }
        feed = try? await load()
    }

    private func rotateFeed() async {
        rotating = true; defer { rotating = false }
        feed = try? await rotate()
    }
}
