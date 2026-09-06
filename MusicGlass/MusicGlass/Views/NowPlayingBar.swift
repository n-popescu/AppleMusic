import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Binding var showFullPlayer: Bool
    @State private var showQueue = false

    var body: some View {
        let info = store.bridge.nowPlaying
        if !info.title.isEmpty {
            GlassSurface(cornerRadius: 22) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ArtworkImage(artwork: Artwork(width: nil, height: nil, url: info.artworkURL ?? ""), size: 40, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(info.artistName)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            showQueue = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .buttonStyle(GlassButtonStyle())

                        Button {
                            Task { try? await store.bridge.togglePlayPause() }
                        } label: {
                            Image(systemName: store.bridge.playbackStatus.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle())

                        Button {
                            Task { try? await store.bridge.skipToNext() }
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    // Slim progress indicator, like the real Apple Music mini
                    // player — read-only here (tap the bar to open the full
                    // player and use its scrubber to seek).
                    GeometryReader { proxy in
                        let fraction = store.bridge.duration > 0
                            ? min(max(store.bridge.currentTime / store.bridge.duration, 0), 1)
                            : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(.pink).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
            .padding(.horizontal, 12)
            .onTapGesture { showFullPlayer = true }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .environmentObject(store)
            }
        }
    }
}
