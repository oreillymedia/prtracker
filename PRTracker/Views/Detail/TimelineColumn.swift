import SwiftUI

struct TimelineColumn: View {
    let events: [TimelineEvent]
    let reviewComments: [ReviewComment]
    let syncActor: SyncActor
    var onTapEvent: (TimelineEvent) -> Void
    var onMarkUpToHere: (TimelineEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Tokens.hairline).frame(width: 1).padding(.leading, 13)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(events.sorted(by: { $0.at < $1.at })) { e in
                    TimelineEventRow(
                        event: e,
                        reviewComments: reviewCommentsFor(e),
                        syncActor: syncActor,
                        onTap: { onTapEvent(e) },
                        onMarkUpToHere: { onMarkUpToHere(e) })
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func reviewCommentsFor(_ event: TimelineEvent) -> [ReviewComment] {
        guard event.type == .review, let rid = event.reviewID else { return [] }
        return reviewComments.filter { $0.parentReviewIntegerID == rid }
    }
}
