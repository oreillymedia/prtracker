import SwiftUI

/// A shared, low-frequency clock that lets relative-time labels ("2m ago")
/// advance on their own. `RelativeTimeFormatter` is a pure function of `now`, so
/// without a ticking source every displayed time is frozen between data changes —
/// a PR list that isn't re-queried keeps showing "just now" long after. Views
/// read `TimeClock`'s `now` (via `RelativeTimeText`); because it's `@Observable`,
/// only the leaf labels that read it re-render on each tick — not their parents.
@Observable
final class TimeClock {
    static let shared = TimeClock()

    private(set) var now: Date = .now
    private var timer: Timer?

    init(interval: TimeInterval = 20) {
        // .common mode so the tick still fires during menu tracking / scrolling.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.now = .now
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    deinit { timer?.invalidate() }
}

private struct TimeClockKey: EnvironmentKey {
    static let defaultValue = TimeClock.shared
}

extension EnvironmentValues {
    var timeClock: TimeClock {
        get { self[TimeClockKey.self] }
        set { self[TimeClockKey.self] = newValue }
    }
}

/// A relative-time label that re-renders itself as time passes. Drop-in for
/// `Text(RelativeTimeFormatter.short(date))`; style it with the usual `Text`
/// modifiers. `prefix` prepends fixed text (e.g. "Updated ") inside the same Text.
struct RelativeTimeText: View {
    @Environment(\.timeClock) private var clock
    let date: Date
    var prefix: String = ""

    var body: some View {
        Text(prefix + RelativeTimeFormatter.short(date, now: clock.now))
    }
}
