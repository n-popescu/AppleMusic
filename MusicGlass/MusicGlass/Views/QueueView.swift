import SwiftUI

/// "Up Next" + "Recently Played". Presented as a sheet from the mini player
/// and from the full-screen player.
struct QueueView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                upNextSection
                realRecentlyPlayedSection
                sessionRecentlyPlayedSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The list used to be pinned in `.active` edit mode, which put a
            // reorder grabber and a delete circle on every row permanently and
            // — because UIKit suppresses swipe-to-delete while a table is
            // editing — was the reason a row couldn't be swiped away at all.
            // Out of edit mode, `.onDelete` gives real swipe-to-delete and
            // `.onMove` still allows long-press drag to reorder.
            .auroraBackground()
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await store.refreshQueue()
                await store.refreshRecentlyPlayedHistory()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
    }

    @ViewBuilder
    private var upNextSection: some View {
        Section {
            if store.isLoadingQueue && store.queue.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if store.queue.items.isEmpty {
                Text("Nothing queued yet. Play something to get started.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.tertiaryText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(store.queue.items.enumerated()), id: \.element.id) { index, item in
                    QueueRow(item: item, isCurrent: index == store.queue.position)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await store.jumpToQueueItem(at: index) }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }
                .onMove { source, destination in
                    Task { await store.moveQueueItem(from: source, to: destination) }
                }
                .onDelete { offsets in
                    guard let index = offsets.first else { return }
                    Task { await store.removeQueueItem(at: index) }
                }
            }
        } header: {
            HStack {
                sectionLabel("Up Next")
                Spacer()
                if store.queue.items.count > 1 {
                    Text("Swipe to remove · hold to reorder")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                        .textCase(nil)
                }
            }
        }
    }

    /// Apple's real, account-tracked history from `/v1/me/recent/played` —
    /// the primary "Recently Played" section now that it's available.
    @ViewBuilder
    private var realRecentlyPlayedSection: some View {
        if store.isLoadingRecentlyPlayedHistory && store.recentlyPlayedHistory.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                sectionLabel("Recently Played")
            }
        } else if !store.recentlyPlayedHistory.isEmpty {
            Section {
                ForEach(store.recentlyPlayedHistory) { item in
                    recentlyPlayedRow(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }
            } header: {
                sectionLabel("Recently Played")
            }
        }
    }

    @ViewBuilder
    private func recentlyPlayedRow(_ item: RecentlyPlayedItem) -> some View {
        if let song = item.song {
            SongRow(song: song, isCurrentlyPlaying: store.bridge.nowPlaying.catalogID == song.id) {
                Task { await store.play(song: song) }
            }
        } else if let album = item.album {
            Button {
                Task { await store.play(album: album) }
            } label: {
                compactRow(artwork: album.artwork, title: album.title, subtitle: album.artistName)
            }
            .buttonStyle(.plain)
        } else if let playlist = item.playlist {
            Button {
                Task { await store.play(playlist: playlist) }
            } label: {
                compactRow(artwork: playlist.artwork, title: playlist.name, subtitle: playlist.curatorName)
            }
            .buttonStyle(.plain)
        }
    }

    private func compactRow(artwork: Artwork?, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            ArtworkImage(artwork: artwork, size: 46, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Session-only list built locally by observing `nowPlaying` changes —
    /// kept as a supplementary section since it updates instantly (no network
    /// round-trip) and reflects anything played this session even before
    /// Apple's own tracked history catches up.
    @ViewBuilder
    private var sessionRecentlyPlayedSection: some View {
        if !store.recentlyPlayed.isEmpty {
            Section {
                ForEach(store.recentlyPlayed) { song in
                    SongRow(
                        song: song,
                        isCurrentlyPlaying: store.bridge.nowPlaying.catalogID == song.id
                    ) {
                        Task { await store.play(song: song) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }
            } header: {
                sectionLabel("This Session")
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.secondaryText)
            .textCase(nil)
    }
}

private struct QueueRow: View {
    let item: QueueItem
    var isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(artwork: item.artwork, size: 46, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Palette.accent : Palette.primaryText)
                    .lineLimit(1)
                Text(item.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
            }
        }
    }
}
