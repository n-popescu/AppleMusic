import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: MusicLibraryStore
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.glassBackdrop()
                ScrollView {
                    VStack(spacing: 20) {
                        GlassCard {
                            VStack(spacing: 14) {
                                Image(systemName: store.bridge.isAuthorized ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                                    .font(.system(size: 40))
                                    .foregroundStyle(store.bridge.isAuthorized ? .green : .white.opacity(0.6))

                                Text(store.bridge.isAuthorized ? "Signed in to Apple Music" : "Not signed in")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("Signing in here opens Apple's own music.apple.com sign-in — the account you use is independent of whichever Apple ID this iPhone uses for iCloud.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)

                                Button {
                                    Task {
                                        isWorking = true
                                        if store.bridge.isAuthorized {
                                            await store.signOut()
                                        } else {
                                            await store.signIn()
                                        }
                                        isWorking = false
                                    }
                                } label: {
                                    if isWorking {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(store.bridge.isAuthorized ? "Sign Out" : "Sign In to Apple Music")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background { GlassSurface(cornerRadius: 16, tint: store.bridge.isAuthorized ? nil : .pink) { Color.clear } }
                                .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if let error = store.errorMessage ?? store.bridge.lastError {
                            GlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                            }
                        }

                        Text(versionString)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Account")
        }
    }

    // CFBundleVersion is stamped per-CI-run (see ios-build.yml), so this is
    // the quickest way to confirm a rebuilt fix is actually what's installed
    // — CFBundleShortVersionString alone (1.0.0) never changes between
    // releases and can't distinguish one build from the next.
    private var versionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(shortVersion) (build \(build))"
    }
}
