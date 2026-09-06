import SwiftUI

struct ArtworkImage: View {
    let artwork: Artwork?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: artwork?.resolvedURL(size: Int(size * 3))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SongRow: View {
    let song: Song
    var isCurrentlyPlaying: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkImage(artwork: song.artwork)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCurrentlyPlaying ? .pink : .white)
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                if isCurrentlyPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(.pink)
                } else {
                    Text(durationLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var durationLabel: String {
        let total = Int(song.durationSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
