import SwiftUI
import UIKit

/// In-memory artwork cache sitting in front of the URL loading system.
///
/// `AsyncImage` restarts its load whenever SwiftUI recreates the view, which a
/// LazyVGrid/LazyVStack does constantly as cells recycle. Even with a warm
/// URLCache that means every scroll flashes the placeholder back in before the
/// decoded image reappears. Holding the decoded `UIImage` here makes a
/// revisited cell paint immediately.
@MainActor
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        // Roughly 64MB of decoded pixels; NSCache evicts under memory
        // pressure regardless, this just stops it growing unboundedly first.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// De-duplicates concurrent loads of the same URL, so a grid showing the
    /// same artwork in several cells fetches it once.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }

        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
        }
        return image
    }
}

struct ArtworkImage: View {
    let artwork: Artwork?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    private var url: URL? {
        artwork?.resolvedURL(size: Int(size * 3))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder picks up the brand gradient rather than a flat
                // grey square, so a wall of not-yet-loaded artwork still
                // looks intentional while it fills in.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent.opacity(0.22), Palette.accentSecondary.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.white.opacity(0.55))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            // Synchronous cache hit: paint in the same frame, no placeholder
            // flash at all on a recycled cell.
            if let hit = ArtworkImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = nil
            let loaded = await ArtworkImageCache.shared.load(url)
            // The cell may have been recycled onto a different item while
            // this was in flight.
            guard url == self.url else { return }
            image = loaded
        }
    }
}

/// What a long-press "Go to…" action opens.
enum RelatedDestination: Identifiable {
    case album(Album)
    case artist(Artist)

    var id: String {
        switch self {
        case .album(let album): return "album-" + album.id
        case .artist(let artist): return "artist-" + artist.id
        }
    }
}

struct SongRow: View {
    @EnvironmentObject var store: MusicLibraryStore
    let song: Song
    var isCurrentlyPlaying: Bool = false
    let onTap: () -> Void

    @State private var showAddToPlaylistSheet = false
    // Long-press navigation is presented as a sheet rather than pushed:
    // SongRow appears inside five different NavigationStacks (Library, Search,
    // Home, playlist and album detail), and a sheet works identically from all
    // of them without plumbing a navigation path through each one.
    @State private var relatedDestination: RelatedDestination?
    @State private var isResolvingRelations = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkImage(artwork: song.artwork)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCurrentlyPlaying ? Palette.accent : Palette.primaryText)
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if store.pendingPlaybackID == song.id {
                    ProgressView().tint(Palette.accent)
                } else if isCurrentlyPlaying {
                    // Three static bars reading as a level meter — enough to
                    // mark the row without animating a whole list.
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(Palette.accentGradient)
                                .frame(width: 3, height: [11.0, 16.0, 8.0][index])
                        }
                    }
                } else {
                    Text(durationLabel)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                // The playing row gets its own soft highlight, so it stays
                // findable when scrolling a long list.
                if isCurrentlyPlaying {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.accent.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { songContextMenu }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await store.playNext(song: song) }
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(Palette.accent)
        }
        .sheet(isPresented: $showAddToPlaylistSheet) {
            AddToPlaylistSheet(song: song)
                .environmentObject(store)
        }
        .sheet(item: $relatedDestination) { destination in
            NavigationStack {
                Group {
                    switch destination {
                    case .album(let album):
                        AlbumDetailView(album: album)
                    case .artist(let artist):
                        ArtistDetailView(artist: artist)
                    }
                }
                // ArtistDetailView deliberately doesn't register this itself
                // (SearchView's stack already does, and registering the same
                // type twice in one stack is ambiguous) — but this sheet is
                // its own stack, so without it the artist's album tiles would
                // be dead links.
                .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { relatedDestination = nil }
                    }
                }
            }
            .environmentObject(store)
        }
    }

    /// Resolves the song's album/artist on demand. Doing it lazily (rather
    /// than prefetching for every visible row) keeps a long list from firing
    /// a request per row just in case someone long-presses it.
    private enum Relation { case album, artist }

    private func openRelation(_ relation: Relation) {
        guard !isResolvingRelations else { return }
        isResolvingRelations = true
        Task {
            defer { isResolvingRelations = false }
            guard let relations = await store.relations(forSong: song) else { return }
            switch relation {
            case .album:
                relatedDestination = relations.album.map(RelatedDestination.album)
            case .artist:
                relatedDestination = relations.artist.map(RelatedDestination.artist)
            }
        }
    }

    @ViewBuilder
    private var songContextMenu: some View {
        Button {
            Task { await store.playNext(song: song) }
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            Task { await store.playLater(song: song) }
        } label: {
            Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
        Divider()
        Button {
            Task { await store.startStation(forSong: song) }
        } label: {
            Label("Start Station", systemImage: "dot.radiowaves.left.and.right")
        }
        Button {
            openRelation(.album)
        } label: {
            Label("Go to Album", systemImage: "square.stack")
        }
        Button {
            openRelation(.artist)
        } label: {
            Label("Go to Artist", systemImage: "music.mic")
        }
        Divider()
        if let kind = song.playParams?.kind {
            Button {
                Task { await store.setRating(id: song.id, kind: kind, value: 1) }
            } label: {
                Label("Love", systemImage: "heart")
            }
            Button {
                Task { await store.setRating(id: song.id, kind: kind, value: -1) }
            } label: {
                Label("Dislike", systemImage: "hand.thumbsdown")
            }
            if song.playParams?.isLibrary != true {
                Button {
                    Task { await store.addToLibrary(id: song.id, kind: kind) }
                } label: {
                    Label("Add to Library", systemImage: "plus.circle")
                }
            }
        }
        Button {
            showAddToPlaylistSheet = true
        } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }
    }

    private var durationLabel: String {
        let total = Int(song.durationSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Minimal "Add to Playlist" flow reachable from any `SongRow`: pick an
/// existing library playlist, or create a new one on the spot.
struct AddToPlaylistSheet: View {
    let song: Song
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var newPlaylistName = ""
    @State private var isCreating = false
    @State private var isAdding = false
    @State private var confirmationMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    Section {
                        HStack {
                            TextField("New Playlist Name", text: $newPlaylistName)
                                .textFieldStyle(.plain)
                            Button {
                                Task { await createAndAdd() }
                            } label: {
                                if isCreating {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Create")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        }
                        .listRowBackground(Palette.contentFill)
                    } header: {
                        Text("New Playlist")
                            .foregroundStyle(Palette.secondaryText)
                    }

                    Section {
                        if store.playlists.isEmpty {
                            Text("No playlists yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.tertiaryText)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(store.playlists) { playlist in
                                Button {
                                    Task { await addToExisting(playlist) }
                                } label: {
                                    HStack {
                                        Text(playlist.name)
                                            .foregroundStyle(Palette.primaryText)
                                        Spacer()
                                        if isAdding {
                                            ProgressView().tint(.white)
                                        }
                                    }
                                }
                                .disabled(isAdding)
                                .listRowBackground(Palette.contentFill)
                            }
                        }
                    } header: {
                        Text("Add to Existing Playlist")
                            .foregroundStyle(Palette.secondaryText)
                    }

                    if let confirmationMessage {
                        Section {
                            Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .auroraBackground()
            .navigationTitle("Add \u{201c}\(song.title)\u{201d}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
    }

    private func createAndAdd() async {
        isCreating = true
        defer { isCreating = false }
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = await store.createPlaylist(name: name, trackIds: [song.id], isLibraryTracks: song.playParams?.isLibrary ?? true)
        newPlaylistName = ""
        confirmationMessage = "Created \u{201c}\(name)\u{201d} and added the track."
    }

    private func addToExisting(_ playlist: Playlist) async {
        isAdding = true
        defer { isAdding = false }
        await store.addTrack(song, toPlaylist: playlist)
        confirmationMessage = "Added to \u{201c}\(playlist.name)\u{201d}."
    }
}
