import Testing
import Foundation
@testable import PRTracker

@Suite struct MailFilterTests {
    @Test func allCasesInOrder() {
        #expect(MailFilter.allCases == [.all, .attention, .review, .mentions, .mine, .involved, .recent])
    }

    @Test func displayLabels() {
        #expect(MailFilter.all.label       == "All")
        #expect(MailFilter.attention.label == "Attention")
        #expect(MailFilter.review.label    == "Review")
        #expect(MailFilter.mentions.label  == "Mentions")
        #expect(MailFilter.mine.label      == "Mine")
        #expect(MailFilter.involved.label  == "Involved")
        #expect(MailFilter.recent.label    == "Merged")
    }

    @Test func sectionMappingMatchesFilter() {
        #expect(MailFilter.attention.section == .attention)
        #expect(MailFilter.review.section    == .review)
        #expect(MailFilter.mentions.section  == .mentions)
        #expect(MailFilter.mine.section      == .mine)
        #expect(MailFilter.involved.section  == .involved)
        #expect(MailFilter.recent.section    == .recent)
        #expect(MailFilter.all.section       == nil)
    }
}
