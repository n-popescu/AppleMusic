import SwiftUI

/// Reachable from catalog search results only (see `MusicKitBridge.fetchArtistAlbums`
/// for why library artists aren't wired up to this — their IDs aren't in the
/// catalog ID space the albums-by-artist endpoint needs).
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let gridColumns = [GridItem(.adaptive(minimum: 152), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DetailHeader(
                    artwork: artist.artwork,
                    title: artist.name,
                    subtitle: nil,
                    detail: albums.isEmpty ? nil : "\(albums.count) album\(albums.count == 1 ? "" : "s")",
                    accent: accent.color,
                    isCircular: true
                )

                content
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .auroraBackground(accent: accent.color)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        // No .navigationDestination(for: Album.self) here on purpose —
        // SearchView (the only current entry point to this view) already
        // registers one on its own NavigationStack. Registering it again on
        // a pushed child for the same type is redundant and SwiftUI logs a
        // runtime warning about it (ambiguous destination) even though both
        // would resolve to the same AlbumDetailView.
        .task { await loadAlbums() }
        .task { await accent.load(from: artist.artwork) }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let loadError, albums.isEmpty {
            DetailErrorState(message: loadError) { await loadAlbums() }
        } else if albums.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No albums",
                message: "Nothing was found in the catalog for this artist."
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Albums")
                LazyVGrid(columns: gridColumns, spacing: 22) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
