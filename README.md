# MusicGlass

A native SwiftUI iPhone app with a real Liquid Glass UI, playing Apple Music
through **MusicKit JS running inside a hidden `WKWebView`** instead of the
native MusicKit framework.

Why: native `MusicKit` (Swift) always uses whichever Apple ID is already
signed into the device's **Media & Purchases** account. MusicKit JS opens
Apple's own `music.apple.com` sign-in and generates a *Music User Token* tied
to whichever Apple ID logs in there — completely independent of the device's
system account. This app uses that path on purpose, so you can sign in with
an Apple Music account that isn't the one your iPhone is otherwise using.

The WebView is **never visible** during normal use — all UI (library,
playlists, search, queue, now playing) is 100% native SwiftUI with the real
Liquid Glass APIs. The only time you see a web view at all is the brief
native-style sheet during sign-in, because Apple's login page itself has to
run somewhere.

---

## Project structure

```
AppleMusic/                              repo root
├── .github/workflows/ios-build.yml      CI: unsigned IPA build
├── README.md                            this file
└── MusicGlass/
    ├── MusicGlass.xcodeproj/            hand-authored Xcode project (see caveat below)
    └── MusicGlass/
        ├── App/
        │   └── MusicGlassApp.swift          entry point; configures AVAudioSession
        ├── Models/
        │   └── MusicModels.swift            Song, Album, Artist, Playlist, NowPlayingInfo, Queue…
        ├── Services/
        │   ├── MusicKitBridge.swift              hidden WKWebView + JS bridge (auth, playback, fetches, queue)
        │   ├── MusicLibraryStore.swift            app-wide ObservableObject views read from
        │   └── NowPlayingRemoteController.swift   mirrors playback into Lock Screen / Control Center
        ├── Views/
        │   ├── GlassComponents.swift        GlassSurface / GlassCard / GlassButtonStyle / shared states
        │   ├── SongRow.swift                shared row + artwork image
        │   ├── LibraryView.swift            Playlists / Albums / Artists / Songs
        │   ├── PlaylistDetailView.swift
        │   ├── AlbumDetailView.swift
        │   ├── SearchView.swift             catalog search across all 4 types
        │   ├── QueueView.swift              Up Next (reorderable) + Recently Played
        │   ├── NowPlayingBar.swift          docked mini player
        │   ├── NowPlayingFullView.swift     full-screen player sheet
        │   ├── AuthPopupSheet.swift         hosts the sign-in popup only
        │   ├── SettingsView.swift           sign in / out
        │   └── RootView.swift               TabView + hidden bridge + sheets
        └── Resources/
            ├── musickit-bridge.html         loads MusicKit JS, exposes window.MusicGlassBridge
            └── Info.plist
```

**Data flow:** SwiftUI views call methods on `MusicLibraryStore`, which calls
`async` methods on `MusicKitBridge`, which runs the corresponding JS in the
hidden web view via `WKWebView.callAsyncJavaScript`, decoding the JSON result
back into Swift models. Playback *events* (track changed, play/pause,
scrubber time) flow the other way: MusicKit JS posts them to
`webkit.messageHandlers.musicKitEvent`, which `MusicKitBridge` publishes as
`@Published` properties SwiftUI observes directly, and which
`NowPlayingRemoteController` also mirrors into the system's Now Playing UI.

**Liquid Glass:** `GlassComponents.swift` wraps the iOS 26 `.glassEffect()` /
`Glass.regular.tint(_:)` APIs behind `#available(iOS 26.0, *)`, with an
`.ultraThinMaterial` fallback so the project still compiles and looks
reasonable on the iOS 17+ deployment target this project uses.

---

## 1. Generate a MusicKit developer token

You need a paid Apple Developer Program membership for this step (Apple's
requirement for any app calling the Apple Music API, native or web).

1. Go to **developer.apple.com → Certificates, Identifiers & Profiles → Keys**.
2. Create a new key, enable **MusicKit**, and download the resulting `.p8`
   private key (you can only download it once — keep it safe).
3. Note your **Key ID** (shown on the key's page) and your **Team ID** (top
   right of the developer portal, under your name).
4. Sign a JWT (ES256) with those values. Example using Node:

   ```js
   // generate-token.js
   const jwt = require('jsonwebtoken');
   const fs = require('fs');

   const privateKey = fs.readFileSync('AuthKey_XXXXXXXXXX.p8');
   const teamId = 'YOUR_TEAM_ID';
   const keyId = 'YOUR_KEY_ID';

   const token = jwt.sign({}, privateKey, {
     algorithm: 'ES256',
     expiresIn: '180d',
     issuer: teamId,
     header: { alg: 'ES256', kid: keyId }
   });

   console.log(token);
   ```

   ```
   npm install jsonwebtoken
   node generate-token.js
   ```

5. Copy the printed token into `MusicGlass/MusicGlass/Resources/Info.plist`,
   replacing `PASTE_YOUR_DEVELOPER_TOKEN_HERE` for the `MusicKitDeveloperToken`
   key.

   **Tokens expire (max 6 months).** This project drops a static token
   straight into `Info.plist` for simplicity — fine for local development,
   but a real shipped app should fetch a fresh token from a small backend at
   launch instead of hardcoding one that will eventually expire in the wild.

**Never commit a real token to a public repo.**

---

## 2. Open / build in Xcode

A `MusicGlass.xcodeproj` is checked in under `MusicGlass/`, hand-authored
(there's no Mac/Xcode available in the environment this was built in, so it
was written directly rather than exported from Xcode). It:

- Targets **iOS 17.0+** (chosen so `#available(iOS 26.0, *)` in
  `GlassComponents.swift` has a meaningful fallback path to fall back *from*).
- Uses bundle identifier **`com.musicglass.app`**.
- Includes every file under `App/`, `Models/`, `Services/`, `Views/` in the
  target's Sources build phase, and `Resources/musickit-bridge.html` in the
  Resources (Copy Bundle Resources) build phase.
- Points `INFOPLIST_FILE` at `MusicGlass/Resources/Info.plist`, which already
  declares `NSAppleMusicUsageDescription` and `UIBackgroundModes = [audio]`
  (Background Modes → Audio, the capability this app needs to keep the
  hidden WebView's audio engine alive in the background).
- Ships a shared scheme (`MusicGlass.xcscheme`) so `xcodebuild -scheme
  MusicGlass` works out of the box, including in CI, without first opening
  the project in Xcode's UI.

**If Xcode complains when first opening it** (hand-authored project files are
inherently more fragile than Xcode-generated ones — e.g. an internal Xcode
version bump changing what it expects), the fix is almost always trivial:
- "Signing & Capabilities" → select your own **Team** (the project ships with
  `CODE_SIGN_STYLE = Automatic` and no team, since none should be committed).
- If a file shows as missing/red in the navigator, re-add it via
  **File → Add Files to "MusicGlass"…** and make sure the **MusicGlass**
  target checkbox is checked.
- If `musickit-bridge.html` doesn't end up in the built app bundle, check its
  **Target Membership** in the File Inspector — Xcode occasionally unchecks
  non-code resources.

Once open:
1. Select your **Team** under Signing & Capabilities so it can run on a
   physical device (see step 1 for the developer token, which is separate
   from your Xcode signing team).
2. Build and run on a **real device** — MusicKit JS's DRM playback needs a
   reliable network + audio session, which the simulator doesn't validate as
   meaningfully.

On first launch:
- Go to the **Account** tab → **Sign In to Apple Music**.
- A native-style sheet appears hosting Apple's real sign-in page — log in
  with whichever Apple ID has the subscription you want.
- The sheet closes itself automatically once sign-in completes.
- Your Library tab populates with that account's playlists, albums, artists
  and songs.

---

## 3. Lock Screen / Control Center

`Services/NowPlayingRemoteController.swift` mirrors playback state from the
hidden JS engine into `MPNowPlayingInfoCenter` (title, artist, album,
artwork, elapsed time, duration, playback rate) and wires
`MPRemoteCommandCenter` play/pause/next/previous/seek commands back into
`MusicKitBridge`. It's created once in `RootView` and lives for the app's
lifetime. Since playback doesn't run through a native `AVPlayer`, none of
this is automatic — it exists specifically to make that visible.

## 4. Queue ("Up Next")

`Views/QueueView.swift` shows the live MusicKit JS playback queue ("Up
Next", reorderable, tap to jump to any item) plus a session-only "Recently
Played" list built by observing now-playing changes. It's reachable from a
button in the mini player (`NowPlayingBar`) and from the full-screen player
(`NowPlayingFullView`). Reordering the live queue is best-effort: MusicKit JS
doesn't publish a first-class "move item" API, so `moveQueueItem` in
`musickit-bridge.html` rebuilds the queue client-side — this is flagged in
its source comments as worth re-verifying against a real device/MusicKit JS
release.

---

## CI: unsigned IPA build

`.github/workflows/ios-build.yml` runs on `macos-latest` (push to `main` and
this branch, PRs into `main`, and manual `workflow_dispatch`), builds
`MusicGlass.xcodeproj` with `xcodebuild … -sdk iphoneos CODE_SIGNING_ALLOWED=NO
clean archive`, then hand-packages the resulting `.xcarchive`'s `.app` into a
`Payload/MusicGlass.app` → `.ipa` zip, and uploads it as a build artifact.

**This produces an unsigned `.ipa`** — there is no signing certificate or
provisioning profile involved anywhere in this workflow, and none should be
added as repo secrets for it. To actually install it on a device you need to
resign it locally with your own certificate + provisioning profile (or run it
through a sideloading tool that does that for you). A real
App Store/TestFlight distribution pipeline is a different, signed workflow
with its own certificate/profile secrets — intentionally out of scope here.

---

## AirPlay

`Views/AirPlayButton.swift` wraps `AVRoutePickerView` (AVKit) so the Now
Playing screen has an inline AirPlay route picker next to the "Up Next"
button. No custom streaming/casting protocol is implemented — audio played
inside the hidden `WKWebView` already goes through the shared
`AVAudioSession` (configured for `.playback` in `MusicGlassApp`), so iOS
already exposes AirPlay output routing automatically via Control Center; this
button just surfaces that same system picker without the user needing to
leave the app.

---

## Explicitly out of scope

Carried over from the original project spec — not implemented, and not
planned as part of this pass:

- **CarPlay** — would need its own native now-playing/media-remote bridge on
  top of the one this app already has for Lock Screen/Control Center.
- **Offline/downloaded playback** — MusicKit JS streams; it doesn't expose
  downloads the way native MusicKit's `MusicLibrary` does.
- **Lyrics**.
- **Social features** (sharing, friend activity, etc).
- **Discord Rich Presence / Last.fm scrobbling** — considered (inspired by
  the discontinued Cider desktop client) and deliberately skipped: Discord's
  Rich Presence protocol is IPC-based and only available to desktop clients,
  not third-party iOS apps, and Last.fm scrobbling was explicitly declined.
- **Dynamic backend-issued developer tokens** — the developer token is a
  static value pasted into `Info.plist` (see step 1). A shipped app should
  fetch a fresh one from a small backend instead, since tokens expire.
