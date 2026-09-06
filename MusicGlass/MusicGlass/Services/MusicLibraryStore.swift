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

    /// Session-only history of what's been played, newest first, built locally
    /// by observing `nowPlaying` changes. Kept as a supplementary "This
    /// Session" list in `QueueView` now that `recentlyPlayedHistory` below
    /// surfaces Apple's own tracked history as the primary list.
    @Published private(set) var recentlyPlayed: [Song] = []

    /// Apple's real, account-tracked history from `/v1/me/recent/played`.
    @Published var recentlyPlayedHistory: [RecentlyPlayedItem] = []
    @Published var isLoadingRecentlyPlayedHistory = false

    // MARK: - Discovery

    @Published var recommendations: [RecommendationItem] = []
    @Published var charts: ChartsResult = .init()
    @Published var stations: [Station] = []
    @Published var isLoadingDiscover = false

    // MARK: - Search hints

    @Published var searchHints: [String] = []

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Weak reference to the most recently created store, so App Intents
    /// (which have no SwiftUI environment to pull one from) can reach it.
    static weak var current: MusicLibraryStore?

    // `bridge` used to default to `MusicKitBridge()` directly in the parameter
    // list, but Swift 6 strict concurrency evaluates default argument
    // expressions in the (nonisolated) context of the call site rather than
    // the (MainActor-isolated) body of this initializer, so constructing the
    // MainActor-isolated `MusicKitBridge` there no longer type-checks. Doing
    // it inside the body instead works because the whole init runs on
    // MainActor (this class is `@MainActor`).
    init(bridge: MusicKitBridge? = nil) {
        self.bridge = bridge ?? MusicKitBridge()
        observeNowPlayingForHistory()
        Self.current = self
    }

    // Note: there used to be a reactive `$isAuthorized` subscription here that
    // auto-triggered `refreshLibrary()`/`refreshDiscover()` the instant
    // sign-in completed. Removed — it was redundant with `LibraryView` and
    // `DiscoverView` already refreshing themselves via `.task` when they
    // appear and are empty, and it fired at the worst possible time: on
    // every cold launch once a session persists (MusicKit JS restores it
    // automatically on `configure()`), before any UI navigation even
    // happens, unconditionally on the launch path rather than lazily when a
    // tab is actually opened.

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

    /// Runs a fire-and-forget bridge call, clearing any previous
    /// `errorMessage` first and setting a fresh one only if this attempt
    /// fails. Without the clear, `errorMessage` — read from both the Library
    /// and Settings tabs — is a one-way ratchet: a single failed rating tap
    /// or play attempt would keep showing that same stale error indefinitely
    /// on whichever screen happens to check it next, long after the actual
    /// problem (or an unrelated one entirely) resolved.
    private func perform(_ operation: () async throws -> Void) async {
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auth

    /// Starts the sign-in flow. It doesn't complete synchronously here —
    /// `authorize()`'s underlying JS call never resolves (MusicKit JS's
    /// popup can't message back to this page; see MusicKitBridge.swift), and
    /// the person dismissing the sign-in sheet is what actually reloads the
    /// bridge and re-checks auth state. There's no reactive auto-refresh
    /// after that — `LibraryView`/`DiscoverView` each refresh themselves via
    /// `.task` once the person actually opens that tab, which is enough and
    /// avoids firing an unconditional refresh at every cold launch.
    func signIn() async {
        await bridge.waitUntilReady()
        await bridge.authorize()
    }

    func signOut() async {
        do {
            try await bridge.unauthorize()
            // Clear every piece of account-scoped state, not just the
            // library grids — this app's whole premise is signing in as a
            // *different* Apple ID than the device's own, so leaving the
            // previous account's recommendations/charts/history/queue
            // sitting around after sign-out (until a new sign-in eventually
            // overwrites them) is stale data leaking across accounts, not
            // just a cosmetic staleness issue.
            playlists = []
            albums = []
            artists = []
            songs = []
            recommendations = []
            charts = .init()
            stations = []
            recentlyPlayedHistory = []
            recentlyPlayed = []
            queue = .empty
            hasLoadedLibraryOnce = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Library

    func refreshLibrary() async {
        guard bridge.isReady, bridge.isAuthorized else { return }
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
            return try await bridge.fetchPlaylistTracks(id: playlist.id, isLibrary: playlist.playParams?.isLibrary ?? true)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func tracks(forAlbum album: Album) async -> [Song] {
        do {
            return try await bridge.fetchAlbumTracks(id: album.id, isLibrary: album.playParams?.isLibrary ?? true)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func albums(forArtist artist: Artist) async -> [Album] {
        do {
            return try await bridge.fetchArtistAlbums(id: artist.id)
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
            searchHints = []
            // `errorMessage` is shared app-wide (Library/Settings read it
            // too) — clearing the search box should clear a search failure
            // along with the results, or a stale search error could later
            // show up on an unrelated screen that also happens to be empty.
            errorMessage = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            // Fire the real search and the lightweight hints/autocomplete
            // fetch together — same debounce window, independent failures.
            async let resultsTask = bridge.search(term: term)
            async let hintsTask = bridge.fetchSearchHints(term: term)
            do {
                let results = try await resultsTask
                if !Task.isCancelled {
                    searchResults = results
                    errorMessage = nil
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            if let hints = try? await hintsTask, !Task.isCancelled {
                searchHints = hints
            }
        }
    }

    // MARK: - Playback

    func play(song: Song) async {
        guard let params = song.playParams else { return }
        await perform { try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true) }
    }

    func play(album: Album) async {
        guard let params = album.playParams else { return }
        await perform { try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true) }
    }

    func play(playlist: Playlist) async {
        guard let params = playlist.playParams else { return }
        await perform { try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true) }
    }

    func play(station: Station) async {
        guard let params = station.playParams else { return }
        await perform { try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: false) }
    }

    // MARK: - Shuffle / Repeat / Volume

    func setShuffleMode(_ mode: ShuffleMode) async {
        await perform { try await self.bridge.setShuffleMode(mode) }
    }

    func cycleRepeatMode() async {
        await perform { try await self.bridge.setRepeatMode(self.bridge.repeatMode.next) }
    }

    func setVolume(_ value: Double) async {
        await perform { try await self.bridge.setVolume(value) }
    }

    // MARK: - Play Next / Play Later

    func playNext(song: Song) async {
        guard let params = song.playParams else { return }
        await perform { try await self.bridge.playNext(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true) }
    }

    func playLater(song: Song) async {
        guard let params = song.playParams else { return }
        await perform { try await self.bridge.playLater(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true) }
    }

    // MARK: - Ratings (love/dislike) + Add to Library

    /// `value` is 1 for love, -1 for dislike; pass the same value again to un-set it.
    func setRating(id: String, kind: String, value: Int) async {
        await perform { try await self.bridge.setRating(id: id, kind: kind, value: value) }
    }

    func removeRating(id: String, kind: String) async {
        await perform { try await self.bridge.removeRating(id: id, kind: kind) }
    }

    func addToLibrary(id: String, kind: String) async {
        await perform { try await self.bridge.addToLibrary(id: id, kind: kind) }
    }

    // MARK: - Playlist create/edit

    @discardableResult
    func createPlaylist(name: String, description: String? = nil, trackIds: [String] = [], isLibraryTracks: Bool = true) async -> Playlist? {
        errorMessage = nil
        do {
            let playlist = try await bridge.createPlaylist(name: name, description: description, trackIds: trackIds, isLibrary: isLibraryTracks)
            await refreshLibrary()
            return playlist
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func addTrack(_ song: Song, toPlaylist playlist: Playlist) async {
        await perform { try await self.bridge.addTracksToPlaylist(playlistId: playlist.id, trackIds: [song.id], isLibrary: song.playParams?.isLibrary ?? true) }
    }

    // MARK: - Real recently played history

    func refreshRecentlyPlayedHistory() async {
        isLoadingRecentlyPlayedHistory = true
        defer { isLoadingRecentlyPlayedHistory = false }
        do {
            recentlyPlayedHistory = try await bridge.fetchRecentlyPlayed()
        } catch {
            // Non-fatal: the session-local `recentlyPlayed` list still works
            // as a fallback, so don't surface this as a blocking error.
        }
    }

    // MARK: - Discovery

    func refreshDiscover() async {
        // Matches the empty state's own copy ("Sign in to see recommendations")
        // and `refreshLibrary()`'s existing isAuthorized guard: don't call into
        // the bridge at all when signed out, full stop. This was reportedly
        // crashing when Discover was opened right after a cold launch, before
        // the person had signed in — whatever the exact mechanism, not calling
        // MusicKit at all pre-auth removes that class of bug entirely.
        guard bridge.isAuthorized else {
            recommendations = []
            charts = .init()
            stations = []
            return
        }

        // Also wait for the engine itself, in case this fires in the brief
        // window right after `isAuthorized` flips true but before a fresh
        // `MusicKit.configure()` (e.g. right after the sign-in reload) has
        // finished — calling in before `isReady` is a premature-call bug
        // independent of the auth guard above.
        await bridge.waitUntilReady()

        isLoadingDiscover = true
        defer { isLoadingDiscover = false }

        async let recommendationsResult = bridge.fetchRecommendations()
        async let chartsResult = bridge.fetchCharts()
        async let stationsResult = bridge.fetchStations()

        do {
            recommendations = try await recommendationsResult
        } catch { /* leave previous value; discovery sections fail independently */ }
        do {
            charts = try await chartsResult
        } catch { /* ditto */ }
        do {
            stations = try await stationsResult
        } catch { /* ditto */ }
    }

    // MARK: - Search hints

    func refreshSearchHints(term: String) async {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchHints = []
            return
        }
        do {
            searchHints = try await bridge.fetchSearchHints(term: term)
        } catch {
            searchHints = []
        }
    }

    /// Fills the search field with a tapped hint; `SearchView`'s
    /// `.onChange(of: searchText)` picks up the change and searches via the
    /// normal debounced path.
    func selectSearchHint(_ hint: String) {
        // Just update the text — SearchView's `.onChange(of: searchText)`
        // calls `performSearchDebounced()` for us. This used to also kick
        // off its own immediate, non-debounced search here, but that search
        // and the one `.onChange` triggers a moment later both mutate
        // `searchTask`, so the immediate one was always cancelled by the
        // debounced one before it could return — wasted work with no
        // behavioral upside, just duplicated logic.
        searchHints = []
        searchText = hint
    }

    // MARK: - Queue (Up Next)

    func refreshQueue() async {
        isLoadingQueue = true
        errorMessage = nil
        defer { isLoadingQueue = false }
        do {
            queue = try await bridge.fetchQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func jumpToQueueItem(at index: Int) async {
        errorMessage = nil
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
            // refreshQueue() clears errorMessage on entry (see its own
            // comment), so it must run — reconciling the optimistic local
            // reorder against the bridge's real state — before setting the
            // message below, not after, or this would immediately wipe it.
            await refreshQueue()
            errorMessage = error.localizedDescription
        }
    }
}
