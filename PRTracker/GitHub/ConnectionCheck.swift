import Foundation

enum ConnectionCheckStatus: String, Equatable, Sendable {
    case ok
    case warning
    case failure
}

struct ConnectionCheckItem: Identifiable, Equatable {
    let id: String
    let title: String
    let status: ConnectionCheckStatus
    let message: String
    let action: GitHubErrorAction?
}

struct ConnectionCheckResult: Equatable {
    let viewer: UserDTO?
    let metadata: GitHubTokenMetadata
    let items: [ConnectionCheckItem]
    let identityError: GitHubError?

    var isHealthy: Bool {
        !items.contains { $0.status == .failure }
    }
}

struct ConnectionCheck {
    let client: GitHubClient
    let token: String

    func run(repos: [RepoRef]) async -> ConnectionCheckResult {
        var items: [ConnectionCheckItem] = []
        let metadata: GitHubTokenMetadata
        let viewer: UserDTO?

        do {
            let response = try await client.validateWithMetadata()
            viewer = response.value
            metadata = GitHubTokenMetadata(token: token, headers: response.headers)
        } catch let error as GitHubError {
            viewer = nil
            metadata = GitHubTokenMetadata(token: token, headers: [:])
            items.append(item(id: "identity", title: "Identity", status: .failure,
                              message: error.userFacing.detail, action: error.userFacing.action))
            items.append(tokenTypeItem(metadata))
            return ConnectionCheckResult(viewer: viewer, metadata: metadata, items: items, identityError: error)
        } catch {
            viewer = nil
            metadata = GitHubTokenMetadata(token: token, headers: [:])
            let problem = GitHubError.network(message: error.localizedDescription).userFacing
            items.append(item(id: "identity", title: "Identity", status: .failure,
                              message: problem.detail, action: problem.action))
            items.append(tokenTypeItem(metadata))
            return ConnectionCheckResult(viewer: viewer, metadata: metadata, items: items, identityError: .network(message: error.localizedDescription))
        }

        items.append(item(id: "identity", title: "Identity", status: .ok,
                          message: "Signed in as \(viewer?.login ?? "GitHub user").", action: nil))
        items.append(tokenTypeItem(metadata))
        items.append(scopeItem(metadata))
        items.append(expiryItem(metadata))

        do {
            let response = try await client.organizationsWithMetadata()
            if GitHubTokenMetadata.hasPartialSSO(in: response.headers) {
                items.append(item(
                    id: "sso",
                    title: "Organization SSO",
                    status: .warning,
                    message: "This token isn't authorized for one or more of your organizations. Configure SSO on the token's page.",
                    action: GitHubErrorAction(label: "Configure SSO", url: GitHubTokenGuide.tokenURL)))
            } else {
                items.append(item(id: "sso", title: "Organization SSO", status: .ok,
                                  message: "Organizations are authorized.", action: nil))
            }
        } catch let error as GitHubError {
            let problem = error.userFacing
            items.append(item(id: "sso", title: "Organization SSO", status: .failure,
                              message: problem.detail, action: problem.action))
        } catch {
            let problem = GitHubError.network(message: error.localizedDescription).userFacing
            items.append(item(id: "sso", title: "Organization SSO", status: .failure,
                              message: problem.detail, action: problem.action))
        }

        for repo in repos {
            await check(repo: repo, metadata: metadata, into: &items)
        }

        return ConnectionCheckResult(viewer: viewer, metadata: metadata, items: items, identityError: nil)
    }

    private func check(repo: RepoRef, metadata: GitHubTokenMetadata, into items: inout [ConnectionCheckItem]) async {
        let prefix = "repo:\(repo.slug)"
        let repoResponse: GitHubResponse<RepoDTO>
        do {
            repoResponse = try await client.repositoryWithMetadata(repo)
            items.append(item(id: "\(prefix):reachable", title: "\(repo.slug) reachable",
                              status: .ok, message: "Repository is accessible.", action: nil))
        } catch let error as GitHubError {
            let problem = repoProblem(error, metadata: metadata)
            items.append(item(id: "\(prefix):reachable", title: "\(repo.slug) reachable",
                              status: .failure, message: problem.detail, action: problem.action))
            return
        } catch {
            let problem = GitHubError.network(message: error.localizedDescription).userFacing
            items.append(item(id: "\(prefix):reachable", title: "\(repo.slug) reachable",
                              status: .failure, message: problem.detail, action: problem.action))
            return
        }

        do {
            _ = try await client.probePullRequests(repo: repo)
            items.append(item(id: "\(prefix):pulls", title: "\(repo.slug) pull requests",
                              status: .ok, message: "Pull requests are readable.", action: nil))
        } catch let error as GitHubError {
            let problem: GitHubErrorPresentation
            if case .forbidden = error {
                problem = GitHubErrorPresentation(
                    title: "Pull requests unavailable.",
                    detail: "Token can't read pull requests here. Fine-grained tokens need Pull requests: Read.",
                    action: nil)
            } else {
                problem = error.userFacing
            }
            items.append(item(id: "\(prefix):pulls", title: "\(repo.slug) pull requests",
                              status: .failure, message: problem.detail, action: problem.action))
        } catch {
            let problem = GitHubError.network(message: error.localizedDescription).userFacing
            items.append(item(id: "\(prefix):pulls", title: "\(repo.slug) pull requests",
                              status: .failure, message: problem.detail, action: problem.action))
        }

        do {
            let branch = repoResponse.value.default_branch ?? "main"
            _ = try await client.probeCheckRuns(repo: repo, ref: branch)
            items.append(item(id: "\(prefix):checks", title: "\(repo.slug) CI checks",
                              status: .ok, message: "CI checks are readable.", action: nil))
        } catch let error as GitHubError {
            let problem: GitHubErrorPresentation
            if case .forbidden = error {
                problem = GitHubErrorPresentation(
                    title: "CI checks unavailable.",
                    detail: "Token can't read CI checks here. Fine-grained tokens need Checks: Read.",
                    action: nil)
            } else {
                problem = error.userFacing
            }
            items.append(item(id: "\(prefix):checks", title: "\(repo.slug) CI checks",
                              status: .failure, message: problem.detail, action: problem.action))
        } catch {
            let problem = GitHubError.network(message: error.localizedDescription).userFacing
            items.append(item(id: "\(prefix):checks", title: "\(repo.slug) CI checks",
                              status: .failure, message: problem.detail, action: problem.action))
        }
    }

    private func tokenTypeItem(_ metadata: GitHubTokenMetadata) -> ConnectionCheckItem {
        let label: String
        switch metadata.type {
        case .classic: label = "Classic personal access token"
        case .fineGrained: label = "Fine-grained personal access token"
        case .other: label = "Personal access token"
        }
        return item(id: "token-type", title: "Token type", status: .ok, message: label, action: nil)
    }

    private func scopeItem(_ metadata: GitHubTokenMetadata) -> ConnectionCheckItem {
        guard metadata.type == .classic else {
            return item(id: "scope", title: "Classic token scope", status: .ok,
                        message: "Fine-grained token permissions are checked per repository.", action: nil)
        }
        guard metadata.scopes.contains("repo") else {
            return item(
                id: "scope",
                title: "Classic token scope",
                status: .failure,
                message: "Token is missing the `repo` scope. Create a new one with the link above.",
                action: GitHubErrorAction(label: "Create a token", url: GitHubTokenGuide.tokenURL))
        }
        return item(id: "scope", title: "Classic token scope", status: .ok,
                    message: "The `repo` scope is present.", action: nil)
    }

    private func expiryItem(_ metadata: GitHubTokenMetadata) -> ConnectionCheckItem {
        guard let expiration = metadata.expiration else {
            return item(id: "expiry", title: "Expiration", status: .ok,
                        message: "No expiration reported.", action: nil)
        }
        let warningDate = Date.now.addingTimeInterval(30 * 24 * 60 * 60)
        let status: ConnectionCheckStatus = expiration < warningDate ? .warning : .ok
        return item(id: "expiry", title: "Expiration", status: status,
                    message: "Expires on \(expiration.formatted(date: .abbreviated, time: .omitted)).", action: nil)
    }

    private func repoProblem(_ error: GitHubError, metadata: GitHubTokenMetadata) -> GitHubErrorPresentation {
        var problem = error.userFacing
        if metadata.type == .fineGrained {
            if case .repoNotFound = error {
                problem = GitHubErrorPresentation(
                    title: problem.title,
                    detail: "\(problem.detail) If you just created a fine-grained token, oreillymedia may still need to approve it.",
                    action: problem.action)
            } else if case .forbidden = error {
                problem = GitHubErrorPresentation(
                    title: problem.title,
                    detail: "\(problem.detail) If you just created a fine-grained token, oreillymedia may still need to approve it.",
                    action: problem.action)
            }
        }
        return problem
    }

    private func item(id: String, title: String, status: ConnectionCheckStatus,
                      message: String, action: GitHubErrorAction?) -> ConnectionCheckItem {
        ConnectionCheckItem(id: id, title: title, status: status, message: message, action: action)
    }
}
