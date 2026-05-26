import Testing
import Foundation
@testable import PRTracker

@Suite struct AppStatePersistenceTests {
    /// Returns a fresh, named UserDefaults suite that's wiped on construction
    /// so each test starts from a known-empty baseline.
    private func freshDefaults(_ suite: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaults_whenStoreEmpty_useAwaitingMeAndNoSelection() {
        let d = freshDefaults()
        let state = AppState(defaults: d)
        #expect(state.activeFilter == .awaitingMe)
        #expect(state.selectedPRID == nil)
    }

    @Test func setActiveFilter_writesRawValueToStore() {
        let d = freshDefaults()
        let state = AppState(defaults: d)
        state.activeFilter = .mine
        #expect(d.string(forKey: "AppState.activeFilter") == "mine")
    }

    @Test func setSelectedPRID_writesToStore() {
        let d = freshDefaults()
        let state = AppState(defaults: d)
        state.selectedPRID = "PR_42"
        #expect(d.string(forKey: "AppState.selectedPRID") == "PR_42")
    }

    @Test func setSelectedPRIDToNil_clearsStore() {
        let d = freshDefaults()
        d.set("PR_42", forKey: "AppState.selectedPRID")
        let state = AppState(defaults: d)
        #expect(state.selectedPRID == "PR_42")
        state.selectedPRID = nil
        #expect(d.object(forKey: "AppState.selectedPRID") == nil)
    }

    @Test func init_restoresPreviouslySavedFilterAndSelection() {
        let d = freshDefaults()
        d.set("done", forKey: "AppState.activeFilter")
        d.set("PR_99", forKey: "AppState.selectedPRID")
        let state = AppState(defaults: d)
        #expect(state.activeFilter == .done)
        #expect(state.selectedPRID == "PR_99")
    }

    @Test func init_unknownFilterRawValue_fallsBackToAwaitingMe() {
        let d = freshDefaults()
        d.set("nonsense", forKey: "AppState.activeFilter")
        let state = AppState(defaults: d)
        #expect(state.activeFilter == .awaitingMe)
    }

    @Test func roundTrip_secondInitSeesFirstInitsWrites() {
        let suite = UUID().uuidString
        let d = freshDefaults(suite)
        do {
            let first = AppState(defaults: d)
            first.activeFilter = .mentions
            first.selectedPRID = "PR_round"
        }
        let second = AppState(defaults: d)
        #expect(second.activeFilter == .mentions)
        #expect(second.selectedPRID == "PR_round")
    }
}
