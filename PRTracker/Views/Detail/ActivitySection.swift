import SwiftUI

/// Collapsible section at the bottom of the detail body that lists non-comment
/// timeline events (commits, opened/merged/closed/labeled/assigned, status).
/// Reuses `TimelineEventRow` but passes empty reviewComments and no-op handlers —
/// taps in this section are inert.
struct ActivitySection: View {
    let events: [TimelineEvent]
    let syncActor: SyncActor

    @State private var collapsed: Bool = true

    private var visibleEvents: [TimelineEvent] {
        events.filter { $0.type != .comment && $0.type != .review }
              .sorted { $0.at < $1.at }
    }

    var body: some View {
        if !visibleEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { collapsed.toggle() } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Tokens.textFaint).frame(width: 6, height: 6)
                        Text("ACTIVITY")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Tokens.text)
                        Text("\(visibleEvents.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Tokens.hairline, in: Capsule())
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.textFaint)
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if !collapsed {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleEvents) { e in
                            TimelineEventRow(
                                event: e,
                                reviewComments: [],
                                syncActor: syncActor,
                                onTap: {},
                                onMarkUpToHere: {})
                        }
                    }
                }
            }
        }
    }
}
