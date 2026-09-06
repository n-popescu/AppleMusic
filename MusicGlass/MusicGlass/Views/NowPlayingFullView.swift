import SwiftUI

struct NowPlayingFullView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var scrubberValue: Double = 0
    @State private var isScrubbing = false
    @State private var showQueue = false

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
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
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

                HStack(spacing: 36) {
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
                }
                .foregroundStyle(.white)

                Button {
                    showQueue = true
                } label: {
                    Label("Up Next", systemImage: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(GlassButtonStyle())
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
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
