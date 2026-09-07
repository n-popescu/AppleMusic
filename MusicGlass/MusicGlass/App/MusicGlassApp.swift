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
            // Deliberately NOT setActive(true) here. Activating a .playback
            // session takes the audio route and interrupts whatever else is
            // playing — so merely opening this app would stop the podcast or
            // music already coming out of the phone, before anyone had asked
            // it to play anything. Activation happens when playback actually
            // starts; see NowPlayingRemoteController.activateSessionIfNeeded.
        } catch {
            // Playback may still work without this (e.g. audio simply won't
            // continue in the background, or will respect the silent switch),
            // so this is logged rather than treated as fatal.
            print("MusicGlass: failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
}
