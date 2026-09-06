import SwiftUI

/// "Up Next" + "Recently Played". Presented as a sheet from the mini player
/// and from the full-screen player.
struct QueueView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()

                List {
                    upNextSection
                    realRecentlyPlayedSection
                    sessionRecentlyPlayedSection
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
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
                    .foregroundStyle(.white.opacity(0.5))
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
                }
                .onMove { source, destination in
                    Task { await store.moveQueueItem(from: source, to: destination) }
                }
            }
        } header: {
            Text("Up Next")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
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
                Text("Recently Played")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else if !store.recentlyPlayedHistory.isEmpty {
            Section {
                ForEach(store.recentlyPlayedHistory) { item in
                    recentlyPlayedRow(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                }
            } header: {
                Text("Recently Played")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
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
                HStack(spacing: 12) {
                    ArtworkImage(artwork: album.artwork, size: 44, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        Text(album.artistName).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else if let playlist = item.playlist {
            Button {
                Task { await store.play(playlist: playlist) }
            } label: {
                HStack(spacing: 12) {
                    ArtworkImage(artwork: playlist.artwork, size: 44, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        if let curator = playlist.curatorName {
                            Text(curator).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
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
                    .moveDisabled(true)
                }
            } header: {
                Text("This Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct QueueRow: View {
    let item: QueueItem
    var isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(artwork: item.artwork, size: 44, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCurrent ? .pink : .white)
                    .lineLimit(1)
                Text(item.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(.pink)
            }
        }
        .padding(.vertical, 4)
    }
}
