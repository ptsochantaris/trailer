import CoreData
import Foundation

extension API {
    static func canUseV4API(for moc: NSManagedObjectContext) -> String? {
        let servers = ApiServer.allApiServers(in: moc)
        if servers.contains(where: { $0.goodToGo && $0.graphQLPath.isEmpty }) {
            Task {
                await Logging.shared.log("Warning: Some servers have a blank v4 API path")
            }
            return Settings.v4DAPIessage
        }

        if Repo.nullNodeIdItems(in: moc) > 0 {
            Task {
                await Logging.shared.log("Warning: Some repos still have a null node ID")
            }
            return Settings.v4DBMessage
        }

        return nil
    }

    // MARK: V4 API

    struct SyncSteps: OptionSet {
        let rawValue: Int

        static let reactions = SyncSteps(rawValue: 1 << 0)
        static let reviews = SyncSteps(rawValue: 1 << 1)
        static let comments = SyncSteps(rawValue: 1 << 2)
        static let reviewRequests = SyncSteps(rawValue: 1 << 3)
        static let statuses = SyncSteps(rawValue: 1 << 4)

        var toString: String {
            var ret = [String]()
            if contains(.reactions) {
                ret.append("Reactions")
            }
            if contains(.reviews) {
                ret.append("Reviews")
            }
            if contains(.comments) {
                ret.append("Comments")
            }
            if contains(.reviewRequests) {
                ret.append("Requests")
            }
            if contains(.statuses) {
                ret.append("Statuses")
            }
            return ret.joined(separator: ", ")
        }
    }

    static func v4Sync(_ repos: [Repo], to moc: NSManagedObjectContext, settings: Settings.Cache) async throws {
        try await V4Sync(repos: repos, moc: moc, settings: settings).run()
    }
}

// The V4 sync fan-out, a main-actor class for the same reason as `V3Sync` — see the commentary
// there. The constraint is milder here because nothing in this file is per-item: every child task
// used to capture `servers`, `repos`, `moc` or `settings`, all of which simply become stored
// properties, so no object IDs are needed at all.
//
// The same convention still applies, and is what makes it work: each `addTask` closure is a single
// call to a method here and captures nothing but `self`, with isolation declared on the method
// rather than on the closure. Reading `self.servers` directly inside an unannotated closure would
// not compile, since the closure is not itself main-actor isolated.
@MainActor
private final class V4Sync {
    private let repos: [Repo]
    private let servers: [ApiServer]
    private let moc: NSManagedObjectContext
    private let settings: Settings.Cache
    private let steps: API.SyncSteps

    init(repos: [Repo], moc: NSManagedObjectContext, settings: Settings.Cache) {
        self.repos = repos
        self.moc = moc
        self.settings = settings
        servers = ApiServer.allApiServers(in: moc).filter(\.goodToGo)

        var steps: API.SyncSteps = [.comments]
        if settings.shouldSyncReviewAssignments {
            steps.insert(.reviewRequests)
        }
        if settings.shouldSyncReviews {
            steps.insert(.reviews)
        }
        self.steps = steps
    }

    private func object<T: NSManagedObject>(with id: NSManagedObjectID) async -> T? {
        await moc.syncObject(with: id)
    }

    func run() async throws {
        if !settings.shouldSyncReviews {
            for r in Review.allItems(in: moc) {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        let prTask = Task { try await syncPullRequests() }
        let issueTask = Task { try await syncIssues() }

        try await prTask.value
        try await issueTask.value

        if settings.notifyOnCommentReactions {
            try await syncCommentReactions()
        }

        await Logging.shared.log("V4 API phase complete")
    }

    // MARK: - Pull requests

    private func syncPullRequests() async throws {
        await withTaskGroup { group in
            if !servers.isEmpty {
                group.addTask { [self] in
                    await fetchAuthoredPrs()
                }
            }
            if !repos.isEmpty {
                group.addTask { [self] in
                    await fetchSubscribedPrs()
                }
            }
        }

        let newOrUpdatedPrs = PullRequest.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)

        try await withThrowingTaskGroup { group in
            if settings.showStatusItems {
                group.addTask { [self] in
                    try await fetchStatuses()
                }
            } else {
                for p in PullRequest.allItems(in: moc) {
                    p.lastStatusScan = nil
                    for status in p.statuses {
                        status.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }
            if settings.notifyOnItemReactions {
                group.addTask { [self] in
                    try await fetchPullRequestReactions()
                }
            }
            try await group.waitForAll()
        }

        try await GraphQL.update(for: newOrUpdatedPrs, steps: steps, settings: settings)
        await Logging.shared.log("PR extras fetch phase complete")

        let reviews = Review.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)
        try await GraphQL.updateComments(for: reviews, profile: settings.syncProfile)
        await Logging.shared.log("Review comment fetch phase complete")
    }

    private func fetchAuthoredPrs() async {
        await withTaskGroup { group in
            for server in servers {
                let serverId = server.objectID
                group.addTask { [self] in
                    await fetchAuthoredPrs(serverId: serverId)
                }
            }
        }
        await Logging.shared.log("Fetching authored PRs phase complete")
    }

    private func fetchAuthoredPrs(serverId: NSManagedObjectID) async {
        guard let server: ApiServer = await object(with: serverId) else { return }
        await GraphQL.fetchAuthoredPrs(from: server, settings: settings)
    }

    private func fetchSubscribedPrs() async {
        await GraphQL.fetchAllSubscribedPrs(from: repos, settings: settings)
        await Logging.shared.log("Fetching subscribed PRs phase complete")
    }

    private func fetchStatuses() async throws {
        let prs = PullRequest.statusCheckBatch(in: moc, settings: settings)
        try await GraphQL.update(for: prs, steps: [.statuses], settings: settings)
        await Logging.shared.log("Status fetch phase complete")
    }

    private func fetchPullRequestReactions() async throws {
        let rp = PullRequest.reactionCheckBatch(in: moc, settings: settings)
        try await GraphQL.update(for: rp, steps: [.reactions], settings: settings)
        await Logging.shared.log("PR reactions fetch phase complete")
    }

    // MARK: - Issues

    private func syncIssues() async throws {
        await withTaskGroup { group in
            if !servers.isEmpty {
                group.addTask { [self] in
                    await fetchAuthoredIssues()
                }
            }
            if !repos.isEmpty {
                group.addTask { [self] in
                    await fetchSubscribedIssues()
                }
            }
        }

        let newOrUpdatedIssues = Issue.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)
        try await GraphQL.update(for: newOrUpdatedIssues, steps: steps, settings: settings)
        await Logging.shared.log("Issue extras fetch phase complete")

        if settings.notifyOnItemReactions {
            let ri = Issue.reactionCheckBatch(in: moc, settings: settings)
            try await GraphQL.update(for: ri, steps: [.reactions], settings: settings)
            await Logging.shared.log("Issue reaction fetch phase complete")
        }
    }

    private func fetchAuthoredIssues() async {
        await withTaskGroup { group in
            for server in servers {
                let serverId = server.objectID
                group.addTask { [self] in
                    await fetchAuthoredIssues(serverId: serverId)
                }
            }
        }
        await Logging.shared.log("Fetching authored issues phase complete")
    }

    private func fetchAuthoredIssues(serverId: NSManagedObjectID) async {
        guard let server: ApiServer = await object(with: serverId) else { return }
        await GraphQL.fetchAuthoredIssues(from: server, settings: settings)
    }

    private func fetchSubscribedIssues() async {
        await GraphQL.fetchAllSubscribedIssues(from: repos, settings: settings)
        await Logging.shared.log("Fetching subscribed issues phase complete")
    }

    // MARK: - Comments

    private func syncCommentReactions() async throws {
        let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)
        for c in comments {
            c.pendingReactionScan = false
            for r in c.reactions {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        try await GraphQL.updateReactions(for: comments, profile: settings.syncProfile)
        await Logging.shared.log("Comment reaction fetch phase complete")
    }
}
