import Foundation

/// Pure helper for reconciling list selection across filter changes.
///
/// The rule: keep the previous selection if it's still in the new list,
/// otherwise pick the first item, otherwise `nil` (empty list).
enum SelectionReconcile {
    static func next(previous: String?, in newList: [String]) -> String? {
        if let previous, newList.contains(previous) { return previous }
        return newList.first
    }
}
