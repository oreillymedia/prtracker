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

    /// Reconfigure mode: pre-fill from the current store (existing viewer + repos).
    func seed(from ctx: ModelContext) {
        if let u = (try? ctx.fetch(FetchDescriptor<ViewerState>()))?.first?.viewer {
            viewer = UserDTO(login: u.login, name: u.name, avatar_url: u.avatarURL)
        }
        let repos = (try? ctx.fetch(FetchDescriptor<Repo>(sortBy: [SortDescriptor(\Repo.id)]))) ?? []
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
        // Fetch all Users and filter in-memory to avoid #Predicate capture issues.
        let all = (try? ctx.fetch(FetchDescriptor<User>())) ?? []
        if let u = all.first(where: { $0.login == dto.login }) {
            u.name = dto.name; u.avatarURL = dto.avatar_url
            return u
        }
        let u = User(login: dto.login, name: dto.name, avatarURL: dto.avatar_url)
        ctx.insert(u)
        return u
    }
}
