import SwiftUI

/// The floating mini player. This is navigation-layer furniture, so it's the
/// one part of the app that legitimately gets Liquid Glass — but the controls
/// on it are plain glyphs rather than glass circles: stacking glass on glass
/// is what the material is explicitly not meant to do, and three little
/// discs on a pill also read as clutter at this size.
struct NowPlayingBar: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Binding var showFullPlayer: Bool
    // Tints the glass toward whatever is playing, so the mini player picks up
    // the album's colour the same way the full player does.
    @StateObject private var accent = ArtworkAccent()
    @State private var dragOffset: CGFloat = 0

    private var progress: Double {
        guard store.bridge.duration > 0 else { return 0 }
        return min(max(store.bridge.currentTime / store.bridge.duration, 0), 1)
    }

    var body: some View {
        let info = store.bridge.nowPlaying
        if !info.title.isEmpty {
            GlassSurface(cornerRadius: 26, tint: accent.color, interactive: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ArtworkImage(
                            artwork: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""),
                            size: 44,
                            cornerRadius: 12
                        )
                        .shadow(color: .black.opacity(0.45), radius: 7, y: 4)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.primaryText)
                                .lineLimit(1)
                            Text(info.artistName)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            Task { await store.togglePlayPause() }
                        } label: {
                            ZStack {
                                if store.isTransportBusy || store.bridge.playbackStatus.isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: store.bridge.playbackStatus.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(Palette.primaryText)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isTransportBusy)

                        Button {
                            Task { await store.skipToNext() }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Palette.primaryText)
                                .frame(width: 38, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isTransportBusy)
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    // Hairline progress pinned to the bottom edge of the pill
                    // rather than floating inside it — it reads as the pill
                    // filling up, and gives back the vertical space the old
                    // inset bar was taking.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule()
                                .fill(accent.color ?? Palette.accent)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 12)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            // The glass backdrop is drawn by a `.background`/`.glassEffect`,
            // neither of which makes the bar hit-testable — so every touch
            // that didn't land exactly on a label or glyph passed straight
            // through to the list behind it. This makes the whole pill a
            // real touch target, which also stops taps meant for the mini
            // player from selecting rows underneath it.
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .offset(x: dragOffset)
            .onTapGesture { showFullPlayer = true }
            // Horizontal flicks skip tracks, the way the real Music app's
            // mini player does. Vertical is left alone so the gesture doesn't
            // fight the scroll view underneath.
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { gesture in
                        guard abs(gesture.translation.width) > abs(gesture.translation.height) else { return }
                        dragOffset = gesture.translation.width / 3
                    }
                    .onEnded { gesture in
                        let horizontal = gesture.translation.width
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                        guard abs(horizontal) > abs(gesture.translation.height), abs(horizontal) > 60 else { return }
                        Task {
                            if horizontal < 0 {
                                await store.skipToNext()
                            } else {
                                await store.skipToPrevious()
                            }
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.snappy(duration: 0.3), value: info.title)
            .task(id: info.artworkURL) {
                await accent.load(from: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""))
            }
        }
    }
}
