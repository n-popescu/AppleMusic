import Foundation
import Combine

/// Central app state. Views read from this; it's the only thing that talks to `MusicKitBridge`.
@MainActor
final class MusicLibraryStore: ObservableObject {

    let bridge: MusicKitBridge

    @Published var playlists: [Playlist] = []
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var songs: [Song] = []

    @Published var searchText: String = ""
    @Published var searchResults: MusicKitBridge.SearchResults = .init()
    @Published var isSearching = false

    @Published var isLoadingLibrary = false
    @Published var errorMessage: String?
    @Published var hasLoadedLibraryOnce = false

    /// The live "Up Next" queue, refreshed whenever it's requested by `QueueView`.
    @Published var queue: QueueSnapshot = .empty
    @Published var isLoadingQueue = false

    /// Session-only history of what's been played, newest first. MusicKit JS
    /// doesn't expose a "recently played" API of its own here, so this is
    /// built locally by observing `nowPlaying` changes.
    @Published private(set) var recentlyPlayed: [Song] = []

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(bridge: MusicKitBridge = MusicKitBridge()) {
        self.bridge = bridge
        observeNowPlayingForHistory()
    }

    private func observeNowPlayingForHistory() {
        bridge.$nowPlaying
            .removeDuplicates()
            .sink { [weak self] info in
                guard let self, !info.title.isEmpty else { return }
                let song = Song(
                    id: info.catalogID ?? info.title,
                    title: info.title,
                    artistName: info.artistName,
                    albumName: info.albumName.isEmpty ? nil : info.albumName,
                    durationMillis: Int(info.durationSeconds * 1000),
                    artwork: info.artworkURL.map { Artwork(width: nil, height: nil, url: $0) },
                    releaseDate: nil,
                    playParams: info.catalogID.map { PlayParams(id: $0, kind: "song", isLibrary: nil) }
                )
                // Keep it a de-duplicated, bounded MRU list.
                self.recentlyPlayed.removeAll { $0.id == song.id }
                self.recentlyPlayed.insert(song, at: 0)
                if self.recentlyPlayed.count > 50 {
                    self.recentlyPlayed.removeLast(self.recentlyPlayed.count - 50)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Auth

    func signIn() async {
        do {
            try await bridge.waitUntilReady()
            try await bridge.authorize()
            await refreshLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await bridge.unauthorize()
            playlists = []
            albums = []
            artists = []
            songs = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Library

    func refreshLibrary() async {
        guard bridge.isAuthorized else { return }
        isLoadingLibrary = true
        errorMessage = nil
        defer {
            isLoadingLibrary = false
            hasLoadedLibraryOnce = true
        }

        async let playlistsResult = bridge.fetchLibraryPlaylists()
        async let albumsResult = bridge.fetchLibraryAlbums()
        async let artistsResult = bridge.fetchLibraryArtists()
        async let songsResult = bridge.fetchLibrarySongs()

        do {
            playlists = try await playlistsResult
            albums = try await albumsResult
            artists = try await artistsResult
            songs = try await songsResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tracks(forPlaylist playlist: Playlist) async -> [Song] {
        do {
            return try await bridge.fetchPlaylistTracks(id: playlist.id)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func tracks(forAlbum album: Album) async -> [Song] {
        do {
            return try await bridge.fetchAlbumTracks(id: album.id)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Search

    func performSearchDebounced() {
        searchTask?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchResults = .init()
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let results = try await bridge.search(term: term)
                if !Task.isCancelled {
                    searchResults = results
                    errorMessage = nil
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Playback

    func play(song: Song) async {
        guard let params = song.playParams else { return }
        do {
            try await bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func play(album: Album) async {
        guard let params = album.playParams else { return }
        do {
            try await bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func play(playlist: Playlist) async {
        guard let params = playlist.playParams else { return }
        do {
            try await bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Queue (Up Next)

    func refreshQueue() async {
        isLoadingQueue = true
        defer { isLoadingQueue = false }
        do {
            queue = try await bridge.fetchQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func jumpToQueueItem(at index: Int) async {
        do {
            try await bridge.jumpToQueueItem(at: index)
            await refreshQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) async {
        guard let from = source.first else { return }
        // Optimistically reorder locally so the UI feels instant, then ask
        // the bridge to make it real and reconcile with the authoritative state.
        var items = queue.items
        guard items.indices.contains(from) else { return }
        let adjustedDestination = destination > from ? destination - 1 : destination
        let moved = items.remove(at: from)
        items.insert(moved, at: min(max(adjustedDestination, 0), items.count))
        queue.items = items

        do {
            try await bridge.moveQueueItem(from: from, to: adjustedDestination)
            await refreshQueue()
        } catch {
            errorMessage = error.localizedDescription
            await refreshQueue()
        }
    }
}
