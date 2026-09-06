import SwiftUI

struct NowPlayingFullView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var scrubberValue: Double = 0
    @State private var isScrubbing = false
    @State private var showQueue = false
    @State private var volumeValue: Double = 1
    @State private var isAdjustingVolume = false
    @State private var showAddToPlaylistSheet = false

    var body: some View {
        let info = store.bridge.nowPlaying

        ZStack {
            // Blurred artwork backdrop for a "glass over content" feel.
            AsyncImage(url: Artwork(width: nil, height: nil, url: info.artworkURL ?? "").resolvedURL(size: 1200)) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill).blur(radius: 60).opacity(0.6)
                }
            }
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(width: 40, height: 5)

                    HStack {
                        Spacer()
                        Menu {
                            nowPlayingMenu
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .disabled(info.catalogID == nil)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 10)

                ArtworkImage(artwork: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""), size: 300, cornerRadius: 24)
                    .shadow(radius: 20)

                VStack(spacing: 6) {
                    Text(info.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(info.artistName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)

                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubberValue : store.bridge.currentTime },
                            set: { scrubberValue = $0 }
                        ),
                        in: 0...(max(store.bridge.duration, 1)),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                Task { try? await store.bridge.seek(to: scrubberValue) }
                            }
                        }
                    )
                    .tint(.white)

                    HStack {
                        Text(timeLabel(store.bridge.currentTime))
                        Spacer()
                        Text(timeLabel(store.bridge.duration))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)

                HStack(spacing: 28) {
                    Button {
                        Task { await store.setShuffleMode(store.bridge.shuffleMode == .off ? .songs : .off) }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(GlassButtonStyle(tint: store.bridge.shuffleMode == .songs ? .pink : nil))
                    .foregroundStyle(store.bridge.shuffleMode == .songs ? .white : .white.opacity(0.6))

                    Button { Task { try? await store.bridge.skipToPrevious() } } label: {
                        Image(systemName: "backward.fill").font(.system(size: 22))
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button { Task { try? await store.bridge.togglePlayPause() } } label: {
                        Image(systemName: store.bridge.playbackStatus.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(GlassButtonStyle(tint: .pink))

                    Button { Task { try? await store.bridge.skipToNext() } } label: {
                        Image(systemName: "forward.fill").font(.system(size: 22))
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button {
                        Task { await store.cycleRepeatMode() }
                    } label: {
                        Image(systemName: repeatIconName)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(GlassButtonStyle(tint: store.bridge.repeatMode == .off ? nil : .pink))
                    .foregroundStyle(store.bridge.repeatMode == .off ? .white.opacity(0.6) : .white)
                }
                .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Slider(
                        value: Binding(
                            get: { isAdjustingVolume ? volumeValue : store.bridge.volume },
                            set: { volumeValue = $0 }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            isAdjustingVolume = editing
                            if !editing {
                                Task { await store.setVolume(volumeValue) }
                            }
                        }
                    )
                    .tint(.white)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    Button {
                        showQueue = true
                    } label: {
                        Label("Up Next", systemImage: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(GlassButtonStyle())

                    AirPlayButton(tintColor: .white)
                        .frame(width: 44, height: 44)
                        .background {
                            if #available(iOS 26.0, *) {
                                Circle().fill(.clear).glassEffect(.regular, in: Circle())
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .foregroundStyle(.white)

                Spacer()
            }
            .padding(.bottom, 20)
        }
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showAddToPlaylistSheet) {
            if let song = currentSong {
                AddToPlaylistSheet(song: song)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private var nowPlayingMenu: some View {
        // The item MusicKit JS reports as "now playing" during active
        // playback is always a song (never an album/playlist itself), so
        // "song" is the right rating/library kind here — same assumption
        // SongRow's own context menu makes for its rows.
        if let id = store.bridge.nowPlaying.catalogID {
            Button {
                Task { await store.setRating(id: id, kind: "song", value: 1) }
            } label: {
                Label("Love", systemImage: "heart")
            }
            Button {
                Task { await store.setRating(id: id, kind: "song", value: -1) }
            } label: {
                Label("Dislike", systemImage: "hand.thumbsdown")
            }
            Button {
                Task { await store.addToLibrary(id: id, kind: "song") }
            } label: {
                Label("Add to Library", systemImage: "plus.circle")
            }
            Button {
                showAddToPlaylistSheet = true
            } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
        }
    }

    /// Builds a `Song` from the bridge's now-playing info, so the same
    /// `AddToPlaylistSheet` used from library/search rows works here too.
    private var currentSong: Song? {
        let info = store.bridge.nowPlaying
        guard let id = info.catalogID else { return nil }
        return Song(
            id: id,
            title: info.title,
            artistName: info.artistName,
            albumName: info.albumName.isEmpty ? nil : info.albumName,
            durationMillis: Int(info.durationSeconds * 1000),
            artwork: info.artworkURL.map { Artwork(width: nil, height: nil, url: $0) },
            releaseDate: nil,
            playParams: PlayParams(id: id, kind: "song", isLibrary: nil)
        )
    }

    private var repeatIconName: String {
        switch store.bridge.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
