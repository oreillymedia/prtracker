import Testing
@testable import PRTracker

@Suite struct BadgeControllerTests {
    final class FakeDock: DockBadgeSetting, @unchecked Sendable {
        var label: String? = nil
        func setLabel(_ value: String?) { label = value }
    }

    @Test func emptyAttentionMeansNoDots() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 0
        c.apply()
        #expect(c.menuBarShowsDot == false)
        #expect(dock.label == nil)
    }

    @Test func attentionShowsDockBadge() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        #expect(dock.label == "●")
    }

    @Test func togglingDockOffClearsLabel() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        c.dockEnabled = false
        c.apply()
        #expect(dock.label == nil)
    }

    @Test func newActivityShowsMenuBarDot() {
        let c = BadgeController(dock: FakeDock())
        c.menuBarEnabled = true
        #expect(c.menuBarShowsDot == false)
        c.noteNewActivity()
        #expect(c.menuBarShowsDot == true)
        c.menuBarEnabled = false
        #expect(c.menuBarShowsDot == false)
    }

    @Test func clearNewActivityHidesDot() {
        let c = BadgeController(dock: FakeDock())
        c.menuBarEnabled = true
        c.noteNewActivity()
        c.clearNewActivity()
        #expect(c.menuBarShowsDot == false)
    }
}
