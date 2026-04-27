import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    var body: some View {
        let signedIn = (keychain.load() != nil) && (viewerStates.first?.viewer != nil) && (viewerStates.first?.activeRepoID != nil)
        Group {
            if signedIn {
                MainView()
                    .task { coordinator.start() }
            } else {
                OnboardingView(keychain: keychain, client: client, onReady: {
                    coordinator.start()
                })
            }
        }
    }
}

/// Placeholder until Task 22 wires the real MainView.
struct MainView: View {
    var body: some View { Text("MainView placeholder") }
}
