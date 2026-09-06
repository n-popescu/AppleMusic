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
        // hierarchy to keep running. This used to be collapsed to a literal
        // 0x0 frame at opacity 0 — WebKit (like a backgrounded Safari tab)
        // throttles JS execution in a webview it judges isn't actually
        // visible, and a zero-size/zero-opacity view is exactly that signal.
        // That throttling was invisible for most of this project's life only
        // because of the call<T>/callVoid bug (see MusicKitBridge.swift)
        // that made every bridge call return before its JS actually finished
        // anyway — now that calls genuinely await real completion, the
        // throttling shows up as calls taking seconds or silently never
        // resolving. A real (if imperceptible) 1x1 point footprint at a
        // near-zero-but-nonzero opacity is the standard workaround: enough
        // for WebKit to keep treating it as an active, unthrottled page.
        .background(
            WebViewHost(webView: store.bridge.webView)
                .frame(width: 1, height: 1)
                .opacity(0.011)
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
