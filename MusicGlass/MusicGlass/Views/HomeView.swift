import SwiftUI

/// The app's landing screen. Replaces the old Discover tab (and absorbs what
/// used to be the Account tab, now a profile button in the toolbar): a
/// greeting, what you were just listening to, then recommendations and charts.
struct HomeView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if isEverythingEmpty && store.isLoadingDiscover {
                        loadingState
                    } else if isEverythingEmpty {
                        EmptyStateView(
                            systemImage: store.bridge.isAuthorized ? "sparkles" : "person.crop.circle.badge.exclamationmark",
                            title: store.bridge.isAuthorized ? "Nothing to show yet" : "Not signed in",
                            message: store.bridge.isAuthorized
                                ? "Recommendations, charts and radio will appear here once Apple Music has something for this account."
                                : "Sign in to Apple Music to see recommendations built for your account.",
                            actionTitle: store.bridge.isAuthorized ? nil : "Sign In",
                            action: signInAction
                        )
                    } else {
                        if !store.recentlyPlayedHistory.isEmpty {
                            recentlyPlayedSection
                        }
                        if !store.recommendations.isEmpty {
                            recommendationsSection
                        }
                        if !store.charts.songs.isEmpty {
                            topSongsSection
                        }
                        if !store.charts.albums.isEmpty {
                            topAlbumsSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .auroraBackground(accent: accent.color)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear }
            }
            .refreshable {
                await store.refreshDiscover()
                await store.refreshRecentlyPlayedHistory()
            }
            .task {
                await store.refreshDiscover()
                await store.refreshRecentlyPlayedHistory()
            }
            .task(id: store.charts.albums.first?.id) {
                await accent.load(from: store.charts.albums.first?.artwork)
            }
            .sheet(isPresented: $showAccount) {
                AccountSheet()
                    .environmentObject(store)
            }
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            ScreenTitle(title: greeting, subtitle: "Lucent")

            Button {
                showAccount = true
            } label: {
                Image(systemName: store.bridge.isAuthorized ? "person.fill" : "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(GlassButtonStyle(tint: store.bridge.isAuthorized ? nil : Palette.accent))
            .accessibilityLabel("Account")
        }
    }

    /// Explicit rather than a ternary at the call site: type inference can't
    /// pick a type for `cond ? nil : { ... }` from a bare closure literal.
    private var signInAction: (() -> Void)? {
        store.bridge.isAuthorized ? nil : { showAccount = true }
    }

    /// Small touch, but it's what makes a landing screen feel like an app
    /// rather than a list of endpoints.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5: return "Late night"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Tonight"
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white)
            Text("Finding something for you…")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Sections

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recently Played", subtitle: "Pick up where you left off")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.recentlyPlayedHistory) { item in
                        recentlyPlayedTile(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func recentlyPlayedTile(_ item: RecentlyPlayedItem) -> some View {
        if let song = item.song {
            Button {
                Task { await store.play(song: song) }
            } label: {
                MediaTile(
                    title: song.title,
                    subtitle: song.artistName,
                    artwork: song.artwork,
                    isLoading: store.pendingPlaybackID == song.id
                )
            }
            .buttonStyle(.plain)
        } else if let album = item.album {
            NavigationLink(value: album) {
                MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork)
            }
            .buttonStyle(.plain)
        } else if let playlist = item.playlist {
            NavigationLink(value: playlist) {
                MediaTile(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork)
            }
            .buttonStyle(.plain)
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Made for You", subtitle: "From your Apple Music account")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.recommendations) { item in
                        if let album = item.album {
                            NavigationLink(value: album) {
                                MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork, size: 168)
                            }
                            .buttonStyle(.plain)
                        } else if let playlist = item.playlist {
                            NavigationLink(value: playlist) {
                                MediaTile(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork, size: 168)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top Songs", subtitle: "Charting right now")
            ContentSurface(padding: 8) {
                VStack(spacing: 2) {
                    ForEach(Array(store.charts.songs.prefix(10).enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.tertiaryText)
                                .frame(width: 22, alignment: .center)
                            SongRow(
                                song: song,
                                isCurrentlyPlaying: store.bridge.nowPlaying.catalogID == song.id
                            ) {
                                Task { await store.play(song: song) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var topAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top Albums")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.charts.albums) { album in
                        NavigationLink(value: album) {
                            MediaTile(title: album.title, subtitle: album.artistName, artwork: album.artwork)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private var isEverythingEmpty: Bool {
        store.recommendations.isEmpty
            && store.charts.songs.isEmpty
            && store.charts.albums.isEmpty
            && store.recentlyPlayedHistory.isEmpty
    }
}
