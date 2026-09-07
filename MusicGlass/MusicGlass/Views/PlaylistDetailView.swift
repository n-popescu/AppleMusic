import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DetailHeader(
                    artwork: playlist.artwork,
                    title: playlist.name,
                    subtitle: playlist.curatorName,
                    detail: trackCountLabel,
                    accent: accent.color
                )

                actions
                    .padding(.horizontal, 20)

                trackList
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .auroraBackground(accent: accent.color)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
        .task { await accent.load(from: playlist.artwork) }
    }

    private var trackCountLabel: String? {
        tracks.isEmpty ? nil : "\(tracks.count) song\(tracks.count == 1 ? "" : "s")"
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.play(playlist: playlist) }
            } label: {
                if store.pendingPlaybackID == playlist.id {
                    ProgressView().tint(.white)
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .buttonStyle(ProminentActionStyle())
            .disabled(store.pendingPlaybackID != nil)

            Button {
                Task { await store.shufflePlay(playlist: playlist) }
            } label: {
                Image(systemName: "shuffle")
            }
            .buttonStyle(SecondaryActionStyle())
            .disabled(store.pendingPlaybackID != nil)

            if let kind = playlist.playParams?.kind, playlist.playParams?.isLibrary != true {
                Button {
                    Task { await store.addToLibrary(id: playlist.id, kind: kind) }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(SecondaryActionStyle())
            }
        }
    }

    @ViewBuilder
    private var trackList: some View {
        if isLoading {
            ProgressView().tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let loadError, tracks.isEmpty {
            DetailErrorState(message: loadError) { await loadTracks() }
        } else if tracks.isEmpty {
            EmptyStateView(
                systemImage: "music.note.list",
                title: "No tracks",
                message: "This playlist is empty."
            )
        } else {
            ContentSurface(padding: 10, tint: accent.color) {
                LazyVStack(spacing: 6) {
                    ForEach(tracks) { song in
                        SongRow(
                            song: song,
                            isCurrentlyPlaying: store.bridge.nowPlaying.catalogID == song.id
                        ) {
                            Task { await store.play(song: song) }
                        }
                    }
                }
            }
        }
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        store.errorMessage = nil
        tracks = await store.tracks(forPlaylist: playlist)
        loadError = store.errorMessage
        isLoading = false
    }
}
