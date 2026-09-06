import SwiftUI

/// "Listen Now" style recommendations + top charts + radio stations. Storefront
/// for the catalog calls is resolved the same way `SearchView`/the bridge's
/// `search()` does: MusicKit JS's own `music.storefrontId` inside the bridge,
/// which is already signed in with the account's own region — there's nothing
/// extra to plumb through here.
struct DiscoverView: View {
    @EnvironmentObject var store: MusicLibraryStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if store.isLoadingDiscover && isEverythingEmpty {
                            ProgressView("Finding something new…")
                                .tint(.white)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else if isEverythingEmpty {
                            emptyState
                        } else {
                            if !store.recommendations.isEmpty {
                                section(title: "Listen Now") {
                                    horizontalScroller {
                                        ForEach(store.recommendations) { item in
                                            recommendationTile(item)
                                        }
                                    }
                                }
                            }

                            if !store.charts.songs.isEmpty {
                                section(title: "Top Songs") {
                                    horizontalScroller {
                                        ForEach(store.charts.songs) { song in
                                            Button {
                                                Task { await store.play(song: song) }
                                            } label: {
                                                TileCard(title: song.title, subtitle: song.artistName, artwork: song.artwork, isLoading: store.pendingPlaybackID == song.id)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(store.pendingPlaybackID != nil)
                                        }
                                    }
                                }
                            }

                            if !store.charts.albums.isEmpty {
                                section(title: "Top Albums") {
                                    horizontalScroller {
                                        ForEach(store.charts.albums) { album in
                                            Button {
                                                Task { await store.play(album: album) }
                                            } label: {
                                                TileCard(title: album.title, subtitle: album.artistName, artwork: album.artwork, isLoading: store.pendingPlaybackID == album.id)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(store.pendingPlaybackID != nil)
                                        }
                                    }
                                }
                            }

                            if !store.stations.isEmpty {
                                section(title: "Radio") {
                                    horizontalScroller {
                                        ForEach(store.stations) { station in
                                            Button {
                                                Task { await store.play(station: station) }
                                            } label: {
                                                TileCard(title: station.name, subtitle: station.isLive == true ? "Live" : nil, artwork: station.artwork, isLoading: store.pendingPlaybackID == station.id)
                                                    .frame(width: 140)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(store.pendingPlaybackID != nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Discover")
            .refreshable { await store.refreshDiscover() }
            .task {
                if isEverythingEmpty { await store.refreshDiscover() }
            }
        }
    }

    private var isEverythingEmpty: Bool {
        store.recommendations.isEmpty && store.charts.songs.isEmpty && store.charts.albums.isEmpty && store.stations.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.4))
            Text(store.bridge.isAuthorized ? "Nothing to discover yet" : "Sign in to see recommendations")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Charts, radio stations and personalized recommendations will show up here.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func recommendationTile(_ item: RecommendationItem) -> some View {
        if let album = item.album {
            Button {
                Task { await store.play(album: album) }
            } label: {
                TileCard(title: album.title, subtitle: album.artistName, artwork: album.artwork, isLoading: store.pendingPlaybackID == album.id)
                    .frame(width: 140)
            }
            .buttonStyle(.plain)
            .disabled(store.pendingPlaybackID != nil)
        } else if let playlist = item.playlist {
            Button {
                Task { await store.play(playlist: playlist) }
            } label: {
                TileCard(title: playlist.name, subtitle: playlist.curatorName, artwork: playlist.artwork, isLoading: store.pendingPlaybackID == playlist.id)
                    .frame(width: 140)
            }
            .buttonStyle(.plain)
            .disabled(store.pendingPlaybackID != nil)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            content()
        }
    }

    private func horizontalScroller<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                content()
            }
        }
    }
}
