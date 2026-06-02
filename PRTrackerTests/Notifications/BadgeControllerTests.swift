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

    @Test func bothEnabledWithAttentionShowsBoth() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        #expect(c.menuBarShowsDot == true)
        #expect(dock.label == "●")
    }

    @Test func togglingDockOffClearsLabel() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.apply()
        c.dockEnabled = false
        c.apply()
        #expect(dock.label == nil)
        #expect(c.menuBarShowsDot == true)
    }

    @Test func togglingMenuBarOffHidesDot() {
        let dock = FakeDock()
        let c = BadgeController(dock: dock)
        c.menuBarEnabled = true
        c.dockEnabled = true
        c.attentionCount = 3
        c.menuBarEnabled = false
        c.apply()
        #expect(c.menuBarShowsDot == false)
        #expect(dock.label == "●")
    }
}
