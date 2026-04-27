import SwiftUI

struct TimelineColumn: View {
    let events: [TimelineEvent]
    var onTapEvent: (TimelineEvent) -> Void
    var onMarkUpToHere: (TimelineEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Tokens.border).frame(width: 1).offset(x: 13)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(events.sorted(by: { $0.at < $1.at })) { e in
                    TimelineEventRow(event: e,
                        onTap: { onTapEvent(e) },
                        onMarkUpToHere: { onMarkUpToHere(e) })
                }
            }
        }
        .padding(.vertical, 12)
    }
}
