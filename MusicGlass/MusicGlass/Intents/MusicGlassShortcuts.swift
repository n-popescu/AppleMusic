import AppIntents

/// Registers MusicGlass's App Intents as Siri phrases / Shortcuts app
/// entries. No Shortcuts/Siri Intents extension target is needed for this —
/// `AppIntents` works declared directly in the main app target on iOS 16+.
struct MusicGlassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Note: App Shortcut phrases can only embed `AppEntity`/`AppEnum`
        // parameters — a free-form `String` like `mediaName` can't appear as
        // `\.$mediaName` here (the App Intents metadata compiler rejects it).
        // The phrase is left static; the playlist/album name is still a
        // configurable parameter on the intent itself via the Shortcuts app's
        // own step editor, just not spoken as part of the Siri phrase.
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: [
                "Play music in \(.applicationName)",
                "Play my library in \(.applicationName)"
            ],
            shortTitle: "Play Media",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: TogglePlaybackIntent(),
            phrases: [
                "Play or pause \(.applicationName)",
                "Toggle playback in \(.applicationName)"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
    }
}
