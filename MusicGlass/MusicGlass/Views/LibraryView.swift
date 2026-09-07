import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: MusicLibraryStore

    private enum Section: String, CaseIterable, Identifiable {
        case playlists = "Playlists"
        case albums = "Albums"
        case artists = "Artists"
        case songs = "Songs"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .playlists: return "music.note.list"
            case .albums: return "square.stack"
            case .artists: return "music.mic"
            case .songs: return "music.note"
            }
        }
    }

    @State private var selectedSection: Section = .playlists
    @State private var showNewPlaylistSheet = false
    @Namespace private var sectionNamespace

    private let gridColumns = [GridItem(.adaptive(minimum: 152), spacing: 16)]
    private let artistColumns = [GridItem(.adaptive(minimum: 108), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    sectionPicker
                    content
                }
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .auroraBackground()
            .navigationBarTitleDisplayMode(.inline)
            // Pull-to-refresh always hits the network, regardless of how
            // fresh the disk cache is — this is the explicit "I want the
            // real current state" action.
            .refreshable { await store.refreshLibrary(force: true) }
            // Not forced: refreshLibrary() itself skips the actual fetch when
            // the disk cache is still fresh, which is what stops every launch
            // from re-running the full paginated fetch.
            .task { await store.refreshLibrary() }
            .sheet(isPresented: $showNewPlaylistSheet) {
                NewPlaylistSheet()
                    .environmentObject(store)
            }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            ScreenTitle(title: "Library", subtitle: "Yours")
            Button {
                showNewPlaylistSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(GlassButtonStyle())
            .accessibilityLabel("New Playlist")
        }
        .padding(.horizontal, 20)
    }

    /// Segmented control as a row of pills. The selected pill's fill is a
    /// matched-geometry element so switching sections slides rather than
    /// pops.
    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Section.allCases) { section in
                    let isSelected = selectedSection == section
                    Button {
                        withAnimation(.snappy(duration: 0.28)) { selectedSection = section }
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : Palette.secondaryText)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Palette.accentGradient)
                                        .matchedGeometryEffect(id: "sectionPill", in: sectionNamespace)
                                } else {
                                    Capsule()
                                        .fill(Palette.contentFill)
                                        .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var content: some View {
        if !isCurrentSectionEmpty {
            // Real content — cached or freshly fetched — always wins over
            // every state below. `bridge.isAuthorized` starts false and only
            // flips true once the hidden WKWebView has restored the session,
            // so checking auth first showed "Not signed in" on cold launch
            // even with cached playlists ready to display.
            sectionGrid
                .padding(.horizontal, 20)
        } else if store.isLoadingLibrary && !store.hasLoadedLibraryOnce {
            centered {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Loading your library…")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        } else if let error = store.errorMessage {
            centered {
                EmptyStateView(
                    systemImage: "wifi.exclamationmark",
                    title: "Couldn't load your library",
                    message: error,
                    actionTitle: "Retry",
                    action: { Task { await store.refreshLibrary(force: true) } }
                )
            }
        } else if !store.bridge.isReady {
            // Not yet confirmed either way — avoid flashing "Not signed in"
            // before the bridge has had a chance to restore a session.
            centered { ProgressView().tint(.white) }
        } else if !store.bridge.isAuthorized {
            centered {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "Not signed in",
                    message: "Sign in to Apple Music from the Home tab to see your library."
                )
            }
        } else {
            centered {
                EmptyStateView(
                    systemImage: selectedSection.icon,
                    title: "Nothing here yet",
                    message: "Your \(selectedSection.rawValue.lowercased()) will show up here."
                )
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    @ViewBuilder
    private var sectionGrid: some View {
        switch selectedSection {
        case .playlists:
            LazyVGrid(columns: gridColumns, spacing: 22) {
                ForEach(store.playlists) { playlist in
                    NavigationLink(value: playlist) {
                        MediaTile(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .albums:
            LazyVGrid(columns: gridColumns, spacing: 22) {
                ForEach(store.albums) { album in
                    NavigationLink(value: album) {
                        MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .artists:
            LazyVGrid(columns: artistColumns, spacing: 22) {
                ForEach(store.artists) { artist in
                    NavigationLink(value: artist) {
                        MediaTile(title: artist.name, subtitle: nil, artwork: artist.artwork, size: 108, isCircular: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .songs:
            ContentSurface(padding: 10) {
                LazyVStack(spacing: 6) {
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

    private var isCurrentSectionEmpty: Bool {
        switch selectedSection {
        case .playlists: return store.playlists.isEmpty
        case .albums: return store.albums.isEmpty
        case .artists: return store.artists.isEmpty
        case .songs: return store.songs.isEmpty
        }
    }
}

/// Minimal "New Playlist" flow: name + optional description, reachable from
/// the "+" button in the Library header.
struct NewPlaylistSheet: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ContentSurface {
                    VStack(spacing: 14) {
                        TextField("Playlist Name", text: $name)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                        Divider().background(Palette.hairline)
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
                    }
                }
                .buttonStyle(ProminentActionStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .auroraBackground()
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Palette.background)
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
