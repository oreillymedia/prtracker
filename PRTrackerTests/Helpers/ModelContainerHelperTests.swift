import Testing
import SwiftData
@testable import PRTracker

@Suite struct ModelContainerHelperTests {
    @Test func canCreateInMemoryContainer() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        context.insert(repo)
        try context.save()
        #expect(repo.id == "oreilly/spark-ios")
    }
}
