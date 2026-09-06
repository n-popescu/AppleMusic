import SwiftUI
import AVKit

/// Native AirPlay output-route picker, wrapped for SwiftUI.
///
/// Audio played inside the hidden `WKWebView` goes through the shared
/// `AVAudioSession` (configured for `.playback` in `MusicGlassApp`), so iOS
/// already offers AirPlay routing automatically via Control Center — this
/// button just surfaces that same system picker inline in the Now Playing UI,
/// matching the rest of the transport controls, rather than requiring the
/// user to leave the app.
struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tintColor
        view.activeTintColor = tintColor
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = tintColor
    }
}
