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
    @StateObject private var accent = ArtworkAccent()

    var body: some View {
        let info = store.bridge.nowPlaying

        GeometryReader { proxy in
            // Artwork used to be pinned at 300pt regardless of the screen.
            // Together with the fixed 28pt section spacing that overflowed
            // the sheet on anything but the largest phones, squashing the
            // controls below it. Sizing it from the space actually
            // available keeps the whole stack on screen everywhere.
            let artworkSize = max(min(proxy.size.width - 80, proxy.size.height * 0.38), 120)
            let spacing = proxy.size.height < 700 ? 16.0 : 24.0

            ZStack {
                Color.black.ignoresSafeArea()

                // Colour wash derived from the artwork. Sits under the blurred
                // image so the screen is already tinted the moment it opens,
                // rather than flashing black until the 1200pt art downloads.
                if let color = accent.color {
                    LinearGradient(
                        colors: [color.opacity(0.85), color.opacity(0.25), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                }

                // Blurred artwork backdrop for a "glass over content" feel.
                // This had no frame of its own, so with `.fill` it sized to
                // the raw 1200pt artwork and dragged the entire ZStack out
                // to those dimensions — which is what made this screen's
                // layout go haywire. It has to be clamped to the view and
                // clipped, not left to its intrinsic size.
                AsyncImage(url: Artwork(width: nil, height: nil, url: info.artworkURL ?? "").resolvedURL(size: 1200)) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60)
                            .opacity(0.6)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.55), .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: spacing) {
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
                                    .foregroundStyle(Palette.secondaryText)
                                    .contentShape(Circle())
                            }
                            .disabled(info.catalogID == nil)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)

                    ArtworkImage(artwork: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""), size: artworkSize, cornerRadius: 26)
                        .shadow(color: .black.opacity(0.6), radius: 32, y: 18)
                        .scaleEffect(store.bridge.playbackStatus.isPlaying ? 1.0 : 0.94)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.bridge.playbackStatus.isPlaying)

                    VStack(spacing: 6) {
                        Text(info.title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(info.artistName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
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
                        .tint(Palette.accent)

                        HStack {
                            Text(timeLabel(isScrubbing ? scrubberValue : store.bridge.currentTime))
                            Spacer()
                            Text("-" + timeLabel(max(store.bridge.duration - (isScrubbing ? scrubberValue : store.bridge.currentTime), 0)))
                        }
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.tertiaryText)
                    }
                    .padding(.horizontal, 24)

                    // Five buttons at a fixed 28pt gap came to ~354pt, which
                    // overflows the narrower phones once horizontal padding
                    // is accounted for — hence the squeezed/clipped row.
                    GlassGroup(spacing: 20) {
                        HStack(spacing: proxy.size.width < 380 ? 14 : 24) {
                            Button {
                                Task { await store.setShuffleMode(store.bridge.shuffleMode == .off ? .songs : .off) }
                            } label: {
                                if store.isTogglingPlaybackMode {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .buttonStyle(GlassButtonStyle(tint: store.bridge.shuffleMode == .songs ? Palette.accent : nil))
                            .foregroundStyle(store.bridge.shuffleMode == .songs ? .white : .white.opacity(0.6))
                            .disabled(store.isTogglingPlaybackMode)

                            Button { Task { await store.skipToPrevious() } } label: {
                                Image(systemName: "backward.fill").font(.system(size: 22))
                            }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(store.isTransportBusy)

                            Button { Task { await store.togglePlayPause() } } label: {
                                if store.isTransportBusy || store.bridge.playbackStatus.isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: store.bridge.playbackStatus.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30))
                                }
                            }
                            .buttonStyle(GlassButtonStyle(tint: Palette.accent, size: 26))
                            .disabled(store.isTransportBusy)

                            Button { Task { await store.skipToNext() } } label: {
                                Image(systemName: "forward.fill").font(.system(size: 22))
                            }
                            .buttonStyle(GlassButtonStyle())
                            .disabled(store.isTransportBusy)

                            Button {
                                Task { await store.cycleRepeatMode() }
                            } label: {
                                if store.isTogglingPlaybackMode {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: repeatIconName)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .buttonStyle(GlassButtonStyle(tint: store.bridge.repeatMode == .off ? nil : Palette.accent))
                            .foregroundStyle(store.bridge.repeatMode == .off ? .white.opacity(0.6) : .white)
                            .disabled(store.isTogglingPlaybackMode)
                        }
                        .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.tertiaryText)
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
                        .tint(Palette.primaryText.opacity(0.85))
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 16) {
                        Button {
                            showQueue = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(GlassButtonStyle())
                        .accessibilityLabel("Up Next")

                        // Not a real MusicKit JS toggle — there's no
                        // confirmed "continue with similar music" API to
                        // hook into (unlike the native Music app's own
                        // Autoplay, which runs on an internal recommendation
                        // algorithm this project has no access to). This
                        // flips MusicLibraryStore.isAutoplayEnabled, which
                        // starts something from Discover's charts/
                        // recommendations once the queue genuinely plays
                        // out — an honest approximation, not the same
                        // feature.
                        Button {
                            store.isAutoplayEnabled.toggle()
                        } label: {
                            Label("Autoplay", systemImage: "infinity")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(GlassButtonStyle(tint: store.isAutoplayEnabled ? Palette.accent : nil))
                        .foregroundStyle(store.isAutoplayEnabled ? .white : .white.opacity(0.6))

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

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 20)
            }
        }
        .presentationDragIndicator(.hidden)
        .task(id: store.bridge.nowPlaying.artworkURL) {
            await accent.load(
                from: Artwork(width: nil, height: nil, url: store.bridge.nowPlaying.artworkURL ?? "")
            )
        }
        .animation(.easeInOut(duration: 0.5), value: accent.color)
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
