import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: MusicLibraryStore

    private enum Section: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"
        case songs = "Songs"
        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .playlists

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()

                VStack(spacing: 0) {
                    sectionPicker

                    if store.isLoadingLibrary && !store.hasLoadedLibraryOnce {
                        Spacer()
                        ProgressView("Loading your library…")
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    } else if let error = store.errorMessage, isCurrentSectionEmpty {
                        Spacer()
                        errorState(message: error)
                        Spacer()
                    } else if !store.bridge.isAuthorized {
                        Spacer()
                        emptyState(
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            title: "Not signed in",
                            message: "Sign in to Apple Music from the Account tab to see your library."
                        )
                        Spacer()
                    } else if isCurrentSectionEmpty {
                        Spacer()
                        emptyState(
                            systemImage: "music.note.list",
                            title: "Nothing here yet",
                            message: "Your \(selectedSection.rawValue.lowercased()) will show up here."
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                switch selectedSection {
                                case .playlists: playlistGrid
                                case .albums: albumGrid
                                case .artists: artistGrid
                                case .songs: songList
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 120) // room for the mini player
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await store.refreshLibrary() }
            .task {
                if store.playlists.isEmpty { await store.refreshLibrary() }
            }
        }
    }

    private var isCurrentSectionEmpty: Bool {
        switch selectedSection {
        case .playlists: return store.playlists.isEmpty
        case .albums: return store.albums.isEmpty
        case .artists: return store.artists.isEmpty
        case .songs: return store.songs.isEmpty
        }
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
        .padding(.horizontal, 32)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load your library")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refreshLibrary() }
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
        .padding(.horizontal, 32)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { section in
                    Button {
                        withAnimation(.snappy) { selectedSection = section }
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selectedSection == section {
                            GlassSurface(cornerRadius: 16, tint: .pink) { Color.clear }
                        } else {
                            GlassSurface(cornerRadius: 16) { Color.clear }
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var playlistGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(store.playlists) { playlist in
                NavigationLink(value: playlist) {
                    TileCard(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(store.albums) { album in
                NavigationLink(value: album) {
                    TileCard(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }

    private var artistGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
            ForEach(store.artists) { artist in
                VStack(spacing: 8) {
                    ArtworkImage(artwork: artist.artwork, size: 96, cornerRadius: 48)
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }

    private var songList: some View {
        GlassCard {
            VStack(spacing: 14) {
                ForEach(store.songs) { song in
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

struct TileCard: View {
    let title: String
    let subtitle: String?
    let artwork: Artwork?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkImage(artwork: artwork, size: 150, cornerRadius: 14)
                .frame(maxWidth: .infinity)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}
