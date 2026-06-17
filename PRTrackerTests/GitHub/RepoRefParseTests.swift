import Testing
@testable import PRTracker

@Suite struct RepoRefParseTests {
    @Test func parsesOwnerName() {
        let r = RepoRef.parse("oreilly/spark-ios")
        #expect(r?.owner == "oreilly")
        #expect(r?.name == "spark-ios")
        #expect(r?.slug == "oreilly/spark-ios")
    }

    @Test func trimsWhitespace() {
        #expect(RepoRef.parse("  oreilly / spark-ios ")?.slug == "oreilly/spark-ios")
    }

    @Test func rejectsMissingSlash() { #expect(RepoRef.parse("oreilly") == nil) }
    @Test func rejectsEmptyParts() {
        #expect(RepoRef.parse("/name") == nil)
        #expect(RepoRef.parse("owner/") == nil)
        #expect(RepoRef.parse("") == nil)
    }
    @Test func rejectsExtraSlashes() { #expect(RepoRef.parse("a/b/c") == nil) }
}
