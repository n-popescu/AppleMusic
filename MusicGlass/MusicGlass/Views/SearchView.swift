import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: MusicLibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !store.searchHints.isEmpty {
                        searchHintsRow
                    }

                    if store.isSearching && hasNoResults {
                        VStack(spacing: 14) {
                            ProgressView().tint(.white)
                            Text("Searching…")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                    } else if let error = store.errorMessage, hasNoResults {
                        EmptyStateView(
                            systemImage: "wifi.exclamationmark",
                            title: "Search failed",
                            message: error,
                            actionTitle: "Retry",
                            action: { store.performSearchDebounced() }
                        )
                    } else if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "Search Apple Music",
                            message: "Find songs, albums, artists and playlists across the whole catalog."
                        )
                    } else if hasNoResults {
                        EmptyStateView(
                            systemImage: "questionmark.circle",
                            title: "No results",
                            message: "Nothing matched \u{201c}\(store.searchText)\u{201d}."
                        )
                    } else {
                        if !store.searchResults.songs.isEmpty { songsSection }
                        if !store.searchResults.albums.isEmpty { albumsSection }
                        if !store.searchResults.artists.isEmpty { artistsSection }
                        if !store.searchResults.playlists.isEmpty { playlistsSection }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .auroraBackground()
            .navigationTitle("Search")
            .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: store.searchText) { _, _ in store.performSearchDebounced() }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        }
    }

    // MARK: - Sections

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Songs").padding(.horizontal, 20)
            ContentSurface(padding: 10) {
                LazyVStack(spacing: 6) {
                    ForEach(store.searchResults.songs) { song in
                        SongRow(
                            song: song,
                            isCurrentlyPlaying: store.bridge.nowPlaying.catalogID == song.id
                        ) {
                            Task { await store.play(song: song) }
                        }
                        .onAppear {
                            if song.id == store.searchResults.songs.last?.id {
                                Task { await store.loadMoreSearchSongs() }
                            }
                        }
                    }
                    if store.isLoadingMoreSongs {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var albumsSection: some View {
        tileSection(title: "Albums") {
            ForEach(store.searchResults.albums) { album in
                NavigationLink(value: album) {
                    MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if album.id == store.searchResults.albums.last?.id {
                        Task { await store.loadMoreSearchAlbums() }
                    }
                }
            }
            if store.isLoadingMoreAlbums {
                ProgressView().tint(.white).frame(width: 60)
            }
        }
    }

    private var artistsSection: some View {
        tileSection(title: "Artists") {
            ForEach(store.searchResults.artists) { artist in
                NavigationLink(value: artist) {
                    MediaTile(title: artist.name, subtitle: nil, artwork: artist.artwork, size: 118, isCircular: true)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if artist.id == store.searchResults.artists.last?.id {
                        Task { await store.loadMoreSearchArtists() }
                    }
                }
            }
            if store.isLoadingMoreArtists {
                ProgressView().tint(.white).frame(width: 60)
            }
        }
    }

    private var playlistsSection: some View {
        tileSection(title: "Playlists") {
            ForEach(store.searchResults.playlists) { playlist in
                NavigationLink(value: playlist) {
                    MediaTile(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if playlist.id == store.searchResults.playlists.last?.id {
                        Task { await store.loadMoreSearchPlaylists() }
                    }
                }
            }
            if store.isLoadingMorePlaylists {
                ProgressView().tint(.white).frame(width: 60)
            }
        }
    }

    private func tileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var searchHintsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.searchHints, id: \.self) { hint in
                    Button {
                        store.selectSearchHint(hint)
                    } label: {
                        Label(hint, systemImage: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.primaryText.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                Capsule()
                                    .fill(Palette.contentFill)
                                    .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private var hasNoResults: Bool {
        store.searchResults.songs.isEmpty
            && store.searchResults.albums.isEmpty
            && store.searchResults.artists.isEmpty
            && store.searchResults.playlists.isEmpty
    }
}
