import SwiftUI

/// Reachable from catalog search results only (see `MusicKitBridge.fetchArtistAlbums`
/// for why library artists aren't wired up to this — their IDs aren't in the
/// catalog ID space the albums-by-artist endpoint needs).
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var store: MusicLibraryStore
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color.clear.glassBackdrop()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        ArtworkImage(artwork: artist.artwork, size: 140, cornerRadius: 70)
                        Text(artist.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else if let loadError, albums.isEmpty {
                            DetailErrorState(message: loadError) {
                                await loadAlbums()
                            }
                            .padding(.horizontal, 16)
                        } else if albums.isEmpty {
                            Text("No albums found for this artist.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.vertical, 12)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                                ForEach(albums) { album in
                                    NavigationLink(value: album) {
                                        TileCard(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        // No .navigationDestination(for: Album.self) here on purpose —
        // SearchView (the only current entry point to this view) already
        // registers one on its own NavigationStack. Registering it again on
        // a pushed child for the same type is redundant and SwiftUI logs a
        // runtime warning about it (ambiguous destination) even though both
        // would resolve to the same AlbumDetailView.
        .task { await loadAlbums() }
    }

    private func loadAlbums() async {
        isLoading = true
        loadError = nil
        store.errorMessage = nil
        albums = await store.albums(forArtist: artist)
        loadError = store.errorMessage
        isLoading = false
    }
}
