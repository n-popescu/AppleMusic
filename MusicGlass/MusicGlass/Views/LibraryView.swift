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
    @State private var showNewPlaylistSheet = false

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
            .toolbar {
                if selectedSection == .playlists {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewPlaylistSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            // Pull-to-refresh always hits the network, regardless of how
            // fresh the disk cache is — this is the explicit "I want the
            // real current state" action.
            .refreshable { await store.refreshLibrary(force: true) }
            // Not forced: refreshLibrary() itself now skips the actual
            // fetch when the disk cache is still fresh (see
            // MusicLibraryStore.libraryCacheMaxAge), which is what stops
            // every single launch from re-running the full paginated fetch
            // regardless of how recently it last succeeded. `.task` still
            // only fires once per view lifetime, not on every tab switch,
            // so this isn't a refresh-on-every-tap either way.
            .task {
                await store.refreshLibrary()
            }
            .sheet(isPresented: $showNewPlaylistSheet) {
                NewPlaylistSheet()
                    .environmentObject(store)
            }
            // These must live on the NavigationStack itself, not inside
            // playlistGrid/albumGrid: those are nested in a LazyVGrid inside
            // a switch inside a conditionally-shown ScrollView, and
            // navigationDestination(for:) registered inside a lazy container
            // or a branch that comes and goes can end up missing or
            // duplicated as content loads lazily — Apple's docs call this
            // out explicitly, and on-device (unlike Preview/Simulator this
            // project couldn't test on) it manifests as a real crash rather
            // than just a broken link.
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
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

/// Minimal "New Playlist" flow: name + optional description, reachable from
/// the "+" button in Library > Playlists.
struct NewPlaylistSheet: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(spacing: 14) {
                            TextField("Playlist Name", text: $name)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.white)
                            Divider().background(.white.opacity(0.15))
                            TextField("Description (optional)", text: $description)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.white)
                        }
                    }

                    Button {
                        Task { await create() }
                    } label: {
                        if isCreating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create Playlist")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background { GlassSurface(cornerRadius: 16, tint: .pink) { Color.clear } }
                    .foregroundStyle(.white)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        _ = await store.createPlaylist(name: trimmedName, description: trimmedDescription.isEmpty ? nil : trimmedDescription)
        dismiss()
    }
}

struct TileCard: View {
    let title: String
    let subtitle: String?
    let artwork: Artwork?
    /// Overlays a spinner on the artwork — used while this tile's own play
    /// request is in flight, so tapping it reads as "working" instead of
    /// "did nothing" for however long buffering takes before playback
    /// (and `nowPlaying`) actually updates.
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkImage(artwork: artwork, size: 150, cornerRadius: 14)
                .frame(maxWidth: .infinity)
                .overlay {
                    if isLoading {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.45))
                            .overlay { ProgressView().tint(.white) }
                    }
                }
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
