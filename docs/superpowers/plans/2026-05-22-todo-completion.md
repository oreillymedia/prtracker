# Todo-first Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire read/unread as the primary state, replace with per-message done/not-done. The detail body becomes OPEN / RESOLVED / ACTIVITY sections of thread cards; the source list shows a `TodoRing` + status chip; filters become Awaiting me / Open / Done / Merged / etc.

**Architecture:** Two new SwiftData columns (`isDone` on `TimelineEvent` and `ReviewComment`) — everything else is derived per-render from existing data via pure helpers in `TodoHelpers.swift`. The mutation path is direct-on-main-context (the pattern proven by the "Mark as unread" fix), so SwiftUI updates instantly.

**Tech Stack:** SwiftUI on macOS 26, SwiftData persistence, Swift Testing (`@Suite`/`@Test`/`#expect`). No new third-party dependencies.

**Spec reference:** `docs/superpowers/specs/2026-05-22-todo-completion-design.md`
**Branch:** `notifications` (current; this work co-lives with the paused notifications spec)

---

## File Structure

### Create

- `PRTracker/Models/TodoHelpers.swift` — pure helpers: `Thread`, `ThreadMessage`, `TodoCounts`, `threads(for:viewerLogin:lastSeenAt:)`, `isResolved`, `hasNew`, `openCount`, `todoCounts`, `ballInMyCourt`
- `PRTracker/DesignSystem/TodoRing.swift` — circular progress
- `PRTracker/DesignSystem/TodoCheckbox.swift` — 18pt rounded checkbox
- `PRTracker/Views/Detail/TodoSummaryBar.swift`
- `PRTracker/Views/Detail/ThreadCard.swift`
- `PRTracker/Views/Detail/ThreadMessageRow.swift`
- `PRTracker/Views/Detail/ActivitySection.swift`
- `PRTracker/Views/Detail/ThreadsView.swift` — replaces `TimelineColumn` as the detail body
- `PRTrackerTests/Mail/TodoHelpersTests.swift`

### Modify

- `PRTracker/Models/TimelineEvent.swift` — add `var isDone: Bool = false`
- `PRTracker/Models/ReviewComment.swift` — add `var isDone: Bool = false`
- `PRTracker/Models/PullRequest.swift` — remove `isUnread` computed property; add `lastSeenAt` accessor
- `PRTracker/Views/Mail/MailFilter.swift` — replace cases: drop `.review`, `.involved`; add `.awaitingMe`, `.open`, `.done`
- `PRTracker/Views/Mail/MailRowView.swift` — full rewrite
- `PRTracker/Views/Mail/MailListView.swift` — sort, selection writes `lastReadAt = .now`, new filter predicates
- `PRTracker/Views/Mail/FilterPillBar.swift` — accent-tinted Awaiting-me when count > 0
- `PRTracker/Views/Mail/MailDetailHeader.swift` — insert `TodoSummaryBar` below metadata
- `PRTracker/Views/Detail/PRDetailView.swift` — body → `ThreadsView`; drop `userMarkedUnread`; simplify `.task`
- `PRTracker/Views/Detail/DetailRightRail.swift` — drop "Mark as unread" button
- `PRTracker/Sync/Classifier.swift` — `bucketFor(pr:viewerLogin:lastSeenAt:)` uses `ballInMyCourt`
- `PRTracker/Views/MenuBar/MenuBarContentView.swift` — replace `pr.isUnread` reference with `todoCounts(for:).open > 0`
- `PRTrackerTests/Mail/MailFilterTests.swift` — new pill expectations
- `PRTrackerTests/Mail/PullRequestReadStateTests.swift` — delete (the `isUnread` it tested is gone)

### Delete

- `PRTracker/Views/Mail/UnreadDot.swift`
- `PRTrackerTests/Mail/PullRequestReadStateTests.swift`

---

## Task 1: Add `isDone` to `TimelineEvent` and `ReviewComment`

**Files:**
- Modify: `PRTracker/Models/TimelineEvent.swift`
- Modify: `PRTracker/Models/ReviewComment.swift`

- [ ] **Step 1: Add the field on `TimelineEvent`**

Open `PRTracker/Models/TimelineEvent.swift`. The existing model has fields ending around `isSeen`. Add `isDone` immediately after `isSeen`:

```swift
    /// Local-only — never overwritten by sync.
    var isSeen: Bool
    /// Local-only — never overwritten by sync. True when the user has marked
    /// this comment-style event as addressed. Only meaningful for `type == .comment`.
    var isDone: Bool = false
```

Do not modify `init` — SwiftData's additive migration handles default `false` for existing rows.

- [ ] **Step 2: Add the field on `ReviewComment`**

Open `PRTracker/Models/ReviewComment.swift`. After the existing `var isSeen: Bool` line, add:

```swift
    /// Local-only — never overwritten by sync.
    var isSeen: Bool
    /// Local-only — never overwritten by sync. True when the user has marked
    /// this code-comment message as addressed.
    var isDone: Bool = false
```

Do not modify `init`.

- [ ] **Step 3: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Models/TimelineEvent.swift PRTracker/Models/ReviewComment.swift
git commit -m "feat(model): add isDone field on TimelineEvent and ReviewComment"
```

---

## Task 2: `TodoHelpers.swift` + value types + unit tests (TDD)

**Files:**
- Create: `PRTracker/Models/TodoHelpers.swift`
- Create: `PRTrackerTests/Mail/TodoHelpersTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `PRTrackerTests/Mail/TodoHelpersTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct TodoHelpersTests {
    // MARK: - Fixture builder

    private func makePR(viewer: String = "alex", author: String = "dan",
                        reviewState: ReviewState? = nil) throws -> (ModelContainer, PullRequest, User) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let viewerUser = User(login: viewer, name: nil, avatarURL: nil)
        let authorUser = User(login: author, name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(viewerUser); ctx.insert(authorUser); ctx.insert(repo)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pr = PullRequest(id: "PR_1", number: 1, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: now, updatedAt: now, author: authorUser, repo: repo)
        ctx.insert(pr)
        try ctx.save()
        return (container, pr, viewerUser)
    }

    private func makeReviewComment(in pr: PullRequest, ctx: ModelContext,
                                   id: String, author: User, body: String = "x",
                                   parentReview: Int? = 1, inReplyTo: String? = nil,
                                   isDone: Bool = false, createdAt: Date = .distantPast) -> ReviewComment {
        let c = ReviewComment(id: id, parentReviewIntegerID: parentReview,
                              inReplyToID: inReplyTo, author: author,
                              body: body, path: "F.swift", line: 1, diffHunk: "@@",
                              createdAt: createdAt, isSeen: false, pullRequest: pr)
        c.isDone = isDone
        ctx.insert(c)
        return c
    }

    // MARK: - Resolution rules

    @Test func isResolved_emptyThread_vacuouslyTrue() {
        let t = Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func isResolved_onlyMineMessages_true() {
        let me = User(login: "alex", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: me, createdAt: .distantPast, body: "x",
                                isMine: true, isDone: false, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func isResolved_oneOpenNonMine_false() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                                isMine: false, isDone: false, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == false)
    }

    @Test func isResolved_allNonMineDone_true() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let msg = ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                                isMine: false, isDone: true, isNew: false,
                                underlying: .timelineEvent(eventID: "m1"))
        let t = Thread(id: "t1", kind: .prComment, location: "Discussion", kindLabel: nil, messages: [msg])
        #expect(TodoHelpers.isResolved(t) == true)
    }

    @Test func openCount_countsOnlyNonMineNotDone() {
        let me = User(login: "alex", name: nil, avatarURL: nil)
        let other = User(login: "dan", name: nil, avatarURL: nil)
        let messages = [
            ThreadMessage(id: "m1", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m1")),
            ThreadMessage(id: "m2", actor: me, createdAt: .distantPast, body: "y",
                          isMine: true, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m2")),
            ThreadMessage(id: "m3", actor: other, createdAt: .distantPast, body: "z",
                          isMine: false, isDone: true, isNew: false,
                          underlying: .timelineEvent(eventID: "m3")),
        ]
        let t = Thread(id: "t1", kind: .prComment, location: "D", kindLabel: nil, messages: messages)
        #expect(TodoHelpers.openCount(t) == 1)
    }

    @Test func hasNew_requiresAllThree() {
        let other = User(login: "dan", name: nil, avatarURL: nil)
        // not-mine, not-done, isNew → has new
        let t1 = Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: true,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t1) == true)
        // not-mine, done, isNew → no
        let t2 = Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: true, isNew: true,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t2) == false)
        // not-mine, not-done, not-new → no
        let t3 = Thread(id: "t", kind: .prComment, location: "D", kindLabel: nil, messages: [
            ThreadMessage(id: "m", actor: other, createdAt: .distantPast, body: "x",
                          isMine: false, isDone: false, isNew: false,
                          underlying: .timelineEvent(eventID: "m"))
        ])
        #expect(TodoHelpers.hasNew(t3) == false)
    }

    // MARK: - PR-level aggregates

    @Test func todoCounts_emptyPR_zeroes() throws {
        let (_, pr, viewer) = try makePR()
        let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(counts == TodoCounts(total: 0, done: 0, open: 0, openMessages: 0))
    }

    @Test func todoCounts_mixedThreads() throws {
        let (container, pr, viewer) = try makePR()
        let ctx = ModelContext(container)
        let other = User(login: "dan", name: nil, avatarURL: nil); ctx.insert(other)
        // Thread 1: 2 open non-mine messages → open thread (open=2)
        let root1 = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other, parentReview: 1)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC2", author: other, parentReview: 1, inReplyTo: "RC1")
        // Thread 2: 1 open non-mine message → open thread (open=1)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC3", author: other, parentReview: 2)
        // Thread 3: 1 done non-mine message → resolved thread
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC4", author: other, parentReview: 3, isDone: true)
        try ctx.save()
        // Re-fetch the PR so reviewComments is current
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let counts = TodoHelpers.todoCounts(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(counts.total == 3)
        #expect(counts.done == 1)
        #expect(counts.open == 2)
        #expect(counts.openMessages == 3)
    }

    @Test func ballInMyCourt_othersPR_noOpenMessages_false() throws {
        let (_, pr, viewer) = try makePR()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    @Test func ballInMyCourt_othersPR_oneOpenMessage_true() throws {
        let (container, pr, viewer) = try makePR()
        let ctx = ModelContext(container)
        let other = User(login: "dan", name: nil, avatarURL: nil); ctx.insert(other)
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        #expect(TodoHelpers.ballInMyCourt(prFresh, viewerLogin: viewer.login, lastSeenAt: nil) == true)
    }

    @Test func ballInMyCourt_mergedPR_alwaysFalse() throws {
        let (container, pr, viewer) = try makePR()
        let ctx = ModelContext(container)
        pr.state = .merged
        try ctx.save()
        #expect(TodoHelpers.ballInMyCourt(pr, viewerLogin: viewer.login, lastSeenAt: nil) == false)
    }

    // MARK: - Thread derivation

    @Test func threads_buildsReviewCommentChain() throws {
        let (container, pr, viewer) = try makePR()
        let ctx = ModelContext(container)
        let other = User(login: "dan", name: nil, avatarURL: nil); ctx.insert(other)
        let root = makeReviewComment(in: pr, ctx: ctx, id: "RC1", author: other,
                                     parentReview: 1, createdAt: Date(timeIntervalSince1970: 1000))
        _ = root
        _ = makeReviewComment(in: pr, ctx: ctx, id: "RC2", author: other,
                              parentReview: 1, inReplyTo: "RC1",
                              createdAt: Date(timeIntervalSince1970: 2000))
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.count == 1)
        #expect(ts[0].kind == .reviewComment)
        #expect(ts[0].messages.count == 2)
        #expect(ts[0].messages[0].id == "RC1")
        #expect(ts[0].messages[1].id == "RC2")
    }

    @Test func threads_buildsPRCommentThread() throws {
        let (container, pr, viewer) = try makePR()
        let ctx = ModelContext(container)
        let other = User(login: "dan", name: nil, avatarURL: nil); ctx.insert(other)
        let event = TimelineEvent(id: "TE_1", type: .comment, at: .distantPast,
                                  pullRequest: pr, actor: other, body: "x")
        ctx.insert(event)
        try ctx.save()
        let prFresh = try ctx.fetch(FetchDescriptor<PullRequest>()).first!
        let ts = TodoHelpers.threads(for: prFresh, viewerLogin: viewer.login, lastSeenAt: nil)
        #expect(ts.count == 1)
        #expect(ts[0].kind == .prComment)
        #expect(ts[0].messages.count == 1)
        #expect(ts[0].location == "Discussion")
    }
}
```

- [ ] **Step 2: Verify tests fail to compile**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "cannot find 'Thread'|cannot find 'TodoHelpers'" | head -3
```
Expected: errors referencing the missing types.

- [ ] **Step 3: Create `TodoHelpers.swift`**

Create `PRTracker/Models/TodoHelpers.swift`:

```swift
import Foundation

// MARK: - Value types

enum ThreadKind: Equatable {
    case reviewComment
    case prComment
}

enum ThreadMessageBacking: Equatable {
    case timelineEvent(eventID: String)
    case reviewComment(commentID: String)
}

struct Thread: Identifiable, Equatable {
    let id: String
    let kind: ThreadKind
    let location: String
    let kindLabel: String?
    let messages: [ThreadMessage]
}

struct ThreadMessage: Identifiable, Equatable {
    let id: String
    let actor: User
    let createdAt: Date
    let body: String
    let isMine: Bool
    let isDone: Bool
    let isNew: Bool
    let underlying: ThreadMessageBacking
}

struct TodoCounts: Equatable {
    let total: Int
    let done: Int
    let open: Int
    let openMessages: Int
}

// MARK: - Helpers

enum TodoHelpers {

    static func threads(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> [Thread] {
        var out: [Thread] = []

        // PR-comment threads: top-level TimelineEvents of type .comment, one message each.
        for e in pr.timeline where e.type == .comment {
            let msg = makeMessage(timelineEvent: e, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
            out.append(Thread(id: "te_\(e.id)", kind: .prComment,
                              location: "Discussion", kindLabel: nil, messages: [msg]))
        }

        // Review-comment threads: group by parent review id + chain replies.
        let comments = pr.reviewComments
        let roots = comments.filter { $0.inReplyToID == nil }
        for root in roots.sorted(by: { $0.createdAt < $1.createdAt }) {
            let replies = comments
                .filter { $0.inReplyToID == root.id }
                .sorted { $0.createdAt < $1.createdAt }
            let messages = ([root] + replies).map {
                makeMessage(reviewComment: $0, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
            }
            let kindLabel = originReviewKindLabel(reviewIntegerID: root.parentReviewIntegerID, in: pr)
            let location = root.line.map { "\(root.path) L\($0)" } ?? root.path
            out.append(Thread(id: "rc_\(root.id)", kind: .reviewComment,
                              location: location, kindLabel: kindLabel, messages: messages))
        }

        return out.sorted { ($0.messages.last?.createdAt ?? .distantPast) > ($1.messages.last?.createdAt ?? .distantPast) }
    }

    static func isResolved(_ thread: Thread) -> Bool {
        thread.messages.allSatisfy { $0.isMine || $0.isDone }
    }

    static func hasNew(_ thread: Thread) -> Bool {
        thread.messages.contains { !$0.isMine && !$0.isDone && $0.isNew }
    }

    static func openCount(_ thread: Thread) -> Int {
        thread.messages.filter { !$0.isMine && !$0.isDone }.count
    }

    static func todoCounts(for pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> TodoCounts {
        let ts = threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
        let total = ts.count
        let done = ts.filter(isResolved).count
        let openMessages = ts.reduce(0) { $0 + openCount($1) }
        return TodoCounts(total: total, done: done, open: total - done, openMessages: openMessages)
    }

    static func ballInMyCourt(_ pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> Bool {
        if pr.state == .merged || pr.state == .closed { return false }
        let counts = todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt)
        if counts.openMessages > 0 { return true }
        if pr.author.login == viewerLogin && pr.reviewState == .changesRequested { return true }
        return false
    }

    // MARK: - Private

    private static func makeMessage(timelineEvent e: TimelineEvent,
                                    viewerLogin: String,
                                    lastSeenAt: Date?) -> ThreadMessage {
        let actor = e.actor ?? User(login: "unknown", name: nil, avatarURL: nil)
        let isMine = actor.login == viewerLogin
        let isNew = !isMine && !e.isDone && (lastSeenAt.map { e.at > $0 } ?? true)
        return ThreadMessage(
            id: e.id, actor: actor, createdAt: e.at, body: e.body ?? "",
            isMine: isMine, isDone: e.isDone, isNew: isNew,
            underlying: .timelineEvent(eventID: e.id))
    }

    private static func makeMessage(reviewComment c: ReviewComment,
                                    viewerLogin: String,
                                    lastSeenAt: Date?) -> ThreadMessage {
        let isMine = c.author.login == viewerLogin
        let isNew = !isMine && !c.isDone && (lastSeenAt.map { c.createdAt > $0 } ?? true)
        return ThreadMessage(
            id: c.id, actor: c.author, createdAt: c.createdAt, body: c.body,
            isMine: isMine, isDone: c.isDone, isNew: isNew,
            underlying: .reviewComment(commentID: c.id))
    }

    private static func originReviewKindLabel(reviewIntegerID: Int?, in pr: PullRequest) -> String? {
        guard let rid = reviewIntegerID,
              let event = pr.timeline.first(where: { $0.reviewID == rid && $0.type == .review }) else {
            return nil
        }
        return event.reviewState == .changesRequested ? "Changes requested" : nil
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/TodoHelpersTests 2>&1 | tail -25
```
Expected: all 11+ tests pass.

- [ ] **Step 5: Full suite**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Models/TodoHelpers.swift PRTrackerTests/Mail/TodoHelpersTests.swift
git commit -m "feat(model): TodoHelpers — pure thread/message derivation + todoCounts + ballInMyCourt"
```

---

## Task 3: `TodoRing` and `TodoCheckbox` SwiftUI primitives

**Files:**
- Create: `PRTracker/DesignSystem/TodoRing.swift`
- Create: `PRTracker/DesignSystem/TodoCheckbox.swift`

- [ ] **Step 1: Create `TodoRing`**

Create `PRTracker/DesignSystem/TodoRing.swift`:

```swift
import SwiftUI

struct TodoRing: View {
    enum RingState { case allResolved, awaitingMe, waiting, empty }

    let done: Int
    let total: Int
    let size: CGFloat
    let state: RingState

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.hairline, lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(arcColor, style: .init(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
            centerLabel
        }
        .frame(width: size, height: size)
    }

    private var progress: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    private var arcColor: Color {
        switch state {
        case .allResolved: return Tokens.approved
        case .awaitingMe:  return Tokens.accent
        case .waiting:     return Tokens.textFaint
        case .empty:       return Tokens.hairline
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if total == 0 {
            Circle().fill(Tokens.textFaint).frame(width: 2, height: 2)
        } else if done == total {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(Tokens.approved)
        } else {
            Text("\(done)/\(total)")
                .font(.system(size: size * 0.42, weight: .bold).monospacedDigit())
                .foregroundStyle(arcColor)
        }
    }
}
```

- [ ] **Step 2: Create `TodoCheckbox`**

Create `PRTracker/DesignSystem/TodoCheckbox.swift`:

```swift
import SwiftUI

struct TodoCheckbox: View {
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.04)
                    .fill(isOn ? Tokens.approved : Color.clear)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5.04)
                            .stroke(isOn ? .clear : Tokens.borderStrong, lineWidth: 1.5)
                    )
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}
```

- [ ] **Step 3: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/DesignSystem/TodoRing.swift PRTracker/DesignSystem/TodoCheckbox.swift
git commit -m "feat(design): TodoRing + TodoCheckbox primitives"
```

---

## Task 4: `ThreadMessageRow`

**Files:**
- Create: `PRTracker/Views/Detail/ThreadMessageRow.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/Views/Detail/ThreadMessageRow.swift`:

```swift
import SwiftUI

struct ThreadMessageRow: View {
    let message: ThreadMessage
    let onToggleDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingRail
            AvatarView(user: message.actor, size: 22)
            VStack(alignment: .leading, spacing: 4) {
                headerLine
                MarkdownText(raw: message.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Tokens.accent).frame(width: 3)
                .opacity((message.isNew && !message.isDone) ? 1 : 0)
        }
        .opacity((message.isDone && !message.isMine) ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var leadingRail: some View {
        if message.isMine {
            Text("↳")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Tokens.textFaint)
                .frame(width: 18)
        } else {
            TodoCheckbox(isOn: message.isDone, onTap: onToggleDone)
        }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            Text(message.actor.name ?? message.actor.login)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.text)
                .strikethrough(message.isDone && !message.isMine, color: Tokens.textFaint)
            if message.isMine { youTag }
            if message.isNew && !message.isDone { newTag }
            Spacer(minLength: 0)
            Text(RelativeTimeFormatter.short(message.createdAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
        }
    }

    private var youTag: some View {
        Text("YOU")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(Tokens.textMuted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Tokens.hairline, in: RoundedRectangle(cornerRadius: 3))
    }

    private var newTag: some View {
        Text("NEW")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Tokens.accent)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Tokens.accentBg, in: RoundedRectangle(cornerRadius: 3))
    }

    private var rowBackground: Color {
        (message.isNew && !message.isDone) ? Tokens.newHighlight : .clear
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ThreadMessageRow.swift
git commit -m "feat(detail): ThreadMessageRow (checkbox/↳ + author + body)"
```

---

## Task 5: `ThreadCard`

**Files:**
- Create: `PRTracker/Views/Detail/ThreadCard.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/Views/Detail/ThreadCard.swift`:

```swift
import SwiftUI

struct ThreadCard: View {
    let thread: Thread
    let onToggleMessageDone: (ThreadMessage) -> Void
    let onResolveAll: () -> Void

    @State private var collapsed: Bool

    init(thread: Thread, onToggleMessageDone: @escaping (ThreadMessage) -> Void, onResolveAll: @escaping () -> Void) {
        self.thread = thread
        self.onToggleMessageDone = onToggleMessageDone
        self.onResolveAll = onResolveAll
        self._collapsed = State(initialValue: TodoHelpers.isResolved(thread))
    }

    private var resolved: Bool { TodoHelpers.isResolved(thread) }
    private var hasNew: Bool { TodoHelpers.hasNew(thread) }
    private var openMessageCount: Int { TodoHelpers.openCount(thread) }
    private var totalNonMine: Int { thread.messages.filter { !$0.isMine }.count }
    private var doneNonMine: Int { thread.messages.filter { !$0.isMine && $0.isDone }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !collapsed {
                Divider().background(Tokens.hairline)
                ForEach(thread.messages) { msg in
                    ThreadMessageRow(message: msg, onToggleDone: { onToggleMessageDone(msg) })
                }
                if !resolved && totalNonMine > 0 {
                    resolveFooter
                }
            }
        }
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hasNew ? Tokens.accent.opacity(0.4) : Tokens.border, lineWidth: 0.5)
        )
        .shadow(color: resolved ? .clear : Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        .opacity(resolved ? 0.78 : 1.0)
        .animation(.easeOut(duration: 0.18), value: collapsed)
    }

    private var header: some View {
        Button { collapsed.toggle() } label: {
            HStack(spacing: 10) {
                statusTile
                VStack(alignment: .leading, spacing: 2) {
                    headerTitleLine
                    Text(subLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.textMuted)
                }
                Spacer(minLength: 0)
                if !resolved && totalNonMine > 1 {
                    Button(action: onResolveAll) {
                        Text("Resolve all")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.textMuted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Tokens.contentBg, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textFaint)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .animation(.easeOut(duration: 0.15), value: collapsed)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerTitleLine: some View {
        HStack(spacing: 6) {
            if let label = thread.kindLabel {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(label == "Changes requested" ? Tokens.changes : Tokens.textMuted)
                Text("·").foregroundStyle(Tokens.textFaint)
            }
            Text(thread.location)
                .font(.system(size: 12.5, weight: .semibold,
                              design: thread.kind == .reviewComment ? .monospaced : .default))
                .foregroundStyle(Tokens.text)
        }
    }

    @ViewBuilder
    private var statusTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(statusTileFill)
                .frame(width: 22, height: 22)
            statusTileLabel
        }
    }

    private var statusTileFill: Color {
        if resolved { return Tokens.approved }
        if hasNew { return Tokens.accent }
        return Tokens.hairline
    }

    @ViewBuilder
    private var statusTileLabel: some View {
        if resolved {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        } else if totalNonMine > 0 {
            Text("\(doneNonMine)/\(totalNonMine)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(hasNew ? .white : Tokens.textMuted)
        }
    }

    private var subLine: String {
        if resolved { return "Resolved" }
        return "\(openMessageCount) open · \(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s")"
    }

    private var resolveFooter: some View {
        Button(action: onResolveAll) {
            Text("Resolve")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Tokens.cardBg)
                .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .top)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ThreadCard.swift
git commit -m "feat(detail): ThreadCard (header + collapsible messages + Resolve footer)"
```

---

## Task 6: `TodoSummaryBar`

**Files:**
- Create: `PRTracker/Views/Detail/TodoSummaryBar.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/Views/Detail/TodoSummaryBar.swift`:

```swift
import SwiftUI

struct TodoSummaryBar: View {
    let counts: TodoCounts

    private var resolved: Bool { counts.total > 0 && counts.open == 0 }

    var body: some View {
        HStack(spacing: 10) {
            TodoRing(done: counts.done, total: counts.total, size: 32,
                     state: resolved ? .allResolved : .awaitingMe)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(resolved ? Tokens.approved : Tokens.accentText)
                Text(secondaryLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tokens.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            (resolved ? Tokens.approvedBg : Tokens.accentBg),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(resolved ? Tokens.approved.opacity(0.27) : Tokens.accent.opacity(0.2),
                        lineWidth: 0.5)
        )
    }

    private var primaryLine: String {
        if resolved { return "All caught up" }
        return "\(counts.done) of \(counts.total) threads resolved"
    }

    private var secondaryLine: String {
        if resolved { return "No outstanding feedback. Ready when CI is." }
        let suffix = counts.openMessages == 1 ? "message" : "messages"
        return "\(counts.openMessages) open \(suffix) to address"
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/TodoSummaryBar.swift
git commit -m "feat(detail): TodoSummaryBar (32pt ring + status text)"
```

---

## Task 7: `ActivitySection` (collapsible non-comment events)

**Files:**
- Create: `PRTracker/Views/Detail/ActivitySection.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/Views/Detail/ActivitySection.swift`:

```swift
import SwiftUI

/// Collapsible section at the bottom of the detail body that lists non-comment
/// timeline events (commits, opened/merged/closed/labeled/assigned, status).
/// Reuses `TimelineEventRow` but passes empty reviewComments and a no-op
/// syncActor binding — taps in this section are inert.
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ActivitySection.swift
git commit -m "feat(detail): ActivitySection (collapsible non-comment events)"
```

---

## Task 8: `ThreadsView` (the new detail body)

**Files:**
- Create: `PRTracker/Views/Detail/ThreadsView.swift`

- [ ] **Step 1: Create the file**

Create `PRTracker/Views/Detail/ThreadsView.swift`:

```swift
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
    private func section<Content: View>(title: String, dotColor: Color, count: Int,
                                        collapsible: Bool = false,
                                        collapsed: Binding<Bool> = .constant(false),
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(title: title, dotColor: dotColor, count: count,
                           collapsible: collapsible, collapsed: collapsed)
            if !collapsible || !collapsed.wrappedValue {
                content()
            }
        }
    }

    @ViewBuilder
    private func sectionHeading(title: String, dotColor: Color, count: Int,
                                collapsible: Bool, collapsed: Binding<Bool>) -> some View {
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/ThreadsView.swift
git commit -m "feat(detail): ThreadsView — OPEN / RESOLVED / ACTIVITY sections + mutations"
```

---

## Task 9: Add `lastSeenAt` accessor on `PullRequest`

**Files:**
- Modify: `PRTracker/Models/PullRequest.swift`

The column stays named `lastReadAt` (no migration risk). Add a read-only accessor for new code.

- [ ] **Step 1: Add the accessor**

Open `PRTracker/Models/PullRequest.swift`. Find the existing `var lastReadAt: Date?` line (around line 29). Right after the relationship lines but BEFORE the `isUnread` computed property, add:

```swift
    /// Semantically: the most recent moment the user selected this PR's row.
    /// Backed by the same column as `lastReadAt` to avoid a SwiftData
    /// migration. New code reads `lastSeenAt`; legacy code reads `lastReadAt`.
    var lastSeenAt: Date? { lastReadAt }
```

Do NOT remove `isUnread` yet — that happens in Task 13 after MailRowView no longer references it.

- [ ] **Step 2: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: both succeed.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Models/PullRequest.swift
git commit -m "feat(model): add PullRequest.lastSeenAt accessor (backed by lastReadAt)"
```

---

## Task 10: Wire `ThreadsView` + `TodoSummaryBar` into `PRDetailView` and drop right-rail unread button

**Files:**
- Modify: `PRTracker/Views/Detail/PRDetailView.swift`
- Modify: `PRTracker/Views/Detail/DetailRightRail.swift`
- Modify: `PRTracker/Views/Mail/MailDetailHeader.swift`

- [ ] **Step 1: Drop the "Mark as unread" button from `DetailRightRail`**

Open `PRTracker/Views/Detail/DetailRightRail.swift`. Remove these pieces:

1. The `var onToggleReadState: () -> Void` property.
2. The bottom Button block (the `Button { onToggleReadState() } label: { Text(pr.isUnread ? "Mark as read" : "Mark as unread") ... }` and its preceding `Spacer()`).

After the edit, the rail's body ends with the existing `section("Changes") { ... }`, then `.padding(18)`, `.frame(width: 260)`, etc. No more bottom button.

- [ ] **Step 2: Add `TodoSummaryBar` to `MailDetailHeader`**

Open `PRTracker/Views/Mail/MailDetailHeader.swift`. The header struct currently has `let pr: PullRequest` and other props. Add:

```swift
    let todoCounts: TodoCounts
```

In the body's `VStack(alignment: .leading, spacing: 8)`, after the existing `metadataRow`, insert (only when there are threads):

```swift
            if todoCounts.total > 0 {
                TodoSummaryBar(counts: todoCounts)
                    .padding(.top, 4)
            }
```

- [ ] **Step 3: Rewrite `PRDetailView.body` to use `ThreadsView` + drop unread tracking**

Open `PRTracker/Views/Detail/PRDetailView.swift`. Replace the entire `body` and supporting state with:

```swift
import SwiftUI
import SwiftData

struct PRDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]
    let pr: PullRequest
    let viewer: User?
    let client: GitHubClient
    let syncActor: SyncActor

    @State private var loadError: GitHubError?
    @State private var isLoading: Bool = false

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    private var todoCounts: TodoCounts {
        TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            MailDetailHeader(
                pr: pr,
                isRefreshing: isLoading,
                lastUpdatedAt: pr.updatedAt,
                onRefresh: { Task { await loadTimeline() } },
                todoCounts: todoCounts)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let loadError {
                            Text("Couldn't load timeline: \(String(describing: loadError)). Click refresh to retry.")
                                .foregroundStyle(Tokens.changes).padding(8)
                                .background(Tokens.changes.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        ThreadsView(pr: pr, viewerLogin: viewerLogin, syncActor: syncActor)
                    }.padding(20)
                }
                DetailRightRail(pr: pr)
            }
        }
        .task(id: pr.id) {
            await loadTimeline()
        }
    }

    private func loadTimeline() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let ref = RepoRef(owner: pr.repo.owner, name: pr.repo.name)
        let number = pr.number
        let prID = pr.id
        let headSha = pr.headSha
        do {
            async let t = client.timeline(repo: ref, number: number)
            async let r = client.reviews(repo: ref, number: number)
            async let c = client.issueComments(repo: ref, number: number)
            async let d = client.pullRequestDetail(repo: ref, number: number)
            async let ck = client.checkRuns(repo: ref, ref: headSha)
            async let rc = client.reviewComments(repo: ref, number: number)
            let (tItems, reviewDTOs, _, detail, checks, reviewComments) = try await (t, r, c, d, ck, rc)
            try await syncActor.upsertTimeline(prID: prID, items: tItems)
            try await syncActor.upsertReviewerStates(prID: prID, fromReviews: reviewDTOs)
            try await syncActor.upsertReviewComments(prID: prID, fromDTOs: reviewComments)
            try await syncActor.updatePRStatistics(prID: prID, dto: detail)
            try await syncActor.upsertCIChecks(prID: prID, dto: checks)
            loadError = nil
        } catch let e as GitHubError {
            loadError = e
        } catch {
            loadError = .network(message: error.localizedDescription)
        }
    }
}
```

Key changes from before:
- No `@State userMarkedUnread`. Read/unread tracking is gone.
- `.task` no longer writes `setSeenForPR` or `setLastReadAt`.
- `DetailRightRail` now takes only `pr` — no `onToggleReadState`.
- `MailDetailHeader` takes a new `todoCounts` parameter.
- The detail body's content is `ThreadsView`, not `TimelineColumn`.
- The `toggleReadStateOnMainContext` helper and its private fields are removed entirely.

- [ ] **Step 4: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: both succeed.

- [ ] **Step 5: Manually verify**

Run the app. Open a PR with code-level review comments:
- Detail header shows the existing breadcrumb + status pill + refresh + title + metadata.
- Below metadata: a `TodoSummaryBar` showing "`done` of `total` threads resolved" (accent-tinted) or "All caught up" (approved-tinted).
- Body shows OPEN section (default expanded) and RESOLVED section (default collapsed if non-empty).
- ACTIVITY section at the bottom (default collapsed).
- Right rail no longer has the "Mark as unread" / "Mark as read" button.
- Clicking a thread's checkbox toggles `isDone` instantly; ring + summary bar animate.
- "Resolve" footer marks all non-mine messages done; thread migrates to RESOLVED.

- [ ] **Step 6: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Detail/PRDetailView.swift PRTracker/Views/Detail/DetailRightRail.swift PRTracker/Views/Mail/MailDetailHeader.swift
git commit -m "feat(detail): swap TimelineColumn for ThreadsView + integrate TodoSummaryBar; drop Mark-as-unread"
```

---

## Task 11: Rewrite `MailFilter` enum + update tests

**Files:**
- Modify: `PRTracker/Views/Mail/MailFilter.swift`
- Modify: `PRTrackerTests/Mail/MailFilterTests.swift`

- [ ] **Step 1: Update the failing tests first (TDD)**

Open `PRTrackerTests/Mail/MailFilterTests.swift`. Replace its contents:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct MailFilterTests {
    @Test func allCasesInOrder() {
        #expect(MailFilter.allCases == [.all, .awaitingMe, .open, .mentions, .mine, .done, .recent])
    }

    @Test func displayLabels() {
        #expect(MailFilter.all.label        == "All")
        #expect(MailFilter.awaitingMe.label == "Awaiting me")
        #expect(MailFilter.open.label       == "Open")
        #expect(MailFilter.mentions.label   == "Mentions")
        #expect(MailFilter.mine.label       == "Mine")
        #expect(MailFilter.done.label       == "Done")
        #expect(MailFilter.recent.label     == "Merged")
    }
}
```

- [ ] **Step 2: Verify tests fail to compile**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "cannot find '\.awaitingMe'|'\.open'|'\.done'" | head -3
```
Expected: errors referencing the missing cases.

- [ ] **Step 3: Rewrite `MailFilter`**

Replace the entire contents of `PRTracker/Views/Mail/MailFilter.swift` with:

```swift
import Foundation
import SwiftUI

/// Filter pills shown across the top of the source list.
enum MailFilter: String, CaseIterable, Identifiable, Codable {
    case all, awaitingMe, open, mentions, mine, done, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        "All"
        case .awaitingMe: "Awaiting me"
        case .open:       "Open"
        case .mentions:   "Mentions"
        case .mine:       "Mine"
        case .done:       "Done"
        case .recent:     "Merged"
        }
    }

    /// Lane color for the pill dot. `.all`, `.open`, and `.done` have no dot
    /// (they're todo-state filters, not bucket-color filters).
    var dotColor: Color? {
        switch self {
        case .awaitingMe: Lane.attention.color
        case .mentions:   Lane.mentions.color
        case .mine:       Lane.mine.color
        case .recent:     Lane.recent.color
        case .all, .open, .done: nil
        }
    }
}
```

The `.section` accessor is no longer used (filter predicates now live in `MailListView`). If anything references `MailFilter.section`, those references will surface in step 4's build error — remove them by updating to use the new predicate names.

- [ ] **Step 4: Run the test suite**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | grep -E "TEST SUCCEEDED|cannot find|error:" | head -10
```

If you see errors referencing `MailFilter.section`, navigate to the call sites (`MailListView` in particular) and update them. The new predicates are introduced in Task 12.

- [ ] **Step 5: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Mail/MailFilter.swift PRTrackerTests/Mail/MailFilterTests.swift
git commit -m "feat(mail): rewrite MailFilter cases (Awaiting me / Open / Done; drop Review / Involved)"
```

Note: build may still fail after this commit if `MailListView` uses the old `.section` accessor or `.review` / `.involved` cases. Task 12 fixes that. Verify by running build and noting which files reference the removed cases — they all get addressed in the next task.

---

## Task 12: Update `MailListView` (filter predicates + sort + selection write)

**Files:**
- Modify: `PRTracker/Views/Mail/MailListView.swift`

- [ ] **Step 1: Rewrite `MailListView`**

Open `PRTracker/Views/Mail/MailListView.swift`. Replace its contents with:

```swift
import SwiftUI
import SwiftData

struct MailListView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]

    let syncActor: SyncActor

    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    var body: some View {
        @Bindable var appState = appState
        let counts = pillCounts()
        let visible = visiblePRs(filter: appState.activeFilter)

        VStack(spacing: 0) {
            FilterPillBar(active: $appState.activeFilter, counts: counts)
            List(selection: $appState.selectedPRID) {
                if visible.isEmpty {
                    Text("Nothing in this filter.")
                        .font(.system(size: 12.5).italic())
                        .foregroundStyle(Tokens.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visible) { pr in
                        MailRowView(pr: pr,
                                    isSelected: appState.selectedPRID == pr.id,
                                    viewerLogin: viewerLogin)
                            .tag(pr.id)
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: appState.selectedPRID) { _, newID in
            // Update lastReadAt on the newly selected PR (semantically: lastSeenAt).
            guard let newID, let pr = prs.first(where: { $0.id == newID }) else { return }
            pr.lastReadAt = .now
            try? ctx.save()
        }
        .onChange(of: appState.activeFilter) { _, newFilter in
            let ids = visiblePRs(filter: newFilter).map(\.id)
            appState.selectedPRID = SelectionReconcile.next(previous: appState.selectedPRID, in: ids)
        }
    }

    // MARK: - Filter predicates

    private func matches(_ pr: PullRequest, filter: MailFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .awaitingMe:
            return TodoHelpers.ballInMyCourt(pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        case .open:
            return pr.state == .open
                && TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt).open > 0
        case .mentions:
            return pr.mentionHint != nil
        case .mine:
            return pr.author.login == viewerLogin && pr.state == .open
        case .done:
            let counts = TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
            return pr.state == .open && counts.total > 0 && counts.open == 0
        case .recent:
            return pr.state == .merged
        }
    }

    private func visiblePRs(filter: MailFilter) -> [PullRequest] {
        prs.filter { matches($0, filter: filter) }
           .sorted(by: ballInMyCourtFirst)
    }

    private func ballInMyCourtFirst(_ a: PullRequest, _ b: PullRequest) -> Bool {
        let aw = TodoHelpers.ballInMyCourt(a, viewerLogin: viewerLogin, lastSeenAt: a.lastSeenAt) ? 0 : 1
        let bw = TodoHelpers.ballInMyCourt(b, viewerLogin: viewerLogin, lastSeenAt: b.lastSeenAt) ? 0 : 1
        if aw != bw { return aw < bw }
        return a.updatedAt > b.updatedAt
    }

    private func pillCounts() -> [MailFilter: Int] {
        var c: [MailFilter: Int] = [:]
        for filter in MailFilter.allCases {
            c[filter] = prs.filter { matches($0, filter: filter) }.count
        }
        return c
    }
}
```

Key changes:
- Filter predicates are inline (no `MailFilter.section` lookups).
- Sort applies `ballInMyCourt`-first.
- Selection write happens on `.onChange(of: appState.selectedPRID)` — sets `pr.lastReadAt = .now` on the main context.
- `MailRowView` now receives only `pr`, `isSelected`, `viewerLogin` (the `onToggleRead` parameter is gone since we don't toggle read state anymore — Task 13 updates the row to match).

- [ ] **Step 2: Verify build**

This step will likely fail because `MailRowView` still has the old signature. The next task fixes it. Run the build to confirm the only outstanding error is in `MailRowView`:

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:" | head -5
```
Expected: errors referencing `MailRowView`'s `onToggleRead` parameter mismatch.

- [ ] **Step 3: Stage the change but don't commit yet**

Hold off committing until Task 13 lands so we don't have a broken commit. Move on to Task 13.

---

## Task 13: Rewrite `MailRowView` + drop `isUnread` + delete `UnreadDot`

**Files:**
- Modify: `PRTracker/Views/Mail/MailRowView.swift`
- Modify: `PRTracker/Models/PullRequest.swift` (remove `isUnread` computed)
- Delete: `PRTracker/Views/Mail/UnreadDot.swift`
- Delete: `PRTrackerTests/Mail/PullRequestReadStateTests.swift`

- [ ] **Step 1: Rewrite `MailRowView`**

Open `PRTracker/Views/Mail/MailRowView.swift`. Replace its contents with:

```swift
import SwiftUI

struct MailRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let viewerLogin: String

    @State private var hover = false

    private var todoCounts: TodoCounts {
        TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    private var awaitingMe: Bool {
        TodoHelpers.ballInMyCourt(pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
    }

    private var fullyResolved: Bool {
        pr.state == .open && todoCounts.total > 0 && todoCounts.open == 0
    }

    private var bucket: Section? {
        if pr.state == .merged { return .recent }
        if awaitingMe { return .attention }
        if pr.author.login == viewerLogin && pr.state == .open { return .mine }
        if pr.mentionHint != nil { return .mentions }
        return .involved
    }

    private var laneColor: Color { (bucket?.lane.color) ?? Tokens.textFaint }

    private var titleWeight: Font.Weight {
        if awaitingMe { return .bold }
        if fullyResolved || pr.state == .merged { return .medium }
        return .semibold
    }

    private var dimRow: Bool {
        if isSelected { return false }
        if pr.state == .merged { return true }
        if fullyResolved { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Priority rail
            Rectangle()
                .fill(laneColor)
                .frame(width: 3)
                .opacity(awaitingMe ? 1 : (dimRow ? 0.5 : 0.85))
                .frame(maxHeight: .infinity)

            TodoRing(done: todoCounts.done, total: todoCounts.total, size: 24, state: ringState)

            VStack(alignment: .leading, spacing: 4) {
                topLine
                bottomLine
                if let hint = preview, !dimRow {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.textMuted)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
        .padding(.bottom, 11)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(Rectangle().fill(Tokens.hairline).frame(height: 0.5), alignment: .bottom)
        .opacity(dimRow ? 0.55 : 1.0)
        .onHover { hover = $0 }
    }

    private var ringState: TodoRing.RingState {
        if todoCounts.total == 0 { return .empty }
        if todoCounts.open == 0 { return .allResolved }
        if awaitingMe { return .awaitingMe }
        return .waiting
    }

    private var rowBackground: Color {
        if isSelected { return Tokens.rowSelect }
        if hover { return Tokens.rowHover }
        return .clear
    }

    private var topLine: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(pr.title)
                .font(.system(size: 13, weight: titleWeight))
                .foregroundStyle(isSelected ? Tokens.accentText : Tokens.text)
                .tracking(-0.05)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(RelativeTimeFormatter.short(pr.updatedAt))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Tokens.textFaint)
                .lineLimit(1)
        }
    }

    private var bottomLine: some View {
        HStack(spacing: 6) {
            AvatarView(user: pr.author, size: 15)
            Text(pr.author.name ?? pr.author.login)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
                .lineLimit(1)
            Text("·").foregroundStyle(Tokens.textFaint)
            Text("#\(pr.number)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Tokens.textFaint)
            Spacer(minLength: 0)
            statusChip
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch chipKind {
        case .merged:
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.merge").font(.system(size: 11).weight(.semibold))
                Text("Merged").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Lane.recent.color)
        case .caughtUp:
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.system(size: 10).weight(.bold))
                Text("Caught up").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Tokens.approved)
        case .forMe(let count):
            HStack(spacing: 4) {
                Circle().fill(Tokens.accent).frame(width: 5, height: 5)
                Text("\(count) for me").font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(Tokens.accent)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Tokens.accentBg, in: Capsule())
        case .waiting:
            Text("waiting on others")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Tokens.textMuted)
        case .none:
            EmptyView()
        }
    }

    private enum ChipKind { case merged, caughtUp, forMe(Int), waiting, none }

    private var chipKind: ChipKind {
        if pr.state == .merged { return .merged }
        if fullyResolved { return .caughtUp }
        if awaitingMe { return .forMe(todoCounts.openMessages) }
        if todoCounts.total > 0 { return .waiting }
        return .none
    }

    /// Preview line: first open non-mine message body, prefixed with the author's first name.
    private var preview: String? {
        let threads = TodoHelpers.threads(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt)
        for thread in threads where !TodoHelpers.isResolved(thread) {
            for msg in thread.messages where !msg.isMine && !msg.isDone {
                let firstName = (msg.actor.name ?? msg.actor.login).split(separator: " ").first.map(String.init)
                    ?? msg.actor.login
                return "\(firstName): \(msg.body)"
            }
        }
        return pr.attentionHint
    }
}
```

- [ ] **Step 2: Drop `isUnread` computed property + delete files**

Open `PRTracker/Models/PullRequest.swift`. Remove the entire `isUnread` computed property block:

```swift
    /// A PR is unread iff it's never been read, or its `updatedAt` is newer than the last read time.
    var isUnread: Bool {
        guard let lastReadAt else { return true }
        return updatedAt > lastReadAt
    }
```

Delete the row-style UnreadDot and the now-stale test file:

```bash
cd /Users/mblackmon/code/PRTracker
git rm PRTracker/Views/Mail/UnreadDot.swift
git rm PRTrackerTests/Mail/PullRequestReadStateTests.swift
```

- [ ] **Step 3: Verify build + tests**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: both succeed.

If you see errors referencing `pr.isUnread`, navigate to the offending file (likely `MenuBarContentView.swift`) — fix it in the next task. If the build fails ONLY in `MenuBarContentView.swift`, proceed to Task 14.

- [ ] **Step 4: Commit combined Tasks 11+12+13**

These three tasks are tightly coupled. Commit them together to keep every commit green:

```bash
cd /Users/mblackmon/code/PRTracker
git add -A
git commit -m "$(cat <<'EOF'
feat(mail): TodoRing source-list row, new filter set, drop isUnread + UnreadDot

Replaces the unread dot + read/unread fade with a 24pt TodoRing + status
chip (Merged / Caught up / N for me / waiting on others). The Awaiting-me
pill draws the eye via accent tinting. Filter predicates inlined into
MailListView. PullRequest.isUnread computed property dropped; UnreadDot
and PullRequestReadStateTests deleted.
EOF
)"
```

---

## Task 14: Minimal `MenuBarContentView` patch

**Files:**
- Modify: `PRTracker/Views/MenuBar/MenuBarContentView.swift`

The menubar dropdown likely references `pr.isUnread` and `UnreadDot`. Patch minimally — keep menubar layout but switch to using todo state.

- [ ] **Step 1: Identify usages**

```bash
cd /Users/mblackmon/code/PRTracker
grep -n "isUnread\|UnreadDot" PRTracker/Views/MenuBar/MenuBarContentView.swift
```

- [ ] **Step 2: Replace `pr.isUnread` references**

Open `PRTracker/Views/MenuBar/MenuBarContentView.swift`. For each line referencing `pr.isUnread`, replace with a computed "PR has open todos" inline:

```swift
// Replace usages like:
//   pr.isUnread
// With:
//   prHasOpenTodos(pr)
```

Then add a helper near the top of the struct (or wherever local helpers live):

```swift
    @Query private var viewerStates: [ViewerState]
    private var viewerLogin: String { viewerStates.first?.viewer?.login ?? "" }

    private func prHasOpenTodos(_ pr: PullRequest) -> Bool {
        TodoHelpers.todoCounts(for: pr, viewerLogin: viewerLogin, lastSeenAt: pr.lastSeenAt).open > 0
    }
```

For any `UnreadDot(on: ...)` usage, remove it. The menubar row stays — it just loses that indicator. The priority rail and title remain.

- [ ] **Step 3: Verify build**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run tests**

```bash
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -3
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/MenuBar/MenuBarContentView.swift
git commit -m "feat(menubar): swap isUnread reference for todo-open count; drop UnreadDot usage"
```

---

## Task 15: `FilterPillBar` — Awaiting-me accent treatment

**Files:**
- Modify: `PRTracker/Views/Mail/FilterPillBar.swift`

- [ ] **Step 1: Update the pill rendering**

Open `PRTracker/Views/Mail/FilterPillBar.swift`. Find the per-pill view builder. The `awaitingMe` pill, when count > 0 AND inactive, uses accent-tinted background + accent foreground + weight 700. When active, accent fill + white text.

Update the pill rendering to:

```swift
@ViewBuilder
private func pill(_ filter: MailFilter) -> some View {
    let isActive = (filter == active)
    let count = counts[filter] ?? 0
    let isAwaitingMe = (filter == .awaitingMe && count > 0)

    let bg: Color = {
        if isActive {
            return isAwaitingMe ? Tokens.accent : Tokens.text
        }
        if isAwaitingMe { return Tokens.accentBg }
        return Tokens.cardBg
    }()

    let fg: Color = {
        if isActive { return .white }
        if isAwaitingMe { return Tokens.accent }
        return Tokens.text
    }()

    let weight: Font.Weight = isAwaitingMe ? .bold : .semibold

    Button { active = filter } label: {
        HStack(spacing: 5) {
            if let dot = filter.dotColor {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(filter.label).font(.system(size: 11.5, weight: weight))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(isActive ? .white.opacity(0.85) : (isAwaitingMe ? Tokens.accent : Tokens.textMuted))
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
        .overlay(Capsule().stroke(isActive ? .clear : Tokens.border, lineWidth: 0.5))
    }
    .buttonStyle(.plain)
}
```

The outer ScrollView + sticky-header logic stays as-is.

- [ ] **Step 2: Build + manual smoke**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

Run the app. Confirm the "Awaiting me" pill is accent-tinted when count > 0 and inactive; when active, it's accent fill + white.

- [ ] **Step 3: Commit**

```bash
cd /Users/mblackmon/code/PRTracker
git add PRTracker/Views/Mail/FilterPillBar.swift
git commit -m "feat(mail): accent-tinted Awaiting-me pill when count > 0"
```

---

## Task 16: Update `Classifier.bucketFor` to use `ballInMyCourt`

**Files:**
- Modify: `PRTracker/Sync/Classifier.swift`

`MailRowView` already uses its own inline `bucket` derivation, so this task is optional — but the spec calls for consolidating. Audit whether `Classifier.bucketFor` is referenced anywhere else; if so, update it. If not, this task is a no-op.

- [ ] **Step 1: Audit usage**

```bash
cd /Users/mblackmon/code/PRTracker
grep -rn "bucketFor\|Classifier\." PRTracker --include='*.swift' | head -20
```

If `bucketFor` is only used by the now-rewritten `MailRowView`, skip this task entirely. The classifier-section grouping in the OLD `MailListView` is also gone (replaced by inline predicates), so `Classifier.section(...)` may be unused now too.

If `Classifier.section(...)` is no longer called anywhere, leave the function in place (it's still consistent), but note the dead-code status.

- [ ] **Step 2: If anything still calls bucketFor, update it**

If a caller exists, update it to:

```swift
static func bucketFor(pr: PullRequest, viewerLogin: String, lastSeenAt: Date?) -> Section? {
    if pr.state == .merged { return .recent }
    if TodoHelpers.ballInMyCourt(pr, viewerLogin: viewerLogin, lastSeenAt: lastSeenAt) { return .attention }
    if pr.reviewers.contains(where: { $0.user.login == viewerLogin && $0.state == .pending }) { return .review }
    if pr.mentionHint != nil { return .mentions }
    if pr.author.login == viewerLogin && pr.state == .open { return .mine }
    return .involved
}
```

If no caller exists, skip.

- [ ] **Step 3: Build + commit (if changes were made)**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
```
If changes were made:
```bash
git add PRTracker/Sync/Classifier.swift
git commit -m "refactor(sync): bucketFor uses TodoHelpers.ballInMyCourt"
```
Otherwise skip the commit.

---

## Task 17: Final smoke + tests

**Files:** none

- [ ] **Step 1: Full test suite**

```bash
cd /Users/mblackmon/code/PRTracker
xcodebuild -project PRTracker.xcodeproj -scheme PRTracker -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 2: Manual smoke**

Run the app and walk through:
- Open a PR with multiple review-comment threads. Confirm OPEN section renders one card per thread.
- Tap a checkbox on a non-mine message. The message dims with strikethrough; thread's status tile updates `done/totalNonMine`; the summary bar's ring + percentage update; the source-list TodoRing updates with the smooth animation.
- Tap "Resolve" footer on an open thread. All non-mine messages flip done, the thread migrates to RESOLVED, RESOLVED's count badge increments.
- Expand RESOLVED, confirm the resolved thread is collapsed by default but visible.
- Expand ACTIVITY at the bottom. Confirm commits, opened event, status events appear with the old TimelineEventRow rendering.
- Source list: confirm row tap updates `lastSeenAt` (you can verify indirectly by checking that NEW tags disappear from messages older than the tap).
- Filter `Awaiting me`: only PRs with open non-mine messages (or `changesRequested` on viewer's own PRs) appear. Pill is accent-tinted with count.
- Filter `Open`: open PRs with any unresolved threads.
- Filter `Done`: open PRs with all threads resolved (and at least one thread).
- Filter `Merged`: only merged PRs appear; their source-list rows are dimmed.
- Right rail: no "Mark as unread" button. Reviewers / CI / Labels / Changes still render.

- [ ] **Step 3: Verify git log is clean**

```bash
cd /Users/mblackmon/code/PRTracker
git log --oneline main..HEAD | head -25
```
Expected: 12–15 commits with the per-task messages above.

- [ ] **Step 4: Optional PR creation**

```bash
gh pr create --base main --title "Todo-first detail view" --body "$(cat <<'EOF'
## Summary
- Replaces read/unread with per-message isDone on TimelineEvent + ReviewComment
- New detail body: OPEN / RESOLVED / ACTIVITY sections of ThreadCards
- Source-list rows get a TodoRing + status chip; filters become Awaiting me / Open / Done / Mentions / Mine / Merged
- Drops Mark-as-read/unread button, UnreadDot, PullRequest.isUnread, MailFilter.review / .involved
- lastReadAt column repurposed as lastSeenAt (updated on row selection only)
- Spec: docs/superpowers/specs/2026-05-22-todo-completion-design.md
- Plan: docs/superpowers/plans/2026-05-22-todo-completion.md

## Test plan
- [x] Unit tests pass (xcodebuild test) including new TodoHelpersTests (~12 cases)
- [ ] Manual smoke: thread checkbox + Resolve + filter switching + activity expansion

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
(Skip if you'd rather merge locally.)

---

## Self-Review

**Spec coverage:**
- §3 architecture: covered by Tasks 1–10
- §4 data model (`isDone` fields + `lastSeenAt` accessor + remove `isUnread`): Tasks 1, 9, 13
- §5 derived thread model + helpers: Task 2 + TodoHelpersTests
- §6 filter set + bucketing: Tasks 11, 12, 16
- §7.1 source-list row: Task 13
- §7.2 filter pill bar: Task 15
- §7.3 TodoSummaryBar: Task 6 + integration in Task 10
- §7.4 ThreadsView body: Tasks 7, 8, 10
- §7.5 TodoRing: Task 3
- §7.6 ThreadCard: Task 5
- §7.7 TodoCheckbox: Task 3
- §7.8 drop right-rail unread button: Task 10
- §8 behavior summary: covered across tasks
- §9 notifications compatibility: orthogonal, no changes needed
- §10 testing: Task 2 covers TodoHelpers; manual smoke covered by Task 17
- §11 risks: addressed during implementation

**Placeholder scan:** No "TBD" / "implement later" patterns. Each step shows complete code.

**Type consistency:**
- `TodoHelpers.isResolved` / `hasNew` / `openCount` / `todoCounts` / `ballInMyCourt` signatures stable across all consumers (Tasks 2, 5, 8, 10, 12, 13, 14).
- `Thread` / `ThreadMessage` / `TodoCounts` value types defined in Task 2, used by Tasks 5, 8, 10, 13.
- `MailRowView` parameter signature change: `pr, isSelected, viewerLogin` (Task 12 + 13 land together to avoid intermediate broken state).
- `DetailRightRail(pr:)` — `onToggleReadState` removed (Task 10).
- `MailDetailHeader(pr:isRefreshing:lastUpdatedAt:onRefresh:todoCounts:)` — `todoCounts` parameter added (Task 10).
- `TodoRing.RingState` enum cases consistent across Tasks 3, 6, 13.

No issues found.
