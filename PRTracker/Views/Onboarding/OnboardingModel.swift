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
