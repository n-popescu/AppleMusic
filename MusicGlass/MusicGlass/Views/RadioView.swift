import SwiftUI

/// Stations used to be a single row buried at the bottom of the old Discover
/// tab. They're a genuinely separate way of listening (nothing to browse or
/// queue — you just start one), so they get the tab slot the Account screen
/// used to occupy.
struct RadioView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()

    private let tileSize: CGFloat = 158
    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle(title: "Radio", subtitle: "Always on")

                    if store.stations.isEmpty && store.isLoadingDiscover {
                        VStack(spacing: 14) {
                            ProgressView().tint(.white)
                            Text("Tuning in…")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else if store.stations.isEmpty {
                        EmptyStateView(
                            systemImage: "dot.radiowaves.left.and.right",
                            title: store.bridge.isAuthorized ? "No stations yet" : "Not signed in",
                            message: store.bridge.isAuthorized
                                ? "Apple Music didn't return any stations for this storefront."
                                : "Sign in from the Home tab to listen to Apple Music radio."
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.stations) { station in
                                Button {
                                    Task { await store.play(station: station) }
                                } label: {
                                    stationTile(station)
                                }
                                .buttonStyle(.plain)
                                .disabled(store.pendingPlaybackID != nil)
                            }
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
            .refreshable { await store.refreshDiscover() }
            .task { await store.refreshDiscover() }
            .task(id: store.stations.first?.id) {
                await accent.load(from: store.stations.first?.artwork)
            }
        }
    }

    private func stationTile(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                ArtworkImage(artwork: station.artwork, size: tileSize, cornerRadius: 18)

                // Every layer here is pinned to the same square as the
                // artwork — an unframed overlay inside the ZStack would
                // stretch to the grid cell instead and sit proud of the art.
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)

                if station.isLive == true {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background { Capsule().fill(Palette.accent) }
                        .padding(10)
                }

                if store.pendingPlaybackID == station.id {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .frame(width: tileSize, height: tileSize)
                        .overlay { ProgressView().tint(.white) }
                }
            }
            .frame(width: tileSize, height: tileSize)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)

            Text(station.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
                .lineLimit(2)
                .frame(width: tileSize, alignment: .leading)
        }
    }
}
