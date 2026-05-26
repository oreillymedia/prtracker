import Testing
import Foundation
@testable import PRTracker

@Suite struct MailFilterTests {
    @Test func allCasesInOrder() {
        #expect(MailFilter.allCases == [.awaitingMe, .mine, .open, .all, .mentions, .done, .recent])
    }

    @Test func displayLabels() {
        #expect(MailFilter.all.label        == "All")
        #expect(MailFilter.awaitingMe.label == "Awaiting me")
        #expect(MailFilter.open.label       == "Open")
        #expect(MailFilter.mentions.label   == "Mentions")
        #expect(MailFilter.mine.label       == "Mine")
        #expect(MailFilter.done.label       == "Done")
        #expect(MailFilter.recent.label     == "Merged")
    }
}
