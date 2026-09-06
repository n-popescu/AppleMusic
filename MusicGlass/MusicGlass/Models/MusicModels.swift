import Foundation

// MARK: - Artwork

struct Artwork: Codable, Hashable {
    let width: Int?
    let height: Int?
    let url: String // template with {w} and {h} placeholders

    /// Resolves the Apple Music artwork URL template to a concrete size.
    func resolvedURL(size: Int) -> URL? {
        let resolved = url
            .replacingOccurrences(of: "{w}", with: "\(size)")
            .replacingOccurrences(of: "{h}", with: "\(size)")
        return URL(string: resolved)
    }
}

// MARK: - Song

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let durationMillis: Int?
    let artwork: Artwork?
    let releaseDate: String?
    /// The catalog or library playback identifier MusicKit JS expects for `setQueue`.
    let playParams: PlayParams?

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case artistName
        case albumName
        case durationMillis = "durationInMillis"
        case artwork
        case releaseDate
        case playParams
    }

    var durationSeconds: Double {
        Double(durationMillis ?? 0) / 1000.0
    }
}

struct PlayParams: Codable, Hashable {
    let id: String
    let kind: String
    let isLibrary: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case isLibrary
    }
}

// MARK: - Album

struct Album: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let artwork: Artwork?
    let trackCount: Int?
    let releaseDate: String?
    let playParams: PlayParams?

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case artistName
        case artwork
        case trackCount
        case releaseDate
        case playParams
    }
}

// MARK: - Artist

struct Artist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artwork: Artwork?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case artwork
    }
}

// MARK: - Playlist

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let curatorName: String?
    let artwork: Artwork?
    let trackCount: Int?
    let playParams: PlayParams?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case curatorName
        case artwork
        case trackCount
        case playParams
        case description
    }
}

// MARK: - Playback state mirrored from MusicKit JS

/// Mirrors `MusicKit.PlaybackStates` from MusicKit JS. These raw values must
/// match Apple's documented enum exactly since they arrive as the raw `state`
/// int off `playbackStateDidChange` events — they are NOT sequential from our
/// own numbering, they're Apple's numbering (none=0 ... completed=9).
enum PlaybackStatus: Int, Codable {
    case none = 0
    case loading = 1
    case playing = 2
    case paused = 3
    case stopped = 4
    case ended = 5
    case seeking = 6
    case waiting = 7
    case stalled = 8
    case completed = 9

    var isPlaying: Bool { self == .playing }
}

struct NowPlayingInfo: Codable, Equatable {
    var title: String
    var artistName: String
    var albumName: String
    var artworkURL: String?
    var durationSeconds: Double
    var currentTimeSeconds: Double
    var catalogID: String?

    static let empty = NowPlayingInfo(
        title: "",
        artistName: "",
        albumName: "",
        artworkURL: nil,
        durationSeconds: 0,
        currentTimeSeconds: 0,
        catalogID: nil
    )
}

// MARK: - Queue (Up Next)

/// One entry in MusicKit JS's live playback queue, as mirrored from `music.queue.items`.
struct QueueItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let artwork: Artwork?
    let durationMillis: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title = "name"
        case artistName
        case albumName
        case artwork
        case durationMillis = "durationInMillis"
    }

    var durationSeconds: Double {
        Double(durationMillis ?? 0) / 1000.0
    }
}

/// A snapshot of the whole playback queue plus which index is currently playing.
struct QueueSnapshot: Codable, Equatable {
    var position: Int
    var items: [QueueItem]

    static let empty = QueueSnapshot(position: -1, items: [])
}

// MARK: - Generic Apple Music API envelope

struct MusicAPIResponse<T: Codable>: Codable {
    struct Datum: Codable {
        let id: String
        let attributes: T
    }
    let data: [Datum]
}
