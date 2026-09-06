import AppIntents

/// Registers MusicGlass's App Intents as Siri phrases / Shortcuts app
/// entries. No Shortcuts/Siri Intents extension target is needed for this —
/// `AppIntents` works declared directly in the main app target on iOS 16+.
struct MusicGlassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: [
                "Play \(\.$mediaName) in \(.applicationName)",
                "Play \(\.$mediaName) on \(.applicationName)"
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
