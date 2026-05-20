import Foundation

enum RelativeTimeFormatter {
    static func short(_ d: Date, now: Date = .now) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "\(max(s,0))s ago" }
        let m = s / 60; if m < 60 { return "\(m)m ago" }
        let h = m / 60; if h < 24 { return "\(h)h ago" }
        let dd = h / 24; if dd < 7 { return "\(dd)d ago" }
        let w = dd / 7; if w < 5 { return "\(w)w ago" }
        return "\(dd / 30)mo ago"
    }
}
