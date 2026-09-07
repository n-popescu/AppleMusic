import SwiftUI

// MARK: - Navigation layer (Liquid Glass)
//
// Everything in this file is for the *functional* layer only: the mini player,
// floating controls, toolbar affordances. Apple's Liquid Glass guidance is
// explicit that glass belongs to controls floating above content, never to the
// content itself (lists, tiles, scrollable cards) — glass sampling glass, or
// glass over an entire screen of content, is what makes an interface read as
// muddy rather than layered. Content-layer surfaces live in DesignSystem.swift
// (`ContentSurface`) and are deliberately plain fills.

/// Wraps content in the real Liquid Glass material on iOS 26+, falling back to
/// `.ultraThinMaterial` on older systems so the project still builds/runs
/// against earlier SDKs.
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var tint: Color? = nil
    /// Enables the system's touch-responsive glass (highlight tracking under
    /// the finger). Only meaningful for things that are actually tappable.
    var interactive: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        glass,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            } else {
                content
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups several glass elements so they share one sampling region and blend
/// into each other instead of each sampling independently (which is both
/// heavier and visually inconsistent). No-op before iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Circular glass control — transport buttons, the queue button, and so on.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var size: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .padding(12)
            .background {
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(.clear)
                        .glassEffect(glass, in: Circle())
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            // Without this the only hit-testable part of the button is the
            // glyph itself: the padding is empty space, and the circular
            // backdrop is a `.background` (never hit-tested) whose iOS 26
            // fill is `.clear` (not hit-testable even where it is drawn).
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        let base = Glass.regular.interactive()
        return tint.map { base.tint($0) } ?? base
    }
}

/// Filled pill for the one primary action on a screen (Play, Retry). Solid
/// gradient rather than glass — it's the loudest thing on the screen and
/// should read that way.
struct ProminentActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                Capsule().fill(Palette.accentGradient)
            }
            .shadow(color: Palette.accent.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary pill next to the primary action (Shuffle, Add to Library).
struct SecondaryActionStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? Palette.accent : Palette.primaryText)
            .frame(height: 50)
            .padding(.horizontal, 18)
            .background {
                Capsule()
                    .fill(Palette.contentFillRaised)
                    .overlay { Capsule().strokeBorder(Palette.hairline, lineWidth: 1) }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shared "couldn't load / retry" state for detail screens.
struct DetailErrorState: View {
    let message: String
    var retry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                Task { await retry() }
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background { Capsule().fill(Palette.accentGradient) }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
