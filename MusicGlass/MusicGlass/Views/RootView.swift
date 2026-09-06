import SwiftUI

struct RootView: View {
    @StateObject private var store = MusicLibraryStore()
    @State private var showFullPlayer = false
    // Held for the lifetime of RootView so its Combine subscriptions (which
    // mirror playback into the Lock Screen / Control Center) stay alive;
    // created lazily since it needs `store`, which isn't available until init.
    @State private var remoteController: NowPlayingRemoteController?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                DiscoverView()
                    .tabItem { Label("Discover", systemImage: "sparkles") }

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }

                SettingsView()
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
            .tint(.pink)

            NowPlayingBar(showFullPlayer: $showFullPlayer)
                .padding(.bottom, 50) // sits just above the tab bar
        }
        .environmentObject(store)
        // The hidden MusicKit JS engine. It must stay mounted somewhere in the
        // hierarchy to keep running, but is visually collapsed to nothing.
        .background(
            WebViewHost(webView: store.bridge.webView)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
        )
        .sheet(isPresented: $showFullPlayer) {
            NowPlayingFullView()
                .environmentObject(store)
        }
        .sheet(item: Binding(
            get: { store.bridge.authPresentationWebView.map { WebViewBox($0) } },
            set: { newValue in
                if newValue == nil { store.bridge.dismissAuthPopup() }
            }
        )) { box in
            AuthPopupSheet(webView: box.webView) {
                store.bridge.dismissAuthPopup()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if remoteController == nil {
                remoteController = NowPlayingRemoteController(store: store)
            }
        }
    }
}

/// UIViewRepresentable wrapper so the (headless) WKWebView instance can be attached
/// to the SwiftUI hierarchy without ever being visible.
import WebKit
import UIKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// `WKWebView` isn't `Identifiable`; this lets us drive `.sheet(item:)` with it.
struct WebViewBox: Identifiable {
    let webView: WKWebView
    var id: ObjectIdentifier { ObjectIdentifier(webView) }
    init(_ webView: WKWebView) { self.webView = webView }
}
