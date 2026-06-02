import Foundation
import SwiftData
@testable import PRTracker

enum TestContainer {
    /// Returns an in-memory ModelContainer with all app schemas registered.
    static func make() throws -> ModelContainer {
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
            ReviewComment.self, NotificationLog.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
