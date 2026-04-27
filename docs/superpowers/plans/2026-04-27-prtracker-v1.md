# PR Tracker v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS PR tracker that pulls a single GitHub repo's PRs, shows them in a priority-grouped feed with drill-in detail view, surfaces an attention count in a menu-bar item, and tracks per-timeline-event seen/unseen state locally.

**Architecture:** Four layers — App shell (scenes + lifecycle), SwiftUI views, Domain (`GitHubClient` actor, `SyncCoordinator`, `@ModelActor` `SyncActor`, `Classifier` pure functions, `Keychain` wrapper), Persistence (SwiftData `@Model` types, with the cached PR list AS the persisted source of truth — every fetch is an upsert). Read/unread is stored per-`TimelineEvent` via `isSeen: Bool`.

**Tech Stack:** macOS 26, SwiftUI, SwiftData, Swift Testing (`@Test` / `#expect`), Security framework (Keychain), `SMAppService` (launch-at-login), no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-04-27-prtracker-design.md`

**Test command:** `xcodebuild test -scheme PRTracker -destination 'platform=macOS'`
**Single-test command:** `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/<TestSuite>/<testName>`

---

## Phase 0 — Project hygiene

### Task 1: Reset shell, set deployment target, create folder structure

**Files:**
- Delete: `PRTracker/Item.swift`
- Replace: `PRTracker/ContentView.swift`, `PRTracker/PRTrackerApp.swift`
- Create: `PRTracker/App/`, `PRTracker/Models/`, `PRTracker/GitHub/`, `PRTracker/GitHub/Fixtures/`, `PRTracker/Sync/`, `PRTracker/Keychain/`, `PRTracker/DesignSystem/`, `PRTracker/Views/Feed/`, `PRTracker/Views/Detail/`, `PRTracker/Views/MenuBar/`, `PRTracker/Views/Onboarding/`, `PRTracker/Views/Settings/`
- Create: `PRTrackerTests/Classifier/`, `PRTrackerTests/GitHub/`, `PRTrackerTests/GitHub/Fixtures/`, `PRTrackerTests/Sync/`, `PRTrackerTests/Keychain/`, `PRTrackerTests/Helpers/`
- Modify: `PRTracker.xcodeproj/project.pbxproj` — set `MACOSX_DEPLOYMENT_TARGET = 26.0` for both build configurations of both targets

- [ ] **Step 1: Delete Item.swift and create folder skeleton**

```bash
cd /Users/mblackmon/code/PRTracker
rm PRTracker/Item.swift
mkdir -p PRTracker/{App,Models,GitHub/Fixtures,Sync,Keychain,DesignSystem,Views/Feed,Views/Detail,Views/MenuBar,Views/Onboarding,Views/Settings}
mkdir -p PRTrackerTests/{Classifier,GitHub/Fixtures,Sync,Keychain,Helpers}
```

- [ ] **Step 2: Replace `PRTrackerApp.swift` with a minimal placeholder that compiles**

Move to `PRTracker/App/PRTrackerApp.swift`:

```swift
import SwiftUI

@main
struct PRTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PR Tracker — under construction")
                .frame(minWidth: 960, minHeight: 600)
        }
    }
}
```

Delete the old `PRTracker/PRTrackerApp.swift` and `PRTracker/ContentView.swift`.

- [ ] **Step 3: Set deployment target to macOS 26**

In Xcode (or by editing `project.pbxproj` directly): for both `PRTracker` and `PRTrackerTests`, set `MACOSX_DEPLOYMENT_TARGET = 26.0` for both Debug and Release configurations.

- [ ] **Step 4: Build to confirm the project compiles with the new layout**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: reset shell, set macOS 26 target, scaffold folders"
```

---

## Phase 1 — Design system

### Task 2: Color tokens, lane colors, typography, density

**Files:**
- Create: `PRTracker/DesignSystem/Tokens.swift`
- Create: `PRTracker/DesignSystem/LaneColors.swift`
- Create: `PRTracker/DesignSystem/Typography.swift`
- Create: `PRTracker/DesignSystem/Density.swift`

- [ ] **Step 1: Write `Tokens.swift` — semantic colors that resolve via dynamic provider**

```swift
import SwiftUI

enum Tokens {
    static let windowBg       = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 0.11, alpha: 1) : .white })
    static let panelBg        = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 0.11, alpha: 0.85) : .init(white: 0.96, alpha: 0.85) })
    static let contentBg      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 0.11, alpha: 1) : .white })
    static let sidebarBg      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 0.17, alpha: 0.55) : .init(red: 0.82, green: 0.88, blue: 0.96, alpha: 0.45) })
    static let border         = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.10) : .init(white: 0, alpha: 0.08) })
    static let borderStrong   = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.16) : .init(white: 0, alpha: 0.14) })
    static let hairline       = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.06) : .init(white: 0, alpha: 0.06) })
    static let text           = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.92) : .init(white: 0, alpha: 0.88) })
    static let textMuted      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.60) : .init(white: 0, alpha: 0.56) })
    static let textFaint      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 1, alpha: 0.40) : .init(white: 0, alpha: 0.38) })
    static let accent         = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.04, green: 0.52, blue: 1.00, alpha: 1) : .init(red: 0.00, green: 0.48, blue: 1.00, alpha: 1) })
    static let accentBg       = Color(.dynamicProvider { _ in .init(red: 0, green: 0.48, blue: 1, alpha: 0.10) })
    static let approved       = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.25, green: 0.73, blue: 0.31, alpha: 1) : .init(red: 0.10, green: 0.50, blue: 0.22, alpha: 1) })
    static let changes        = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.97, green: 0.32, blue: 0.29, alpha: 1) : .init(red: 0.81, green: 0.13, blue: 0.18, alpha: 1) })
    static let pending        = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.82, green: 0.60, blue: 0.13, alpha: 1) : .init(red: 0.60, green: 0.40, blue: 0, alpha: 1) })
    static let commented      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.55, green: 0.58, blue: 0.62, alpha: 1) : .init(red: 0.43, green: 0.47, blue: 0.51, alpha: 1) })
    static let cardBg         = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(white: 0.17, alpha: 1) : .white })
    static let unreadDot      = Color(.dynamicProvider { $0.userInterfaceStyle == .dark ? .init(red: 0.04, green: 0.52, blue: 1.00, alpha: 1) : .init(red: 0.00, green: 0.48, blue: 1.00, alpha: 1) })
    static let newHighlight   = Color(.dynamicProvider { _ in .init(red: 0, green: 0.48, blue: 1, alpha: 0.06) })
}
```

- [ ] **Step 2: Write `LaneColors.swift`**

```swift
import SwiftUI

enum Lane: String, CaseIterable {
    case attention, review, mine, involved, mentions, recent

    var color: Color {
        switch self {
        case .attention: Color(red: 1.00, green: 0.58, blue: 0.00)
        case .review:    Color(red: 0.04, green: 0.52, blue: 1.00)
        case .mine:      Color(red: 0.19, green: 0.72, blue: 0.30)
        case .involved:  Color(red: 0.56, green: 0.56, blue: 0.58)
        case .mentions:  Color(red: 0.75, green: 0.35, blue: 0.95)
        case .recent:    Color(red: 0.51, green: 0.31, blue: 0.87)
        }
    }

    var label: String {
        switch self {
        case .attention: "Needs my attention"
        case .review:    "Needs my review"
        case .mine:      "My open PRs"
        case .involved:  "Others' PRs"
        case .mentions:  "Mentions"
        case .recent:    "Recently merged"
        }
    }
}
```

- [ ] **Step 3: Write `Typography.swift`**

```swift
import SwiftUI

extension View {
    func cardTitle(unread: Bool) -> some View {
        font(.system(size: 13.5, weight: unread ? .semibold : .medium))
    }
    func sectionHeader() -> some View {
        font(.system(size: 12.5, weight: .bold))
    }
    func metaText() -> some View {
        font(.system(size: 11.5, weight: .medium))
    }
    func microText() -> some View {
        font(.system(size: 10.5))
    }
    func monoText() -> some View {
        font(.system(size: 10.5, design: .monospaced))
    }
}
```

- [ ] **Step 4: Write `Density.swift`**

```swift
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
```

- [ ] **Step 5: Build to confirm**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/DesignSystem
git commit -m "feat: add design system tokens, lane colors, typography, density"
```

---

## Phase 2 — Models

### Task 3: Enums and User model

**Files:**
- Create: `PRTracker/Models/Enums.swift`
- Create: `PRTracker/Models/User.swift`

- [ ] **Step 1: Write `Enums.swift`**

```swift
import Foundation

enum PRState: String, Codable { case open, closed, merged, draft }
enum ReviewState: String, Codable { case pending = "PENDING", approved = "APPROVED", changesRequested = "CHANGES_REQUESTED", commented = "COMMENTED" }
enum Mergeable: String, Codable { case clean = "CLEAN", conflicts = "CONFLICTS", unknown = "UNKNOWN", blocked = "BLOCKED" }
enum CIState: String, Codable { case pass, fail, running, pending }
enum EventType: String, Codable { case commit, opened, review, comment, status, merged, closed, assigned, labeled }
```

- [ ] **Step 2: Write `User.swift`**

```swift
import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var login: String
    var name: String?
    var avatarURL: URL?

    init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Models
git commit -m "feat: add enums and User model"
```

### Task 4: Repo and PullRequest models

**Files:**
- Create: `PRTracker/Models/Repo.swift`
- Create: `PRTracker/Models/PullRequest.swift`

- [ ] **Step 1: Write `Repo.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Repo {
    @Attribute(.unique) var id: String   // "owner/name"
    var owner: String
    var name: String
    var lastFetchedAt: Date?
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \PullRequest.repo)
    var pullRequests: [PullRequest] = []

    init(owner: String, name: String, isActive: Bool = false) {
        self.id = "\(owner)/\(name)"
        self.owner = owner
        self.name = name
        self.isActive = isActive
    }
}
```

- [ ] **Step 2: Write `PullRequest.swift`**

```swift
import Foundation
import SwiftData

@Model
final class PullRequest {
    @Attribute(.unique) var id: String   // GitHub node ID
    var number: Int
    var title: String
    var stateRaw: String
    var branchHead: String
    var branchBase: String
    var headSha: String
    var additions: Int
    var deletions: Int
    var changedFiles: Int
    var openedAt: Date
    var updatedAt: Date
    var mergedAt: Date?
    var reviewStateRaw: String?
    var mergeableRaw: String
    var ciPass: Int
    var ciFail: Int
    var ciRunning: Int
    var ciPending: Int
    var ciTotal: Int
    var attentionHint: String?
    var mentionHint: String?
    var involvedHint: String?

    var author: User
    var repo: Repo

    @Relationship(deleteRule: .cascade, inverse: \TimelineEvent.pullRequest)
    var timeline: [TimelineEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \Reviewer.pr)
    var reviewers: [Reviewer] = []
    @Relationship(deleteRule: .cascade, inverse: \Label.pr)
    var labels: [Label] = []
    @Relationship(deleteRule: .cascade, inverse: \CIRun.pr)
    var ciChecks: [CIRun] = []

    var state: PRState {
        get { PRState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }
    var reviewState: ReviewState? {
        get { reviewStateRaw.flatMap(ReviewState.init(rawValue:)) }
        set { reviewStateRaw = newValue?.rawValue }
    }
    var mergeable: Mergeable {
        get { Mergeable(rawValue: mergeableRaw) ?? .unknown }
        set { mergeableRaw = newValue.rawValue }
    }

    /// A PR is unread iff any timeline event is unseen.
    var isUnread: Bool { timeline.contains { !$0.isSeen } }

    init(id: String, number: Int, title: String, state: PRState, branchHead: String, branchBase: String, headSha: String, openedAt: Date, updatedAt: Date, author: User, repo: Repo) {
        self.id = id
        self.number = number
        self.title = title
        self.stateRaw = state.rawValue
        self.branchHead = branchHead
        self.branchBase = branchBase
        self.headSha = headSha
        self.additions = 0; self.deletions = 0; self.changedFiles = 0
        self.openedAt = openedAt; self.updatedAt = updatedAt
        self.mergeableRaw = Mergeable.unknown.rawValue
        self.ciPass = 0; self.ciFail = 0; self.ciRunning = 0; self.ciPending = 0; self.ciTotal = 0
        self.author = author
        self.repo = repo
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED. (Compiler will complain about missing `TimelineEvent`, `Reviewer`, `Label`, `CIRun` — that's expected; we add them next.)

> Note: If the build fails on the inverse-relationship references, leave the relationships uninitialized (no `inverse:`) for now and we'll fix in Task 5 when those types exist. Or comment them out and uncomment after Task 5.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Models
git commit -m "feat: add Repo and PullRequest models"
```

### Task 5: TimelineEvent, Reviewer, Label, CIRun

**Files:**
- Create: `PRTracker/Models/TimelineEvent.swift`
- Create: `PRTracker/Models/Reviewer.swift`
- Create: `PRTracker/Models/Label.swift`
- Create: `PRTracker/Models/CIRun.swift`

- [ ] **Step 1: Write `TimelineEvent.swift`**

```swift
import Foundation
import SwiftData

@Model
final class TimelineEvent {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var at: Date
    var actor: User?
    var body: String?
    var sha: String?
    var reviewStateRaw: String?
    /// Local-only — never overwritten by sync.
    var isSeen: Bool

    var pullRequest: PullRequest

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .comment }
        set { typeRaw = newValue.rawValue }
    }
    var reviewState: ReviewState? {
        get { reviewStateRaw.flatMap(ReviewState.init(rawValue:)) }
        set { reviewStateRaw = newValue?.rawValue }
    }

    init(id: String, type: EventType, at: Date, pullRequest: PullRequest, actor: User? = nil, body: String? = nil, sha: String? = nil, reviewState: ReviewState? = nil, isSeen: Bool = false) {
        self.id = id
        self.typeRaw = type.rawValue
        self.at = at
        self.pullRequest = pullRequest
        self.actor = actor
        self.body = body
        self.sha = sha
        self.reviewStateRaw = reviewState?.rawValue
        self.isSeen = isSeen
    }
}
```

- [ ] **Step 2: Write `Reviewer.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Reviewer {
    var user: User
    var stateRaw: String
    var pr: PullRequest

    var state: ReviewState {
        get { ReviewState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(user: User, state: ReviewState, pr: PullRequest) {
        self.user = user
        self.stateRaw = state.rawValue
        self.pr = pr
    }
}
```

- [ ] **Step 3: Write `Label.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Label {
    var name: String
    var pr: PullRequest

    init(name: String, pr: PullRequest) {
        self.name = name
        self.pr = pr
    }
}
```

- [ ] **Step 4: Write `CIRun.swift`**

```swift
import Foundation
import SwiftData

@Model
final class CIRun {
    var name: String
    var stateRaw: String
    var durationSeconds: Int?
    var pr: PullRequest

    var state: CIState {
        get { CIState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(name: String, state: CIState, pr: PullRequest, durationSeconds: Int? = nil) {
        self.name = name
        self.stateRaw = state.rawValue
        self.pr = pr
        self.durationSeconds = durationSeconds
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add PRTracker/Models
git commit -m "feat: add TimelineEvent, Reviewer, Label, CIRun models"
```

### Task 6: ViewerState and HTTPCache

**Files:**
- Create: `PRTracker/Models/ViewerState.swift`
- Create: `PRTracker/Models/HTTPCache.swift`

- [ ] **Step 1: Write `ViewerState.swift`**

```swift
import Foundation
import SwiftData

@Model
final class ViewerState {
    var viewer: User?
    var activeRepoID: String?
    var refreshIntervalMinutes: Int
    var launchAtLoginEnabled: Bool

    init(viewer: User? = nil, activeRepoID: String? = nil, refreshIntervalMinutes: Int = 2, launchAtLoginEnabled: Bool = false) {
        self.viewer = viewer
        self.activeRepoID = activeRepoID
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
```

- [ ] **Step 2: Write `HTTPCache.swift`**

```swift
import Foundation
import SwiftData

@Model
final class HTTPCache {
    @Attribute(.unique) var url: String
    var etag: String?
    var lastModified: String?
    var fetchedAt: Date

    init(url: String, etag: String? = nil, lastModified: String? = nil, fetchedAt: Date = .now) {
        self.url = url
        self.etag = etag
        self.lastModified = lastModified
        self.fetchedAt = fetchedAt
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/Models
git commit -m "feat: add ViewerState and HTTPCache models"
```

---

## Phase 3 — Test infrastructure

### Task 7: ModelContainer test helper

**Files:**
- Create: `PRTrackerTests/Helpers/ModelContainerHelper.swift`

- [ ] **Step 1: Write the helper**

```swift
import Foundation
import SwiftData
@testable import PRTracker

enum TestContainer {
    /// Returns an in-memory ModelContainer with all app schemas registered.
    static func make() throws -> ModelContainer {
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
```

- [ ] **Step 2: Sanity test**

Create `PRTrackerTests/Helpers/ModelContainerHelperTests.swift`:

```swift
import Testing
import SwiftData
@testable import PRTracker

@Suite struct ModelContainerHelperTests {
    @Test func canCreateInMemoryContainer() throws {
        let container = try TestContainer.make()
        let context = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        context.insert(repo)
        try context.save()
        #expect(repo.id == "oreilly/spark-ios")
    }
}
```

- [ ] **Step 3: Run the test**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/ModelContainerHelperTests -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTrackerTests/Helpers
git commit -m "test: add in-memory ModelContainer helper"
```

---

## Phase 4 — Keychain

### Task 8: Keychain wrapper for the PAT

**Files:**
- Create: `PRTracker/Keychain/Keychain.swift`
- Create: `PRTrackerTests/Keychain/KeychainTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import PRTracker

@Suite struct KeychainTests {
    @Test func saveLoadDelete() {
        let kc = Keychain(service: "com.prtracker.github.test", account: "pat")
        kc.delete()
        #expect(kc.load() == nil)
        kc.save("ghp_test_token")
        #expect(kc.load() == "ghp_test_token")
        kc.save("ghp_replaced")
        #expect(kc.load() == "ghp_replaced")
        kc.delete()
        #expect(kc.load() == nil)
    }
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/KeychainTests -quiet`
Expected: BUILD FAILED with "cannot find 'Keychain' in scope".

- [ ] **Step 3: Implement `Keychain.swift`**

```swift
import Foundation
import Security

struct Keychain {
    let service: String
    let account: String

    init(service: String = "com.prtracker.github", account: String = "pat") {
        self.service = service
        self.account = account
    }

    func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/KeychainTests -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Keychain PRTrackerTests/Keychain
git commit -m "feat(keychain): add PAT wrapper around Security framework"
```

---

## Phase 5 — GitHub network layer

### Task 9: GitHubError and DTOs

**Files:**
- Create: `PRTracker/GitHub/GitHubError.swift`
- Create: `PRTracker/GitHub/DTOs.swift`

- [ ] **Step 1: Write `GitHubError.swift`**

```swift
import Foundation

enum GitHubError: Error, Equatable {
    case unauthorized
    case repoNotFound
    case rateLimited(resetAt: Date)
    case network(message: String)
    case decoding(message: String)
    case notModified
}
```

- [ ] **Step 2: Write `DTOs.swift` (initial set)**

```swift
import Foundation

struct UserDTO: Decodable, Equatable {
    let login: String
    let name: String?
    let avatar_url: URL?
}

struct LabelDTO: Decodable, Equatable {
    let name: String
}

struct PullRequestDTO: Decodable {
    let node_id: String
    let number: Int
    let title: String
    let state: String                 // "open" | "closed"
    let draft: Bool
    let merged_at: Date?
    let created_at: Date
    let updated_at: Date
    let user: UserDTO
    let head: RefDTO
    let base: RefDTO
    let additions: Int?
    let deletions: Int?
    let changed_files: Int?
    let mergeable_state: String?
    let labels: [LabelDTO]
    let requested_reviewers: [UserDTO]?
}

struct RefDTO: Decodable {
    let ref: String
    let sha: String
}

struct CheckRunDTO: Decodable {
    let name: String
    let status: String                // "queued" | "in_progress" | "completed"
    let conclusion: String?           // "success" | "failure" | "neutral" | "cancelled" | "timed_out" | "action_required"
    let started_at: Date?
    let completed_at: Date?
}

struct CheckRunsResponseDTO: Decodable {
    let total_count: Int
    let check_runs: [CheckRunDTO]
}

struct ReviewDTO: Decodable {
    let id: Int
    let user: UserDTO
    let state: String                 // "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "PENDING"
    let body: String?
    let submitted_at: Date?
}

struct CommentDTO: Decodable {
    let id: Int
    let user: UserDTO
    let body: String
    let created_at: Date
    let updated_at: Date
}

struct TimelineItemDTO: Decodable {
    let event: String                 // "commented" | "reviewed" | "committed" | "labeled" | ...
    let id: Int?
    let node_id: String?
    let actor: UserDTO?
    let created_at: Date?
    let body: String?
    let sha: String?
    let state: String?                // for review events
}

struct NotificationDTO: Decodable {
    let id: String
    let reason: String                // "mention" | "review_requested" | "comment" | ...
    let updated_at: Date
    let subject: SubjectDTO

    struct SubjectDTO: Decodable {
        let title: String
        let url: String
        let type: String              // "PullRequest" | "Issue"
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/GitHub
git commit -m "feat(github): add error type and REST DTOs"
```

### Task 10: URLProtocol stub harness

**Files:**
- Create: `PRTrackerTests/GitHub/StubURLProtocol.swift`

- [ ] **Step 1: Write the stub**

```swift
import Foundation

final class StubURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    /// URL.absoluteString → Stub
    static var responses: [String: Stub] = [:]
    /// Captured requests (for assertions)
    static var captured: [URLRequest] = []

    static func reset() {
        responses.removeAll()
        captured.removeAll()
    }

    static func register(url: String, status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        responses[url] = Stub(status: status, headers: headers, body: body)
    }

    static func register(url: String, status: Int = 200, headers: [String: String] = [:], json: String) {
        register(url: url, status: status, headers: headers, body: json.data(using: .utf8)!)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured.append(request)
        guard let url = request.url?.absoluteString,
              let stub = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension URLSessionConfiguration {
    static var stubbed: URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        return c
    }
}
```

- [ ] **Step 2: Sanity test**

Append to `PRTrackerTests/GitHub/StubURLProtocolTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct StubURLProtocolTests {
    @Test func roundtrip() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.register(url: "https://example.com/x", status: 200, json: #"{"ok":true}"#)
        let session = URLSession(configuration: .stubbed)
        let (data, resp) = try await session.data(from: URL(string: "https://example.com/x")!)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == #"{"ok":true}"#)
    }
}
```

- [ ] **Step 3: Run the test**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/StubURLProtocolTests -quiet`
Expected: TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PRTrackerTests/GitHub
git commit -m "test: add URLProtocol stub harness"
```

### Task 11: GitHubClient skeleton + validate()

**Files:**
- Create: `PRTracker/GitHub/Endpoints.swift`
- Create: `PRTracker/GitHub/GitHubClient.swift`
- Create: `PRTrackerTests/GitHub/Fixtures/user.json`
- Create: `PRTrackerTests/GitHub/GitHubClientTests.swift`

- [ ] **Step 1: Capture a fixture for `/user`**

Create `PRTrackerTests/GitHub/Fixtures/user.json`:

```json
{
  "login": "alex.chen",
  "id": 100,
  "name": "Alex Chen",
  "avatar_url": "https://avatars.githubusercontent.com/u/100"
}
```

Add the file to the `PRTrackerTests` target in Xcode (drag into the Fixtures group, ensure "Copy items if needed" and target membership for tests).

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite(.serialized) struct GitHubClientTests {
    private func makeClient(token: String? = "ghp_test") -> GitHubClient {
        GitHubClient(
            session: URLSession(configuration: .stubbed),
            tokenProvider: { token }
        )
    }
    private func fixture(_ name: String) -> Data {
        // Xcode test bundle — find the resource by walking from the test bundle.
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
    private final class BundleToken {}

    @Test func validateReturnsUser() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.register(
            url: "https://api.github.com/user",
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: fixture("user")
        )
        let user = try await makeClient().validate()
        #expect(user.login == "alex.chen")
        #expect(user.name == "Alex Chen")
    }

    @Test func validateUnauthorizedThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.register(url: "https://api.github.com/user", status: 401, body: Data())
        do {
            _ = try await makeClient().validate()
            Issue.record("expected throw")
        } catch let e as GitHubError {
            #expect(e == .unauthorized)
        } catch { Issue.record("wrong error type: \(error)") }
    }
}
```

> Note: ensure each fixture JSON file has Target Membership for `PRTrackerTests` (Xcode → File Inspector). The `BundleToken` class above is just a hook to find the test bundle's resources at runtime.

- [ ] **Step 3: Run test, verify it fails**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/GitHubClientTests -quiet`
Expected: BUILD FAILED with "cannot find 'GitHubClient' in scope".

- [ ] **Step 4: Implement `Endpoints.swift`**

```swift
import Foundation

struct RepoRef: Equatable, Sendable {
    let owner: String
    let name: String
    var slug: String { "\(owner)/\(name)" }
}

enum Endpoints {
    static let base = URL(string: "https://api.github.com")!

    static var user: URL { base.appending(path: "/user") }

    static func pulls(_ r: RepoRef, state: String, perPage: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/pulls"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        return c.url!
    }
    static func checkRuns(_ r: RepoRef, ref: String) -> URL { base.appending(path: "/repos/\(r.slug)/commits/\(ref)/check-runs") }
    static var notificationsParticipating: URL {
        var c = URLComponents(url: base.appending(path: "/notifications"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "participating", value: "true")]
        return c.url!
    }
    static func timeline(_ r: RepoRef, number: Int) -> URL {
        var c = URLComponents(url: base.appending(path: "/repos/\(r.slug)/issues/\(number)/timeline"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        return c.url!
    }
    static func reviews(_ r: RepoRef, number: Int) -> URL { base.appending(path: "/repos/\(r.slug)/pulls/\(number)/reviews") }
    static func issueComments(_ r: RepoRef, number: Int) -> URL { base.appending(path: "/repos/\(r.slug)/issues/\(number)/comments") }
    static func repo(_ r: RepoRef) -> URL { base.appending(path: "/repos/\(r.slug)") }
}
```

- [ ] **Step 5: Implement `GitHubClient.swift` with `validate()`**

```swift
import Foundation

actor GitHubClient {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?

    init(session: URLSession, tokenProvider: @escaping @Sendable () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    private static let isoDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PRTracker/1.0", forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider() {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return r
    }

    private func send<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let req = request(url)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitHubError.network(message: error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.network(message: "non-HTTP response") }
        switch http.statusCode {
        case 200..<300:
            do { return try Self.isoDecoder.decode(T.self, from: data) }
            catch { throw GitHubError.decoding(message: String(describing: error)) }
        case 401: throw GitHubError.unauthorized
        case 404: throw GitHubError.repoNotFound
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let resetStr = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetEpoch = TimeInterval(resetStr) {
                throw GitHubError.rateLimited(resetAt: Date(timeIntervalSince1970: resetEpoch))
            }
            throw GitHubError.network(message: "403 forbidden")
        default: throw GitHubError.network(message: "HTTP \(http.statusCode)")
        }
    }

    func validate() async throws -> UserDTO {
        try await send(Endpoints.user, as: UserDTO.self)
    }
}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/GitHubClientTests -quiet`
Expected: TEST SUCCEEDED (both `validateReturnsUser` and `validateUnauthorizedThrows`).

- [ ] **Step 7: Commit**

```bash
git add PRTracker/GitHub PRTrackerTests/GitHub
git commit -m "feat(github): add client skeleton with validate() endpoint and tests"
```

### Task 12: Add remaining endpoints (pulls, check-runs, notifications, timeline, reviews, comments)

**Files:**
- Modify: `PRTracker/GitHub/GitHubClient.swift`
- Create fixtures: `pulls_open.json`, `pulls_closed.json`, `check_runs.json`, `notifications.json`, `timeline_5107.json`, `reviews_5107.json`, `comments_5107.json`
- Modify: `PRTrackerTests/GitHub/GitHubClientTests.swift`

- [ ] **Step 1: Capture minimal fixtures**

Create `PRTrackerTests/GitHub/Fixtures/pulls_open.json` (truncated example):

```json
[
  {
    "node_id": "PR_5107",
    "number": 5107,
    "title": "Fetch badge data when credlyID is missing",
    "state": "open",
    "draft": false,
    "merged_at": null,
    "created_at": "2026-04-21T09:14:00Z",
    "updated_at": "2026-04-23T10:47:00Z",
    "user": {"login": "alex.chen", "id": 100, "name": null, "avatar_url": "https://example.com/a"},
    "head": {"ref": "alex/guac-6450-badge-fallback", "sha": "d4f91ee"},
    "base": {"ref": "main", "sha": "deadbeef"},
    "additions": 142,
    "deletions": 38,
    "changed_files": 7,
    "mergeable_state": "blocked",
    "labels": [{"name": "bug"}, {"name": "badges"}],
    "requested_reviewers": [{"login": "danieldraper", "id": 101, "name": null, "avatar_url": null}]
  }
]
```

Create stubs (single empty array `[]` is fine to start) for `pulls_closed.json`, `notifications.json`, `reviews_5107.json`, `comments_5107.json`. For `check_runs.json`:

```json
{"total_count": 12, "check_runs": [
  {"name": "Build", "status": "completed", "conclusion": "success", "started_at": null, "completed_at": null},
  {"name": "ASC: TestFlight upload", "status": "in_progress", "conclusion": null, "started_at": null, "completed_at": null}
]}
```

For `timeline_5107.json`, copy the relevant subset from the spec's reference data.

Ensure all are added to the `PRTrackerTests` target.

- [ ] **Step 2: Add the public methods to `GitHubClient`**

Append to `GitHubClient.swift`:

```swift
extension GitHubClient {
    func listOpenPRs(repo: RepoRef) async throws -> [PullRequestDTO] {
        try await send(Endpoints.pulls(repo, state: "open", perPage: 50), as: [PullRequestDTO].self)
    }
    func listRecentlyMerged(repo: RepoRef, limit: Int) async throws -> [PullRequestDTO] {
        try await send(Endpoints.pulls(repo, state: "closed", perPage: limit), as: [PullRequestDTO].self)
    }
    func checkRuns(repo: RepoRef, ref: String) async throws -> CheckRunsResponseDTO {
        try await send(Endpoints.checkRuns(repo, ref: ref), as: CheckRunsResponseDTO.self)
    }
    func participatingNotifications() async throws -> [NotificationDTO] {
        try await send(Endpoints.notificationsParticipating, as: [NotificationDTO].self)
    }
    func timeline(repo: RepoRef, number: Int) async throws -> [TimelineItemDTO] {
        try await send(Endpoints.timeline(repo, number: number), as: [TimelineItemDTO].self)
    }
    func reviews(repo: RepoRef, number: Int) async throws -> [ReviewDTO] {
        try await send(Endpoints.reviews(repo, number: number), as: [ReviewDTO].self)
    }
    func issueComments(repo: RepoRef, number: Int) async throws -> [CommentDTO] {
        try await send(Endpoints.issueComments(repo, number: number), as: [CommentDTO].self)
    }
}
```

- [ ] **Step 3: Add tests for each new method**

Append to `GitHubClientTests.swift`:

```swift
extension GitHubClientTests {
    @Test func listOpenPRsDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.register(
            url: "https://api.github.com/repos/oreilly/spark-ios/pulls?state=open&sort=updated&direction=desc&per_page=50",
            status: 200, body: fixture("pulls_open"))
        let prs = try await makeClient().listOpenPRs(repo: RepoRef(owner: "oreilly", name: "spark-ios"))
        #expect(prs.count == 1)
        #expect(prs[0].number == 5107)
        #expect(prs[0].title.contains("Fetch badge"))
    }

    @Test func checkRunsDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.register(
            url: "https://api.github.com/repos/oreilly/spark-ios/commits/d4f91ee/check-runs",
            status: 200, body: fixture("check_runs"))
        let r = try await makeClient().checkRuns(repo: RepoRef(owner: "oreilly", name: "spark-ios"), ref: "d4f91ee")
        #expect(r.total_count == 12)
        #expect(r.check_runs.count == 2)
    }

    @Test func rateLimitedThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.register(
            url: "https://api.github.com/user",
            status: 403,
            headers: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": "1900000000"
            ],
            body: Data())
        do { _ = try await makeClient().validate(); Issue.record("expected throw") }
        catch let e as GitHubError {
            if case .rateLimited(let when) = e {
                #expect(when.timeIntervalSince1970 == 1900000000)
            } else { Issue.record("wrong case: \(e)") }
        } catch { Issue.record("wrong type: \(error)") }
    }
}
```

- [ ] **Step 4: Run all GitHubClient tests, verify they pass**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/GitHubClientTests -quiet`
Expected: 5 tests succeed.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/GitHub PRTrackerTests/GitHub
git commit -m "feat(github): add pulls, check-runs, notifications, timeline, reviews, comments endpoints"
```

### Task 13: ETag / 304 conditional-request support

**Files:**
- Modify: `PRTracker/GitHub/GitHubClient.swift`
- Modify: `PRTrackerTests/GitHub/GitHubClientTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `GitHubClientTests.swift`:

```swift
extension GitHubClientTests {
    @Test func notModifiedThrowsNotModified() async {
        StubURLProtocol.reset()
        StubURLProtocol.register(url: "https://api.github.com/user", status: 304, body: Data())
        do {
            _ = try await makeClient().validate()
            Issue.record("expected throw")
        } catch let e as GitHubError {
            #expect(e == .notModified)
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func sendsIfNoneMatchWhenEtagProvided() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.register(
            url: "https://api.github.com/user", status: 200,
            headers: ["ETag": "W/\"abc\""], body: fixture("user"))
        let client = GitHubClient(
            session: URLSession(configuration: .stubbed),
            tokenProvider: { "ghp_test" },
            etagProvider: { _ in "W/\"abc\"" },
            etagSink: { _,_ in }
        )
        _ = try await client.validate()
        let lastReq = StubURLProtocol.captured.last!
        #expect(lastReq.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
    }
}
```

- [ ] **Step 2: Update `GitHubClient` initializer signature and `send`**

```swift
actor GitHubClient {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let etagProvider: @Sendable (URL) -> String?
    private let etagSink: @Sendable (URL, String?) -> Void

    init(session: URLSession,
         tokenProvider: @escaping @Sendable () -> String?,
         etagProvider: @escaping @Sendable (URL) -> String? = { _ in nil },
         etagSink: @escaping @Sendable (URL, String?) -> Void = { _,_ in }) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.etagProvider = etagProvider
        self.etagSink = etagSink
    }

    // ... isoDecoder ...

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PRTracker/1.0", forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider() {
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag = etagProvider(url) {
            r.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return r
    }

    private func send<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
        let req = request(url)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw GitHubError.network(message: error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw GitHubError.network(message: "non-HTTP response") }
        switch http.statusCode {
        case 304: throw GitHubError.notModified
        case 200..<300:
            etagSink(url, http.value(forHTTPHeaderField: "ETag"))
            do { return try Self.isoDecoder.decode(T.self, from: data) }
            catch { throw GitHubError.decoding(message: String(describing: error)) }
        case 401: throw GitHubError.unauthorized
        case 404: throw GitHubError.repoNotFound
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let resetStr = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetEpoch = TimeInterval(resetStr) {
                throw GitHubError.rateLimited(resetAt: Date(timeIntervalSince1970: resetEpoch))
            }
            throw GitHubError.network(message: "403 forbidden")
        default: throw GitHubError.network(message: "HTTP \(http.statusCode)")
        }
    }
}
```

> Note: existing tests use the simpler `init(session:tokenProvider:)`. The default values on `etagProvider`/`etagSink` keep them working unchanged.

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/GitHubClientTests -quiet`
Expected: all GitHubClient tests pass.

- [ ] **Step 4: Commit**

```bash
git add PRTracker/GitHub PRTrackerTests/GitHub
git commit -m "feat(github): conditional-request (ETag) support in GitHubClient"
```

---

## Phase 6 — Domain logic

### Task 14: Classifier — section assignment and hint synthesis

**Files:**
- Create: `PRTracker/Sync/Classifier.swift`
- Create: `PRTrackerTests/Classifier/ClassifierTests.swift`

- [ ] **Step 1: Write the failing tests (full matrix)**

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct ClassifierTests {
    private let me = "alex.chen"
    private let now = Date(timeIntervalSince1970: 1745_500_000) // 2026-04-24

    private func pr(
        id: String = "PR_1", number: Int = 1, author: String = "iris",
        state: String = "open", merged_at: Date? = nil,
        requested: [String] = [], reviewers: [(String, String)] = [],
        ciFail: Int = 0, ciRunning: Int = 0,
        commenters: [String] = [], updated: Date? = nil
    ) -> ClassifierInput.PR {
        ClassifierInput.PR(
            id: id, number: number, authorLogin: author, state: state,
            mergedAt: merged_at, requestedReviewerLogins: requested,
            reviewerStates: reviewers, ciFail: ciFail, ciRunning: ciRunning,
            commenterLogins: commenters, updatedAt: updated ?? now.addingTimeInterval(-3600)
        )
    }

    @Test func mineWithNoReviews() {
        let p = pr(author: me)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .mine)
    }

    @Test func mineWithFailingCIBecomesAttention() {
        let p = pr(author: me, ciFail: 2)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }

    @Test func mineWithChangesRequestedBecomesAttention() {
        let p = pr(author: me, reviewers: [("iris", "CHANGES_REQUESTED")])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }

    @Test func requestedReviewerNotYetReviewedIsReview() {
        let p = pr(author: "iris", requested: [me])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .review)
    }

    @Test func reviewerWhoApprovedIsInvolved() {
        let p = pr(author: "iris", reviewers: [(me, "APPROVED")])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .involved)
    }

    @Test func commenterIsInvolved() {
        let p = pr(author: "iris", commenters: [me])
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .involved)
    }

    @Test func mentionPRIsMention() {
        let p = pr(id: "PR_M", author: "iris")
        let mentioned: Set<String> = ["PR_M"]
        #expect(Classifier.section(for: p, viewer: me, mentions: mentioned, now: now) == .mentions)
    }

    @Test func mergedWithin7DaysIsRecent() {
        let p = pr(author: "iris", state: "closed", merged_at: now.addingTimeInterval(-3 * 86400))
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .recent)
    }

    @Test func mergedOlderThan7DaysIsNil() {
        let p = pr(author: "iris", state: "closed", merged_at: now.addingTimeInterval(-8 * 86400))
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == nil)
    }

    @Test func attentionWinsOverMine() {
        let p = pr(author: me, ciFail: 1)
        #expect(Classifier.section(for: p, viewer: me, mentions: [], now: now) == .attention)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/ClassifierTests -quiet`
Expected: BUILD FAILED ("cannot find 'Classifier' in scope").

- [ ] **Step 3: Implement `Classifier.swift`**

```swift
import Foundation

enum Section: String, CaseIterable, Equatable {
    case attention, review, mentions, mine, involved, recent
    var lane: Lane {
        switch self {
        case .attention: .attention
        case .review:    .review
        case .mentions:  .mentions
        case .mine:      .mine
        case .involved:  .involved
        case .recent:    .recent
        }
    }
}

enum ClassifierInput {
    struct PR {
        let id: String
        let number: Int
        let authorLogin: String
        let state: String         // "open" | "closed"
        let mergedAt: Date?
        let requestedReviewerLogins: [String]
        let reviewerStates: [(String, String)]   // (login, state)
        let ciFail: Int
        let ciRunning: Int
        let commenterLogins: [String]
        let updatedAt: Date
    }
}

enum Classifier {
    /// Returns the single section the PR belongs to, or `nil` if it's not in the feed at all.
    static func section(for pr: ClassifierInput.PR, viewer: String, mentions: Set<String>, now: Date) -> Section? {
        // Recent merged: closed + merged within 7 days
        if pr.state == "closed", let m = pr.mergedAt, now.timeIntervalSince(m) <= 7 * 86400 {
            return .recent
        }
        if pr.state == "closed" { return nil }

        let isAuthor = pr.authorLogin == viewer
        let someoneRequestedChanges = pr.reviewerStates.contains { $0.1 == "CHANGES_REQUESTED" }
        let ciHasFailures = pr.ciFail > 0
        let amRequestedReviewer = pr.requestedReviewerLogins.contains(viewer)
        let myReviewState = pr.reviewerStates.first(where: { $0.0 == viewer })?.1
        let didReview = myReviewState != nil
        let didComment = pr.commenterLogins.contains(viewer)
        let mentioned = mentions.contains(pr.id)

        // attention precedence: my PR with problems
        if isAuthor && (ciHasFailures || someoneRequestedChanges) { return .attention }

        // mentions
        if mentioned { return .mentions }

        // needs my review: requested reviewer who hasn't reviewed
        if amRequestedReviewer && !didReview { return .review }

        // mine
        if isAuthor { return .mine }

        // involved: I've reviewed or commented
        if didReview || didComment { return .involved }

        return nil
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/ClassifierTests -quiet`
Expected: 10 tests succeed.

- [ ] **Step 5: Add hint synthesis**

Append to `Classifier.swift`:

```swift
extension Classifier {
    static func attentionHint(for pr: ClassifierInput.PR) -> String? {
        if pr.ciFail > 0 { return "CI failed (\(pr.ciFail) check\(pr.ciFail == 1 ? "" : "s"))." }
        if pr.reviewerStates.contains(where: { $0.1 == "CHANGES_REQUESTED" }) {
            return "A reviewer requested changes."
        }
        return nil
    }
}
```

Add a smoke test:

```swift
extension ClassifierTests {
    @Test func attentionHintForCIFailure() {
        let p = pr(author: me, ciFail: 2)
        #expect(Classifier.attentionHint(for: p)?.contains("CI") == true)
    }
}
```

- [ ] **Step 6: Run, verify**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/ClassifierTests -quiet`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PRTracker/Sync PRTrackerTests/Classifier
git commit -m "feat(sync): Classifier with section assignment and hint synthesis"
```

### Task 15: SyncActor — upsert with isSeen preservation

**Files:**
- Create: `PRTracker/Sync/SyncActor.swift`
- Create: `PRTrackerTests/Sync/SyncActorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct SyncActorTests {
    private func setup() throws -> (ModelContainer, Repo) {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(repo)
        try ctx.save()
        return (container, repo)
    }

    private func samplePullDTO(number: Int = 5107, head: String = "d4f91ee") -> PullRequestDTO {
        let json = """
        {"node_id":"PR_\(number)","number":\(number),"title":"T","state":"open","draft":false,
         "merged_at":null,"created_at":"2026-04-21T09:14:00Z","updated_at":"2026-04-23T10:47:00Z",
         "user":{"login":"alex.chen","id":1,"name":null,"avatar_url":null},
         "head":{"ref":"alex/x","sha":"\(head)"},"base":{"ref":"main","sha":"deadbeef"},
         "additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean","labels":[],"requested_reviewers":[]}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try! d.decode(PullRequestDTO.self, from: json.data(using: .utf8)!)
    }

    @Test func upsertInsertsNewPR() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs.count == 1)
        #expect(prs[0].number == 5107)
        #expect(prs[0].author.login == "alex.chen")
    }

    @Test func upsertReusesUserByLogin() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO(number: 1), samplePullDTO(number: 2)], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let users = try ctx.fetch(FetchDescriptor<User>())
        #expect(users.count == 1)
        #expect(users[0].login == "alex.chen")
    }

    @Test func upsertPreservesIsSeenOnExistingTimelineEvent() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        // First sync — inserts PR + a timeline event
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        try await actor.upsertTimeline(prID: "PR_5107", items: [
            TimelineItemDTO(event: "commented", id: 1, node_id: "TE_1",
                            actor: UserDTO(login: "iris", name: nil, avatar_url: nil),
                            created_at: Date(timeIntervalSince1970: 1700_000_000),
                            body: "hi", sha: nil, state: nil)
        ])
        // Mark seen
        try await actor.setSeen(eventID: "TE_1", isSeen: true)
        // Second sync — same event reappears
        try await actor.upsertTimeline(prID: "PR_5107", items: [
            TimelineItemDTO(event: "commented", id: 1, node_id: "TE_1",
                            actor: UserDTO(login: "iris", name: nil, avatar_url: nil),
                            created_at: Date(timeIntervalSince1970: 1700_000_000),
                            body: "hi (edited)", sha: nil, state: nil)
        ])
        let ctx = ModelContext(container)
        let events = try ctx.fetch(FetchDescriptor<TimelineEvent>())
        #expect(events.count == 1)
        #expect(events[0].isSeen == true)
        #expect(events[0].body == "hi (edited)")
    }

    @Test func openPRMissingFromResponseIsClosed() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO()], inRepoID: repo.id)
        try await actor.upsertPullRequests([], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs.count == 1)
        #expect(prs[0].state == .closed)
    }

    @Test func newHeadShaClearsCIChecks() async throws {
        let (container, repo) = try setup()
        let actor = SyncActor(modelContainer: container)
        try await actor.upsertPullRequests([samplePullDTO(head: "sha1")], inRepoID: repo.id)
        try await actor.upsertCIChecks(prID: "PR_5107", dto: CheckRunsResponseDTO(
            total_count: 1, check_runs: [CheckRunDTO(name: "Build", status: "completed", conclusion: "success", started_at: nil, completed_at: nil)]))
        try await actor.upsertPullRequests([samplePullDTO(head: "sha2")], inRepoID: repo.id)
        let ctx = ModelContext(container)
        let prs = try ctx.fetch(FetchDescriptor<PullRequest>())
        #expect(prs[0].ciChecks.count == 0)
        #expect(prs[0].headSha == "sha2")
    }
}
```

- [ ] **Step 2: Run, verify failure**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/SyncActorTests -quiet`
Expected: BUILD FAILED ("cannot find 'SyncActor' in scope").

- [ ] **Step 3: Implement `SyncActor.swift`**

```swift
import Foundation
import SwiftData

@ModelActor
actor SyncActor {
    private func userBy(login: String, ctx: ModelContext) -> User? {
        let predicate = #Predicate<User> { $0.login == login }
        return try? ctx.fetch(FetchDescriptor<User>(predicate: predicate)).first
    }

    private func upsertUser(_ dto: UserDTO, ctx: ModelContext) -> User {
        if let existing = userBy(login: dto.login, ctx: ctx) {
            if let n = dto.name { existing.name = n }
            if let a = dto.avatar_url { existing.avatarURL = a }
            return existing
        }
        let u = User(login: dto.login, name: dto.name, avatarURL: dto.avatar_url)
        ctx.insert(u)
        return u
    }

    private func repoByID(_ id: String, ctx: ModelContext) -> Repo? {
        let predicate = #Predicate<Repo> { $0.id == id }
        return try? ctx.fetch(FetchDescriptor<Repo>(predicate: predicate)).first
    }

    private func prByID(_ id: String, ctx: ModelContext) -> PullRequest? {
        let predicate = #Predicate<PullRequest> { $0.id == id }
        return try? ctx.fetch(FetchDescriptor<PullRequest>(predicate: predicate)).first
    }

    func upsertPullRequests(_ dtos: [PullRequestDTO], inRepoID repoID: String) throws {
        let ctx = modelContext
        guard let repo = repoByID(repoID, ctx: ctx) else { return }

        let dtoIDs = Set(dtos.map(\.node_id))

        // Mark missing open PRs as closed
        let predicate = #Predicate<PullRequest> { $0.repo.id == repoID }
        let existing = (try? ctx.fetch(FetchDescriptor<PullRequest>(predicate: predicate))) ?? []
        for pr in existing where pr.state == .open && !dtoIDs.contains(pr.id) {
            pr.state = .closed
        }

        for dto in dtos {
            let author = upsertUser(dto.user, ctx: ctx)
            let pr: PullRequest
            if let existing = prByID(dto.node_id, ctx: ctx) {
                pr = existing
            } else {
                pr = PullRequest(
                    id: dto.node_id, number: dto.number, title: dto.title,
                    state: .open, branchHead: dto.head.ref, branchBase: dto.base.ref,
                    headSha: dto.head.sha, openedAt: dto.created_at, updatedAt: dto.updated_at,
                    author: author, repo: repo)
                ctx.insert(pr)
            }
            // server-owned fields
            pr.title = dto.title
            pr.author = author
            pr.branchHead = dto.head.ref
            pr.branchBase = dto.base.ref
            // Force-push detection
            if pr.headSha != dto.head.sha {
                pr.headSha = dto.head.sha
                for c in pr.ciChecks { ctx.delete(c) }
            }
            pr.additions = dto.additions ?? 0
            pr.deletions = dto.deletions ?? 0
            pr.changedFiles = dto.changed_files ?? 0
            pr.openedAt = dto.created_at
            pr.updatedAt = dto.updated_at
            pr.mergedAt = dto.merged_at
            if dto.draft { pr.state = .draft }
            else if dto.merged_at != nil { pr.state = .merged }
            else if dto.state == "open" { pr.state = .open }
            else { pr.state = .closed }
            pr.mergeable = dto.mergeable_state.flatMap { Mergeable(rawValue: $0.uppercased()) } ?? .unknown

            // Labels: replace
            for l in pr.labels { ctx.delete(l) }
            for ldto in dto.labels { ctx.insert(Label(name: ldto.name, pr: pr)) }

            // Reviewers: union of requested + existing review states (states from /reviews come later)
            for r in pr.reviewers { ctx.delete(r) }
            for ureq in dto.requested_reviewers ?? [] {
                let user = upsertUser(ureq, ctx: ctx)
                ctx.insert(Reviewer(user: user, state: .pending, pr: pr))
            }
        }

        repo.lastFetchedAt = .now
        try ctx.save()
    }

    func upsertCIChecks(prID: String, dto: CheckRunsResponseDTO) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        for c in pr.ciChecks { ctx.delete(c) }
        var pass = 0, fail = 0, running = 0, pending = 0
        for r in dto.check_runs {
            let state: CIState = {
                if r.status == "completed" {
                    switch r.conclusion {
                    case "success": return .pass
                    case "failure", "timed_out", "cancelled": return .fail
                    default: return .pass
                    }
                }
                if r.status == "in_progress" { return .running }
                return .pending
            }()
            switch state {
            case .pass: pass += 1; case .fail: fail += 1
            case .running: running += 1; case .pending: pending += 1
            }
            let dur: Int? = {
                guard let s = r.started_at, let e = r.completed_at else { return nil }
                return Int(e.timeIntervalSince(s))
            }()
            ctx.insert(CIRun(name: r.name, state: state, pr: pr, durationSeconds: dur))
        }
        pr.ciPass = pass; pr.ciFail = fail; pr.ciRunning = running; pr.ciPending = pending
        pr.ciTotal = dto.total_count
        try ctx.save()
    }

    func upsertTimeline(prID: String, items: [TimelineItemDTO]) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        // Index existing by id
        var byID: [String: TimelineEvent] = [:]
        for e in pr.timeline { byID[e.id] = e }

        var seenIDs: Set<String> = []
        for dto in items {
            guard let id = dto.node_id ?? dto.id.map({ "TI_\($0)" }) else { continue }
            seenIDs.insert(id)
            let typ: EventType = {
                switch dto.event {
                case "commented": return .comment
                case "reviewed": return .review
                case "committed": return .commit
                case "labeled": return .labeled
                case "merged": return .merged
                case "closed": return .closed
                case "assigned": return .assigned
                default: return .status
                }
            }()
            let actor = dto.actor.map { upsertUser($0, ctx: ctx) }
            let revState = dto.state.flatMap { ReviewState(rawValue: $0) }
            if let e = byID[id] {
                e.body = dto.body ?? e.body
                e.actor = actor ?? e.actor
                if let at = dto.created_at { e.at = at }
                if let s = dto.sha { e.sha = s }
                e.reviewState = revState ?? e.reviewState
                // isSeen preserved deliberately
            } else {
                let e = TimelineEvent(
                    id: id, type: typ, at: dto.created_at ?? .now,
                    pullRequest: pr, actor: actor,
                    body: dto.body, sha: dto.sha, reviewState: revState, isSeen: false)
                ctx.insert(e)
            }
        }
        // Delete events absent from a full timeline response
        for e in pr.timeline where !seenIDs.contains(e.id) {
            ctx.delete(e)
        }
        try ctx.save()
    }

    func setSeen(eventID: String, isSeen: Bool) throws {
        let ctx = modelContext
        let predicate = #Predicate<TimelineEvent> { $0.id == eventID }
        guard let e = try ctx.fetch(FetchDescriptor<TimelineEvent>(predicate: predicate)).first else { return }
        e.isSeen = isSeen
        try ctx.save()
    }

    func setSeenForPR(prID: String, isSeen: Bool) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx) else { return }
        for e in pr.timeline { e.isSeen = isSeen }
        try ctx.save()
    }

    func setSeenUpTo(prID: String, throughEventID eventID: String) throws {
        let ctx = modelContext
        guard let pr = prByID(prID, ctx: ctx),
              let target = pr.timeline.first(where: { $0.id == eventID }) else { return }
        for e in pr.timeline where e.at <= target.at { e.isSeen = true }
        try ctx.save()
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -only-testing:PRTrackerTests/SyncActorTests -quiet`
Expected: 5 tests succeed.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Sync PRTrackerTests/Sync
git commit -m "feat(sync): SyncActor with upsert preserving isSeen, force-push CI clearing"
```

### Task 16: SyncCoordinator — refresh orchestration, timer, lifecycle

**Files:**
- Create: `PRTracker/Sync/SyncCoordinator.swift`

(No tests here — `SyncCoordinator` is a thin orchestrator over already-tested pieces. Manual smoke test through the running app suffices.)

- [ ] **Step 1: Implement `SyncCoordinator.swift`**

```swift
import Foundation
import SwiftData
import AppKit

@Observable
final class SyncCoordinator {
    private let client: GitHubClient
    private let actor: SyncActor
    private let modelContainer: ModelContainer

    var isSyncing: Bool = false
    var lastSyncAt: Date?
    var lastSyncError: GitHubError?

    private var task: Task<Void, Never>?
    private var foregroundIntervalSec: TimeInterval = 120
    private var backgroundIntervalSec: TimeInterval = 600
    private var isBackgroundMode = false

    init(client: GitHubClient, actor: SyncActor, modelContainer: ModelContainer) {
        self.client = client
        self.actor = actor
        self.modelContainer = modelContainer
        observeLifecycle()
    }

    func setIntervals(foregroundMinutes: Int) {
        foregroundIntervalSec = TimeInterval(max(1, foregroundMinutes) * 60)
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in await self?.loop() }
    }

    func stop() {
        task?.cancel(); task = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await refresh()
            let interval = isBackgroundMode ? backgroundIntervalSec : foregroundIntervalSec
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func refresh() async {
        if isSyncing { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let ctx = ModelContext(modelContainer)
        guard let active = (try? ctx.fetch(FetchDescriptor<Repo>(predicate: #Predicate { $0.isActive == true })))?.first else {
            return
        }
        let ref = RepoRef(owner: active.owner, name: active.name)
        let repoID = active.id

        do {
            async let openPRs = client.listOpenPRs(repo: ref)
            async let recent = client.listRecentlyMerged(repo: ref, limit: 20)
            async let notifs = client.participatingNotifications()
            let (open, closed, _) = try await (openPRs, recent, notifs)
            let allPRs = open + closed
            try await actor.upsertPullRequests(allPRs, inRepoID: repoID)

            // Throttled per-PR check-runs
            await withTaskGroup(of: Void.self) { group in
                let semaphore = AsyncSemaphore(value: 5)
                for pr in open {
                    group.addTask { [actor, client] in
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }
                        do {
                            let dto = try await client.checkRuns(repo: ref, ref: pr.head.sha)
                            try await actor.upsertCIChecks(prID: pr.node_id, dto: dto)
                        } catch is GitHubError {
                            // ignore per-PR failures; toolbar surfaces aggregate errors only
                        } catch { }
                    }
                }
            }

            lastSyncAt = .now
        } catch let e as GitHubError {
            lastSyncError = e
        } catch {
            lastSyncError = .network(message: error.localizedDescription)
        }
    }

    private func observeLifecycle() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            self?.isBackgroundMode = !win.occlusionState.contains(.visible)
        }
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.start()
        }
    }
}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(value: Int) { self.value = value }
    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if !waiters.isEmpty { waiters.removeFirst().resume() } else { value += 1 }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Sync
git commit -m "feat(sync): SyncCoordinator with refresh loop, lifecycle, semaphore"
```

---

## Phase 7 — App state, root view, onboarding

### Task 17: AppState

**Files:**
- Create: `PRTracker/App/AppState.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import SwiftData

@Observable
final class AppState {
    var activeSection: Section? = nil          // nil == "All"
    var selectedPRID: String? = nil
    var rateLimitRemaining: Int? = nil
    var rateLimitResetAt: Date? = nil
}
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
git add PRTracker/App
git commit -m "feat(app): AppState observable"
```

### Task 18: RootView and OnboardingView

**Files:**
- Create: `PRTracker/App/RootView.swift`
- Create: `PRTracker/Views/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Write `OnboardingView.swift`**

```swift
import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var ctx
    @State private var token: String = ""
    @State private var ownerRepo: String = ""
    @State private var error: String?
    @State private var isValidating = false
    @State private var stage: Stage = .token

    enum Stage { case token, repo }

    let keychain: Keychain
    let client: GitHubClient
    var onReady: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up PR Tracker").font(.title2).fontWeight(.semibold)
            switch stage {
            case .token:
                Text("Paste a GitHub Personal Access Token (classic or fine-grained) with `repo` scope.")
                SecureField("ghp_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Button("Validate") { Task { await validateToken() } }
                    .disabled(token.isEmpty || isValidating)
            case .repo:
                Text("Which repository do you want to track?")
                TextField("owner/name", text: $ownerRepo)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                Button("Save") { Task { await saveRepo() } }
                    .disabled(!ownerRepo.contains("/") || isValidating)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .padding(28)
        .frame(width: 520, height: 320)
    }

    private func validateToken() async {
        isValidating = true; defer { isValidating = false }
        keychain.save(token)
        do {
            let user = try await client.validate()
            // Persist viewer
            let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first ?? {
                let new = ViewerState(); ctx.insert(new); return new
            }()
            let u = User(login: user.login, name: user.name, avatarURL: user.avatar_url)
            ctx.insert(u)
            vs.viewer = u
            try ctx.save()
            stage = .repo; error = nil
        } catch {
            keychain.delete()
            self.error = "Token rejected. Check the value and try again."
        }
    }

    private func saveRepo() async {
        isValidating = true; defer { isValidating = false }
        let parts = ownerRepo.split(separator: "/")
        guard parts.count == 2 else { error = "Use owner/name format."; return }
        let owner = String(parts[0]); let name = String(parts[1])
        let id = "\(owner)/\(name)"
        let existing = (try? ctx.fetch(FetchDescriptor<Repo>())) ?? []
        for r in existing { r.isActive = false }
        let repo: Repo
        if let already = existing.first(where: { $0.id == id }) {
            already.isActive = true; repo = already
        } else {
            repo = Repo(owner: owner, name: name, isActive: true)
            ctx.insert(repo)
        }
        let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first
        vs?.activeRepoID = repo.id
        try? ctx.save()
        onReady()
    }
}
```

- [ ] **Step 2: Write `RootView.swift`**

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    var body: some View {
        let signedIn = (keychain.load() != nil) && (viewerStates.first?.viewer != nil) && (viewerStates.first?.activeRepoID != nil)
        Group {
            if signedIn {
                MainView()
                    .task { coordinator.start() }
            } else {
                OnboardingView(keychain: keychain, client: client, onReady: {
                    coordinator.start()
                })
            }
        }
    }
}

/// Placeholder until Task 22 wires the real MainView.
struct MainView: View {
    var body: some View { Text("MainView placeholder") }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

- [ ] **Step 4: Commit**

```bash
git add PRTracker/App PRTracker/Views/Onboarding
git commit -m "feat(app): RootView routing + OnboardingView (token + repo)"
```

---

## Phase 8 — Feed UI

### Task 19: StatusGauge (bars style with shimmer)

**Files:**
- Create: `PRTracker/Views/Feed/StatusGauge.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct StatusGauge: View {
    enum Stage { case review, ci, merge }
    enum StageState { case ok, bad, running, inactive }

    let review: StageState
    let ci: StageState
    let merge: StageState

    var body: some View {
        HStack(spacing: 6) {
            bar(.review, review)
            bar(.ci, ci)
            bar(.merge, merge)
        }
    }

    private func bar(_ stage: Stage, _ state: StageState) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(barFill(state)).frame(width: 34, height: 4)
                if state == .running {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)
                        Capsule()
                            .fill(.white.opacity(0.55))
                            .frame(width: 10, height: 4)
                            .offset(x: -10 + phase * 44)
                            .clipShape(Capsule())
                            .mask(Capsule().frame(width: 34, height: 4))
                    }
                }
            }
            Text(label(stage))
                .font(.system(size: 9.5).weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(state == .inactive ? Tokens.textFaint : labelColor(state))
        }
    }

    private func barFill(_ s: StageState) -> Color {
        switch s {
        case .ok: Tokens.approved
        case .bad: Tokens.changes
        case .running: Tokens.pending
        case .inactive: Tokens.hairline
        }
    }
    private func labelColor(_ s: StageState) -> Color {
        switch s {
        case .ok: Tokens.approved
        case .bad: Tokens.changes
        case .running: Tokens.pending
        case .inactive: Tokens.textFaint
        }
    }
    private func label(_ s: Stage) -> String {
        switch s { case .review: "REVIEW"; case .ci: "CI"; case .merge: "MERGE" }
    }
}

#Preview {
    HStack(spacing: 24) {
        StatusGauge(review: .bad, ci: .running, merge: .inactive)
        StatusGauge(review: .ok, ci: .ok, merge: .ok)
        StatusGauge(review: .inactive, ci: .ok, merge: .running)
    }.padding(40).background(Tokens.contentBg)
}
```

- [ ] **Step 2: Build, eyeball preview**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Open `StatusGauge.swift` in Xcode and verify the preview renders three gauges with the running bar shimmering.

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Views/Feed/StatusGauge.swift
git commit -m "feat(ui): StatusGauge with bars style and shimmer"
```

### Task 20: PRCardView

**Files:**
- Create: `PRTracker/Views/Feed/PRCardView.swift`

- [ ] **Step 1: Implement**

```swift
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
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add PRTracker/Views/Feed/PRCardView.swift
git commit -m "feat(ui): PRCardView with lane rail, unread styling, gauge, hint bubble"
```

### Task 21: FeedSection, FeedToolbar, Sidebar

**Files:**
- Create: `PRTracker/Views/Feed/FeedSection.swift`
- Create: `PRTracker/Views/Feed/FeedToolbar.swift`
- Create: `PRTracker/Views/Feed/Sidebar.swift`

- [ ] **Step 1: Implement `FeedSection.swift`**

```swift
import SwiftUI

struct FeedSection<Content: View>: View {
    let lane: Lane
    let title: String
    let count: Int
    @Binding var collapsed: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10).weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(Tokens.textMuted)
                    RoundedRectangle(cornerRadius: 2).fill(lane.color).frame(width: 8, height: 8)
                    Text(title).sectionHeader().foregroundStyle(Tokens.text)
                    if count > 0 { CountPill(count: count, tint: lane.color) }
                    Spacer()
                }
            }.buttonStyle(.plain)
            if !collapsed { content() }
        }
    }
}

struct CountPill: View {
    let count: Int
    let tint: Color
    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5).weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
```

- [ ] **Step 2: Implement `FeedToolbar.swift`**

```swift
import SwiftUI

struct FeedToolbar: View {
    let repoSlug: String
    let lastSyncAt: Date?
    let isSyncing: Bool
    let lastError: GitHubError?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PR Tracker").font(.system(size: 14).weight(.semibold))
                Text(repoSlug).font(.system(size: 11.5)).foregroundStyle(Tokens.textMuted)
            }
            Spacer()
            statusChip
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(isSyncing)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    @ViewBuilder private var statusChip: some View {
        if isSyncing {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Refreshing…").microText() }
        } else if let lastError {
            Text(errorMessage(lastError)).microText().foregroundStyle(Tokens.changes)
        } else if let t = lastSyncAt {
            HStack(spacing: 6) { Image(systemName: "clock"); Text("Updated \(RelativeTimeFormatter.short(t))").microText() }
                .foregroundStyle(Tokens.textMuted)
        } else {
            EmptyView()
        }
    }

    private func errorMessage(_ e: GitHubError) -> String {
        switch e {
        case .unauthorized: "Token rejected"
        case .repoNotFound: "Repo not found"
        case .rateLimited: "Rate-limited"
        case .network: "Sync failed — click refresh"
        case .decoding: "Schema error"
        case .notModified: "Up to date"
        }
    }
}
```

- [ ] **Step 3: Implement `Sidebar.swift`**

```swift
import SwiftUI

struct Sidebar: View {
    let viewer: User?
    let repoSlug: String
    let counts: [Section: Int]
    @Binding var selection: Section?
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repoSlug).font(.system(size: 12).weight(.semibold))
                Spacer()
            }.padding(12)

            List(selection: $selection) {
                row(label: "All", icon: "tray", section: nil)
                ForEach(Section.allCases, id: \.self) { s in
                    row(label: s.lane.label, lane: s.lane, section: s)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 8) {
                if let v = viewer { AvatarView(user: v, size: 22); Text(v.name ?? v.login).metaText() }
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }.padding(12)
        }
        .background(Tokens.sidebarBg)
        .frame(width: 220)
    }

    @ViewBuilder
    private func row(label: String, icon: String? = nil, lane: Lane? = nil, section: Section?) -> some View {
        HStack(spacing: 8) {
            if let lane { RoundedRectangle(cornerRadius: 1).fill(lane.color).frame(width: 4, height: 14) }
            if let icon { Image(systemName: icon).foregroundStyle(Tokens.textMuted) }
            Text(label).font(.system(size: 12.5))
            Spacer()
            let displayCount = section.flatMap { counts[$0] } ?? counts.values.reduce(0, +)
            if displayCount > 0 { CountPill(count: displayCount, tint: Tokens.textMuted) }
        }
        .tag(section)
    }
}
```

> Note: the "All" row's count is the sum across all sections; per-section rows use the per-key count.

- [ ] **Step 4: Build**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Feed
git commit -m "feat(ui): FeedSection, FeedToolbar, Sidebar"
```

### Task 22: FeedView (compose)

**Files:**
- Create: `PRTracker/Views/Feed/FeedView.swift`
- Modify: `PRTracker/App/RootView.swift`

- [ ] **Step 1: Implement `FeedView.swift`**

```swift
import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\PullRequest.updatedAt, order: .reverse)])
    private var prs: [PullRequest]
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]

    let coordinator: SyncCoordinator
    @State private var collapsed: [Section: Bool] = [:]
    @State private var mentionedIDs: Set<String> = []  // populated on refresh; live-updated by NotificationCenter or actor

    var body: some View {
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)
        let viewerLogin = viewer?.login ?? ""
        let buckets = grouped(viewerLogin: viewerLogin)
        let activeSection = appState.activeSection

        VStack(spacing: 0) {
            FeedToolbar(
                repoSlug: repo?.id ?? "",
                lastSyncAt: coordinator.lastSyncAt,
                isSyncing: coordinator.isSyncing,
                lastError: coordinator.lastSyncError,
                onRefresh: { Task { await coordinator.refresh() } })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let activeSection {
                        ForEach(buckets[activeSection] ?? []) { pr in
                            PRCardView(pr: pr, lane: activeSection.lane, hint: hint(for: pr, section: activeSection))
                                .onTapGesture { appState.selectedPRID = pr.id }
                        }
                    } else {
                        ForEach(Section.allCases, id: \.self) { section in
                            let items = buckets[section] ?? []
                            if !items.isEmpty {
                                FeedSection(lane: section.lane, title: section.lane.label, count: items.count, collapsed: bindingForCollapsed(section)) {
                                    VStack(spacing: 7) {
                                        ForEach(items) { pr in
                                            PRCardView(pr: pr, lane: section.lane, hint: hint(for: pr, section: section))
                                                .onTapGesture { appState.selectedPRID = pr.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Tokens.contentBg)
        }
    }

    private func bindingForCollapsed(_ s: Section) -> Binding<Bool> {
        Binding(get: { collapsed[s] ?? false },
                set: { collapsed[s] = $0 })
    }

    private func grouped(viewerLogin: String) -> [Section: [PullRequest]] {
        var out: [Section: [PullRequest]] = [:]
        let now = Date.now
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: pr.timeline.compactMap { $0.type == .comment ? $0.actor?.login : nil },
                updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: mentionedIDs, now: now) {
                out[s, default: []].append(pr)
            }
        }
        return out
    }

    private func hint(for pr: PullRequest, section: Section) -> String? {
        switch section {
        case .attention: pr.attentionHint
        case .mentions:  pr.mentionHint
        case .involved:  pr.involvedHint
        default: nil
        }
    }
}
```

- [ ] **Step 2: Update `RootView.MainView` to use `FeedView` + `Sidebar`**

In `RootView.swift`, replace the placeholder `MainView`:

```swift
struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query private var repos: [Repo]
    @Query private var prs: [PullRequest]

    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        @Bindable var appState = appState
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)

        NavigationSplitView {
            Sidebar(
                viewer: viewer,
                repoSlug: repo?.id ?? "",
                counts: counts(viewerLogin: viewer?.login ?? ""),
                selection: $appState.activeSection,
                onOpenSettings: onOpenSettings)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                Text("Detail for #\(pr.number)") // replaced in Phase 9
            } else {
                FeedView(coordinator: coordinator)
            }
        }
    }

    private func counts(viewerLogin: String) -> [Section: Int] {
        var c: [Section: Int] = [:]
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: [], updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: [], now: .now) {
                c[s, default: 0] += 1
            }
        }
        return c
    }
}
```

Update the call site in `RootView`:

```swift
if signedIn {
    MainView(coordinator: coordinator, onOpenSettings: { /* opens Settings — wired in Task 28 */ })
        .task { coordinator.start() }
}
```

- [ ] **Step 3: Wire `PRTrackerApp` so the app actually runs end-to-end**

Update `PRTracker/App/PRTrackerApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct PRTrackerApp: App {
    let container: ModelContainer
    let appState: AppState
    let keychain: Keychain
    let client: GitHubClient
    let syncActor: SyncActor
    let coordinator: SyncCoordinator

    init() {
        let schema = Schema([
            User.self, Repo.self, PullRequest.self, TimelineEvent.self,
            Reviewer.self, Label.self, CIRun.self, ViewerState.self, HTTPCache.self,
        ])
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let c = try! ModelContainer(for: schema, configurations: [cfg])
        let kc = Keychain()
        self.container = c
        self.appState = AppState()
        self.keychain = kc
        self.client = GitHubClient(
            session: URLSession(configuration: .default),
            tokenProvider: { kc.load() })
        self.syncActor = SyncActor(modelContainer: c)
        self.coordinator = SyncCoordinator(client: client, actor: syncActor, modelContainer: c)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(keychain: keychain, client: client, coordinator: coordinator)
                .environment(appState)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 4: Build & run manually**

Run: `xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet`
Then run from Xcode: paste a real PAT, paste a real `owner/repo`, see the feed populate.

- [ ] **Step 5: Commit**

```bash
git add PRTracker
git commit -m "feat(ui): FeedView with grouped sections; wire PRTrackerApp end-to-end"
```

---

## Phase 9 — Detail UI

### Task 23: TimelineEventRow + TimelineColumn

**Files:**
- Create: `PRTracker/Views/Detail/TimelineEventRow.swift`
- Create: `PRTracker/Views/Detail/TimelineColumn.swift`

- [ ] **Step 1: Implement `TimelineEventRow.swift`**

```swift
import SwiftUI

struct TimelineEventRow: View {
    let event: TimelineEvent
    var onTap: () -> Void
    var onMarkUpToHere: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Tokens.contentBg).frame(width: 22, height: 22)
                Circle().fill(dotColor).frame(width: 18, height: 18)
                Image(systemName: dotIcon).foregroundStyle(.white).font(.system(size: 10).weight(.bold))
                if !event.isSeen {
                    Circle().stroke(Tokens.accent.opacity(0.22), lineWidth: 4)
                        .frame(width: 22, height: 22)
                }
            }.padding(.leading, 4)

            VStack(alignment: .leading, spacing: 4) {
                header
                if let body = event.body, [.comment, .review].contains(event.type) {
                    Text(body)
                        .font(.system(size: 12.5))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
                }
            }
        }
        .opacity(event.isSeen ? 0.48 : 1.0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Mark up to here as seen", action: onMarkUpToHere)
            Button(event.isSeen ? "Mark unseen" : "Mark seen", action: onTap)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let actor = event.actor { Text(actor.name ?? actor.login).metaText() }
            Text(verb).foregroundStyle(Tokens.textMuted).font(.system(size: 12))
            if let sha = event.sha { Text(sha).monoText().padding(.horizontal, 6).padding(.vertical, 1).background(Tokens.hairline, in: Capsule()) }
            Spacer()
            Text(RelativeTimeFormatter.short(event.at)).microText().foregroundStyle(Tokens.textFaint)
        }
    }

    private var verb: String {
        switch event.type {
        case .commit: "pushed"
        case .opened: "opened this pull request"
        case .review: switch event.reviewState {
            case .approved: "approved"
            case .changesRequested: "requested changes"
            case .commented: "commented on the review"
            default: "left a review"
        }
        case .comment: "commented"
        case .status: "status update"
        case .merged: "merged"
        case .closed: "closed"
        case .assigned: "assigned"
        case .labeled: "labeled"
        }
    }

    private var dotColor: Color {
        switch event.type {
        case .commit: Tokens.commented
        case .opened, .merged: Tokens.approved
        case .review:
            switch event.reviewState {
            case .approved: Tokens.approved
            case .changesRequested: Tokens.changes
            default: Tokens.commented
            }
        case .comment: Tokens.accent
        case .status: Tokens.pending
        default: Tokens.textFaint
        }
    }
    private var dotIcon: String {
        switch event.type {
        case .commit: "circle.dotted"
        case .opened: "arrow.triangle.pull"
        case .review:
            switch event.reviewState {
            case .approved: "checkmark"
            case .changesRequested: "xmark"
            default: "bubble.left"
            }
        case .comment: "bubble.left"
        case .status: "circle.dashed"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark"
        default: "tag"
        }
    }
}
```

- [ ] **Step 2: Implement `TimelineColumn.swift`**

```swift
import SwiftUI

struct TimelineColumn: View {
    let events: [TimelineEvent]
    var onTapEvent: (TimelineEvent) -> Void
    var onMarkUpToHere: (TimelineEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Vertical rail
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
```

- [ ] **Step 3: Build & commit**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
git add PRTracker/Views/Detail
git commit -m "feat(ui): timeline event row and column with seen/unseen styling"
```

### Task 24: DetailRightRail + QuickReply (placeholder)

**Files:**
- Create: `PRTracker/Views/Detail/DetailRightRail.swift`
- Create: `PRTracker/Views/Detail/QuickReply.swift`

- [ ] **Step 1: Implement `DetailRightRail.swift`**

```swift
import SwiftUI

struct DetailRightRail: View {
    let pr: PullRequest
    var onMarkAllSeen: () -> Void
    var onMarkAllUnseen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Status") {
                row("Review", pill: pr.reviewState?.rawValue ?? "—", tint: reviewTint)
                row("CI", pill: ciSummary, tint: ciTint)
                row("Mergeable", pill: pr.mergeable.rawValue, tint: mergeTint)
            }
            section("CI checks") {
                ForEach(pr.ciChecks) { run in
                    HStack(spacing: 8) {
                        Image(systemName: ciIcon(run.state)).foregroundStyle(ciColor(run.state))
                        Text(run.name).font(.system(size: 12))
                        Spacer()
                        if let d = run.durationSeconds { Text("\(d)s").microText().foregroundStyle(Tokens.textFaint) }
                    }
                }
            }
            section("Reviewers") {
                ForEach(pr.reviewers) { r in
                    HStack(spacing: 8) {
                        AvatarView(user: r.user, size: 18)
                        Text(r.user.name ?? r.user.login).metaText()
                        Spacer()
                        Text(r.state.rawValue).microText().foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            section("Labels") {
                FlowLayout(spacing: 6) {
                    ForEach(pr.labels) { l in
                        Text(l.name).microText().padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Tokens.hairline, in: Capsule()).foregroundStyle(Tokens.textMuted)
                    }
                }
            }
            section("Changes") {
                HStack(spacing: 6) {
                    Text("+\(pr.additions)").foregroundStyle(Tokens.approved)
                    Text("−\(pr.deletions)").foregroundStyle(Tokens.changes)
                    Text("· \(pr.changedFiles) files").foregroundStyle(Tokens.textFaint)
                }.font(.system(size: 12))
            }
            Spacer()
            Button(pr.isUnread ? "Mark all as seen" : "Mark all as unseen") {
                pr.isUnread ? onMarkAllSeen() : onMarkAllUnseen()
            }.buttonStyle(.bordered).frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 260)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(width: 0.5), alignment: .leading)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionHeader().foregroundStyle(Tokens.textMuted)
            content()
        }
    }
    private func row(_ label: String, pill: String, tint: Color) -> some View {
        HStack { Text(label).font(.system(size: 12)); Spacer()
            Text(pill).microText().padding(.horizontal, 8).padding(.vertical, 2)
                .background(tint.opacity(0.18), in: Capsule()).foregroundStyle(tint)
        }
    }
    private var reviewTint: Color {
        switch pr.reviewState {
        case .approved: Tokens.approved; case .changesRequested: Tokens.changes
        case .commented: Tokens.commented; default: Tokens.textFaint
        }
    }
    private var ciSummary: String {
        if pr.ciTotal == 0 { return "—" }
        if pr.ciFail > 0 { return "\(pr.ciFail) failed" }
        if pr.ciRunning > 0 { return "\(pr.ciRunning) running" }
        return "\(pr.ciPass)/\(pr.ciTotal) passed"
    }
    private var ciTint: Color { pr.ciFail > 0 ? Tokens.changes : (pr.ciRunning > 0 ? Tokens.pending : Tokens.approved) }
    private var mergeTint: Color {
        switch pr.mergeable { case .clean: Tokens.approved; case .conflicts, .blocked: Tokens.changes; case .unknown: Tokens.textFaint }
    }
    private func ciIcon(_ s: CIState) -> String {
        switch s { case .pass: "checkmark.circle.fill"; case .fail: "xmark.circle.fill"; case .running: "arrow.triangle.2.circlepath"; case .pending: "circle" }
    }
    private func ciColor(_ s: CIState) -> Color {
        switch s { case .pass: Tokens.approved; case .fail: Tokens.changes; case .running: Tokens.pending; case .pending: Tokens.textFaint }
    }
}

/// Minimal flow layout for label chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
```

- [ ] **Step 2: Implement `QuickReply.swift`**

```swift
import SwiftUI

struct QuickReply: View {
    let viewer: User?
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let v = viewer { AvatarView(user: v, size: 22); Text("Reply as \(v.name ?? v.login)").metaText() }
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.border, lineWidth: 0.5))
            HStack {
                Spacer()
                Button("Approve") {}.buttonStyle(.bordered).disabled(true).help("Coming soon")
                Button("Request changes") {}.buttonStyle(.bordered).disabled(true).help("Coming soon")
                Button("Comment") {}.buttonStyle(.borderedProminent).disabled(true).help("Coming soon")
            }
        }
        .padding(12)
        .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
    }
}
```

- [ ] **Step 3: Build & commit**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
git add PRTracker/Views/Detail
git commit -m "feat(ui): DetailRightRail and QuickReply (disabled buttons)"
```

### Task 25: PRDetailView (compose, lazy timeline fetch, live refresh)

**Files:**
- Create: `PRTracker/Views/Detail/PRDetailView.swift`
- Modify: `PRTracker/App/RootView.swift` to use it

- [ ] **Step 1: Implement `PRDetailView.swift`**

```swift
import SwiftUI
import SwiftData

struct PRDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var appState
    let pr: PullRequest
    let viewer: User?
    let client: GitHubClient
    let actor: SyncActor

    @State private var loadError: GitHubError?

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let loadError {
                            Text("Couldn't load timeline: \(String(describing: loadError)). Click refresh to retry.")
                                .foregroundStyle(Tokens.changes).padding(8)
                                .background(Tokens.changes.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        TimelineColumn(events: pr.timeline,
                            onTapEvent: { e in Task { try? await actor.setSeen(eventID: e.id, isSeen: !e.isSeen) } },
                            onMarkUpToHere: { e in Task { try? await actor.setSeenUpTo(prID: pr.id, throughEventID: e.id) } })
                        QuickReply(viewer: viewer)
                    }.padding(20)
                }
                DetailRightRail(pr: pr,
                    onMarkAllSeen: { Task { try? await actor.setSeenForPR(prID: pr.id, isSeen: true) } },
                    onMarkAllUnseen: { Task { try? await actor.setSeenForPR(prID: pr.id, isSeen: false) } })
            }
        }
        .task(id: pr.id) { await loadTimeline() }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: { appState.selectedPRID = nil }) {
                    Label("Feed", systemImage: "chevron.left")
                }.buttonStyle(.borderless)
                Text("\(pr.repo.id) / #\(pr.number)").foregroundStyle(Tokens.textMuted)
                Spacer()
                Link("Open", destination: URL(string: "https://github.com/\(pr.repo.id)/pull/\(pr.number)")!)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Tokens.accentBg, in: Capsule())
            }
            Text(pr.title).font(.system(size: 18).weight(.bold)).tracking(-0.2)
            HStack(spacing: 6) {
                AvatarView(user: pr.author, size: 18)
                Text(pr.author.name ?? pr.author.login).metaText()
                Text("wants to merge into").foregroundStyle(Tokens.textFaint)
                Text(pr.branchBase).monoText().padding(.horizontal, 4).background(Tokens.hairline, in: Capsule())
                Text("from").foregroundStyle(Tokens.textFaint)
                Text(pr.branchHead).monoText().padding(.horizontal, 4).background(Tokens.hairline, in: Capsule())
                Text("· opened \(RelativeTimeFormatter.short(pr.openedAt))").foregroundStyle(Tokens.textFaint).microText()
            }
        }
        .padding(24)
        .background(Tokens.panelBg)
        .overlay(Rectangle().fill(Tokens.border).frame(height: 0.5), alignment: .bottom)
    }

    private func loadTimeline() async {
        let ref = RepoRef(owner: pr.repo.owner, name: pr.repo.name)
        do {
            async let t = client.timeline(repo: ref, number: pr.number)
            async let r = client.reviews(repo: ref, number: pr.number)
            async let c = client.issueComments(repo: ref, number: pr.number)
            let (tItems, _, _) = try await (t, r, c)
            try await actor.upsertTimeline(prID: pr.id, items: tItems)
            loadError = nil
        } catch let e as GitHubError {
            loadError = e
        } catch {
            loadError = .network(message: error.localizedDescription)
        }
    }
}
```

> Note: the `/timeline` endpoint already covers commits, reviews, and comments as a unified stream — that's the source we render. The separate `reviews` and `issueComments` calls are awaited so a future task can use them to (a) display review bodies that the timeline endpoint truncates and (b) catch issue-level comments that timeline omits. In v1 they're fired-and-forgotten; their data isn't rendered.

- [ ] **Step 2: Replace placeholder in `RootView.MainView`**

In the `detail:` branch, replace the `Text("Detail for #\(pr.number)")` with:

```swift
PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, actor: coordinator.actorForView)
```

Add accessor properties to `SyncCoordinator`:

```swift
extension SyncCoordinator {
    var clientForView: GitHubClient { client }
    var actorForView: SyncActor { actor }
}
```

(These exist purely so views don't have to be passed `client` and `actor` directly from the App initializer.)

- [ ] **Step 3: Build & manual smoke**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

Run the app, open a PR, click events, verify they mark seen/unseen, click "Mark all as unseen" and verify the card returns to bold.

- [ ] **Step 4: Commit**

```bash
git add PRTracker
git commit -m "feat(ui): PRDetailView with lazy timeline fetch, live refresh, seen toggling"
```

---

## Phase 10 — Menu bar

### Task 26: MenuBarIconRenderer + MenuBarContentView

**Files:**
- Create: `PRTracker/Views/MenuBar/MenuBarIconRenderer.swift`
- Create: `PRTracker/Views/MenuBar/MenuBarContentView.swift`
- Modify: `PRTracker/App/PRTrackerApp.swift` to add the `MenuBarExtra` scene

- [ ] **Step 1: Implement `MenuBarIconRenderer.swift`**

```swift
import SwiftUI
import AppKit

enum MenuBarIconRenderer {
    static func image(attentionCount: Int) -> NSImage {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRs")!
        if attentionCount == 0 { return base }
        let composite = NSImage(size: NSSize(width: 18, height: 18))
        composite.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        let badgeRect = NSRect(x: 8, y: 8, width: 10, height: 10)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        let label = "\(min(attentionCount, 9))" + (attentionCount > 9 ? "+" : "")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: NSColor.white]
        (label as NSString).draw(in: badgeRect.insetBy(dx: 1, dy: 0), withAttributes: attrs)
        composite.unlockFocus()
        composite.isTemplate = false
        return composite
    }
}
```

- [ ] **Step 2: Implement `MenuBarContentView.swift`**

```swift
import SwiftUI
import SwiftData

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState
    @Query private var prs: [PullRequest]
    @Query private var repos: [Repo]
    @Query private var viewerStates: [ViewerState]

    let coordinator: SyncCoordinator

    var body: some View {
        let viewer = viewerStates.first?.viewer
        let repo = repos.first(where: \.isActive)
        let buckets = grouped(viewerLogin: viewer?.login ?? "")

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(repo?.id ?? "—").font(.system(size: 12).weight(.bold))
                Spacer()
                Text(coordinator.lastSyncAt.map { "Updated \(RelativeTimeFormatter.short($0))" } ?? "—")
                    .microText().foregroundStyle(Tokens.textMuted)
            }.padding(12)
            Divider()
            row(.attention, count: buckets[.attention]?.count ?? 0)
            row(.review,    count: buckets[.review]?.count ?? 0)
            row(.mine,      count: buckets[.mine]?.count ?? 0)
            row(.mentions,  count: buckets[.mentions]?.count ?? 0)
            if let top = buckets[.attention]?.first {
                Divider()
                Button(action: {
                    appState.selectedPRID = top.id
                    openWindow(id: "main")
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(top.number) \(top.title)").font(.system(size: 12).weight(.medium))
                        if let snippet = top.timeline.last(where: { $0.type == .comment })?.body {
                            Text(snippet).italic().foregroundStyle(Tokens.textMuted).lineLimit(1)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Divider()
            menuButton("Open PR Tracker", shortcut: nil) { openWindow(id: "main") }
            menuButton("Refresh now", shortcut: "⌘R") { Task { await coordinator.refresh() } }
            menuButton("Preferences…", shortcut: "⌘,") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Divider()
            menuButton("Quit", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
        }
        .frame(width: 320)
    }

    private func row(_ section: Section, count: Int) -> some View {
        Button(action: {
            appState.activeSection = section
            openWindow(id: "main")
        }) {
            HStack {
                Circle().fill(section.lane.color).frame(width: 8, height: 8)
                Text(section.lane.label).font(.system(size: 12))
                Spacer()
                if count > 0 { Text("\(count)").microText().foregroundStyle(Tokens.textMuted) }
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }.buttonStyle(.plain)
    }

    private func menuButton(_ label: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(label).font(.system(size: 12)); Spacer()
                if let s = shortcut { Text(s).microText().foregroundStyle(Tokens.textMuted) } }
                .padding(.horizontal, 12).padding(.vertical, 6)
        }.buttonStyle(.plain)
    }

    private func grouped(viewerLogin: String) -> [Section: [PullRequest]] {
        // Same logic as FeedView; duplicated intentionally to keep menu-bar self-contained.
        var out: [Section: [PullRequest]] = [:]
        for pr in prs {
            let input = ClassifierInput.PR(
                id: pr.id, number: pr.number, authorLogin: pr.author.login,
                state: pr.state == .closed || pr.state == .merged ? "closed" : "open",
                mergedAt: pr.mergedAt,
                requestedReviewerLogins: pr.reviewers.filter { $0.state == .pending }.map(\.user.login),
                reviewerStates: pr.reviewers.map { ($0.user.login, $0.stateRaw) },
                ciFail: pr.ciFail, ciRunning: pr.ciRunning,
                commenterLogins: [], updatedAt: pr.updatedAt)
            if let s = Classifier.section(for: input, viewer: viewerLogin, mentions: [], now: .now) {
                out[s, default: []].append(pr)
            }
        }
        return out
    }
}
```

- [ ] **Step 3: Add a small badge model**

Create `PRTracker/Views/MenuBar/MenuBarBadge.swift`:

```swift
import SwiftUI

@Observable
final class MenuBarBadge {
    var count: Int = 0
}
```

Add a SwiftUI label view that reads the model and renders the icon:

```swift
struct MenuBarLabel: View {
    let badge: MenuBarBadge
    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(attentionCount: badge.count))
    }
}
```

In `MenuBarContentView`, accept `let badge: MenuBarBadge` as an injected property, and add a `.task(id: prs.count)` modifier on the body that recomputes the attention count and writes it: `badge.count = (buckets[.attention] ?? []).count`.

- [ ] **Step 4: Add the `MenuBarExtra` scene to `PRTrackerApp`**

In `PRTrackerApp` add `let badge = MenuBarBadge()` as a stored property, then:

```swift
MenuBarExtra {
    MenuBarContentView(coordinator: coordinator, badge: badge)
        .environment(appState)
        .modelContainer(container)
} label: {
    MenuBarLabel(badge: badge)
}
.menuBarExtraStyle(.window)
```

- [ ] **Step 4: Build & manual smoke**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

Run app, verify menu-bar icon appears, dropdown opens, clicking a section row activates the main window with that section selected.

- [ ] **Step 5: Commit**

```bash
git add PRTracker
git commit -m "feat(ui): menu-bar icon with badge and dropdown content"
```

---

## Phase 11 — Settings + lifecycle integration

### Task 27: SettingsView with three tabs + launch-at-login

**Files:**
- Create: `PRTracker/Views/Settings/SettingsView.swift`
- Modify: `PRTracker/App/PRTrackerApp.swift` to add `Settings` scene

- [ ] **Step 1: Implement `SettingsView.swift`**

```swift
import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var viewerStates: [ViewerState]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            accountTab.tabItem { Label("Account", systemImage: "person.circle") }
            repoTab.tabItem { Label("Repository", systemImage: "folder") }
        }
        .frame(width: 480, height: 280).padding(20)
    }

    private var vs: ViewerState { viewerStates.first ?? ViewerState() }

    @ViewBuilder private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Refresh interval: \(vs.refreshIntervalMinutes) min",
                value: Binding(get: { vs.refreshIntervalMinutes }, set: {
                    vs.refreshIntervalMinutes = $0
                    coordinator.setIntervals(foregroundMinutes: $0)
                    try? ctx.save()
                }), in: 1...10)
            Toggle("Launch at login", isOn: Binding(get: { vs.launchAtLoginEnabled }, set: { newValue in
                vs.launchAtLoginEnabled = newValue
                try? ctx.save()
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch { /* surface in UI later */ }
            }))
        }
    }

    @ViewBuilder private var accountTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let v = vs.viewer {
                HStack { AvatarView(user: v, size: 32); VStack(alignment: .leading) {
                    Text(v.name ?? v.login).font(.system(size: 14).weight(.semibold))
                    Text("@\(v.login)").microText().foregroundStyle(Tokens.textMuted)
                } }
            }
            Button("Sign out") {
                keychain.delete()
                vs.viewer = nil
                try? ctx.save()
            }.foregroundStyle(Tokens.changes)
        }
    }

    @State private var newRepo: String = ""

    @ViewBuilder private var repoTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Active repository: \(vs.activeRepoID ?? "—")")
            HStack {
                TextField("owner/name", text: $newRepo).textFieldStyle(.roundedBorder)
                Button("Switch") { switchRepo() }.disabled(!newRepo.contains("/"))
            }
        }
    }

    private func switchRepo() {
        let parts = newRepo.split(separator: "/")
        guard parts.count == 2 else { return }
        let owner = String(parts[0]); let name = String(parts[1])
        let id = "\(owner)/\(name)"
        let existing = (try? ctx.fetch(FetchDescriptor<Repo>())) ?? []
        for r in existing { r.isActive = false }
        if let already = existing.first(where: { $0.id == id }) {
            already.isActive = true
            vs.activeRepoID = already.id
        } else {
            let r = Repo(owner: owner, name: name, isActive: true)
            ctx.insert(r)
            vs.activeRepoID = r.id
        }
        try? ctx.save()
        Task { await coordinator.refresh() }
    }
}
```

- [ ] **Step 2: Add the `Settings` scene to `PRTrackerApp.swift`**

```swift
Settings {
    SettingsView(keychain: keychain, client: client, coordinator: coordinator)
        .modelContainer(container)
        .environment(appState)
}
```

Also entitlement: Settings + launch-at-login require sandboxed app entitlements. In `PRTracker.entitlements` (create if missing), set `com.apple.security.app-sandbox = true` and `com.apple.security.network.client = true`. Add the file to the target if not already.

- [ ] **Step 3: Build & manual smoke**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
```

Open Settings (⌘,), confirm all three tabs render, change refresh interval, toggle launch-at-login (verify in System Settings → General → Login Items & Extensions), sign out and back in.

- [ ] **Step 4: Commit**

```bash
git add PRTracker
git commit -m "feat(settings): three-tab Settings with launch-at-login support"
```

### Task 28: scenePhase active-debounce + final wiring

**Files:**
- Modify: `PRTracker/App/RootView.swift`

- [ ] **Step 1: Add scenePhase observation**

```swift
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastActiveTriggerAt: Date = .distantPast
    // ...

    var body: some View {
        // existing content
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let now = Date.now
                if now.timeIntervalSince(lastActiveTriggerAt) > 30 {
                    lastActiveTriggerAt = now
                    Task { await coordinator.refresh() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build & commit**

```bash
xcodebuild build -scheme PRTracker -destination 'platform=macOS' -quiet
git add PRTracker/App
git commit -m "feat(app): scenePhase debounced refresh on activate"
```

---

## Phase 12 — Verification

### Task 29: Full test run + manual verification checklist

- [ ] **Step 1: Run the entire test suite**

Run: `xcodebuild test -scheme PRTracker -destination 'platform=macOS' -quiet`
Expected: all tests pass.

- [ ] **Step 2: Walk through manual checklist**

Manual checks (from spec §9.6):
- [ ] Toggle dark mode mid-app (System Settings → Appearance) — colors flip correctly
- [ ] Drag window across displays with different scale factors — layout intact
- [ ] Sleep Mac for 1h, wake — sync fires once on wake, no duplicate timeline events
- [ ] Block `api.github.com` via `/etc/hosts`, refresh — toolbar shows "Sync failed"; remove block, next tick recovers
- [ ] Paste an obviously bad PAT — onboarding routes back with "Token rejected" message
- [ ] Repo with 0 PRs — sections render empty; counts hidden
- [ ] Repo with 50 PRs — feed renders without lag (LazyVStack)
- [ ] Open a PR — events render unseen (full opacity); click an event → it dims; click again → restored
- [ ] Right-click an event → "Mark up to here as seen" → all earlier events dim
- [ ] Right-rail "Mark all as unseen" → card returns to bold in feed
- [ ] Force-push a branch externally; observe new headSha + cleared CI on next tick
- [ ] Menu-bar icon shows red badge when there's an attention PR; clears when zero
- [ ] Click menu-bar "Refresh now ⌘R" — manual refresh fires
- [ ] Quit and relaunch — last-known data renders before network completes

- [ ] **Step 3: If any check fails, file a follow-up note in `docs/superpowers/specs/2026-04-27-prtracker-design.md` under a new "Post-v1 follow-ups" section and create a small fix in a follow-up commit.**

- [ ] **Step 4: Tag v1**

```bash
git tag v1.0.0
```

---

## Spec coverage check

| Spec section | Implementing tasks |
|---|---|
| §3.1 App shell scenes | Task 22, 26, 27 |
| §3.2 UI views | Tasks 19–25 |
| §3.3 Domain layer | Tasks 9–16 |
| §3.4 Persistence | Tasks 3–6 |
| §3.5 AppState | Task 17 |
| §3.6 Concurrency | Tasks 11, 15, 16 |
| §4 Data model | Tasks 3–6 |
| §4 Seen-state mutations (1–5) | Task 15 (actor) + 23, 24, 25 (UI bindings) |
| §4 Upsert algorithm | Task 15 |
| §5 Networking & auth | Tasks 8–13 |
| §6.1 Sidebar | Task 21 |
| §6.2 Feed | Task 22 |
| §6.3 Status gauge | Task 19 |
| §6.4 Detail view | Task 25 |
| §6.5 Right rail | Task 24 |
| §6.6 Menu-bar dropdown | Task 26 |
| §6.7 Onboarding | Task 18 |
| §6.8 Settings | Task 27 |
| §7 Refresh / lifecycle | Tasks 16, 28 |
| §8 Errors & edge cases | Tasks 11–13, 25 (inline error), 21 (toolbar chip) |
| §9 Testing strategy | Tasks 7, 8, 10–15, 29 |
