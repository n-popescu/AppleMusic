import AppIntents

/// "Play [playlist/album name] in Lucent" — resolves against whatever's
/// already loaded in `MusicLibraryStore` (falling back to a fresh library
/// fetch if nothing has loaded yet), then starts playback the same way a tap
/// on a `TileCard` would.
///
/// App Intents have no SwiftUI environment to pull a store from, so this
/// reaches `MusicLibraryStore.current` — a weak static reference the store
/// sets on itself in `init`. If the app has never launched in this process
/// (e.g. a cold Shortcuts-only invocation before first open), there's no
/// store yet and the intent reports that back via its dialog rather than
/// crashing.
struct PlayMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "Play in Lucent"
    static var description = IntentDescription(
        "Plays a playlist or album from your Lucent library by name."
    )

    @Parameter(title: "Playlist or Album Name")
    var mediaName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$mediaName) in Lucent")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = MusicLibraryStore.current else {
            return .result(dialog: "Open Lucent at least once, then try again.")
        }

        let query = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .result(dialog: "Tell me a playlist or album name to play.")
        }

        if store.playlists.isEmpty && store.albums.isEmpty && store.bridge.isAuthorized {
            await store.refreshLibrary()
        }

        let lowered = query.lowercased()
        if let playlist = store.playlists.first(where: { $0.name.lowercased().contains(lowered) }) {
            await store.play(playlist: playlist)
            return .result(dialog: "Playing \(playlist.name).")
        }
        if let album = store.albums.first(where: { $0.title.lowercased().contains(lowered) }) {
            await store.play(album: album)
            return .result(dialog: "Playing \(album.title).")
        }
        return .result(dialog: "Couldn't find \"\(query)\" in your Lucent library.")
    }
}
