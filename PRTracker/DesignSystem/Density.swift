import SwiftUI

enum Density {
    case compact, comfortable, spacious

    var padY: CGFloat   { self == .compact ? 7  : self == .comfortable ? 11 : 14 }
    var padX: CGFloat   { self == .compact ? 12 : self == .comfortable ? 14 : 16 }
    var inner: CGFloat  { self == .compact ? 6  : self == .comfortable ? 8  : 10 }
    var outer: CGFloat  { self == .compact ? 4  : self == .comfortable ? 7  : 10 }
    var rail: CGFloat   { self == .compact ? 3  : self == .comfortable ? 4  : 5  }
    var avatar: CGFloat { self == .compact ? 16 : self == .comfortable ? 18 : 20 }
}

private struct DensityKey: EnvironmentKey {
    static let defaultValue: Density = .comfortable
}
extension EnvironmentValues {
    var density: Density {
        get { self[DensityKey.self] }
        set { self[DensityKey.self] = newValue }
    }
}
