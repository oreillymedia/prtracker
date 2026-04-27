import SwiftUI

struct PRCardView: View {
    let pr: PullRequest
    let lane: Lane
    let hint: String?

    @Environment(\.density) private var density

    private var gauge: StatusGauge {
        let review: StatusGauge.StageState = {
            switch pr.reviewState {
            case .approved: .ok
            case .changesRequested: .bad
            case .pending, .commented, .none: .inactive
            }
        }()
        let ci: StatusGauge.StageState = {
            if pr.ciFail > 0 { return .bad }
            if pr.ciRunning > 0 || pr.ciPending > 0 { return .running }
            if pr.ciPass > 0 { return .ok }
            return .inactive
        }()
        let merge: StatusGauge.StageState = {
            switch pr.mergeable {
            case .clean: .ok
            case .conflicts, .blocked: .bad
            case .unknown: .inactive
            }
        }()
        return StatusGauge(review: review, ci: ci, merge: merge)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(lane.color).frame(width: density.rail)
            VStack(alignment: .leading, spacing: density.inner) {
                HStack(spacing: 8) {
                    if pr.isUnread {
                        Circle().fill(Tokens.unreadDot).frame(width: 8, height: 8)
                    } else {
                        Spacer().frame(width: 8, height: 8)
                    }
                    Text("#\(pr.number)").microText().monospacedDigit().foregroundStyle(Tokens.textMuted)
                    Text(pr.title).cardTitle(unread: pr.isUnread).foregroundStyle(Tokens.text)
                    Spacer()
                    Text(RelativeTimeFormatter.short(pr.updatedAt))
                        .microText().foregroundStyle(Tokens.textFaint)
                }
                if density != .compact {
                    HStack(spacing: 8) {
                        AvatarView(user: pr.author, size: density.avatar)
                        Text(pr.author.name ?? pr.author.login).metaText().foregroundStyle(Tokens.text)
                        Text("·").foregroundStyle(Tokens.textFaint)
                        Text(pr.branchHead).monoText().foregroundStyle(Tokens.textFaint).lineLimit(1)
                        Spacer()
                        gauge
                    }
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.text)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Tokens.newHighlight, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, density.padY).padding(.horizontal, density.padX)
        }
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.border, lineWidth: 0.5))
        .opacity(pr.isUnread ? 1.0 : 0.5)
    }
}

struct AvatarView: View {
    let user: User
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Tokens.commented)
            if let url = user.avatarURL {
                AsyncImage(url: url) { img in img.resizable() } placeholder: { Color.clear }
                    .clipShape(Circle())
            } else {
                Text(String(user.login.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5).weight(.semibold))
                    .foregroundStyle(.white)
            }
        }.frame(width: size, height: size)
    }
}

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
