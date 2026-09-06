import AppIntents

/// "Play/Pause" — toggles whatever Lucent is currently playing, without
/// needing to open the app. Like `PlayMediaIntent`, this reaches the running
/// app's state through `MusicLibraryStore.current` since App Intents don't
/// have a SwiftUI environment of their own.
struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause Lucent"
    static var description = IntentDescription(
        "Toggles play/pause for whatever Lucent is currently playing."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = MusicLibraryStore.current else {
            return .result(dialog: "Open Lucent at least once, then try again.")
        }
        let wasPlaying = store.bridge.playbackStatus.isPlaying
        do {
            try await store.bridge.togglePlayPause()
            return .result(dialog: wasPlaying ? "Paused." : "Playing.")
        } catch {
            return .result(dialog: "Couldn't toggle playback.")
        }
    }
}
