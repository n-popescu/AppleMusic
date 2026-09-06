import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var store: MusicLibraryStore
    @State private var tracks: [Song] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color.clear.glassBackdrop()
            ScrollView {
                VStack(spacing: 20) {
                    header

                    HStack(spacing: 12) {
                        Button {
                            Task { await store.play(album: album) }
                        } label: {
                            Label("Play Album", systemImage: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .background { GlassSurface(cornerRadius: 18, tint: .pink) { Color.clear } }
                        .foregroundStyle(.white)

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
                                    .frame(width: 44, height: 44)
                            }
                            .background { GlassSurface(cornerRadius: 18) { Color.clear } }
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16)

                    GlassCard {
                        VStack(spacing: 14) {
                            if isLoading {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else if let loadError, tracks.isEmpty {
                                DetailErrorState(message: loadError) {
                                    await loadTracks()
                                }
                            } else if tracks.isEmpty {
                                Text("This album has no tracks.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                                    HStack(spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.4))
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        store.errorMessage = nil
        tracks = await store.tracks(forAlbum: album)
        loadError = store.errorMessage
        isLoading = false
    }

    private var header: some View {
        VStack(spacing: 10) {
            ArtworkImage(artwork: album.artwork, size: 180, cornerRadius: 18)
            Text(album.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(album.artistName)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}
