import SwiftUI
import AVFoundation

@main
struct MusicGlassApp: App {

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    /// Playback happens inside a hidden `WKWebView`'s `<audio>`/media engine, not
    /// a native `AVPlayer` — the system won't automatically treat this as
    /// "playback audio" (background audio, silent-switch behavior, mixing with
    /// other apps) unless the audio session category is configured up front.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Playback may still work without this (e.g. audio simply won't
            // continue in the background, or will respect the silent switch),
            // so this is logged rather than treated as fatal.
            print("MusicGlass: failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
}
