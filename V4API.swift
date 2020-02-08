import Foundation
import CoreData

extension API {
    static func canUseV4API(for moc: NSManagedObjectContext) -> String? {
        let servers = ApiServer.allApiServers(in: moc)
        if servers.contains(where: { $0.goodToGo && S($0.graphQLPath).isEmpty }) {
            DLog("Warning: Some servers have a blank v4 API path")
            return Settings.v4DAPIessage
        }
        
        var c = 0
        c += DataItem.nullNodeIdItems(of: Repo.self, in: moc)
        c += DataItem.nullNodeIdItems(of: PullRequest.self, in: moc)
        c += DataItem.nullNodeIdItems(of: PRStatus.self, in: moc)
        c += DataItem.nullNodeIdItems(of: PRComment.self, in: moc)
        c += DataItem.nullNodeIdItems(of: PRLabel.self, in: moc)
        c += DataItem.nullNodeIdItems(of: Issue.self, in: moc)
        c += DataItem.nullNodeIdItems(of: Team.self, in: moc)
        c += DataItem.nullNodeIdItems(of: Review.self, in: moc)
        c += DataItem.nullNodeIdItems(of: Reaction.self, in: moc)

        if c > 0 {
            DLog("Warning: Some items still have a null node ID")
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
            checkPrMerges(in: moc)
            checkClosures(of: PullRequest.self, in: moc)
            checkClosures(of: Issue.self, in: moc)

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
    
    static func checkPrMerges(in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.merged.excludingPredicate, ItemCondition.merged.matchingPredicate])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let items = try! moc.fetch(f)
        for i in items.filter({ $0.shouldCheckForClosing }) {
            i.stateChanged = ListableItem.StateChange.merged.rawValue
        }
    }

    static func checkClosures<T: ListableItem>(of: T.Type, in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<T>(entityName: String(describing: T.self))
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.closed.excludingPredicate, ItemCondition.closed.matchingPredicate])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let items = try! moc.fetch(f)
        for i in items.filter({ $0.shouldCheckForClosing }) {
            i.stateChanged = ListableItem.StateChange.closed.rawValue
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
