import Foundation
import MediaPlayer
import Combine
#if canImport(UIKit)
import UIKit
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

    init(store: MusicLibraryStore) {
        self.store = store
        configureRemoteCommands()
        observePlaybackState()
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

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artistName,
            MPMediaItemPropertyAlbumTitle: nowPlaying.albumName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyPlaybackRate: status.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
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

        // Scrubbing/seeking-by-offset isn't meaningful for a streaming JS
        // player without a known seek granularity, so only position-based
        // seeking (above) and the transport commands are enabled.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
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
