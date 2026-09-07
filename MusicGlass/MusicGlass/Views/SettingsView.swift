import SwiftUI

/// Was a whole tab; now a sheet reached from the profile button on Home.
/// Signing in/out and an error readout never justified a permanent slot in the
/// tab bar — Radio, which is actual content, does.
struct AccountSheet: View {
    @EnvironmentObject var store: MusicLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    statusCard

                    if let error = store.errorMessage ?? store.bridge.lastError {
                        ContentSurface(tint: .orange) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.primaryText.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Text(versionString)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .auroraBackground()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
    }

    private var statusCard: some View {
        ContentSurface(padding: 22, tint: store.bridge.isAuthorized ? .green : Palette.accent) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(store.bridge.isAuthorized ? Color.green.opacity(0.18) : Palette.accent.opacity(0.18))
                        .frame(width: 72, height: 72)
                    Image(systemName: store.bridge.isAuthorized ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 32))
                        .foregroundStyle(store.bridge.isAuthorized ? .green : Palette.accent)
                }

                Text(store.bridge.isAuthorized ? "Signed in to Apple Music" : "Not signed in")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)

                Text("Signing in here opens Apple's own music.apple.com sign-in — the account you use is independent of whichever Apple ID this iPhone uses for iCloud.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryText)
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
                    }
                }
                .buttonStyle(store.bridge.isAuthorized ? AnyButtonStyle(SecondaryActionStyle()) : AnyButtonStyle(ProminentActionStyle()))
                .disabled(isWorking)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // CFBundleVersion is stamped per-CI-run (see ios-build.yml), so this is
    // the quickest way to confirm a rebuilt fix is actually what's installed.
    private var versionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(shortVersion) (build \(build))"
    }
}

/// Lets one `.buttonStyle(...)` call site pick between two concrete styles,
/// which SwiftUI otherwise refuses because they're different types.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
