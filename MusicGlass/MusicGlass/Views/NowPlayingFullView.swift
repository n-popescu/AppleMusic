import SwiftUI

struct NowPlayingFullView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var scrubberValue: Double = 0
    @State private var isScrubbing = false
    @State private var volumeValue: Double = 1
    @State private var isAdjustingVolume = false
    @State private var showQueue = false
    @State private var showAddToPlaylistSheet = false
    @StateObject private var accent = ArtworkAccent()

    var body: some View {
        let info = store.bridge.nowPlaying

        GeometryReader { proxy in
            // Artwork used to be pinned at 300pt regardless of the screen.
            // Together with the fixed section spacing that overflowed the
            // sheet on anything but the largest phones, squashing the
            // controls below it. Sizing it from the space actually available
            // keeps the whole stack on screen everywhere.
            let isCompact = proxy.size.height < 720
            let artworkSize = max(min(proxy.size.width - 72, proxy.size.height * 0.40), 120)
            let spacing: CGFloat = isCompact ? 18 : 28

            ZStack {
                backdrop(info: info, size: proxy.size)

                VStack(spacing: spacing) {
                    grabber

                    artwork(info: info, size: artworkSize)

                    titleBlock(info: info)

                    scrubber

                    transport

                    if !isCompact {
                        volumeRow
                    }

                    utilityRow

                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    // MARK: - Backdrop

    private func backdrop(info: NowPlayingInfo, size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Colour wash derived from the artwork. Sits under the blurred
            // image so the screen is already tinted the moment it opens,
            // rather than flashing black until the large art downloads.
            if let color = accent.color {
                LinearGradient(
                    colors: [color.opacity(0.9), color.opacity(0.30), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // This had no frame of its own, so with `.fill` it sized to the
            // raw 1200pt artwork and dragged the entire ZStack out to those
            // dimensions — which is what made this screen's layout go
            // haywire. It has to be clamped to the view and clipped, not
            // left to its intrinsic size.
            AsyncImage(url: Artwork(width: nil, height: nil, url: info.artworkURL ?? "").resolvedURL(size: 1200)) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 70)
                        .opacity(0.55)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.5), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Pieces

    private var grabber: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 38, height: 5)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    nowPlayingMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .disabled(info.catalogID == nil)
            }
            .padding(.horizontal, 20)
        }
    }

    private var info: NowPlayingInfo { store.bridge.nowPlaying }

    private func artwork(info: NowPlayingInfo, size: CGFloat) -> some View {
        ArtworkImage(
            artwork: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""),
            size: size,
            cornerRadius: 18
        )
        .shadow(color: .black.opacity(0.6), radius: 34, y: 20)
        // Paused art sits back a little, the way the real Music app's does —
        // a cheap but effective read on playback state without another label.
        .scaleEffect(store.bridge.playbackStatus.isPlaying ? 1.0 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: store.bridge.playbackStatus.isPlaying)
    }

    private func titleBlock(info: NowPlayingInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(info.artistName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.primaryText.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let id = info.catalogID {
                Button {
                    Task { await store.setRating(id: id, kind: "song", value: 1) }
                } label: {
                    Image(systemName: "heart")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.primaryText.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 30)
    }

    private var scrubber: some View {
        // While dragging, the labels have to follow the finger rather than the
        // player — the player hasn't been told to seek yet, so reading its
        // currentTime here would leave the numbers frozen mid-drag.
        let shown = isScrubbing ? scrubberValue : store.bridge.currentTime

        return VStack(spacing: 4) {
            ScrubBar(
                value: Binding(
                    get: { isScrubbing ? scrubberValue : store.bridge.currentTime },
                    set: { scrubberValue = $0 }
                ),
                range: 0...(max(store.bridge.duration, 1)),
                accent: accent.color ?? Palette.accent,
                onEditingChanged: { editing in isScrubbing = editing }
            ) { committed in
                scrubberValue = committed
                Task { try? await store.bridge.seek(to: committed) }
            }

            HStack {
                Text(timeLabel(shown))
                Spacer()
                Text("-" + timeLabel(max(store.bridge.duration - shown, 0)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Palette.primaryText.opacity(0.5))
        }
        .padding(.horizontal, 30)
    }

    /// Transport is deliberately *not* five glass discs any more. Prev/next
    /// are bare glyphs and only play/pause is a filled target, which is the
    /// hierarchy people actually use these controls in.
    private var transport: some View {
        HStack(spacing: 0) {
            Button {
                Task { await store.setShuffleMode(store.bridge.shuffleMode == .off ? .songs : .off) }
            } label: {
                modeGlyph("shuffle", isActive: store.bridge.shuffleMode == .songs)
            }
            .buttonStyle(.plain)
            .disabled(store.isTogglingPlaybackMode)

            Spacer(minLength: 0)

            Button { Task { await store.skipToPrevious() } } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isTransportBusy)

            Spacer(minLength: 0)

            Button { Task { await store.togglePlayPause() } } label: {
                ZStack {
                    Circle()
                        .fill(Palette.primaryText)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)

                    if store.isTransportBusy || store.bridge.playbackStatus.isBusy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: store.bridge.playbackStatus.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.black)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isTransportBusy)

            Spacer(minLength: 0)

            Button { Task { await store.skipToNext() } } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.isTransportBusy)

            Spacer(minLength: 0)

            Button {
                Task { await store.cycleRepeatMode() }
            } label: {
                modeGlyph(repeatIconName, isActive: store.bridge.repeatMode != .off)
            }
            .buttonStyle(.plain)
            .disabled(store.isTogglingPlaybackMode)
        }
        .padding(.horizontal, 28)
    }

    private func modeGlyph(_ systemName: String, isActive: Bool) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .fill((accent.color ?? Palette.accent).opacity(0.28))
                    .frame(width: 38, height: 38)
            }
            if store.isTogglingPlaybackMode {
                ProgressView().tint(.white)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive ? Palette.primaryText : Palette.primaryText.opacity(0.55))
            }
        }
        .frame(width: 46, height: 46)
        .contentShape(Circle())
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.primaryText.opacity(0.45))

            ScrubBar(
                value: Binding(
                    get: { isAdjustingVolume ? volumeValue : store.bridge.volume },
                    set: { volumeValue = $0 }
                ),
                range: 0...1,
                accent: Palette.primaryText.opacity(0.85),
                onEditingChanged: { editing in isAdjustingVolume = editing }
            ) { committed in
                volumeValue = committed
                Task { await store.setVolume(committed) }
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.primaryText.opacity(0.45))
        }
        .padding(.horizontal, 30)
    }

    /// Queue / Autoplay / AirPlay share one glass capsule instead of each
    /// carrying its own disc — one sampling region, and it reads as a single
    /// secondary control cluster rather than three competing buttons.
    private var utilityRow: some View {
        GlassGroup(spacing: 10) {
            GlassSurface(cornerRadius: 26) {
                HStack(spacing: 6) {
                    Button {
                        showQueue = true
                    } label: {
                        utilityGlyph("list.bullet", isActive: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Up Next")

                    // Not a real MusicKit JS toggle — there's no confirmed
                    // "continue with similar music" API to hook into (unlike
                    // the native Music app's own Autoplay, which runs on an
                    // internal recommendation algorithm this project has no
                    // access to). This flips
                    // MusicLibraryStore.isAutoplayEnabled, which starts
                    // something from Home's charts/recommendations once the
                    // queue genuinely plays out — an honest approximation,
                    // not the same feature.
                    Button {
                        store.isAutoplayEnabled.toggle()
                    } label: {
                        utilityGlyph("infinity", isActive: store.isAutoplayEnabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Autoplay")

                    AirPlayButton(tintColor: .white)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func utilityGlyph(_ systemName: String, isActive: Bool) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .fill((accent.color ?? Palette.accent).opacity(0.35))
                    .frame(width: 36, height: 36)
            }
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Palette.primaryText : Palette.primaryText.opacity(0.65))
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    // MARK: - Menu

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
