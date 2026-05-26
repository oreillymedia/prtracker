import SwiftUI
import SwiftData

struct ThreadsView: View {
    @Environment(\.modelContext) private var ctx
    let pr: PullRequest
    let viewerLogin: String
    let syncActor: SyncActor

    @State private var resolvedCollapsed: Bool = true

    private var threads: [Thread] {
        TodoHelpers.threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    var body: some View {
        let open = threads.filter { !TodoHelpers.isResolved($0) }
        let resolved = threads.filter(TodoHelpers.isResolved)
        let activity = pr.timeline.filter { $0.type != .comment && $0.type != .review }

        VStack(alignment: .leading, spacing: 18) {
            if !open.isEmpty {
                section(title: "OPEN", dotColor: Tokens.accent, count: open.count) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(open) { thread in
                            ThreadCard(
                                thread: thread,
                                onToggleMessageDone: { msg in toggle(message: msg) },
                                onResolveAll: { resolveAll(thread) })
                        }
                    }
                }
            }
            if !resolved.isEmpty {
                section(title: "RESOLVED", dotColor: Tokens.approved, count: resolved.count, collapsible: true,
                        collapsed: $resolvedCollapsed) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(resolved) { thread in
                            ThreadCard(
                                thread: thread,
                                onToggleMessageDone: { msg in toggle(message: msg) },
                                onResolveAll: { resolveAll(thread) })
                        }
                    }
                }
            }
            if open.isEmpty && resolved.isEmpty && activity.isEmpty {
                emptyState
            }
            ActivitySection(events: pr.timeline, syncActor: syncActor)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, dotColor: Color, count: Int, collapsible: Bool = false, collapsed: Binding<Bool> = .constant(false), @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(title: title, dotColor: dotColor, count: count, collapsible: collapsible, collapsed: collapsed)
            if !collapsible || !collapsed.wrappedValue {
                content()
            }
        }
    }

    @ViewBuilder
    private func sectionHeading(title: String, dotColor: Color, count: Int, collapsible: Bool, collapsed: Binding<Bool>) -> some View {
        if collapsible {
            Button { collapsed.wrappedValue.toggle() } label: {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(title).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Tokens.text)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textMuted)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Tokens.hairline, in: Capsule())
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textFaint)
                        .rotationEffect(.degrees(collapsed.wrappedValue ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Tokens.text)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textMuted)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Tokens.hairline, in: Capsule())
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        Text("No conversation on this PR yet.")
            .font(.system(size: 13))
            .foregroundStyle(Tokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.border, lineWidth: 0.5))
    }

    // MARK: - Mutations (direct on main context, instant reactive)

    private func toggle(message msg: ThreadMessage) {
        switch msg.underlying {
        case .timelineEvent(let id):
            if let e = pr.timeline.first(where: { $0.id == id }) {
                e.isDone.toggle()
            }
        case .reviewComment(let id):
            if let c = pr.reviewComments.first(where: { $0.id == id }) {
                c.isDone.toggle()
            }
        }
        try? ctx.save()
    }

    private func resolveAll(_ thread: Thread) {
        for msg in thread.messages where !msg.isMine {
            switch msg.underlying {
            case .timelineEvent(let id):
                if let e = pr.timeline.first(where: { $0.id == id }) {
                    e.isDone = true
                }
            case .reviewComment(let id):
                if let c = pr.reviewComments.first(where: { $0.id == id }) {
                    c.isDone = true
                }
            }
        }
        try? ctx.save()
    }
}
