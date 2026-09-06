import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Binding var showFullPlayer: Bool
    @State private var showQueue = false

    var body: some View {
        let info = store.bridge.nowPlaying
        if !info.title.isEmpty {
            GlassSurface(cornerRadius: 22) {
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
                .padding(.vertical, 8)
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
