import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DetailHeader(
                    artwork: album.artwork,
                    title: album.title,
                    subtitle: album.artistName,
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
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
        .task { await accent.load(from: album.artwork) }
    }

    private var trackCountLabel: String? {
        tracks.isEmpty ? nil : "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.play(album: album) }
            } label: {
                if store.pendingPlaybackID == album.id {
                    ProgressView().tint(.white)
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .buttonStyle(ProminentActionStyle())
            .disabled(store.pendingPlaybackID != nil)

            if let kind = album.playParams?.kind {
                Menu {
                    Button {
                        Task { await store.setRating(id: album.id, kind: kind, value: 1) }
                    } label: {
                        Label("Love", systemImage: "heart")
                    }
                    Button {
                        Task { await store.setRating(id: album.id, kind: kind, value: -1) }
                    } label: {
                        Label("Dislike", systemImage: "hand.thumbsdown")
                    }
                    if album.playParams?.isLibrary != true {
                        Button {
                            Task { await store.addToLibrary(id: album.id, kind: kind) }
                        } label: {
                            Label("Add to Library", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                        .frame(height: 50)
                        .padding(.horizontal, 18)
                        .background {
                            Capsule()
                                .fill(Palette.contentFillRaised)
                                .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
                        }
                }
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
                systemImage: "square.stack",
                title: "No tracks",
                message: "This album has no playable tracks."
            )
        } else {
            ContentSurface(padding: 10, tint: accent.color) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.tertiaryText)
                                .frame(width: 20)
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
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        store.errorMessage = nil
        tracks = await store.tracks(forAlbum: album)
        loadError = store.errorMessage
        isLoading = false
    }
}
