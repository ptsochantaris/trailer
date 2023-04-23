import CoreData
import Foundation

extension API {
    static func canUseV4API(for moc: NSManagedObjectContext) -> String? {
        let servers = ApiServer.allApiServers(in: moc)
        if servers.contains(where: { $0.goodToGo && S($0.graphQLPath).isEmpty }) {
            DLog("Warning: Some servers have a blank v4 API path")
            return Settings.v4DAPIessage
        }

        if DataItem.nullNodeIdItems(of: Repo.self, in: moc) > 0 {
            DLog("Warning: Some repos still have a null node ID")
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
            for r in DataItem.allItems(of: Review.self, in: moc) {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        let prTask = Task {
            await withTaskGroup(of: Void.self) { group in
                if !servers.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllAuthoredPrs(from: servers)
                    }
                }
                if !repos.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllSubscribedPrs(from: repos)
                    }
                }
            }
            let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)

            try await withThrowingTaskGroup(of: Void.self) { group in
                if Settings.showStatusItems {
                    group.addTask { @MainActor in
                        let prs = PullRequest.statusCheckBatch(in: moc)
                        try await GraphQL.update(for: prs, steps: [.statuses])
                    }
                } else {
                    for p in DataItem.allItems(of: PullRequest.self, in: moc) {
                        p.lastStatusScan = nil
                        p.statuses.forEach {
                            $0.postSyncAction = PostSyncAction.delete.rawValue
                        }
                    }
                }
                if Settings.notifyOnItemReactions {
                    group.addTask { @MainActor in
                        let rp = PullRequest.reactionCheckBatch(for: PullRequest.self, in: moc)
                        try await GraphQL.update(for: rp, steps: [.reactions])
                    }
                }
                try await group.waitForAll()
            }

            try await GraphQL.update(for: newOrUpdatedPrs, steps: steps)

            let reviews = DataItem.newOrUpdatedItems(of: Review.self, in: moc, fromSuccessfulSyncOnly: true)
            try await GraphQL.updateComments(for: reviews)
        }

        let issueTask = Task {
            await withTaskGroup(of: Void.self) { group in
                if !servers.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllAuthoredIssues(from: servers)
                    }
                }
                if !repos.isEmpty {
                    group.addTask { @MainActor in
                        await GraphQL.fetchAllSubscribedIssues(from: repos)
                    }
                }
            }
            
            let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)
            try await GraphQL.update(for: newOrUpdatedIssues, steps: steps)

            if Settings.notifyOnItemReactions {
                let ri = Issue.reactionCheckBatch(for: Issue.self, in: moc)
                try await GraphQL.update(for: ri, steps: [.reactions])
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
        }
    }
}
