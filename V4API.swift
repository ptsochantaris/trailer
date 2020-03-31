import Foundation
import CoreData

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
        
        static let reactions         = SyncSteps(rawValue: 1 << 0)
        static let reviews           = SyncSteps(rawValue: 1 << 1)
        static let comments          = SyncSteps(rawValue: 1 << 2)
        static let reviewRequests    = SyncSteps(rawValue: 1 << 3)
        static let statuses          = SyncSteps(rawValue: 1 << 4)
        
        var toString: String {
            var ret = [String]()
            if self.contains(.reactions) { ret.append("Reactions") }
            if self.contains(.reviews) { ret.append("Reviews") }
            if self.contains(.comments) { ret.append("Comments") }
            if self.contains(.reviewRequests) { ret.append("Requests") }
            if self.contains(.statuses) { ret.append("Statuses") }
            return ret.joined(separator: ", ")
        }
    }
    
    static func v4Sync(to moc: NSManagedObjectContext, newOrUpdatedPrs: [PullRequest], newOrUpdatedIssues: [Issue], with group: DispatchGroup) {
        var steps: SyncSteps = [.comments]

        if shouldSyncReviewAssignments {
            steps.insert(.reviewRequests)
        }

        if Settings.notifyOnItemReactions {
            steps.insert(.reactions)
        }

        if Settings.showStatusItems {
            steps.insert(.statuses)
        } else {
            for p in DataItem.allItems(of: PullRequest.self, in: moc) {
                p.lastStatusScan = nil
                p.statuses.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
        }
        
        if shouldSyncReviews {
            steps.insert(.reviews)
        } else {
            for r in DataItem.allItems(of: Review.self, in: moc) {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        
        v4_sync(to: moc, prs: newOrUpdatedPrs, issues: newOrUpdatedIssues, steps: steps) { error in
            if Settings.notifyOnCommentReactions {
                let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)
                for c in comments {
                    c.pendingReactionScan = false
                    for r in c.reactions {
                        r.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
                GraphQL.updateReactions(for: comments, moc: moc) { error in
                    group.leave()
                }
                
            } else {
                group.leave()
            }
        }
    }
        
    private static func v4_sync(to moc: NSManagedObjectContext, prs: [PullRequest], issues: [Issue], steps: SyncSteps, callback: @escaping (Error?)->Void) {
        var steps = steps
        
        let group = DispatchGroup()
        var finalError: Error?
        
        if steps.contains(.statuses) {
            group.enter()
            let prs = PullRequest.statusCheckBatch(in: moc)
            GraphQL.update(for: prs, of: PullRequest.self, in: moc, steps: [.statuses]) { error in
                if let error = error { finalError = error }
                group.leave()
            }
            steps.remove(.statuses)
        }
        
        if steps.contains(.reactions) {
            let rp = PullRequest.reactionCheckBatch(for: PullRequest.self, in: moc)
            group.enter()
            GraphQL.update(for: rp, of: PullRequest.self, in: moc, steps: [.reactions]) { error in
                if let error = error { finalError = error }
                group.leave()
            }
            
            let ri = Issue.reactionCheckBatch(for: Issue.self, in: moc)
            group.enter()
            GraphQL.update(for: ri, of: Issue.self, in: moc, steps: [.reactions]) { error in
                if let error = error { finalError = error }
                group.leave()
            }
            steps.remove(.reactions)
        }

        group.enter()
        GraphQL.update(for: prs, of: PullRequest.self, in: moc, steps: steps) { error in
            if let error = error {
                finalError = error
                group.leave()
            } else {
                let reviews = DataItem.newOrUpdatedItems(of: Review.self, in: moc, fromSuccessfulSyncOnly: true)
                GraphQL.updateComments(for: reviews, moc: moc) { error in // must run after fetching reviews
                    if let error = error { finalError = error }
                    group.leave()
                }
            }
        }
        
        group.enter()
        GraphQL.update(for: issues, of: Issue.self, in: moc, steps: steps) { error in
            if let error = error { finalError = error }
            group.leave()
        }
        
        group.notify(queue: .main) {
            callback(finalError)
        }
    }
}
