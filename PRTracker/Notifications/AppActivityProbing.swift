import Foundation
import AppKit

protocol AppActivityProbing: Sendable {
    @MainActor func isFrontmost() -> Bool
}

struct NSAppActivityProbe: AppActivityProbing {
    @MainActor func isFrontmost() -> Bool { NSApp.isActive }
}
