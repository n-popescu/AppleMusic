import SwiftUI
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Palette
//
// One place for every colour in the app, so screens can't drift apart the way
// they had (each view hardcoding its own `.white.opacity(0.6)` variants).

enum Palette {
    /// Deep, slightly violet black — warmer than pure black, which reads as a
    /// dead rectangle next to album art.
    static let background = Color(red: 0.035, green: 0.030, blue: 0.055)
    static let backgroundRaised = Color(red: 0.075, green: 0.068, blue: 0.105)

    static let accent = Color(red: 0.98, green: 0.22, blue: 0.42)
    static let accentSecondary = Color(red: 0.50, green: 0.34, blue: 0.96)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    static let hairline = Color.white.opacity(0.09)
    /// Content-layer fills. Deliberately *not* glass — per Apple's Liquid Glass
    /// guidance glass belongs to the navigation layer (tab bar, mini player,
    /// toolbars, floating controls) and content must stay on its own layer
    /// beneath it. Glass-on-content also means glass sampling glass, which is
    /// what makes a screen look muddy.
    static let contentFill = Color.white.opacity(0.055)
    static let contentFillRaised = Color.white.opacity(0.095)

    /// Brand gradient used for headers, the mini player's progress and any
    /// "this is playing" affordance.
    static let accentGradient = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Artwork-derived accent colour

/// Pulls a single representative colour out of a piece of artwork so a screen
/// can tint itself to whatever it's showing — the gradient treatment the
/// now-playing screen already had, now reusable for playlist/album headers and
/// tiles.
///
/// Averaging (rather than a full k-means "dominant colour" pass) is deliberate:
/// it's one CoreImage filter over a thumbnail, cheap enough to run per-screen,
/// and the saturation/brightness floor below is what keeps the result vivid
/// rather than the muddy grey a raw average of a busy cover tends to produce.
@MainActor
final class ArtworkAccent: ObservableObject {
    @Published private(set) var color: Color?

    private static let cache = NSCache<NSString, UIColor>()
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    func load(from artwork: Artwork?) async {
        guard let url = artwork?.resolvedURL(size: 160) else { return }
        let key = url.absoluteString as NSString

        if let cached = Self.cache.object(forKey: key) {
            color = Color(cached)
            return
        }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data),
              let ciImage = CIImage(image: image) else { return }

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ]), let output = filter.outputImage else { return }

        var pixel = [UInt8](repeating: 0, count: 4)
        Self.context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let raw = UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard raw.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return }

        // A flat average of real cover art lands somewhere desaturated and dim
        // more often than not. Floor both so the gradient actually reads as a
        // colour, and cap brightness so it never washes out white text on top.
        let tuned = UIColor(
            hue: hue,
            saturation: max(saturation, 0.45),
            brightness: min(max(brightness, 0.42), 0.72),
            alpha: 1
        )

        Self.cache.setObject(tuned, forKey: key)
        color = Color(tuned)
    }
}

// MARK: - Backdrops

/// The app-wide background: a near-black base with two soft colour blooms.
/// `accent` lets a screen bias those blooms toward whatever it's displaying
/// (an album's own colour, say) while every screen keeps the same shape of
/// backdrop so they still feel like one app.
struct AuroraBackdrop: View {
    var accent: Color?

    var body: some View {
        ZStack {
            Palette.background

            GeometryReader { proxy in
                let bloom = accent ?? Palette.accent
                let secondary = accent?.opacity(0.9) ?? Palette.accentSecondary

                Circle()
                    .fill(bloom.opacity(0.30))
                    .frame(width: proxy.size.width * 1.1)
                    .blur(radius: 110)
                    .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.18)

                Circle()
                    .fill(secondary.opacity(0.22))
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 120)
                    .offset(x: proxy.size.width * 0.45, y: proxy.size.height * 0.30)
            }
            // The blooms are decoration only — never let them intercept taps
            // meant for the content sitting on top of them.
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Standard screen background. Replaces the old flat `glassBackdrop()`.
    func auroraBackground(accent: Color? = nil) -> some View {
        background(AuroraBackdrop(accent: accent))
    }
}

// MARK: - Content surfaces (content layer — deliberately not glass)

/// A content-layer card. Uses a plain translucent fill + hairline border
/// rather than `.glassEffect`, because glass on scrollable content is exactly
/// what Apple's guidance says not to do — it belongs to the floating
/// navigation layer only.
struct ContentSurface<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    /// Optional colour wash, e.g. an album's own artwork colour.
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.contentFill)

                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.30), tint.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                }
            }
    }
}

// MARK: - Typography / section furniture

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var accessory: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

/// Large screen title, used where a plain `.navigationTitle` would sit oddly
/// over the aurora backdrop.
struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let subtitle {
                Text(subtitle.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Palette.accent)
            }
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Media tile

/// The standard artwork tile used across Home, Radio, Search and Library.
/// Replaces the old flat `TileCard`: rounded artwork with a real drop shadow
/// so tiles lift off the backdrop, a subtle top-light gradient over the art,
/// and the loading overlay used while this specific item's play request is in
/// flight.
struct MediaTile: View {
    let title: String
    var subtitle: String?
    let artwork: Artwork?
    var size: CGFloat = 152
    var isLoading: Bool = false
    /// Circular crop for artists, where a square reads as an album.
    var isCircular: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                ArtworkImage(
                    artwork: artwork,
                    size: size,
                    cornerRadius: isCircular ? size / 2 : 16
                )

                // Gentle sheen so flat, single-colour covers still have shape.
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isCircular ? size / 2 : 16,
                        style: .continuous
                    )
                )
                .allowsHitTesting(false)

                if isLoading {
                    RoundedRectangle(cornerRadius: isCircular ? size / 2 : 16, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: size, height: size)
                        .overlay { ProgressView().tint(.white) }
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: size, alignment: .leading)
        }
        .frame(width: size)
    }
}

// MARK: - Empty / error states

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent.opacity(0.85))
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.primaryText)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background {
                    Capsule().fill(Palette.accentGradient)
                }
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
}

// MARK: - Detail header

/// Shared hero header for playlist / album / artist screens: oversized artwork
/// sitting in a colour bleed pulled from that artwork, so each screen takes on
/// the identity of what it's showing — the same treatment the now-playing
/// screen uses, applied everywhere it makes sense.
struct DetailHeader: View {
    let artwork: Artwork?
    let title: String
    var subtitle: String?
    var detail: String?
    var accent: Color?
    var isCircular: Bool = false

    private let artSize: CGFloat = 208

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Colour bleed *behind* the art, so the artwork appears to be
                // lighting the screen rather than sitting on it.
                if let accent {
                    Circle()
                        .fill(accent.opacity(0.55))
                        .frame(width: artSize * 1.15, height: artSize * 1.15)
                        .blur(radius: 60)
                        .offset(y: 22)
                }

                ArtworkImage(
                    artwork: artwork,
                    size: artSize,
                    cornerRadius: isCircular ? artSize / 2 : 22
                )
                .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accent ?? Palette.accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Scrubber

/// Apple-Music-style progress bar: a slim capsule that thickens while you drag
/// it. A plain `Slider` with a visible knob reads as a settings control here;
/// this reads as playback.
///
/// Dragging is reported continuously through `value` but only committed on
/// release via `onCommit`, so the underlying player isn't seeked on every
/// pixel of movement.
struct ScrubBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accent: Color = Palette.accent
    /// Mirrors `Slider`'s own callback: true when a drag starts, false when it
    /// ends. Lets the caller show the dragged position in its own labels.
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onCommit: (Double) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private var span: Double { max(range.upperBound - range.lowerBound, 0.001) }

    var body: some View {
        let shown = isDragging ? dragValue : value
        let fraction = min(max((shown - range.lowerBound) / span, 0), 1)
        let height: CGFloat = isDragging ? 11 : 6

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(accent)
                    .frame(width: max(proxy.size.width * fraction, 0))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragValue = shown
                            onEditingChanged(true)
                        }
                        let ratio = min(max(gesture.location.x / proxy.size.width, 0), 1)
                        dragValue = range.lowerBound + ratio * span
                        value = dragValue
                    }
                    .onEnded { _ in
                        let committed = dragValue
                        isDragging = false
                        value = committed
                        onEditingChanged(false)
                        onCommit(committed)
                    }
            )
        }
        .frame(height: 22)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isDragging)
    }
}
