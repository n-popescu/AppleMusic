import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: MusicLibraryStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !store.searchHints.isEmpty {
                            searchHintsRow
                        }

                        if store.isSearching {
                            ProgressView().tint(.white).padding(.top, 40)
                        } else if let error = store.errorMessage, hasNoResults {
                            errorState(message: error)
                        } else if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            emptyState(
                                systemImage: "magnifyingglass",
                                title: "Search Apple Music",
                                message: "Find songs, albums, artists and playlists in the catalog."
                            )
                        } else if hasNoResults {
                            emptyState(
                                systemImage: "questionmark.circle",
                                title: "No results",
                                message: "Nothing matched \u{201c}\(store.searchText)\u{201d}."
                            )
                        } else if !store.searchResults.songs.isEmpty {
                            resultSection(title: "Songs") {
                                GlassCard {
                                    VStack(spacing: 14) {
                                        ForEach(store.searchResults.songs) { song in
                                            SongRow(song: song) {
                                                Task { await store.play(song: song) }
                                            }
                                            .onAppear {
                                                if song.id == store.searchResults.songs.last?.id {
                                                    Task { await store.loadMoreSearchSongs() }
                                                }
                                            }
                                        }
                                        if store.isLoadingMoreSongs {
                                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }

                        if !store.searchResults.albums.isEmpty {
                            resultSection(title: "Albums") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(store.searchResults.albums) { album in
                                            NavigationLink(value: album) {
                                                TileCard(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .onAppear {
                                                if album.id == store.searchResults.albums.last?.id {
                                                    Task { await store.loadMoreSearchAlbums() }
                                                }
                                            }
                                        }
                                        if store.isLoadingMoreAlbums {
                                            ProgressView().tint(.white).frame(width: 140)
                                        }
                                    }
                                }
                            }
                        }

                        if !store.searchResults.artists.isEmpty {
                            resultSection(title: "Artists") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(store.searchResults.artists) { artist in
                                            NavigationLink(value: artist) {
                                                TileCard(title: artist.name, subtitle: nil, artwork: artist.artwork)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .onAppear {
                                                if artist.id == store.searchResults.artists.last?.id {
                                                    Task { await store.loadMoreSearchArtists() }
                                                }
                                            }
                                        }
                                        if store.isLoadingMoreArtists {
                                            ProgressView().tint(.white).frame(width: 140)
                                        }
                                    }
                                }
                            }
                        }

                        if !store.searchResults.playlists.isEmpty {
                            resultSection(title: "Playlists") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(store.searchResults.playlists) { playlist in
                                            NavigationLink(value: playlist) {
                                                TileCard(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .onAppear {
                                                if playlist.id == store.searchResults.playlists.last?.id {
                                                    Task { await store.loadMoreSearchPlaylists() }
                                                }
                                            }
                                        }
                                        if store.isLoadingMorePlaylists {
                                            ProgressView().tint(.white).frame(width: 140)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $store.searchText, placement: .navigationBarDrawer(displayMode: .always))
            .onChange(of: store.searchText) { _, _ in store.performSearchDebounced() }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist)
            }
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background { GlassSurface(cornerRadius: 14) { Color.clear } }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var hasNoResults: Bool {
        store.searchResults.songs.isEmpty
            && store.searchResults.albums.isEmpty
            && store.searchResults.artists.isEmpty
            && store.searchResults.playlists.isEmpty
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.4))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Search failed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                store.performSearchDebounced()
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background { GlassSurface(cornerRadius: 14, tint: .pink) { Color.clear } }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func resultSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            content()
        }
    }

}
