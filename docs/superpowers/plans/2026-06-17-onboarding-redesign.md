# Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-stage onboarding with a refined, native, stepped setup (Welcome → Connect → Repositories → Notifications) that supports adding multiple validated repos with per-repo notification levels, and can be re-run from a menu command to reconfigure an existing install.

**Architecture:** A network-free `@Observable OnboardingModel` holds all transient state, the step-gating logic, and a single `commit(into:)` that reconciles SwiftData (works for both first-run insert and reconfigure upsert/delete). Thin SwiftUI step views bind to the model; `OnboardingView` owns the async GitHub calls (validate token, verify repo). First-run shows in `RootView`; reconfigure shows as a `.sheet` over `MainView` driven by an `AppState` flag set from a menu command.

**Tech Stack:** SwiftUI, SwiftData, Swift Concurrency, Swift Testing, Sparkle (unaffected), GitHub REST.

---

## File Structure

- `PRTracker/GitHub/Endpoints.swift` — **modify**: add `RepoRef.parse(_:)`.
- `PRTracker/GitHub/DTOs.swift` — **modify**: add `RepoDTO`.
- `PRTracker/GitHub/GitHubClient.swift` — **modify**: add `repository(_:)`.
- `PRTracker/Views/Settings/SettingsView.swift`, `Views/Settings/RepositoriesSettingsView.swift` — **modify**: route `owner/name` parsing through `RepoRef.parse`.
- `PRTracker/App/AppState.swift` — **modify**: add `showReconfigure`.
- `PRTracker/App/PRTrackerApp.swift` — **modify**: add the "Set Up PR Tracker Again…" menu command.
- `PRTracker/App/RootView.swift` — **modify**: new `OnboardingView` call; pass `keychain`/`client` to `MainView`; add reconfigure `.sheet`.
- `PRTracker/Views/Onboarding/OnboardingModel.swift` — **create**: state + gating + commit.
- `PRTracker/Views/Onboarding/OnboardingView.swift` — **rewrite**: container + nav + async orchestration.
- `PRTracker/Views/Onboarding/OnboardingStepRail.swift` — **create**.
- `PRTracker/Views/Onboarding/Steps/WelcomeStepView.swift`, `ConnectStepView.swift`, `RepositoriesStepView.swift`, `NotificationsStepView.swift` — **create**.
- `PRTrackerTests/GitHub/RepoRefParseTests.swift`, `PRTrackerTests/GitHub/RepoDTOTests.swift`, `PRTrackerTests/Onboarding/OnboardingModelTests.swift` — **create**.

The project uses file-system-synchronized Xcode groups — new files under `PRTracker/`/`PRTrackerTests/` are picked up automatically; no `project.pbxproj` edits.

Run tests with: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` (filter a suite with `-only-testing:PRTrackerTests/<SuiteName>`).

---

## Task 1: `RepoRef.parse` + de-dup existing call sites

**Files:**
- Modify: `PRTracker/GitHub/Endpoints.swift`
- Test: `PRTrackerTests/GitHub/RepoRefParseTests.swift`
- Modify: `PRTracker/Views/Settings/SettingsView.swift`, `PRTracker/Views/Settings/RepositoriesSettingsView.swift`

- [ ] **Step 1: Write the failing test**

Create `PRTrackerTests/GitHub/RepoRefParseTests.swift`:

```swift
import Testing
@testable import PRTracker

@Suite struct RepoRefParseTests {
    @Test func parsesOwnerName() {
        let r = RepoRef.parse("oreilly/spark-ios")
        #expect(r?.owner == "oreilly")
        #expect(r?.name == "spark-ios")
        #expect(r?.slug == "oreilly/spark-ios")
    }

    @Test func trimsWhitespace() {
        #expect(RepoRef.parse("  oreilly / spark-ios ")?.slug == "oreilly/spark-ios")
    }

    @Test func rejectsMissingSlash() { #expect(RepoRef.parse("oreilly") == nil) }
    @Test func rejectsEmptyParts() {
        #expect(RepoRef.parse("/name") == nil)
        #expect(RepoRef.parse("owner/") == nil)
        #expect(RepoRef.parse("") == nil)
    }
    @Test func rejectsExtraSlashes() { #expect(RepoRef.parse("a/b/c") == nil) }
}
```

- [ ] **Step 2: Run it; expect failure**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/RepoRefParseTests`
Expected: compile failure — `RepoRef` has no `parse`.

- [ ] **Step 3: Add `RepoRef.parse`**

In `PRTracker/GitHub/Endpoints.swift`, add to the `RepoRef` struct (it has `let owner`, `let name`, `var slug`):

```swift
extension RepoRef {
    /// Parse an "owner/name" string. Trims whitespace around the whole string
    /// and each part; requires exactly two non-empty parts. Returns nil otherwise.
    static func parse(_ raw: String) -> RepoRef? {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return RepoRef(owner: parts[0], name: parts[1])
    }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run the same command. Expected: PASS (5 tests).

- [ ] **Step 5: Route existing parsing through it**

In `PRTracker/Views/Settings/RepositoriesSettingsView.swift`, replace the body of `canAddRepo` and `addRepo`:

```swift
private var canAddRepo: Bool {
    guard let ref = RepoRef.parse(newRepo) else { return false }
    return !repos.contains { $0.id == ref.slug }
}

private func addRepo() {
    guard let ref = RepoRef.parse(newRepo), !repos.contains(where: { $0.id == ref.slug }) else { return }
    ctx.insert(Repo(owner: ref.owner, name: ref.name))
    try? ctx.save()
    newRepo = ""
    showAddSheet = false
    selectedRepoID = ref.slug
    Task { await coordinator.refresh() }
}
```

In `PRTracker/Views/Settings/SettingsView.swift`, the `repoTab`/onboarding-era helpers no longer parse repos (repo management moved to `RepositoriesSettingsView`); confirm via `grep -n 'split(separator: "/")' PRTracker/Views/Settings/SettingsView.swift` returns nothing. If any remain, replace with `RepoRef.parse`.

- [ ] **Step 6: Build + commit**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` — expect BUILD SUCCEEDED.

```bash
git add PRTracker/GitHub/Endpoints.swift PRTracker/Views/Settings/RepositoriesSettingsView.swift PRTracker/Views/Settings/SettingsView.swift PRTrackerTests/GitHub/RepoRefParseTests.swift
git commit -m "feat: add RepoRef.parse and route repo entry through it"
```

---

## Task 2: `RepoDTO` + `GitHubClient.repository(_:)`

**Files:**
- Modify: `PRTracker/GitHub/DTOs.swift`, `PRTracker/GitHub/GitHubClient.swift`
- Test: `PRTrackerTests/GitHub/RepoDTOTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PRTrackerTests/GitHub/RepoDTOTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@Suite struct RepoDTOTests {
    @Test func decodesFullName() throws {
        let json = #"{"full_name":"oreilly/spark-ios","private":true,"default_branch":"main"}"#
        let dto = try JSONDecoder().decode(RepoDTO.self, from: Data(json.utf8))
        #expect(dto.full_name == "oreilly/spark-ios")
    }
}
```

- [ ] **Step 2: Run it; expect failure**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/RepoDTOTests`
Expected: compile failure — `RepoDTO` undefined.

- [ ] **Step 3: Add the DTO and client method**

In `PRTracker/GitHub/DTOs.swift` (match the file's `nonisolated struct` convention), add:

```swift
nonisolated struct RepoDTO: Decodable, Equatable {
    let full_name: String
}
```

In `PRTracker/GitHub/GitHubClient.swift`, add to the `extension GitHubClient` block (alongside `listOpenPRs` etc.):

```swift
/// Verify a repo exists and is accessible to the token. Throws
/// `.repoNotFound` (404) or `.unauthorized` (401) otherwise.
func repository(_ repo: RepoRef) async throws -> RepoDTO {
    try await send(Endpoints.repo(repo), as: RepoDTO.self)
}
```

- [ ] **Step 4: Run tests; expect pass**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/GitHub/DTOs.swift PRTracker/GitHub/GitHubClient.swift PRTrackerTests/GitHub/RepoDTOTests.swift
git commit -m "feat: add RepoDTO and GitHubClient.repository verify call"
```

---

## Task 3: `OnboardingModel` — state, gating, pending-repo edits

**Files:**
- Create: `PRTracker/Views/Onboarding/OnboardingModel.swift`
- Test: `PRTrackerTests/Onboarding/OnboardingModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PRTrackerTests/Onboarding/OnboardingModelTests.swift`:

```swift
import Testing
import Foundation
@testable import PRTracker

@MainActor
@Suite struct OnboardingModelTests {
    @Test func welcomeAlwaysContinues() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(m.canContinue(from: .welcome))
    }

    @Test func connectRequiresViewer() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(!m.canContinue(from: .connect))
        m.applyValidatedViewer(UserDTO(login: "alex", name: "Alex", avatar_url: nil))
        #expect(m.canContinue(from: .connect))
    }

    @Test func repositoriesRequireAtLeastOne() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(!m.canContinue(from: .repositories))
        #expect(m.addRepo("oreilly/spark-ios"))
        #expect(m.canContinue(from: .repositories))
    }

    @Test func addRepoRejectsDuplicatesAndGarbage() {
        let m = OnboardingModel(mode: .firstRun)
        #expect(m.addRepo("oreilly/spark-ios"))
        #expect(!m.addRepo("oreilly/spark-ios"))   // duplicate
        #expect(!m.addRepo("garbage"))             // unparseable
        #expect(m.pending.count == 1)
    }

    @Test func removeRepo() {
        let m = OnboardingModel(mode: .firstRun)
        _ = m.addRepo("a/b"); _ = m.addRepo("c/d")
        m.removeRepo(id: "a/b")
        #expect(m.pending.map(\.id) == ["c/d"])
    }
}
```

- [ ] **Step 2: Run it; expect failure**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test -only-testing:PRTrackerTests/OnboardingModelTests`
Expected: compile failure — `OnboardingModel` undefined.

- [ ] **Step 3: Create the model**

Create `PRTracker/Views/Onboarding/OnboardingModel.swift`:

```swift
import Foundation
import SwiftData
import UserNotifications

@MainActor
@Observable
final class OnboardingModel {
    enum Mode { case firstRun, reconfigure }

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, connect, repositories, notifications
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .connect: "Connect"
            case .repositories: "Repositories"
            case .notifications: "Notifications"
            }
        }
        var symbol: String {
            switch self {
            case .welcome: "hand.wave"
            case .connect: "key.horizontal"
            case .repositories: "folder"
            case .notifications: "bell"
            }
        }
    }

    struct PendingRepo: Identifiable, Equatable {
        let owner: String
        let name: String
        var level: NotificationLevel = .personal
        var id: String { "\(owner)/\(name)" }
    }

    let mode: Mode
    var step: Step = .welcome

    // Connect
    var token: String = ""
    var viewer: UserDTO?
    var connectError: String?
    var isValidating = false

    // Repositories
    var pending: [PendingRepo] = []
    var newRepo: String = ""
    var addError: String?
    var isCheckingRepo = false

    // Notifications
    var notifStatus: UNAuthorizationStatus = .notDetermined

    init(mode: Mode) { self.mode = mode }

    /// A throwaway User (not inserted) for AvatarView display of the validated viewer.
    var displayUser: User? {
        viewer.map { User(login: $0.login, name: $0.name, avatarURL: $0.avatar_url) }
    }

    func canContinue(from step: Step) -> Bool {
        switch step {
        case .welcome: return true
        case .connect: return viewer != nil
        case .repositories: return !pending.isEmpty
        case .notifications: return true
        }
    }

    func applyValidatedViewer(_ dto: UserDTO) {
        viewer = dto
        connectError = nil
    }

    /// Add a verified repo. Returns false if the string is unparseable or a duplicate.
    @discardableResult
    func addRepo(_ raw: String, level: NotificationLevel = .personal) -> Bool {
        guard let ref = RepoRef.parse(raw), !pending.contains(where: { $0.id == ref.slug }) else { return false }
        pending.append(PendingRepo(owner: ref.owner, name: ref.name, level: level))
        return true
    }

    func removeRepo(id: String) { pending.removeAll { $0.id == id } }
}
```

- [ ] **Step 4: Run tests; expect pass**

Run the Step 2 command. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Onboarding/OnboardingModel.swift PRTrackerTests/Onboarding/OnboardingModelTests.swift
git commit -m "feat: add OnboardingModel state, gating, pending-repo edits"
```

---

## Task 4: `OnboardingModel.seed(from:)` and `commit(into:)`

**Files:**
- Modify: `PRTracker/Views/Onboarding/OnboardingModel.swift`
- Test: `PRTrackerTests/Onboarding/OnboardingModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `OnboardingModelTests.swift` (inside the suite):

```swift
    @Test func commitFirstRunInsertsViewerAndRepos() throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let m = OnboardingModel(mode: .firstRun)
        m.applyValidatedViewer(UserDTO(login: "alex", name: "Alex", avatar_url: nil))
        _ = m.addRepo("oreilly/spark-ios", level: .everything)
        _ = m.addRepo("oreilly/mobile-lot", level: .none)

        m.commit(into: ctx)

        let repos = try ctx.fetch(FetchDescriptor<Repo>()).sorted { $0.id < $1.id }
        #expect(repos.map(\.id) == ["oreilly/mobile-lot", "oreilly/spark-ios"])
        #expect(repos.first { $0.id == "oreilly/spark-ios" }?.notificationLevel == .everything)
        #expect(repos.first { $0.id == "oreilly/mobile-lot" }?.notificationLevel == .none)
        #expect(repos.allSatisfy { $0.isEnabled })
        let vs = try ctx.fetch(FetchDescriptor<ViewerState>())
        #expect(vs.first?.viewer?.login == "alex")
    }

    @Test func reconfigureReconcilesKeepsRemovesAdds() throws {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        // Existing store: two repos, one disabled, with a PR under "keep".
        let viewer = User(login: "alex"); ctx.insert(viewer)
        let vs = ViewerState(viewer: viewer); ctx.insert(vs)
        let keep = Repo(owner: "oreilly", name: "keep"); keep.notificationLevel = .personal; ctx.insert(keep)
        let drop = Repo(owner: "oreilly", name: "drop", isEnabled: false); ctx.insert(drop)
        ctx.insert(PullRequest(id: "PR1", number: 1, title: "t", state: .open,
                               branchHead: "h", branchBase: "main", headSha: "s",
                               openedAt: .now, updatedAt: .now, author: viewer, repo: keep))
        try ctx.save()

        let m = OnboardingModel(mode: .reconfigure)
        m.seed(from: ctx)
        #expect(Set(m.pending.map(\.id)) == ["oreilly/keep", "oreilly/drop"])

        // Keep+relevel "keep", remove "drop", add "new".
        m.pending.removeAll { $0.id == "oreilly/drop" }
        if let i = m.pending.firstIndex(where: { $0.id == "oreilly/keep" }) { m.pending[i].level = .everything }
        _ = m.addRepo("oreilly/new", level: .personal)

        m.commit(into: ctx)

        let repos = try ctx.fetch(FetchDescriptor<Repo>())
        #expect(Set(repos.map(\.id)) == ["oreilly/keep", "oreilly/new"])
        let kept = repos.first { $0.id == "oreilly/keep" }
        #expect(kept?.notificationLevel == .everything)
        #expect(kept?.pullRequests.count == 1)          // PR preserved
        #expect((repos.first { $0.id == "oreilly/new" })?.isEnabled == true)
    }
```

`TestContainer.make()` already exists (`PRTrackerTests/Helpers/ModelContainerHelper.swift`).

- [ ] **Step 2: Run; expect failure**

Run: `-only-testing:PRTrackerTests/OnboardingModelTests`. Expected: compile failure — no `seed`/`commit`.

- [ ] **Step 3: Implement `seed` and `commit`**

Append to `OnboardingModel` (before the closing brace):

```swift
    /// Reconfigure mode: pre-fill from the current store (existing viewer + repos).
    func seed(from ctx: ModelContext) {
        if let u = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first?.viewer {
            viewer = UserDTO(login: u.login, name: u.name, avatar_url: u.avatarURL)
        }
        let repos = (try? ctx.fetch(FetchDescriptor<Repo>(sort: [SortDescriptor(\Repo.id)]))) ?? []
        pending = repos.map { PendingRepo(owner: $0.owner, name: $0.name, level: $0.notificationLevel) }
    }

    /// Write the collected setup. Unified for both modes: repos are reconciled by
    /// id, so first-run (empty store) inserts everything, and reconfigure keeps
    /// matched repos (preserving their cached PRs and `isEnabled`), updates their
    /// level, deletes repos no longer listed, and inserts new ones.
    func commit(into ctx: ModelContext) {
        if let dto = viewer {
            let user = upsertUser(dto, into: ctx)
            let vs = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first ?? {
                let v = ViewerState(); ctx.insert(v); return v
            }()
            vs.viewer = user
        }

        let current = (try? ctx.fetch(FetchDescriptor<Repo>())) ?? []
        let keepIDs = Set(pending.map(\.id))
        for r in current where !keepIDs.contains(r.id) { ctx.delete(r) }
        for p in pending {
            if let existing = current.first(where: { $0.id == p.id }) {
                existing.notificationLevel = p.level   // preserve isEnabled
            } else {
                let r = Repo(owner: p.owner, name: p.name)
                r.notificationLevel = p.level
                ctx.insert(r)
            }
        }
        try? ctx.save()
    }

    private func upsertUser(_ dto: UserDTO, into ctx: ModelContext) -> User {
        let login = dto.login
        if let u = (try? ctx.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.login == login })))?.first {
            u.name = dto.name; u.avatarURL = dto.avatar_url
            return u
        }
        let u = User(login: dto.login, name: dto.name, avatarURL: dto.avatar_url)
        ctx.insert(u)
        return u
    }
```

- [ ] **Step 4: Run tests; expect pass**

Run `-only-testing:PRTrackerTests/OnboardingModelTests`. Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Onboarding/OnboardingModel.swift PRTrackerTests/Onboarding/OnboardingModelTests.swift
git commit -m "feat: OnboardingModel seed + reconcile commit"
```

---

## Task 5: `AppState.showReconfigure` + menu command + sheet wiring

**Files:**
- Modify: `PRTracker/App/AppState.swift`, `PRTracker/App/PRTrackerApp.swift`, `PRTracker/App/RootView.swift`

No unit test (App-scene/menu wiring); verified by build + manual.

- [ ] **Step 1: Add the flag**

In `PRTracker/App/AppState.swift`, add below `searchText`:

```swift
    /// Set by the "Set Up PR Tracker Again…" menu command; presents the
    /// reconfigure onboarding sheet. Ephemeral.
    var showReconfigure: Bool = false
```

- [ ] **Step 2: Add the menu command**

In `PRTracker/App/PRTrackerApp.swift`, inside the existing `CommandGroup(after: .appInfo)` (next to the "Check for Updates…" button):

```swift
                Button("Set Up PR Tracker Again…") {
                    appState.showReconfigure = true
                }
```

- [ ] **Step 3: Pass keychain/client to MainView and present the sheet**

In `PRTracker/App/RootView.swift`:

In `RootView.body`, update the `MainView` construction to pass the dependencies it now needs for the reconfigure sheet:

```swift
                MainView(keychain: keychain, client: client, coordinator: coordinator, onOpenSettings: { openSettings() })
```

In `MainView`, add the new stored properties and the sheet. Replace the `MainView` property block and `body` opening:

```swift
struct MainView: View {
    @Environment(AppState.self) private var appState
    @Query private var viewerStates: [ViewerState]
    @Query(filter: #Predicate<PullRequest> { $0.repo.isEnabled }) private var prs: [PullRequest]

    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator
    var onOpenSettings: () -> Void

    var body: some View {
        @Bindable var appState = appState
        let viewer = viewerStates.first?.viewer

        NavigationSplitView {
            MailSourceColumn(coordinator: coordinator, onOpenSettings: onOpenSettings)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            if let prID = appState.selectedPRID, let pr = prs.first(where: { $0.id == prID }) {
                PRDetailView(pr: pr, viewer: viewer, client: coordinator.clientForView, syncActor: coordinator.syncActorForView)
            } else {
                MailEmptyDetailView()
            }
        }
        .sheet(isPresented: $appState.showReconfigure) {
            OnboardingView(mode: .reconfigure, keychain: keychain, client: client, coordinator: coordinator)
        }
    }
}
```

(The `OnboardingView(mode:keychain:client:coordinator:)` initializer is created in Task 8. This task will not build until Task 8 lands — that's expected; do Steps 1–2 now, and complete Step 3's sheet line as part of Task 8's build. Commit Steps 1–2 here.)

- [ ] **Step 4: Build the parts that stand alone + commit**

Apply Steps 1 and 2 (AppState flag + menu button referencing it). Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` — expect BUILD SUCCEEDED (the flag + button compile; the menu button only reads `appState.showReconfigure`).

```bash
git add PRTracker/App/AppState.swift PRTracker/App/PRTrackerApp.swift
git commit -m "feat: add showReconfigure flag and rerun-onboarding menu command"
```

---

## Task 6: `OnboardingStepRail`

**Files:**
- Create: `PRTracker/Views/Onboarding/OnboardingStepRail.swift`

No unit test (pure view); verified by build + manual.

- [ ] **Step 1: Create the rail**

```swift
import SwiftUI

/// Left rail listing the onboarding steps with progress state. Visited/active
/// steps are tappable to go back; upcoming steps are disabled.
struct OnboardingStepRail: View {
    let steps: [OnboardingModel.Step]
    let current: OnboardingModel.Step
    let onSelect: (OnboardingModel.Step) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(steps) { step in
                let state = state(for: step)
                Button { if state != .upcoming { onSelect(step) } } label: {
                    HStack(spacing: 9) {
                        badge(step: step, state: state)
                        Text(step.title)
                            .font(.system(size: 12.5, weight: state == .active ? .semibold : .regular))
                            .foregroundStyle(state == .upcoming ? Tokens.textFaint : Tokens.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(state == .active ? Tokens.accentBg : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state == .upcoming)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 168)
    }

    private enum StepState { case done, active, upcoming }
    private func state(for step: OnboardingModel.Step) -> StepState {
        if step.rawValue < current.rawValue { return .done }
        if step == current { return .active }
        return .upcoming
    }

    @ViewBuilder private func badge(step: OnboardingModel.Step, state: StepState) -> some View {
        ZStack {
            Circle().fill(fill(state)).frame(width: 20, height: 20)
            if state == .done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(step.rawValue + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(state == .active ? .white : Tokens.textMuted)
            }
        }
    }
    private func fill(_ s: StepState) -> Color {
        switch s {
        case .done: Tokens.approved
        case .active: Tokens.accent
        case .upcoming: Tokens.hairline
        }
    }
}
```

- [ ] **Step 2: Build + commit**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` — expect BUILD SUCCEEDED.

```bash
git add PRTracker/Views/Onboarding/OnboardingStepRail.swift
git commit -m "feat: onboarding step rail"
```

---

## Task 7: Step content views

**Files:**
- Create: `PRTracker/Views/Onboarding/Steps/WelcomeStepView.swift`, `ConnectStepView.swift`, `RepositoriesStepView.swift`, `NotificationsStepView.swift`

No unit test (pure views); verified by build + manual. Each takes the model and (where needed) async action closures owned by `OnboardingView` (Task 8).

- [ ] **Step 1: WelcomeStepView**

```swift
import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Tokens.accent, Tokens.accent.opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "arrow.triangle.pull").font(.system(size: 24, weight: .medium)).foregroundStyle(.white))
            Text("Welcome to PR Tracker").font(.system(size: 20, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Keep an eye on your GitHub pull requests across every repository you care about — reviews, comments, CI, and merges, all in one place.")
                .font(.system(size: 13)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                bullet("key.horizontal", "Connect with a GitHub token")
                bullet("folder", "Add the repositories you want to follow")
                bullet("bell", "Choose how each one notifies you")
            }.padding(.top, 4)
            Spacer()
        }
    }
    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Tokens.accent).frame(width: 18)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
        }
    }
}
```

- [ ] **Step 2: ConnectStepView**

```swift
import SwiftUI

struct ConnectStepView: View {
    @Bindable var model: OnboardingModel
    var onValidate: () -> Void

    private let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=PRTracker")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your GitHub account").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("PR Tracker needs a personal access token with the **repo** scope to read your pull requests. Fine-grained tokens with read access to pull requests also work.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)
            Link(destination: tokenURL) {
                HStack(spacing: 5) { Image(systemName: "arrow.up.forward.square"); Text("Create a token on GitHub") }
                    .font(.system(size: 12.5, weight: .medium))
            }

            if let v = model.viewer, let user = model.displayUser {
                HStack(spacing: 9) {
                    AvatarView(user: user, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(v.name ?? v.login).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tokens.text)
                        Text("@\(v.login)").font(.system(size: 11)).foregroundStyle(Tokens.textMuted)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.approved)
                }
                .padding(10).background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                Text(model.mode == .reconfigure ? "Paste a new token below to switch accounts." : "")
                    .font(.system(size: 11)).foregroundStyle(Tokens.textFaint)
            }

            HStack {
                SecureField("ghp_…", text: $model.token).textFieldStyle(.roundedBorder)
                Button("Validate") { onValidate() }
                    .disabled(model.token.isEmpty || model.isValidating)
            }
            if let err = model.connectError {
                Text(err).font(.system(size: 11, weight: .medium)).foregroundStyle(Tokens.changes)
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 3: RepositoriesStepView**

```swift
import SwiftUI

struct RepositoriesStepView: View {
    @Bindable var model: OnboardingModel
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add repositories").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Enter repositories as **owner/name**. We'll verify each one before adding it. You can track as many as you like.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("owner/name", text: $model.newRepo).textFieldStyle(.roundedBorder)
                    .onSubmit { onAdd() }
                Button { onAdd() } label: {
                    if model.isCheckingRepo { ProgressView().controlSize(.small) } else { Text("Add") }
                }
                .disabled(RepoRef.parse(model.newRepo) == nil || model.isCheckingRepo)
            }
            if let err = model.addError {
                Text(err).font(.system(size: 11, weight: .medium)).foregroundStyle(Tokens.changes)
            }

            if model.pending.isEmpty {
                Text("No repositories yet.").font(.system(size: 12)).foregroundStyle(Tokens.textFaint).padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.pending) { repo in
                            HStack(spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Tokens.textMuted)
                                Text(repo.id).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
                                Spacer()
                                Button { model.removeRepo(id: repo.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Tokens.textFaint)
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 4: NotificationsStepView**

```swift
import SwiftUI
import UserNotifications

struct NotificationsStepView: View {
    @Bindable var model: OnboardingModel
    var onRequestPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications").font(.system(size: 18, weight: .bold)).foregroundStyle(Tokens.text)
            Text("Choose how much each repository notifies you. You can change this any time in Settings.")
                .font(.system(size: 12.5)).foregroundStyle(Tokens.textMuted).fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($model.pending) { $repo in
                        HStack(spacing: 9) {
                            Text(repo.id).font(.system(size: 12.5)).foregroundStyle(Tokens.text)
                            Spacer()
                            Picker("", selection: $repo.level) {
                                Text("Everything").tag(NotificationLevel.everything)
                                Text("Personal").tag(NotificationLevel.personal)
                                Text("None").tag(NotificationLevel.none)
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Tokens.cardBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.border, lineWidth: 0.5))

            permissionRow
            Spacer()
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch model.notifStatus {
        case .authorized, .provisional, .ephemeral:
            HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.approved); Text("macOS notifications enabled").font(.system(size: 12)).foregroundStyle(Tokens.textMuted) }
        case .denied:
            Text("macOS notifications are turned off. Enable them in System Settings → Notifications → PR Tracker.")
                .font(.system(size: 11)).foregroundStyle(Tokens.textFaint)
        default:
            Button("Enable macOS notifications") { onRequestPermission() }
        }
    }
}
```

- [ ] **Step 5: Build + commit**

These reference `OnboardingModel` (exists). Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` — expect BUILD SUCCEEDED.

```bash
git add PRTracker/Views/Onboarding/Steps/
git commit -m "feat: onboarding step content views"
```

---

## Task 8: `OnboardingView` container + async orchestration + RootView wiring

**Files:**
- Rewrite: `PRTracker/Views/Onboarding/OnboardingView.swift`
- Modify: `PRTracker/App/RootView.swift` (firstRun call site + complete Task 5 Step 3 sheet line)

No unit test (view + async glue); verified by build + manual.

- [ ] **Step 1: Rewrite OnboardingView**

Replace the entire contents of `PRTracker/Views/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let mode: OnboardingModel.Mode
    let keychain: Keychain
    let client: GitHubClient
    let coordinator: SyncCoordinator

    @State private var model: OnboardingModel
    @State private var didSeed = false

    init(mode: OnboardingModel.Mode, keychain: Keychain, client: GitHubClient, coordinator: SyncCoordinator) {
        self.mode = mode
        self.keychain = keychain
        self.client = client
        self.coordinator = coordinator
        _model = State(initialValue: OnboardingModel(mode: mode))
    }

    private let steps = OnboardingModel.Step.allCases

    var body: some View {
        HStack(spacing: 0) {
            OnboardingStepRail(steps: steps, current: model.step) { step in
                if step.rawValue <= model.step.rawValue { model.step = step }
            }
            .background(Tokens.cardBg)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                content.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                navBar.padding(.horizontal, 24).padding(.vertical, 14)
            }
        }
        .frame(width: 660, height: 480)
        .task {
            if !didSeed {
                didSeed = true
                if mode == .reconfigure { model.seed(from: ctx) }
                model.notifStatus = await NotificationAuthorization().currentStatus()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStepView()
        case .connect: ConnectStepView(model: model, onValidate: { Task { await validateToken() } })
        case .repositories: RepositoriesStepView(model: model, onAdd: { Task { await addRepo() } })
        case .notifications: NotificationsStepView(model: model, onRequestPermission: { Task { await requestPermission() } })
        }
    }

    private var navBar: some View {
        HStack {
            if mode == .reconfigure { Button("Cancel") { dismiss() } }
            if model.step != .welcome {
                Button("Back") { if let prev = OnboardingModel.Step(rawValue: model.step.rawValue - 1) { model.step = prev } }
            }
            Spacer()
            if model.step == .notifications {
                Button(mode == .reconfigure ? "Save" : "Finish") { finish() }
                    .buttonStyle(.glassProminent).controlSize(.large)
            } else {
                Button("Continue") { advance() }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(!model.canContinue(from: model.step))
            }
        }
    }

    private func advance() {
        guard model.canContinue(from: model.step),
              let next = OnboardingModel.Step(rawValue: model.step.rawValue + 1) else { return }
        model.step = next
    }

    private func finish() {
        model.commit(into: ctx)
        if mode == .firstRun {
            coordinator.start()
        } else {
            Task { await coordinator.refresh() }
            dismiss()
        }
    }

    private func validateToken() async {
        model.isValidating = true; defer { model.isValidating = false }
        keychain.save(model.token)
        do {
            let dto = try await client.validate()
            model.applyValidatedViewer(dto)
            model.token = ""
        } catch {
            keychain.delete()
            model.connectError = "That token was rejected. Check it has repo access and try again."
        }
    }

    private func addRepo() async {
        guard let ref = RepoRef.parse(model.newRepo) else { return }
        if model.pending.contains(where: { $0.id == ref.slug }) {
            model.addError = "That repository is already in your list."; return
        }
        model.isCheckingRepo = true; defer { model.isCheckingRepo = false }
        model.addError = nil
        do {
            _ = try await client.repository(ref)
            _ = model.addRepo(model.newRepo)
            model.newRepo = ""
        } catch GitHubError.repoNotFound {
            model.addError = "Couldn't find \(ref.slug), or your token can't access it."
        } catch GitHubError.unauthorized {
            model.addError = "Your token can't access \(ref.slug)."
        } catch {
            model.addError = "Couldn't reach GitHub. Check your connection and try again."
        }
    }

    private func requestPermission() async {
        model.notifStatus = await NotificationAuthorization().requestAuthorization()
    }
}
```

- [ ] **Step 2: Wire RootView (firstRun) + complete the reconfigure sheet**

In `PRTracker/App/RootView.swift`, replace the `else` branch of the `signedIn` `if` (the current `OnboardingView(keychain:client:onReady:)`) with:

```swift
            } else {
                OnboardingView(mode: .firstRun, keychain: keychain, client: client, coordinator: coordinator)
            }
```

Confirm the `MainView(keychain:client:coordinator:onOpenSettings:)` call site and the `.sheet { OnboardingView(mode: .reconfigure, …) }` from Task 5 Step 3 are present (complete them now if deferred).

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' build` — expect BUILD SUCCEEDED. Fix any signature mismatches (the old `onReady` parameter is gone).

- [ ] **Step 4: Full test run**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` — expect TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add PRTracker/Views/Onboarding/OnboardingView.swift PRTracker/App/RootView.swift
git commit -m "feat: stepped onboarding container and first-run/reconfigure wiring"
```

---

## Task 9: End-to-end verification

**Files:** none (manual).

- [ ] **Step 1: Build + tests green**

Run: `xcodebuild -scheme PRTracker -destination 'platform=macOS' test` — expect TEST SUCCEEDED.

- [ ] **Step 2: First-run (use the `run` skill or launch the built app)**

To simulate a fresh install: sign out (Settings → Account → Sign out) and remove repos, or delete the local store. Confirm:
- Welcome → Connect: a bad token shows the inline rejection; a good token shows your avatar + login with a ✓ and enables Continue.
- Repositories: a real `owner/name` adds after a brief check; a bogus one shows "Couldn't find …"; Continue is disabled until ≥1 repo.
- Notifications: each repo shows a level menu (default Personal); "Enable macOS notifications" requests permission and the row updates.
- Finish → lands in the app with the repos tracked and **no notification storm** (first sync baselines silently).

- [ ] **Step 3: Reconfigure**

Menu → **Set Up PR Tracker Again…**: the sheet opens pre-filled (Connected as you; current repos listed; current levels shown). Remove a repo, add another, change a level, then **Cancel** → nothing changed. Reopen, make the same edits, **Save** → reconciled: the kept repo still has its cached PRs, the removed repo is gone, the new repo syncs in. Changing the level of a kept repo persists.

- [ ] **Step 4: Final commit (if any fixups)**

```bash
git add -A && git commit -m "test: verify onboarding first-run and reconfigure"
```
