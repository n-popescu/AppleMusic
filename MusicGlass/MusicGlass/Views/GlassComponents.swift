import SwiftUI

/// Wraps content in the real Liquid Glass material on iOS 26+, falling back to
/// `.ultraThinMaterial` on older systems so the project still builds/runs against
/// earlier SDKs during development.
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        tint.map { Glass.regular.tint($0) } ?? .regular,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            } else {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }
}

/// A glass card used for rows, tiles and grouped content throughout the app.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        GlassSurface(cornerRadius: cornerRadius) {
            content.padding(padding)
        }
    }
}

/// Button style that renders as a Liquid Glass pill, e.g. for the mini player controls.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .padding(12)
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear)
                            .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: Circle())
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
            )
            // Without this the only hit-testable part of the button is the
            // glyph itself: the padding is empty space, and the circular
            // backdrop is a `.background` (never hit-tested) whose iOS 26
            // fill is `.clear` (not hit-testable even where it is drawn).
            // That made these buttons feel dead — taps in the ring around
            // the icon fell straight through to whatever was behind them.
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shared "couldn't load / retry" state for detail screens (playlist, album
/// track lists) that fetch their contents asynchronously.
struct DetailErrorState: View {
    let message: String
    var retry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                Task { await retry() }
            } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background { GlassSurface(cornerRadius: 12, tint: .pink) { Color.clear } }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

extension View {
    /// Consistent glass-friendly background gradient behind scrollable content.
    func glassBackdrop() -> some View {
        self.background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.05, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
