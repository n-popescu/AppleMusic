import SwiftUI

/// Stations used to be a single row buried at the bottom of the old Discover
/// tab. They're a genuinely separate way of listening (nothing to browse or
/// queue — you just start one), so they get the tab slot the Account screen
/// used to occupy.
struct RadioView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @StateObject private var accent = ArtworkAccent()

    private var liveStations: [Station] { store.stations.filter { $0.isLive == true } }
    private var otherStations: [Station] { store.stations.filter { $0.isLive != true } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScreenTitle(title: "Radio", subtitle: "Always on")

                    if store.stations.isEmpty {
                        emptyOrLoading
                    } else {
                        if !liveStations.isEmpty {
                            section(title: "Live Radio", subtitle: "Hosted, right now") {
                                VStack(spacing: 14) {
                                    ForEach(liveStations) { station in
                                        stationButton(station) { LiveStationCard(station: station, isLoading: store.pendingPlaybackID == station.id) }
                                    }
                                }
                            }
                        }
                        if !otherStations.isEmpty {
                            section(title: "For You", subtitle: "Built from what you listen to") {
                                VStack(spacing: 14) {
                                    ForEach(otherStations) { station in
                                        stationButton(station) { LiveStationCard(station: station, isLoading: store.pendingPlaybackID == station.id) }
                                    }
                                }
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

    @ViewBuilder
    private var emptyOrLoading: some View {
        if store.isLoadingDiscover {
            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Tuning in…")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        } else if let error = store.stationsError {
            // Previously this failure mode was indistinguishable from "no
            // stations exist", which is exactly how a permanently broken
            // endpoint went unnoticed.
            EmptyStateView(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: "Couldn't load stations",
                message: error,
                actionTitle: "Retry",
                action: { Task { await store.refreshDiscover() } }
            )
        } else {
            EmptyStateView(
                systemImage: "dot.radiowaves.left.and.right",
                title: store.bridge.isAuthorized ? "No stations here" : "Not signed in",
                message: store.bridge.isAuthorized
                    ? "Apple Music didn't return any stations for this storefront."
                    : "Sign in from the Home tab to listen to Apple Music radio."
            )
        }
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle)
            content()
        }
    }

    private func stationButton<Label: View>(_ station: Station, @ViewBuilder label: () -> Label) -> some View {
        Button {
            Task { await store.play(station: station) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(store.pendingPlaybackID != nil)
    }
}

/// Wide card. Apple's live-station artwork is a 4:1 banner (4320x1080 in their
/// own docs sample) with the station's name baked into the image, so cropping
/// it into a square tile literally cuts the branding in half — this renders it
/// at its real aspect ratio instead.
private struct LiveStationCard: View {
    let station: Station
    var isLoading: Bool

    /// Slightly tighter than Apple's native 4:1 so the card doesn't read as a
    /// letterbox slot on a phone.
    private let bannerAspect: CGFloat = 3.4

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The clear-rectangle-plus-overlay idiom rather than a
            // GeometryReader: GeometryReader is greedy about the space it
            // takes, which fights an aspect-ratio constraint applied to it.
            Rectangle()
                .fill(.clear)
                .aspectRatio(bannerAspect, contentMode: .fit)
                .overlay {
                    AsyncImage(url: station.artwork?.resolvedURL(width: 1200, height: Int(1200 / bannerAspect))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            LinearGradient(
                                colors: [Palette.accent.opacity(0.35), Palette.accentSecondary.opacity(0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                }
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if station.isLive == true {
                        Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background { Capsule().fill(Palette.accent) }
                    }
                    Text(station.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let tagline = station.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                    if isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.black)
                            .offset(x: 1)
                    }
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 9)
    }
}
