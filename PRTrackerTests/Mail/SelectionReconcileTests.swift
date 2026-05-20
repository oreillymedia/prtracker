import Testing
@testable import PRTracker

@Suite struct SelectionReconcileTests {
    @Test func keepsExistingWhenStillInList() {
        let result = SelectionReconcile.next(previous: "B", in: ["A", "B", "C"])
        #expect(result == "B")
    }

    @Test func selectsFirstWhenPreviousIsGone() {
        let result = SelectionReconcile.next(previous: "X", in: ["A", "B", "C"])
        #expect(result == "A")
    }

    @Test func selectsFirstWhenPreviousWasNil() {
        let result = SelectionReconcile.next(previous: nil, in: ["A", "B", "C"])
        #expect(result == "A")
    }

    @Test func returnsNilWhenListEmpty() {
        let result = SelectionReconcile.next(previous: "B", in: [])
        #expect(result == nil)
    }

    @Test func returnsNilWhenListEmptyAndPreviousNil() {
        let result = SelectionReconcile.next(previous: nil, in: [])
        #expect(result == nil)
    }
}
