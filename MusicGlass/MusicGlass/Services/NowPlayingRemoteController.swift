import Foundation
import MediaPlayer
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Mirrors playback state from the hidden MusicKit JS engine into the system's
/// Lock Screen / Control Center "Now Playing" UI, and wires transport controls
/// from there back into `MusicKitBridge`.
///
/// This exists because playback here runs inside a `WKWebView`'s JS engine
/// rather than a native `AVPlayer`/`MPMusicPlayerController`, so none of this
/// is automatic — the OS has no idea audio is even playing unless we tell it.
@MainActor
final class NowPlayingRemoteController {
    private let store: MusicLibraryStore
    private var cancellables = Set<AnyCancellable>()

    /// Cache so we don't re-download the same artwork on every playback-time tick.
    private var cachedArtworkURLString: String?
    private var cachedArtworkImage: UIImage?
    private var artworkLoadTask: Task<Void, Never>?

    /// The running Live Activity, if any. Typed `Any` (rather than
    /// `Activity<MusicGlassActivityAttributes>`) so this property itself
    /// doesn't need an `@available` annotation, which Swift doesn't allow on
    /// stored properties of a non-`@available` class.
    private var liveActivity: Any?

    init(store: MusicLibraryStore) {
        self.store = store
        configureRemoteCommands()
        observePlaybackState()
        // Disabled: this was assumed to fail silently without a Widget
        // Extension target to render the Live Activity's actual content
        // (see the big comment below), but `Activity.request` apparently
        // succeeds anyway and reserves a real, visible Live Activity slot —
        // which on-device showed up as an empty bar spanning the top of the
        // screen, expanded but rendering nothing, since there's no extension
        // providing any UI for it. Re-enable this once that extension
        // actually exists (see the README's "Live Activity / Widget —
        // manual Xcode step required" section); until then, starting one is
        // strictly worse than not having the feature.
        // observePlaybackStateForLiveActivity()
        endAnyExistingLiveActivities()
    }

    /// Live Activities started by a previous launch (before this was
    /// disabled above) can still be running — ActivityKit persists them
    /// independent of the app's own process, so simply not starting new
    /// ones doesn't clear an old one already stuck showing an empty bar.
    /// Ends every activity for this app's attributes type on launch, once,
    /// as cleanup; harmless (and near-instant) once none exist.
    private func endAnyExistingLiveActivities() {
        guard #available(iOS 16.2, *) else { return }
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<MusicGlassActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    // MARK: - Mirroring MusicKitBridge -> MPNowPlayingInfoCenter

    private func observePlaybackState() {
        store.bridge.$nowPlaying
            .combineLatest(store.bridge.$playbackStatus, store.bridge.$currentTime, store.bridge.$duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlaying, status, currentTime, duration in
                self?.updateNowPlayingInfo(nowPlaying: nowPlaying, status: status, currentTime: currentTime, duration: duration)
            }
            .store(in: &cancellables)
    }

    private func updateNowPlayingInfo(nowPlaying: NowPlayingInfo, status: PlaybackStatus, currentTime: Double, duration: Double) {
        guard !nowPlaying.title.isEmpty else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        // WebKit runs its own media-remote integration for the <audio>
        // element MusicKit JS drives, and it configures the *shared*
        // MPRemoteCommandCenter when that element starts playing — enabling
        // its skip-interval commands and disabling next/previous track,
        // which is what put "skip 10 seconds" buttons on the Lock Screen in
        // place of real track controls. Our own setup only ran once at
        // launch, before any playback existed, so WebKit's always won.
        // Re-asserting it here (on every now-playing/state change, i.e.
        // right after WebKit has done its thing) reclaims the command
        // center each time.
        applyCommandEnablement()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artistName,
            MPMediaItemPropertyAlbumTitle: nowPlaying.albumName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyPlaybackRate: status.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            // Declares this as music rather than letting the system infer a
            // generic/video-ish type from the underlying web media element,
            // which also influences which transport controls it offers.
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]

        if cachedArtworkURLString == nowPlaying.artworkURL, let image = cachedArtworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if cachedArtworkURLString != nowPlaying.artworkURL {
            loadArtwork(urlString: nowPlaying.artworkURL)
        }
    }

    private func loadArtwork(urlString: String?) {
        artworkLoadTask?.cancel()
        cachedArtworkURLString = urlString
        cachedArtworkImage = nil

        guard let urlString,
              let url = Artwork(width: nil, height: nil, url: urlString).resolvedURL(size: 600) else {
            return
        }

        artworkLoadTask = Task { [weak self] in
            guard let self else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard !Task.isCancelled, let image = UIImage(data: data) else { return }
            // The now-playing item may have changed again while this was in flight.
            guard self.cachedArtworkURLString == urlString else { return }
            self.cachedArtworkImage = image

            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    // MARK: - Remote commands -> MusicKitBridge

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.run { try await $0.bridge.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { try await $0.bridge.pause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.run { try await $0.bridge.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.run { try await $0.bridge.skipToNext() }
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.run { try await $0.bridge.skipToPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let seconds = event.positionTime
            self.run { try await $0.bridge.seek(to: seconds) }
            return .success
        }

        applyCommandEnablement()
    }

    /// Which transport controls the system offers, split out from
    /// `configureRemoteCommands()` so it can be re-applied on every
    /// now-playing update. The `addTarget` calls above must run exactly
    /// once (re-adding would stack duplicate handlers, so one tap would
    /// skip several tracks), but the `isEnabled` flags are just state on
    /// the shared command center that WebKit's own media integration
    /// overwrites when web audio starts playing — so those do need
    /// re-asserting, and are safe to set repeatedly.
    private func applyCommandEnablement() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        // Scrubbing/seeking-by-offset isn't meaningful for a streaming JS
        // player without a known seek granularity, so only position-based
        // seeking (above) and the transport commands are enabled. Leaving
        // these on is also what makes the system show interval-skip buttons
        // instead of previous/next.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    // MARK: - Live Activity / Dynamic Island
    //
    // This is code-ready but currently inert: `Activity.request` needs a
    // matching Widget Extension target (which owns the actual Live Activity
    // UI) to be present in the app bundle, and this project intentionally
    // doesn't hand-author one blind — see the README's "Live Activity /
    // Widget — manual Xcode step required" section. Until that extension is
    // added, these calls will simply fail (caught and ignored below) rather
    // than doing anything visible. `MusicGlassActivityAttributes` (in
    // Models/) is the shared type both sides would use.

    private func observePlaybackStateForLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        store.bridge.$nowPlaying
            .combineLatest(store.bridge.$playbackStatus, store.bridge.$currentTime, store.bridge.$duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlaying, status, currentTime, duration in
                self?.updateLiveActivity(nowPlaying: nowPlaying, status: status, currentTime: currentTime, duration: duration)
            }
            .store(in: &cancellables)
    }

    @available(iOS 16.2, *)
    private func updateLiveActivity(nowPlaying: NowPlayingInfo, status: PlaybackStatus, currentTime: Double, duration: Double) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard !nowPlaying.title.isEmpty else {
            Task { await endLiveActivity() }
            return
        }

        let state = MusicGlassActivityAttributes.ContentState(
            title: nowPlaying.title,
            artistName: nowPlaying.artistName,
            albumName: nowPlaying.albumName,
            artworkURL: nowPlaying.artworkURL,
            isPlaying: status.isPlaying,
            currentTimeSeconds: currentTime,
            durationSeconds: duration
        )

        if let activity = liveActivity as? Activity<MusicGlassActivityAttributes> {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            do {
                let activity = try Activity<MusicGlassActivityAttributes>.request(
                    attributes: MusicGlassActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil)
                )
                liveActivity = activity
            } catch {
                // No Widget Extension target present yet (or the user has
                // Live Activities disabled) — nothing to do until the
                // manual Xcode step in the README is completed.
            }
        }
        #endif
    }

    @available(iOS 16.2, *)
    private func endLiveActivity() async {
        #if canImport(ActivityKit)
        guard let activity = liveActivity as? Activity<MusicGlassActivityAttributes> else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        liveActivity = nil
        #endif
    }

    /// Fires a bridge call from a synchronous MPRemoteCommandCenter callback,
    /// swallowing errors (there's no UI to surface them to from here — they
    /// still land on `MusicKitBridge.lastError` for the Settings screen).
    private func run(_ operation: @escaping (MusicLibraryStore) async throws -> Void) {
        let store = store
        Task { @MainActor in
            do {
                try await operation(store)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}
