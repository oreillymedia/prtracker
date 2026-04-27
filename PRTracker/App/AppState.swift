import Foundation
import SwiftData

@Observable
final class AppState {
    var activeSection: Section? = nil          // nil == "All"
    var selectedPRID: String? = nil
    var rateLimitRemaining: Int? = nil
    var rateLimitResetAt: Date? = nil
}
