import SwiftUI

struct ReviewCommentThreadView: View {
    let root: ReviewComment
    let replies: [ReviewComment]   // pre-filtered & pre-sorted by caller
    let syncActor: SyncActor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewCommentCard(comment: root, showsAnchor: true,
                onToggleSeen: { toggleSeen(root) })

            if !replies.isEmpty {
                ZStack(alignment: .leading) {
                    // Hairline rail behind the indented reply stack.
                    Rectangle()
                        .fill(Tokens.hairline)
                        .frame(width: 1)
                        .padding(.leading, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(replies) { reply in
                            ReviewCommentCard(comment: reply, showsAnchor: false,
                                onToggleSeen: { toggleSeen(reply) })
                        }
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }

    private func toggleSeen(_ c: ReviewComment) {
        let id = c.id
        let wasSeen = c.isSeen
        Task { try? await syncActor.setSeen(reviewCommentID: id, isSeen: !wasSeen) }
    }
}
