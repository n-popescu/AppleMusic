import Foundation
import WebKit
import Combine
import Security

/// Errors surfaced from the JS side of the bridge.
enum MusicKitBridgeError: LocalizedError {
    case notReady
    case javascriptError(String)
    case decodingFailed(String? = nil)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notReady: return "The Apple Music engine isn't ready yet."
        case .javascriptError(let message): return message
        case .decodingFailed(let detail):
            let base = "Couldn't understand the response from Apple Music."
            return detail.map { "\(base) (\($0))" } ?? base
        case .unauthorized: return "Not signed in to Apple Music."
        }
    }
}

/// Walks a JS-bridged value depth-first and describes the first thing that
/// makes it unrepresentable as strict JSON — almost always a NaN/Infinity
/// NSNumber (e.g. a live radio station's `Infinity` duration) or a raw
/// non-container value at the top level. Purely diagnostic: used to turn
/// "Couldn't understand the response" into something a bug report can
/// actually act on, since this project has no way to attach a debugger.
private func describeFirstInvalidJSONValue(_ value: Any, path: String = "root") -> String? {
    // `isValidJSONObject` requires specifically an array or dictionary at
    // the top level — a bare NSNull there (as when a JS call resolves to
    // `undefined`) is exactly what it rejects, but NSNull is otherwise a
    // perfectly normal, valid *nested* value. Missing this distinction is
    // what let this function silently return `nil` while the object it was
    // asked to explain really was invalid — hiding this project's actual
    // longest-standing bug (see `call<T>`'s comment) behind a message with
    // no diagnostic detail at all, for as long as this function existed.
    if path == "root", value is NSNull {
        return "root is undefined/null (the JS call resolved with no value)"
    }
    if let number = value as? NSNumber {
        // NSNumber also boxes Bool; only doubles/floats can be non-finite.
        let double = number.doubleValue
        if double.isNaN { return "\(path) is NaN" }
        if double.isInfinite { return "\(path) is Infinite" }
        return nil
    }
    if value is NSString || value is NSNull { return nil }
    if let array = value as? [Any] {
        for (index, element) in array.enumerated() {
            if let found = describeFirstInvalidJSONValue(element, path: "\(path)[\(index)]") { return found }
        }
        return nil
    }
    if let dict = value as? [String: Any] {
        for (key, element) in dict {
            if let found = describeFirstInvalidJSONValue(element, path: "\(path).\(key)") { return found }
        }
        return nil
    }
    return "\(path) is an unsupported type (\(type(of: value)))"
}

/// Recursively rebuilds a JS-bridged value into one guaranteed safe for
/// `JSONSerialization`: non-finite numbers become `NSNull`, and every string
/// is round-tripped through Swift's `String` (which repairs any ill-formed
/// UTF-16 — an unpaired surrogate — by substituting U+FFFD). The `Any` boxes
/// `callAsyncJavaScript` hands back can still be the original `NSString`
/// instances, invalid content and all; casting to `String` alone doesn't
/// copy/repair that in place, only constructing a *new* Swift `String` does.
private func sanitizedForJSON(_ value: Any) -> Any {
    if let number = value as? NSNumber {
        let double = number.doubleValue
        if double.isNaN || double.isInfinite { return NSNull() }
        return number
    }
    if value is NSNull { return NSNull() }
    if let string = value as? String {
        return String(string)
    }
    if let array = value as? [Any] {
        return array.map { sanitizedForJSON($0) }
    }
    if let dict = value as? [String: Any] {
        return dict.mapValues { sanitizedForJSON($0) }
    }
    return value
}

/// Events pushed asynchronously from MusicKit JS -> native, via `webkit.messageHandlers.musicKitEvent`.
enum MusicKitEvent {
    case authorizationStatusDidChange(Bool)
    case nowPlayingItemDidChange(NowPlayingInfo)
    case playbackStateDidChange(PlaybackStatus)
    case playbackTimeDidChange(current: Double, duration: Double)
    case bridgeReady
    case bridgeError(String)
}

/// Hosts a hidden WKWebView running MusicKit JS. This is the *only* thing that talks
/// to Apple's servers for auth + playback. It intentionally never becomes visible —
/// all UI is native SwiftUI; this is just the DRM playback + auth engine underneath.
@MainActor
final class MusicKitBridge: NSObject, ObservableObject {

    @Published private(set) var isReady = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var nowPlaying: NowPlayingInfo = .empty
    @Published private(set) var playbackStatus: PlaybackStatus = .none
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var shuffleMode: ShuffleMode = .off
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var volume: Double = 1.0
    @Published var lastError: String?

    /// Non-nil while the Apple Music sign-in popup needs to be shown to the
    /// person — a genuine separate `WKWebView` handed back from
    /// `WKUIDelegate.createWebViewWith` in response to MusicKit JS's
    /// `window.open()` call, sharing this bridge's cookies/session. The
    /// engine `webView` below stays hidden and running the whole time.
    @Published var authPresentationWebView: WKWebView?

    /// The hidden web view. Add it to the view hierarchy with zero frame / .hidden —
    /// WKWebView will throttle or suspend JS if it's never attached at all, so keep it
    /// mounted (e.g. via `.background(bridge.webViewContainer)`), just invisible.
    let webView: WKWebView

    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // MusicKit JS's `authorize()` opens the sign-in popup via `window.open()`
        // from inside an async/Promise chain. Script run through
        // `callAsyncJavaScript` never carries a "user gesture" flag into WebKit
        // (even though the native button tap that triggered it did), so without
        // this, WKWebView's popup blocker silently swallows the `window.open()`
        // call before `WKUIDelegate.createWebViewWith` is ever invoked — the
        // button just does nothing.
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let controller = WKUserContentController()
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear

        super.init()

        // `WKUserContentController.add(_:name:)` retains its handler strongly.
        // Since this bridge owns `webView` -> `config` -> `controller`, adding
        // `self` directly here would create a permanent retain cycle (the
        // bridge would never deinit). Route through a weak-referencing proxy
        // instead, per Apple's documented workaround.
        controller.add(WeakScriptMessageHandler(target: self), name: "musicKitEvent")

        // Inject the developer token before any page script runs, so it's
        // already on `window` by the time musickit.js fires `musickitloaded`.
        let token = Bundle.main.object(forInfoDictionaryKey: "MusicKitDeveloperToken") as? String ?? ""
        let tokenScript = WKUserScript(
            source: "window.MUSICGLASS_DEVELOPER_TOKEN = \(Self.jsStringLiteral(token));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(tokenScript)

        // Sign-in state otherwise lives only in the WKWebView's cookie store,
        // which is deleted along with everything else in the app's container
        // on uninstall — the person has to sign in again after every
        // reinstall even though nothing about their actual Apple Music
        // account changed. The Keychain, by contrast, survives an uninstall
        // on the same device by default. So the music-user-token MusicKit JS
        // hands back once signed in is *also* mirrored into the Keychain
        // (see the `userTokenDidChange` case below), and on every fresh
        // launch that stored token — if any — is handed back to the page
        // here so it can try to resume the session without a real cookie
        // store to restore from. See `restoreUserToken` in the JS bridge for
        // the validity check this goes through before being trusted.
        let storedToken = Self.loadStoredUserToken() ?? ""
        let storedTokenScript = WKUserScript(
            source: "window.MUSICGLASS_STORED_USER_TOKEN = \(Self.jsStringLiteral(storedToken));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(storedTokenScript)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        loadBridgePage()

        if token.isEmpty {
            lastError = "No MusicKit developer token set. Add MusicKitDeveloperToken to Info.plist."
        }

        startPlaybackTimePolling()
    }

    /// Drives `currentTime`/`duration` from a native timer instead of
    /// relying solely on the JS-side `playbackTimeDidChange` event. That
    /// event is driven by an internal MusicKit JS timer, and WebKit
    /// throttles a hidden page's own JS timers/requestAnimationFrame
    /// independently of whether the app itself is in the foreground — which
    /// showed up as the mini/full player's progress only ever updating at a
    /// discrete state change like pause (driven directly and immediately by
    /// the native `pause()` call, not a JS timer) rather than continuously
    /// during playback. A `Task.sleep` loop here is native scheduling, not a
    /// JS-engine timer, so it isn't subject to that same throttling — each
    /// tick is a single one-off JS call, not something JS scheduled itself.
    private func startPlaybackTimePolling() {
        Task { [weak self] in
            while let self, !Task.isCancelled {
                var isPlaying = false
                if self.isReady {
                    isPlaying = self.playbackStatus.isPlaying
                    if let time = try? await self.fetchPlaybackTime() {
                        self.currentTime = time.currentTime
                        self.duration = time.duration
                    }
                }
                // Tighter while playing so the bar moves smoothly; slower
                // otherwise, since nothing is changing between state events.
                try? await Task.sleep(nanoseconds: isPlaying ? 250_000_000 : 1_000_000_000)
            }
        }
    }

    // Note: no explicit teardown of the script message handler is needed here.
    // `WeakScriptMessageHandler` only holds `self` weakly, and the controller
    // it's registered on is owned (transitively) by `webView`, which this
    // bridge itself owns — so the whole chain is freed together with no cycle.

    // MARK: - Bootstrapping

    private func loadBridgePage() {
        guard let url = Bundle.main.url(forResource: "musickit-bridge", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            lastError = "musickit-bridge.html is missing from the app bundle."
            return
        }
        // Loaded via `loadHTMLString(_:baseURL:)` with a real https:// base
        // rather than `loadFileURL`: a file:// load gives the page a null/
        // opaque origin, which some of MusicKit JS's internal requests and
        // origin checks reject outright. No real network request happens for
        // the HTML itself this way — only for the musickit.js <script src>
        // and the API calls — but the page behaves as if genuinely hosted at
        // this https URL.
        webView.loadHTMLString(html, baseURL: URL(string: "https://music.apple.com"))
    }

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            readyContinuations.append(continuation)
        }
    }

    // MARK: - Auth

    /// Triggers Apple's own sign-in. `MusicKit.authorize()`'s promise never
    /// resolves in this environment — `window.opener` is null in a real
    /// WKWebView popup, so the postMessage handshake it waits on never
    /// arrives — so this deliberately does NOT await it; it fires the JS
    /// call and returns immediately once the popup has had a moment to
    /// appear. `createWebViewWith` below sets `authPresentationWebView` as
    /// soon as MusicKit JS actually calls `window.open()`. Completion is the
    /// person tapping Done/Cancel in the sheet, not anything this function
    /// or its JS call reports back.
    func authorize() async {
        Task { try? await self.callVoid("await MusicGlassBridge.authorize();") }
    }

    func unauthorize() async throws {
        try await callVoid("await MusicGlassBridge.unauthorize();")
        // A deliberate sign-out should stay signed out — including on the
        // next cold launch — so the Keychain-persisted token from
        // `userTokenDidChange` must not outlive it.
        Self.deleteStoredUserToken()
    }

    /// Ends the sign-in flow (cancelled or actually completed — there's no
    /// way to tell which from here) and reloads the bridge page fresh.
    /// MusicKit JS's own `configure()` restores an existing session from the
    /// shared cookie store on load, same as it would for a returning visitor
    /// on a real website, so this is what actually picks up a completed
    /// sign-in — not anything reported by `authorize()` or the popup itself.
    func dismissAuthPopup() {
        guard authPresentationWebView != nil else { return }
        authPresentationWebView = nil
        isReady = false
        loadBridgePage()
    }

    // MARK: - Playback controls

    func play() async throws { try await callVoid("await MusicGlassBridge.play();") }
    func pause() async throws { try await callVoid("await MusicGlassBridge.pause();") }
    func skipToNext() async throws { try await callVoid("await MusicGlassBridge.skipToNext();") }
    func skipToPrevious() async throws { try await callVoid("await MusicGlassBridge.skipToPrevious();") }

    func seek(to seconds: Double) async throws {
        try await callVoid("await MusicGlassBridge.seek(\(seconds));")
    }

    private struct PlaybackTime: Decodable {
        var currentTime: Double
        var duration: Double
    }

    private func fetchPlaybackTime() async throws -> PlaybackTime {
        try await call("return await MusicGlassBridge.getPlaybackTime();")
    }

    func togglePlayPause() async throws {
        if playbackStatus.isPlaying {
            try await pause()
        } else {
            try await play()
        }
    }

    /// Sets the playback queue from a catalog or library item (song, album, playlist or station) and starts playing.
    func setQueueAndPlay(id: String, kind: String, isLibrary: Bool) async throws {
        let js = "await MusicGlassBridge.setQueueAndPlay(\(js: id), \(js: kind), \(isLibrary));"
        try await callVoid(js)
    }

    // MARK: - Shuffle / Repeat / Volume

    func setShuffleMode(_ mode: ShuffleMode) async throws {
        try await callVoid("await MusicGlassBridge.setShuffleMode(\(mode.rawValue));")
    }

    func setRepeatMode(_ mode: RepeatMode) async throws {
        try await callVoid("await MusicGlassBridge.setRepeatMode(\(mode.rawValue));")
    }

    func setVolume(_ value: Double) async throws {
        try await callVoid("await MusicGlassBridge.setVolume(\(value));")
    }

    /// Best-effort insert into the live queue right after the currently playing
    /// item. MusicKit JS's documented `music.playNext(descriptor)` is used when
    /// present; if it's unavailable in the loaded MusicKit JS release, the
    /// bridge falls back to rebuilding the queue client-side (same caveat as
    /// `moveQueueItem`).
    func playNext(id: String, kind: String, isLibrary: Bool) async throws {
        try await callVoid("await MusicGlassBridge.playNext(\(js: id), \(js: kind), \(isLibrary));")
    }

    /// Best-effort append to the end of the live queue. See `playNext`.
    func playLater(id: String, kind: String, isLibrary: Bool) async throws {
        try await callVoid("await MusicGlassBridge.playLater(\(js: id), \(js: kind), \(isLibrary));")
    }

    // MARK: - Ratings (love/dislike) + library

    func setRating(id: String, kind: String, value: Int) async throws {
        try await callVoid("await MusicGlassBridge.setRating(\(js: id), \(js: kind), \(value));")
    }

    func removeRating(id: String, kind: String) async throws {
        try await callVoid("await MusicGlassBridge.removeRating(\(js: id), \(js: kind));")
    }

    func addToLibrary(id: String, kind: String) async throws {
        try await callVoid("await MusicGlassBridge.addToLibrary(\(js: id), \(js: kind));")
    }

    // MARK: - Playlist create/edit

    /// `isLibrary` picks the relationship resource type for `trackIds`
    /// (`library-songs` vs `songs`) — a library song's ID is a different ID
    /// namespace than a catalog song's, so this must match whichever kind of
    /// song these IDs actually are. Every real call site adds one song at a
    /// time, always of one kind, so a single flag for the whole array is enough.
    func createPlaylist(name: String, description: String?, trackIds: [String], isLibrary: Bool) async throws -> Playlist {
        let idsJSON = Self.jsStringArrayLiteral(trackIds)
        let descriptionJS = description.map { Self.jsStringLiteral($0) } ?? "null"
        return try await call("return await MusicGlassBridge.createPlaylist(\(js: name), \(descriptionJS), \(idsJSON), \(isLibrary));")
    }

    func addTracksToPlaylist(playlistId: String, trackIds: [String], isLibrary: Bool) async throws {
        let idsJSON = Self.jsStringArrayLiteral(trackIds)
        try await callVoid("await MusicGlassBridge.addTracksToPlaylist(\(js: playlistId), \(idsJSON), \(isLibrary));")
    }

    // MARK: - Real recently played + discovery

    func fetchRecentlyPlayed() async throws -> [RecentlyPlayedItem] {
        try await call("return await MusicGlassBridge.fetchRecentlyPlayed();")
    }

    func fetchRecommendations() async throws -> [RecommendationItem] {
        try await call("return await MusicGlassBridge.fetchRecommendations();")
    }

    func fetchCharts() async throws -> ChartsResult {
        try await call("return await MusicGlassBridge.fetchCharts();")
    }

    func fetchStations() async throws -> [Station] {
        try await call("return await MusicGlassBridge.fetchStations();")
    }

    // MARK: - Search hints

    func fetchSearchHints(term: String) async throws -> [String] {
        try await call("return await MusicGlassBridge.fetchSearchHints(\(js: term));")
    }

    // MARK: - Library + catalog fetches

    func fetchLibraryPlaylists() async throws -> [Playlist] {
        try await call("return await MusicGlassBridge.fetchLibraryPlaylists();")
    }

    func fetchLibraryAlbums() async throws -> [Album] {
        try await call("return await MusicGlassBridge.fetchLibraryAlbums();")
    }

    func fetchLibraryArtists() async throws -> [Artist] {
        try await call("return await MusicGlassBridge.fetchLibraryArtists();")
    }

    func fetchLibrarySongs() async throws -> [Song] {
        try await call("return await MusicGlassBridge.fetchLibrarySongs();")
    }

    func fetchPlaylistTracks(id: String, isLibrary: Bool) async throws -> [Song] {
        try await call("return await MusicGlassBridge.fetchPlaylistTracks(\(js: id), \(isLibrary));")
    }

    func fetchAlbumTracks(id: String, isLibrary: Bool) async throws -> [Song] {
        try await call("return await MusicGlassBridge.fetchAlbumTracks(\(js: id), \(isLibrary));")
    }

    /// Catalog-only — see the JS side for why this doesn't take an
    /// `isLibrary` flag the way the track fetches above do.
    func fetchArtistAlbums(id: String) async throws -> [Album] {
        try await call("return await MusicGlassBridge.fetchArtistAlbums(\(js: id));")
    }

    struct SearchResults: Codable {
        var songs: [Song] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var playlists: [Playlist] = []
        var hasMoreSongs: Bool = false
        var hasMoreAlbums: Bool = false
        var hasMoreArtists: Bool = false
        var hasMorePlaylists: Bool = false
    }

    func search(term: String) async throws -> SearchResults {
        try await call("return await MusicGlassBridge.search(\(js: term));")
    }

    /// One additional page of a single search category, fetched at
    /// `offset` (the count of that type already shown) — see the JS side's
    /// `searchMore*` functions for why this isn't just "call search again
    /// with a bigger limit".
    struct SearchPage<T: Codable>: Codable {
        var items: [T] = []
        var hasMore: Bool = false
    }

    func searchMoreSongs(term: String, offset: Int) async throws -> SearchPage<Song> {
        try await call("return await MusicGlassBridge.searchMoreSongs(\(js: term), \(offset));")
    }

    func searchMoreAlbums(term: String, offset: Int) async throws -> SearchPage<Album> {
        try await call("return await MusicGlassBridge.searchMoreAlbums(\(js: term), \(offset));")
    }

    func searchMoreArtists(term: String, offset: Int) async throws -> SearchPage<Artist> {
        try await call("return await MusicGlassBridge.searchMoreArtists(\(js: term), \(offset));")
    }

    func searchMorePlaylists(term: String, offset: Int) async throws -> SearchPage<Playlist> {
        try await call("return await MusicGlassBridge.searchMorePlaylists(\(js: term), \(offset));")
    }

    // MARK: - Queue (Up Next)

    /// The live MusicKit JS playback queue: currently playing index + upcoming items.
    func fetchQueue() async throws -> QueueSnapshot {
        try await call("return await MusicGlassBridge.fetchQueue();")
    }

    /// Jumps directly to an item already in the queue by its index.
    func jumpToQueueItem(at index: Int) async throws {
        try await callVoid("await MusicGlassBridge.jumpToQueueItem(\(index));")
    }

    /// Best-effort client-side reorder of the upcoming queue. MusicKit JS doesn't
    /// expose a first-class "move" API, so the bridge rebuilds the queue array
    /// itself; see the JS side for caveats.
    func moveQueueItem(from: Int, to: Int) async throws {
        try await callVoid("await MusicGlassBridge.moveQueueItem(\(from), \(to));")
    }

    /// The station Apple derives from a specific song (falling back to the
    /// song's artist) — the seed used for Autoplay. `nil` when no station
    /// exists for it; see the JS side for why that isn't an error.
    func fetchAutoplayStation(songID: String) async throws -> Station? {
        let result: AutoplayStationResult = try await call(
            "return await MusicGlassBridge.fetchAutoplayStation(\(Self.jsStringLiteral(songID)));"
        )
        return result.station
    }

    /// The song's album and primary artist, for the long-press menu. Either
    /// side can be nil (a library-only id isn't in the catalog id space).
    func fetchSongRelations(songID: String) async throws -> SongRelations {
        try await call("return await MusicGlassBridge.fetchSongRelations(\(Self.jsStringLiteral(songID)));")
    }

    struct SongRelations: Decodable {
        let album: Album?
        let artist: Artist?
    }

    /// Wrapper so "no station for this song" comes back as a decodable
    /// object rather than a bare top-level null, which `call<T>` rejects.
    private struct AutoplayStationResult: Decodable {
        let station: Station?
    }

    /// Removes one item from the live queue. Uses `MusicKit.Queue.remove(index)`
    /// where the running MusicKit JS build has it (no rebuild, no interruption),
    /// falling back to a queue rebuild otherwise — see the JS side.
    func removeQueueItem(at index: Int) async throws {
        try await callVoid("await MusicGlassBridge.removeQueueItem(\(index));")
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    // `Any` boxing an `NSNumber` bridged from a JS number does not reliably
    // cast directly via `as? Double`/`as? Int` — whether it succeeds can
    // depend on how the underlying NSNumber was constructed (e.g. an
    // integer-valued JS number bridging to an NSNumber whose declared
    // Objective-C type isn't a floating-point one), a well-known Swift/
    // Foundation gotcha. Going through NSNumber's own `doubleValue`/
    // `intValue` accessors always coerces correctly regardless.
    private static func doubleValue(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    private static func intValue(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }

    // MARK: - Keychain-persisted music-user-token (survives app uninstall)

    private static let keychainService = "com.lucent.app.musicUserToken"
    private static let keychainAccount = "musicUserToken"

    private static func loadStoredUserToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private static func saveUserToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        // `kSecAttrAccessibleAfterFirstUnlock` (rather than the
        // `...ThisDeviceOnly` variants) is still device-local — it just
        // doesn't require the device to be unlocked right now, since this
        // can run while playback continues in the background.
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            SecItemAdd((query.merging(attributes) { _, new in new }) as CFDictionary, nil)
        }
    }

    private static func deleteStoredUserToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Encodes `[String]` as a JS array literal, e.g. for a list of track IDs.
    private static func jsStringArrayLiteral(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - Low-level JS call helpers

    /// Calls an async JS expression that returns Codable JSON, decodes it.
    private func call<T: Decodable>(_ expression: String) async throws -> T {
        // `callAsyncJavaScript` already runs the string it's given as the
        // *body* of its own async function — top-level `await`/`return`
        // work directly, no wrapper needed. This used to additionally wrap
        // `expression` in its own `(async () => { ... })()` IIFE, which is
        // where every bug in this whole call chain actually traced back to:
        // that inner IIFE's promise was never awaited or returned by the
        // *outer* function callAsyncJavaScript generates, so the outer
        // function always resolved to `undefined` immediately, no matter
        // what `expression` itself returned. Every T-returning bridge call
        // (search, library fetches, Discover) was therefore always decoding
        // a bare `undefined` — which is exactly what crashed
        // NSJSONSerialization in the first place (a bare top-level NSNull
        // isn't a valid JSON object) and, after that crash was patched over
        // with validity checks, is exactly why every one of those checks
        // kept failing with no useful diagnostic detail (NSNull doesn't
        // register as "invalid" the way a NaN or malformed string would).
        let result: Any
        do {
            result = try await webView.callAsyncJavaScript(
                expression, arguments: [:], in: nil, contentWorld: .page
            ) ?? NSNull()
        } catch {
            throw MusicKitBridgeError.javascriptError(error.localizedDescription)
        }
        // `JSONSerialization.data(withJSONObject:options:)` raises a raw
        // Objective-C exception (NSInvalidArgumentException), not a catchable
        // Swift error, if `result`'s object graph contains anything outside
        // strict JSON types anywhere in it — most commonly a NaN/Infinity
        // number (e.g. a live radio station's `duration` bridging to
        // `Infinity`) or a non-array/dictionary top-level value. `try?`
        // around that call does nothing to stop it: it isn't a Swift `throw`,
        // it's `objc_exception_throw`, which aborts the process. This crashed
        // real devices on search/library/discover alike, since they all
        // funnel through this one function. `isValidJSONObject` performs the
        // same recursive check but reports the result as a plain `Bool`
        // instead of throwing, so it's safe to call first.
        // `isValidJSONObject` only checks *structural* types (NSNumber,
        // NSString, NSArray, NSDictionary, NSNull, all finite) — it does not
        // check *string content*. An NSString can legally hold an ill-formed
        // UTF-16 sequence (an unpaired surrogate), something ordinary real
        // catalog metadata (foreign-language titles, certain emoji) can
        // trigger, and `data(withJSONObject:)` then fails on it anyway, via
        // its normal `error:` outcome rather than an exception this time —
        // which the `try?` this used to use was silently discarding, hiding
        // the real reason behind the same generic message every time.
        // `sanitizedForJSON` repairs this ahead of time by round-tripping
        // every string through Swift's `String`, which replaces invalid
        // UTF-16 with U+FFFD, since `NSString`->`Any`->back doesn't do that
        // automatically the way constructing a fresh Swift `String` does.
        let sanitized = sanitizedForJSON(result)
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            throw MusicKitBridgeError.decodingFailed(describeFirstInvalidJSONValue(sanitized))
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sanitized, options: [])
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            throw MusicKitBridgeError.decodingFailed("\(error)")
        }
    }

    /// Calls an async JS expression with no meaningful return value.
    private func callVoid(_ expression: String) async throws {
        // Same fix as `call<T>` above — no extra IIFE wrapper needed, and
        // this one mattered even when the return value itself didn't:
        // wrapping `expression` in its own un-awaited `(async () => {...})()`
        // meant a *rejection* inside it (e.g. `MusicGlassBridge.play()`
        // throwing) was an unhandled rejection inside the page, never
        // propagated to the outer function — so the `catch` below could
        // never actually see a failure, and native code moved on before the
        // JS call had necessarily finished. Passing `expression` directly
        // makes the outer function actually await it, so both the timing
        // and error propagation are correct now.
        do {
            _ = try await webView.callAsyncJavaScript(
                expression, arguments: [:], in: nil, contentWorld: .page
            )
        } catch {
            throw MusicKitBridgeError.javascriptError(error.localizedDescription)
        }
    }
}

// MARK: - WKNavigationDelegate

// Note: these WKNavigationDelegate/WKUIDelegate/WKScriptMessageHandler
// conformances used to mark each method `nonisolated` and hop onto MainActor
// internally (via `Task { @MainActor in ... }`) for anything touching
// actor-isolated state. Under Swift 6 strict concurrency that fell apart as
// soon as a method needed to *synchronously return* a MainActor-isolated
// value (e.g. `createWebViewWith` must return the new `WKWebView` itself,
// which is created and configured on the MainActor-isolated `webView`
// property's peers). WebKit always invokes these delegate callbacks on the
// main thread in practice, so it's both correct and necessary here to mark
// the whole conformances `@MainActor` instead of `nonisolated` per-method.
extension MusicKitBridge: WKNavigationDelegate {
    @MainActor func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page itself calls back into `musicKitEvent` with `bridgeReady`
        // once MusicKit JS has configured and (if a stored token exists) restored auth.
    }
}

// MARK: - WKUIDelegate (surfaces the sign-in popup only)

extension MusicKitBridge: WKUIDelegate {
    @MainActor func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        // `MusicKit.authorize()` triggers this via window.open() for the real
        // Apple sign-in page. Create a *visible* web view using the same
        // configuration (so it shares session/cookies with the engine
        // webview) and hand it back — WebKit drives navigation in it
        // directly. The engine webview (and its `music`/MusicKit JS
        // instance) keeps running throughout, untouched.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        self.authPresentationWebView = popup
        return popup
    }

    @MainActor func webViewDidClose(_ webView: WKWebView) {
        // Opportunistic: if Apple's sign-in page ever does call
        // window.close() on itself after finishing, this dismisses the sheet
        // (and reloads the bridge, per dismissAuthPopup()) automatically.
        // Not relied upon as the only path — the sheet's manual Cancel/Done
        // buttons call the same dismissAuthPopup() regardless.
        if self.authPresentationWebView === webView {
            dismissAuthPopup()
        }
    }
}

// MARK: - WKScriptMessageHandler

extension MusicKitBridge: WKScriptMessageHandler {
    @MainActor func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard message.name == "musicKitEvent",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            // `lastError` otherwise never clears once set (e.g. a transient
            // "MusicKit configure failed" on a bad network moment) — a fresh
            // `ready` means this configure() attempt succeeded, so whatever
            // was wrong before no longer applies. Without this, the Account
            // screen's error banner could get stuck showing a stale failure
            // forever, including right after a sign-in that actually worked
            // (dismissAuthPopup() reloads the bridge, which re-fires this).
            lastError = nil
            readyContinuations.forEach { $0.resume() }
            readyContinuations.removeAll()

        case "authorizationStatusDidChange":
            isAuthorized = (body["isAuthorized"] as? Bool) ?? false

        case "userTokenDidChange":
            // Mirrors the music-user-token into the Keychain so a future
            // cold launch — even after an uninstall/reinstall, which wipes
            // the WKWebView cookie store this session otherwise depends on —
            // can hand it back to the page and try to resume without
            // forcing a fresh sign-in. See `restoreUserToken` in the JS
            // bridge for the validity check the restored token goes through.
            if let token = body["token"] as? String, !token.isEmpty {
                Self.saveUserToken(token)
            }

        case "nowPlayingItemDidChange":
            // Same hazards as `call<T>` above (see its comments) — a live
            // radio station's `playbackDuration` can bridge to JS `Infinity`,
            // and title/artist/album strings are arbitrary real catalog text
            // that can carry ill-formed UTF-16 — so this goes through the
            // same sanitize-then-validate path rather than raw `try?`.
            let item = sanitizedForJSON(body["item"] ?? [:])
            if JSONSerialization.isValidJSONObject(item),
               let data = try? JSONSerialization.data(withJSONObject: item),
               let info = try? JSONDecoder().decode(NowPlayingInfo.self, from: data) {
                nowPlaying = info
            }

        case "playbackStateDidChange":
            if let raw = Self.intValue(body["state"]), let status = PlaybackStatus(rawValue: raw) {
                playbackStatus = status
            }

        case "playbackTimeDidChange":
            currentTime = Self.doubleValue(body["currentTime"]) ?? currentTime
            duration = Self.doubleValue(body["duration"]) ?? duration

        case "playbackModesDidChange":
            if let raw = Self.intValue(body["shuffleMode"]), let mode = ShuffleMode(rawValue: raw) {
                shuffleMode = mode
            }
            if let raw = Self.intValue(body["repeatMode"]), let mode = RepeatMode(rawValue: raw) {
                repeatMode = mode
            }
            if let vol = Self.doubleValue(body["volume"]) {
                volume = vol
            }

        case "error":
            lastError = body["message"] as? String

        default:
            break
        }
    }
}

// MARK: - Weak WKScriptMessageHandler proxy

/// `WKUserContentController.add(_:name:)` retains its handler strongly. Since
/// `MusicKitBridge` owns the web view (and therefore the controller), handing
/// it `self` directly would keep the bridge alive forever. This proxy is what
/// actually gets retained by the controller; it only references the real
/// handler weakly and simply forwards messages while it's still alive.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Small helper for safely embedding Swift strings into JS

private extension String.StringInterpolation {
    /// Usage: "\(js: someString)" -> a properly quoted + escaped JS string literal.
    mutating func appendInterpolation(js value: String) {
        if let data = try? JSONEncoder().encode(value),
           let jsonString = String(data: data, encoding: .utf8) {
            appendLiteral(jsonString)
        } else {
            appendLiteral("\"\"")
        }
    }
}
