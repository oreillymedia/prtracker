import Testing
import Foundation
import SwiftData
@testable import PRTracker

@Suite struct PullRequestReadStateTests {
    private func makePR(updatedAt: Date, lastReadAt: Date?) throws -> PullRequest {
        let container = try TestContainer.make()
        let ctx = ModelContext(container)
        let user = User(login: "alex", name: nil, avatarURL: nil)
        let repo = Repo(owner: "oreilly", name: "spark-ios", isActive: true)
        ctx.insert(user); ctx.insert(repo)
        let pr = PullRequest(id: "PR_1", number: 1, title: "T", state: .open,
                             branchHead: "h", branchBase: "main", headSha: "abc",
                             openedAt: updatedAt, updatedAt: updatedAt,
                             author: user, repo: repo)
        pr.lastReadAt = lastReadAt
        ctx.insert(pr)
        try ctx.save()
        return pr
    }

    @Test func unreadWhenNeverRead() throws {
        let pr = try makePR(updatedAt: Date(timeIntervalSince1970: 1000), lastReadAt: nil)
        #expect(pr.isUnread == true)
    }

    @Test func readWhenLastReadAtEqualsUpdatedAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t, lastReadAt: t)
        #expect(pr.isUnread == false)
    }

    @Test func readWhenLastReadAtAfterUpdatedAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t, lastReadAt: t.addingTimeInterval(60))
        #expect(pr.isUnread == false)
    }

    @Test func unreadWhenUpdatedAtAfterLastReadAt() throws {
        let t = Date(timeIntervalSince1970: 1000)
        let pr = try makePR(updatedAt: t.addingTimeInterval(60), lastReadAt: t)
        #expect(pr.isUnread == true)
    }
}
