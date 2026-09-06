import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Live Activity / Dynamic Island attributes
//
// This struct is written now so it's ready to share between the main app
// target and a future Widget Extension target (which is what would actually
// render the Live Activity / Dynamic Island UI and Home Screen widget). See
// the README's "Live Activity / Widget — manual Xcode step required" section
// for exactly why that extension isn't part of this pass and how to add it.
//
// Once that extension exists, this same file should be given membership in
// *both* targets (File Inspector -> Target Membership, check both boxes) so
// `Activity<MusicGlassActivityAttributes>` type-checks on both sides.

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct MusicGlassActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artistName: String
        var albumName: String
        var artworkURL: String?
        var isPlaying: Bool
        var currentTimeSeconds: Double
        var durationSeconds: Double
    }

    // No fixed (non-updating) attributes needed beyond the content state —
    // every field here can change over the life of the activity.
}
#endif
