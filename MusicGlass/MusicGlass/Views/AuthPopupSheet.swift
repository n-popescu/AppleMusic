import SwiftUI
import WebKit

/// Shown only while signing in. Wraps the popup WKWebView that MusicKit JS
/// opens for the real Apple ID login — this is genuine Apple sign-in UI,
/// not something we can (or should) restyle, but we frame it natively.
struct AuthPopupSheet: View {
    let webView: WKWebView
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            WebViewHost(webView: webView)
                .navigationTitle("Sign in to Apple Music")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDone)
                    }
                }
        }
    }
}
