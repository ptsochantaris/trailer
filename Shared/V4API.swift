import CoreData
import Foundation

extension API {
    static func canUseV4API(for moc: NSManagedObjectContext) -> String? {
        let servers = ApiServer.allApiServers(in: moc)
        if servers.contains(where: { $0.goodToGo && $0.graphQLPath.isEmpty }) {
            Logging.log("Warning: Some servers have a blank v4 API path")
            return Settings.v4DAPIessage
        }

        if Repo.nullNodeIdItems(in: moc) > 0 {
            Logging.log("Warning: Some repos still have a null node ID")
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
            if contains(.reactions) { ret.append("Reactions") }
            if contains(.reviews) { ret.append("Reviews") }
            if contains(.comments) { ret.append("Comments") }
            if contains(.reviewRequests) { ret.append("Requests") }
            if contains(.statuses) { ret.append("Statuses") }
            return ret.joined(separator: ", ")
        }
    }

    static func v4Sync(_ repos: [Repo], to moc: NSManagedObjectContext) async throws {
        let servers = ApiServer.allApiServers(in: moc).filter(\.goodToGo)

        var steps: SyncSteps = [.comments]

        if shouldSyncReviewAssignments {
            steps.insert(.reviewRequests)
        }

        if shouldSyncReviews {
            steps.insert(.reviews)
        } else {
            for r in Review.allItems(in: moc) {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        let prTask = Task {
            await withTaskGroup(of: Void.self) { group in
                if !servers.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllAuthoredPrs(from: servers)
                        Logging.log("Fetching authored PRs phase complete")
                    }
                }
                if !repos.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllSubscribedPrs(from: repos)
                        Logging.log("Fetching subscribed PRs phase complete")
                    }
                }
            }
            let newOrUpdatedPrs = PullRequest.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)

            try await withThrowingTaskGroup(of: Void.self) { group in
                if Settings.showStatusItems {
                    group.addTask { @MainActor in
                        let prs = PullRequest.statusCheckBatch(in: moc)
                        try await GraphQL.update(for: prs, steps: [.statuses])
                        Logging.log("Status fetch phase complete")
                    }
                } else {
                    for p in PullRequest.allItems(in: moc) {
                        p.lastStatusScan = nil
                        p.statuses.forEach {
                            $0.postSyncAction = PostSyncAction.delete.rawValue
                        }
                    }
                }
                if Settings.notifyOnItemReactions {
                    group.addTask { @MainActor in
                        let rp = PullRequest.reactionCheckBatch(in: moc)
                        try await GraphQL.update(for: rp, steps: [.reactions])
                        Logging.log("PR reactions fetch phase complete")
                    }
                }
                try await group.waitForAll()
            }

            try await GraphQL.update(for: newOrUpdatedPrs, steps: steps)
            Logging.log("PR extras fetch phase complete")

            let reviews = Review.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)
            try await GraphQL.updateComments(for: reviews)
            Logging.log("Review comment fetch phase complete")
        }

        let issueTask = Task {
            await withTaskGroup(of: Void.self) { group in
                if !servers.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllAuthoredIssues(from: servers)
                        Logging.log("Fetching authored issues phase complete")
                    }
                }
                if !repos.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllSubscribedIssues(from: repos)
                        Logging.log("Fetching subscribed issues phase complete")
                    }
                }
            }

            let newOrUpdatedIssues = Issue.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)
            try await GraphQL.update(for: newOrUpdatedIssues, steps: steps)
            Logging.log("Issue extras fetch phase complete")

            if Settings.notifyOnItemReactions {
                let ri = Issue.reactionCheckBatch(in: moc)
                try await GraphQL.update(for: ri, steps: [.reactions])
                Logging.log("Issue reaction fetch phase complete")
            }
        }

        try await prTask.value
        try await issueTask.value

        if Settings.notifyOnCommentReactions {
            let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)
            for c in comments {
                c.pendingReactionScan = false
                for r in c.reactions {
                    r.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
            try await GraphQL.updateReactions(for: comments)
            Logging.log("Comment reaction fetch phase complete")
        }
        
        Logging.log("V4 API phase complete")
    }
}
