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

    /// One flag per search category so scrolling two lists at once (or
    /// re-triggering the same one before it resolves) can't fire overlapping
    /// "load more" requests for the same category.
    @Published var isLoadingMoreSongs = false
    @Published var isLoadingMoreAlbums = false
    @Published var isLoadingMoreArtists = false
    @Published var isLoadingMorePlaylists = false

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
    /// Kept separate from `errorMessage` so a stations failure can be shown on
    /// the Radio tab itself. This used to be swallowed by a bare `catch`, which
    /// is why an endpoint that failed on every single call still presented as
    /// a merely empty screen.
    @Published var stationsError: String?
    @Published var isLoadingDiscover = false

    // MARK: - Autoplay
    //
    // MusicKit JS has no exposed "continue with similar music" toggle or a
    // verified way to derive a station from a specific song (unlike the
    // native Music app's own Autoplay, which is backed by an internal
    // recommendation algorithm this project has no access to) — checked
    // against the real API surface rather than assumed, the same way every
    // other bridge call in this project now is. So this is an honest
    // approximation built entirely from endpoints already confirmed working
    // elsewhere: when the queue plays out with Autoplay on, it starts
    // something from whatever Discover already has (top chart song first,
    // falling back to a recommended album/playlist), refreshing Discover
    // first if it's empty. Session-only by design, same as MusicKit JS's
    // own shuffle/repeat state — it doesn't persist across a relaunch.
    @Published var isAutoplayEnabled = false
    private var isHandlingAutoplay = false

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
        observeAutoplay()
        Self.current = self
        loadCachedLibrary()
    }

    // MARK: - Library disk cache
    //
    // fetchLibraryPlaylists/Albums/Artists/Songs now paginate through a
    // person's *entire* library (see musickit-bridge.html's fetchAllPages) —
    // correct, since the old single-page fetch silently truncated anyone
    // with a large library, but for the same reason it can take 30+ seconds
    // from a cold launch with nothing cached yet to fall back on while that
    // runs. Caching the last successful fetch to disk and loading it
    // synchronously at launch means the Library tab has *something* to show
    // immediately; refreshLibrary() still runs in the background afterward
    // (see LibraryView's `.task`) to bring it back in sync with the account,
    // it just no longer blocks the first paint.

    private struct LibraryCache: Codable {
        var playlists: [Playlist]
        var albums: [Album]
        var artists: [Artist]
        var songs: [Song]
        var cachedAt: Date
    }

    /// How long a cached library is trusted before a plain launch/tab-open
    /// re-fetches it over the network again. Pull-to-refresh always forces a
    /// real fetch regardless — this only governs the automatic background
    /// one, which is what made every single launch pay the full paginated
    /// fetch even though the account's library rarely changes minute to
    /// minute.
    private static let libraryCacheMaxAge: TimeInterval = 60 * 60 * 6 // 6 hours

    private var libraryCachedAt: Date?

    private static var libraryCacheURL: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("library-cache.json")
    }

    private func loadCachedLibrary() {
        guard let url = Self.libraryCacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) else { return }
        playlists = cache.playlists
        albums = cache.albums
        artists = cache.artists
        songs = cache.songs
        libraryCachedAt = cache.cachedAt
        // Loaded from cache counts as "already loaded" for LibraryView's
        // purposes — it should show this immediately rather than a
        // full-screen spinner, even though a background refresh may still
        // run (if the cache is stale enough) and replace it.
        hasLoadedLibraryOnce = true
    }

    private func saveCachedLibrary() {
        guard let url = Self.libraryCacheURL else { return }
        let cachedAt = Date()
        let cache = LibraryCache(playlists: playlists, albums: albums, artists: artists, songs: songs, cachedAt: cachedAt)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
        libraryCachedAt = cachedAt
    }

    /// Sign-out clears the in-memory library state for the account that's
    /// leaving, but leaves the file on disk untouched — this deletes it too,
    /// since otherwise the *next* account to sign in would flash the
    /// previous account's cached playlists for a moment before its own
    /// refreshLibrary() finishes, which is exactly the cross-account data
    /// leak this app has otherwise been careful to avoid elsewhere.
    private func clearCachedLibrary() {
        guard let url = Self.libraryCacheURL else { return }
        try? FileManager.default.removeItem(at: url)
        libraryCachedAt = nil
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

    /// `.ended`/`.completed` is what MusicKit JS reports once the whole
    /// queue has genuinely played out (not between tracks *within* a
    /// queue, which just advances on its own) — the right moment for
    /// Autoplay to hand it something new.
    private func observeAutoplay() {
        bridge.$playbackStatus
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self, self.isAutoplayEnabled,
                      status == .ended || status == .completed else { return }
                Task { await self.playSomethingForAutoplay() }
            }
            .store(in: &cancellables)
    }

    private func playSomethingForAutoplay() async {
        guard !isHandlingAutoplay else { return }
        isHandlingAutoplay = true
        defer { isHandlingAutoplay = false }

        if charts.songs.isEmpty && recommendations.isEmpty {
            await refreshDiscover()
        }
        if let song = charts.songs.randomElement() {
            await play(song: song)
        } else if let recommendation = recommendations.first {
            if let album = recommendation.album {
                await play(album: album)
            } else if let playlist = recommendation.playlist {
                await play(playlist: playlist)
            }
        }
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
            clearCachedLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Library

    /// `force: false` (the default, used by LibraryView's `.task` on every
    /// launch/tab-open) skips the actual network fetch entirely when the
    /// disk cache is still fresh (see `libraryCacheMaxAge`) — previously
    /// every single launch re-ran the full paginated fetch regardless of
    /// how recently it had last succeeded, which is what made the library
    /// feel like it "reloaded everything" every time the app was opened.
    /// `force: true` (pull-to-refresh, the Retry button) always hits the
    /// network no matter how fresh the cache is.
    func refreshLibrary(force: Bool = false) async {
        // `bridge.isReady`/`.isAuthorized` both start false and only become
        // meaningful once the hidden WKWebView finishes loading musickit.js,
        // calls configure(), and restores the session from cookies — a few
        // real seconds after a cold launch. Library is the default tab, so
        // its `.task` used to fire and check these *before* that finished,
        // see `false` for isAuthorized (even for someone genuinely signed
        // in), and bail out via the old `guard ... else { return }` — and
        // since `.task` only runs once per view lifetime, the background
        // sync this is meant to do then just never happened for the rest of
        // the session. Waiting for ready first, then checking isAuthorized,
        // means that check reflects the real current state instead of a
        // startup race.
        await bridge.waitUntilReady()
        guard bridge.isAuthorized else { return }
        if !force, let cachedAt = libraryCachedAt, Date().timeIntervalSince(cachedAt) < Self.libraryCacheMaxAge {
            hasLoadedLibraryOnce = true
            return
        }
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
            saveCachedLibrary()
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

    /// Fetches one more page of search songs (offset = how many are already
    /// shown) and appends it, for a "load more"/infinite-scroll trigger at
    /// the end of the results list. A fresh `performSearchDebounced()` call
    /// (new search text) replaces `searchResults` wholesale, which is what
    /// naturally resets pagination for a new term.
    func loadMoreSearchSongs() async {
        guard searchResults.hasMoreSongs, !isLoadingMoreSongs else { return }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoadingMoreSongs = true
        defer { isLoadingMoreSongs = false }
        do {
            let page = try await bridge.searchMoreSongs(term: term, offset: searchResults.songs.count)
            searchResults.songs.append(contentsOf: page.items)
            searchResults.hasMoreSongs = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreSearchAlbums() async {
        guard searchResults.hasMoreAlbums, !isLoadingMoreAlbums else { return }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoadingMoreAlbums = true
        defer { isLoadingMoreAlbums = false }
        do {
            let page = try await bridge.searchMoreAlbums(term: term, offset: searchResults.albums.count)
            searchResults.albums.append(contentsOf: page.items)
            searchResults.hasMoreAlbums = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreSearchArtists() async {
        guard searchResults.hasMoreArtists, !isLoadingMoreArtists else { return }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoadingMoreArtists = true
        defer { isLoadingMoreArtists = false }
        do {
            let page = try await bridge.searchMoreArtists(term: term, offset: searchResults.artists.count)
            searchResults.artists.append(contentsOf: page.items)
            searchResults.hasMoreArtists = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreSearchPlaylists() async {
        guard searchResults.hasMorePlaylists, !isLoadingMorePlaylists else { return }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoadingMorePlaylists = true
        defer { isLoadingMorePlaylists = false }
        do {
            let page = try await bridge.searchMorePlaylists(term: term, offset: searchResults.playlists.count)
            searchResults.playlists.append(contentsOf: page.items)
            searchResults.hasMorePlaylists = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Playback

    /// True while a play/pause/skip call is actually in flight. The mini
    /// player and full player used to call `store.bridge.togglePlayPause()`
    /// etc. directly with a bare `try?`, so a tap gave zero visual feedback
    /// until (if ever) `playbackStatus` itself changed — which for a tap
    /// that fails outright never happens, and even for one that succeeds can
    /// lag behind by however long buffering takes. This is read by both
    /// `NowPlayingBar` and `NowPlayingFullView` to show a spinner and
    /// disable the buttons for the duration of the call, and it fixes the
    /// silent-failure side of the same bug: `try?` discarded any error, this
    /// surfaces it through the normal `errorMessage` path via `perform`.
    @Published var isTransportBusy = false

    func togglePlayPause() async {
        isTransportBusy = true
        defer { isTransportBusy = false }
        await perform { try await self.bridge.togglePlayPause() }
    }

    func skipToNext() async {
        isTransportBusy = true
        defer { isTransportBusy = false }
        await perform { try await self.bridge.skipToNext() }
    }

    func skipToPrevious() async {
        isTransportBusy = true
        defer { isTransportBusy = false }
        await perform { try await self.bridge.skipToPrevious() }
    }

    /// The id of whatever's currently being requested to play, so a tapped
    /// row/tile can show its own spinner immediately. `nowPlaying`/
    /// `playbackStatus` only update once MusicKit JS's own events fire,
    /// which lags behind a tap by however long buffering takes — until
    /// then, without this, a tap looked like it did nothing at all.
    @Published var pendingPlaybackID: String?

    private func performPlayback(id: String, _ operation: () async throws -> Void) async {
        pendingPlaybackID = id
        defer { pendingPlaybackID = nil }
        await perform(operation)
    }

    func play(song: Song) async {
        guard let params = song.playParams else { return }
        await performPlayback(id: song.id) {
            try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        }
    }

    func play(album: Album) async {
        guard let params = album.playParams else { return }
        await performPlayback(id: album.id) {
            try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        }
    }

    func play(playlist: Playlist) async {
        guard let params = playlist.playParams else { return }
        await performPlayback(id: playlist.id) {
            try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        }
    }

    /// Sets shuffle on *before* loading the new queue, so the playlist starts
    /// shuffled from the first track rather than shuffling only once it's
    /// already playing in its original order.
    func shufflePlay(playlist: Playlist) async {
        guard let params = playlist.playParams else { return }
        await performPlayback(id: playlist.id) {
            try await self.bridge.setShuffleMode(.songs)
            try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: params.isLibrary ?? true)
        }
    }

    func play(station: Station) async {
        guard let params = station.playParams else { return }
        await performPlayback(id: station.id) {
            try await self.bridge.setQueueAndPlay(id: params.id, kind: params.kind, isLibrary: false)
        }
    }

    // MARK: - Shuffle / Repeat / Volume

    /// True while a shuffle/repeat toggle is actually in flight. Every
    /// bridge call (even one that's "just flipping a property" JS-side, no
    /// network round trip involved) still goes through a full
    /// `callAsyncJavaScript` round trip, which is real but easy to mistake
    /// for "nothing happened" when the button gives no feedback in the
    /// meantime — same class of issue play/pause/skip had before they got
    /// isTransportBusy. This makes tapping shuffle/repeat show *something*
    /// changing immediately instead of a silent gap before the icon updates.
    @Published var isTogglingPlaybackMode = false

    func setShuffleMode(_ mode: ShuffleMode) async {
        isTogglingPlaybackMode = true
        defer { isTogglingPlaybackMode = false }
        await perform { try await self.bridge.setShuffleMode(mode) }
    }

    func cycleRepeatMode() async {
        isTogglingPlaybackMode = true
        defer { isTogglingPlaybackMode = false }
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
        // `isAuthorized` starts false and only becomes meaningful once the
        // bridge is actually ready (see refreshLibrary()'s comment for the
        // same race in more detail) — checking it *before* waiting for ready
        // meant this could see `false` for a genuinely signed-in person in
        // the brief window right after a cold launch, wipe Discover's state,
        // and return, with nothing left to ever retry since `.task` only
        // runs once per view lifetime. Waiting for ready first makes the
        // check below reflect the real current state.
        await bridge.waitUntilReady()

        // Matches the empty state's own copy ("Sign in to see recommendations"):
        // don't call into the bridge at all when signed out, full stop. This
        // was reportedly crashing when Discover was opened right after a cold
        // launch, before the person had signed in — whatever the exact
        // mechanism, not calling MusicKit at all pre-auth removes that class
        // of bug entirely.
        guard bridge.isAuthorized else {
            recommendations = []
            charts = .init()
            stations = []
            stationsError = nil
            return
        }

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
            stationsError = nil
        } catch {
            stationsError = error.localizedDescription
        }
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
        var items = queue.items
        guard items.indices.contains(from) else { return }
        let adjustedDestination = destination > from ? destination - 1 : destination
        let target = min(max(adjustedDestination, 0), items.count - 1)
        guard target != from else { return }

        // Optimistically reorder locally so the drag lands where the finger
        // let go instead of snapping back while the bridge works.
        let moved = items.remove(at: from)
        items.insert(moved, at: target)
        queue.items = items
        // Keep the "now playing" marker pointing at the same track rather
        // than at whatever ends up at the old index.
        queue.position = Self.positionAfterMove(queue.position, from: from, to: target)

        errorMessage = nil
        do {
            try await bridge.moveQueueItem(from: from, to: target)
            // Rebuilding the queue in MusicKit JS is asynchronous on its side:
            // reading it back immediately returns the pre-move array and makes
            // a move that actually worked look like it silently reverted.
            await reconcileQueue(expecting: items.map(\.id))
        } catch {
            let message = error.localizedDescription
            // refreshQueue() clears errorMessage on entry (see its own
            // comment), so it must run — reconciling the optimistic local
            // reorder against the bridge's real state — before setting the
            // message below, not after, or this would immediately wipe it.
            await refreshQueue()
            errorMessage = message
        }
    }

    func removeQueueItem(at index: Int) async {
        var items = queue.items
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        queue.items = items
        if queue.position > index { queue.position -= 1 }

        errorMessage = nil
        do {
            try await bridge.removeQueueItem(at: index)
            await reconcileQueue(expecting: items.map(\.id))
        } catch {
            let message = error.localizedDescription
            await refreshQueue()
            errorMessage = message
        }
    }

    /// Re-reads the queue until it matches what we just asked for, then adopts
    /// the bridge's authoritative copy. A single immediate read races MusicKit
    /// JS's own queue rebuild and would clobber a successful edit with the
    /// stale pre-edit order — which is exactly what made reordering look like
    /// it did nothing.
    private func reconcileQueue(expecting expectedIDs: [String]) async {
        for attempt in 0..<6 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard let snapshot = try? await bridge.fetchQueue() else { continue }
            if snapshot.items.map(\.id) == expectedIDs {
                queue = snapshot
                return
            }
        }
        // Never converged: the edit didn't take on MusicKit's side, so show
        // the real queue rather than leaving a local fiction on screen.
        await refreshQueue()
    }

    /// Where the currently-playing index lands after moving one row.
    static func positionAfterMove(_ position: Int, from: Int, to: Int) -> Int {
        guard position >= 0 else { return position }
        if position == from { return to }
        if from < position && to >= position { return position - 1 }
        if from > position && to <= position { return position + 1 }
        return position
    }
}
