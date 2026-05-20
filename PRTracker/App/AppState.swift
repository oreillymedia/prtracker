import Foundation
import SwiftData

@Observable
final class AppState {
    var activeFilter: MailFilter = .all
    var selectedPRID: String? = nil
    var rateLimitRemaining: Int? = nil
    var rateLimitResetAt: Date? = nil
}
