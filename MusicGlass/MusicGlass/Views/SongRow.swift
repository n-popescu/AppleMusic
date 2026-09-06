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
    @EnvironmentObject var store: MusicLibraryStore
    let song: Song
    var isCurrentlyPlaying: Bool = false
    let onTap: () -> Void

    @State private var showAddToPlaylistSheet = false

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
        .contextMenu { songContextMenu }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Task { await store.playNext(song: song) }
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.pink)
        }
        .sheet(isPresented: $showAddToPlaylistSheet) {
            AddToPlaylistSheet(song: song)
                .environmentObject(store)
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
                Color.clear.glassBackdrop()
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
                        .listRowBackground(Color.white.opacity(0.05))
                    } header: {
                        Text("New Playlist")
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Section {
                        if store.playlists.isEmpty {
                            Text("No playlists yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(store.playlists) { playlist in
                                Button {
                                    Task { await addToExisting(playlist) }
                                } label: {
                                    HStack {
                                        Text(playlist.name)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        if isAdding {
                                            ProgressView().tint(.white)
                                        }
                                    }
                                }
                                .disabled(isAdding)
                                .listRowBackground(Color.white.opacity(0.05))
                            }
                        }
                    } header: {
                        Text("Add to Existing Playlist")
                            .foregroundStyle(.white.opacity(0.6))
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
            .navigationTitle("Add \u{201c}\(song.title)\u{201d}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
