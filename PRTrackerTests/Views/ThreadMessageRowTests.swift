import Testing
@testable import PRTracker

@Suite struct ThreadMessageRowTests {
    @Test func collapsedCommentHidesBody() {
        #expect(ThreadMessageRow.showsBody(isCollapsed: true) == false)
        #expect(ThreadMessageRow.showsBody(isCollapsed: false) == true)
    }
}
