import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
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
                            Task { await store.play(playlist: playlist) }
                        } label: {
                            Group {
                                if store.pendingPlaybackID == playlist.id {
                                    ProgressView().tint(.white)
                                } else {
                                    Label("Play", systemImage: "play.fill")
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .background { GlassSurface(cornerRadius: 18, tint: .pink) { Color.clear } }
                        .foregroundStyle(.white)
                        .disabled(store.pendingPlaybackID != nil)

                        Button {
                            Task { await store.shufflePlay(playlist: playlist) }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .background { GlassSurface(cornerRadius: 18) { Color.clear } }
                        .foregroundStyle(.white)
                        .disabled(store.pendingPlaybackID != nil)

                        if let kind = playlist.playParams?.kind, playlist.playParams?.isLibrary != true {
                            Button {
                                Task { await store.addToLibrary(id: playlist.id, kind: kind) }
                            } label: {
                                Image(systemName: "plus.circle")
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
                                Text("This playlist has no tracks.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.vertical, 12)
                            } else {
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }

    private func loadTracks() async {
        isLoading = true
        loadError = nil
        store.errorMessage = nil
        tracks = await store.tracks(forPlaylist: playlist)
        loadError = store.errorMessage
        isLoading = false
    }

    private var header: some View {
        VStack(spacing: 10) {
            ArtworkImage(artwork: playlist.artwork, size: 180, cornerRadius: 18)
            Text(playlist.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let curator = playlist.curatorName {
                Text(curator)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
