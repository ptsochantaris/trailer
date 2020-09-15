import Foundation
import CoreData

extension API {
    static func V3_markExtraUpdatedItems(from repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

        let group = DispatchGroup()

        for r in repos {
            let repoFullName = S(r.fullName)
            let lastLocalEvent = r.lastScannedIssueEventId
            let isFirstEventSync = lastLocalEvent == 0
            r.lastScannedIssueEventId = 0
            group.enter()
            RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues/events", from: r.apiServer, perPageCallback: { data, lastPage in
                guard let data = data, !data.isEmpty else { return true }

                if isFirstEventSync {

                    DLog("First event check for this repo. Let's ensure all items are marked as updated")
                    for i in r.pullRequests { i.setToUpdatedIfIdle() }
                    for i in r.issues { i.setToUpdatedIfIdle() }
                    r.lastScannedIssueEventId = data.first!["id"] as? Int64 ?? 0
                    return true

                } else {

                    var numbers = Set<Int64>()
                    var reasons = Set<String>()
                    var foundLastEvent = false
                    for event in data {
                        if let eventId = event["id"] as? Int64, let issue = event["issue"] as? [AnyHashable:Any], let issueNumber = issue["number"] as? Int64 {
                            if r.lastScannedIssueEventId == 0 {
                                r.lastScannedIssueEventId = eventId
                            }
                            if eventId == lastLocalEvent {
                                foundLastEvent = true
                                DLog("Parsed all repo issue events up to the one we already have");
                                break // we're done
                            }
                            if let reason = event["event"] as? String {
                                numbers.insert(issueNumber)
                                reasons.insert(reason)
                            }
                        }
                    }
                    if r.lastScannedIssueEventId == 0 {
                        r.lastScannedIssueEventId = lastLocalEvent
                    }
                    if !numbers.isEmpty {
                        r.markItemsAsUpdated(with: numbers, reasons: reasons)
                    }
                    return foundLastEvent

                }

            }) { success, resultCode in
                if !success {
                    r.apiServer.lastSyncSucceeded = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }
    
    static func v3Sync(to moc: NSManagedObjectContext, newOrUpdatedPrs: [PullRequest], newOrUpdatedIssues: [Issue], with group: DispatchGroup) {
        
        if Settings.showStatusItems {
            group.enter()
            V3_fetchStatusesForCurrentPullRequests(to: moc) {
                group.leave()
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
            group.enter()
            V3_fetchItemReactionsIfNeeded(for: PullRequest.self, to: moc) {
                group.leave()
            }
            
            group.enter()
            V3_fetchItemReactionsIfNeeded(for: Issue.self, to: moc) {
                group.leave()
            }
        }
        
        if Settings.showLabels {
            group.enter()
            V3_fetchLabelsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs) {
                group.leave()
            }
            group.enter()
            V3_fetchLabelsForCurrentIssues(to: moc, for: newOrUpdatedIssues) {
                group.leave()
            }
        } else {
            for l in DataItem.allItems(of: PRLabel.self, in: moc) {
                l.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        
        let commentGroup = DispatchGroup()
        
        if shouldSyncReviews {
            commentGroup.enter()
            V3_fetchReviewsForForCurrentPullRequests(to: moc, for: newOrUpdatedPrs) {
                commentGroup.enter()
                V3_fetchCommentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs) { // some comments may depend on reviews
                    commentGroup.leave()
                }
                commentGroup.leave()
            }
        } else {
            for r in DataItem.allItems(of: Review.self, in: moc) {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
            commentGroup.enter()
            V3_fetchCommentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs) {
                commentGroup.leave()
            }
        }
        
        commentGroup.enter()
        V3_fetchCommentsForCurrentIssues(to: moc, for: newOrUpdatedIssues) {
            V3_checkIssueClosures(in: moc)
            commentGroup.leave()
        }
        
        group.enter()
        V3_checkPrClosures(in: moc) {
            group.leave()
        }
        
        group.enter()
        V3_detectAssignedPullRequests(in: moc, for: newOrUpdatedPrs) {
            group.leave()
        }
        
        if shouldSyncReviewAssignments {
            group.enter()
            V3_fetchReviewAssignmentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs) {
                group.leave()
            }
        }
        
        group.enter()
        commentGroup.notify(queue: .main) {
            if Settings.notifyOnCommentReactions {
                V3_fetchCommentReactionsIfNeeded(to: moc) {
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        
        group.leave() // the one passed-in is already entered
    }
    
    private static func V3_checkIssueClosures(in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.predicate =
            NSCompoundPredicate(type: .and, subpredicates: [
                ItemCondition.closed.matchingPredicate,
                NSCompoundPredicate(type: .or, subpredicates: [
                    PostSyncAction.isUpdated.matchingPredicate,
                    PostSyncAction.delete.matchingPredicate,
                ])
            ])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let items = try! moc.fetch(f)
        for i in items.filter({ $0.shouldCheckForClosing }) {
            i.stateChanged = ListableItem.StateChange.closed.rawValue
        }
    }

    private static func V3_fetchCommentReactionsIfNeeded(to moc: NSManagedObjectContext, callback: @escaping Completion) {
        let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)

        if comments.isEmpty {
            callback()
            return
        }
                
        let group = DispatchGroup()
        
        for c in comments {
            for r in c.reactions {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
            guard let reactionUrl = c.reactionsUrl else { continue }
            let apiServer = c.apiServer
            group.enter()
            RestAccess.getPagedData(at: reactionUrl, from: apiServer, perPageCallback: { data, lastPage in
                Reaction.syncReactions(from: data, comment: c)
                return false
            }) { success, resultCode in
                if success {
                    c.pendingReactionScan = false
                } else {
                    apiServer.lastSyncSucceeded = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchItemReactionsIfNeeded<T: ListableItem>(for type: T.Type, to moc: NSManagedObjectContext, callback: @escaping Completion) {

        let items = T.reactionCheckBatch(for: type, in: moc)
        if items.isEmpty {
            callback()
            return
        }

        let group = DispatchGroup()

        let now = Date()
        for i in items {
            i.lastReactionScan = now
            for r in i.reactions {
                r.postSyncAction = PostSyncAction.delete.rawValue
            }
            guard let reactionsUrl = i.reactionsUrl else {
                continue
            }
            let apiServer = i.apiServer
            group.enter()
            RestAccess.getPagedData(at: reactionsUrl, from: apiServer, perPageCallback: { data, lastPage in
                Reaction.syncReactions(from: data, parent: i)
                return false
            }) { success, resultCode in
                if !success {
                    apiServer.lastSyncSucceeded = false
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }
    
    private static func V3_fetchCommentsForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest], callback: @escaping Completion) {
        if prs.isEmpty {
            callback()
            return
        }
        
        for p in prs {
            for c in p.comments {
                c.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        
        func _fetchComments(for pullRequests: [PullRequest], issues: Bool, in moc: NSManagedObjectContext, callback: @escaping Completion) {

            let group = DispatchGroup()
            for p in pullRequests {
                if let link = (issues ? p.commentsLink : p.reviewCommentLink) {

                    let apiServer = p.apiServer
                    group.enter()
                    RestAccess.getPagedData(at: link, from: apiServer, perPageCallback: { data, lastPage in
                        PRComment.syncComments(from: data, parent: p)
                        return false
                    }) { success, resultCode in
                        if !success {
                            apiServer.lastSyncSucceeded = false
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main, execute: callback)
        }

        let group = DispatchGroup()
        group.enter()
        _fetchComments(for: prs, issues: true, in: moc) {
            group.leave()
        }
        group.enter()
        _fetchComments(for: prs, issues: false, in: moc) {
            group.leave()
        }
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchCommentsForCurrentIssues(to moc: NSManagedObjectContext, for issues: [Issue], callback: @escaping Completion) {
        if issues.isEmpty {
            callback()
            return
        }
        
        let group = DispatchGroup()

        for i in issues {
            for c in i.comments {
                c.postSyncAction = PostSyncAction.delete.rawValue
            }

            if let link = i.commentsLink {
                let apiServer = i.apiServer

                group.enter()
                RestAccess.getPagedData(at: link, from: apiServer, perPageCallback: { data, lastPage in
                    PRComment.syncComments(from: data, parent: i)
                    return false
                }) { success, resultCode in
                    if !success {
                        apiServer.lastSyncSucceeded = false
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchReviewsForForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest], callback: @escaping Completion) {
        if prs.isEmpty {
            callback()
            return
        }

        let group = DispatchGroup()
        for p in prs {
            for l in p.reviews {
                l.postSyncAction = PostSyncAction.delete.rawValue
            }
            let repoFullName = S(p.repo.fullName)
            group.enter()
            RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls/\(p.number)/reviews", from: p.apiServer, perPageCallback: { data, lastPage in
                Review.syncReviews(from: data, withParent: p)
                return false
            }) { success, resultCode in
                if !success {
                    p.apiServer.lastSyncSucceeded = false
                }
                group.leave()
            }
        }
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_investigatePrClosure(for pullRequest: PullRequest, callback: @escaping Completion) {
        DLog("Checking closed PR to see if it was merged: %@", pullRequest.title)

        let repoFullName = S(pullRequest.repo.fullName)
        let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

        RestAccess.getData(in: path, from: pullRequest.apiServer) { data, lastPage, resultCode in

            if let d = data as? [AnyHashable : Any] {
                if let mergeInfo = d["merged_by"] as? [AnyHashable : Any], let mergeUserId = mergeInfo["node_id"] as? String {
                    pullRequest.mergedByNodeId = mergeUserId
                    pullRequest.stateChanged = ListableItem.StateChange.merged.rawValue
                } else {
                    pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
                }
            } else if resultCode == 404 || resultCode == 410 { // PR gone for good
                pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
            } else { // fetch/server problem
                pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // don't delete this, we couldn't check, play it safe
                pullRequest.apiServer.lastSyncSucceeded = false
            }
            callback()
        }
    }

    private static func V3_checkPrClosures(in moc: NSManagedObjectContext, callback: @escaping Completion) {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false

        let prsToCheck = try! moc.fetch(f).filter { $0.shouldCheckForClosing }

        let group = DispatchGroup()
        for r in prsToCheck {
            group.enter()
            V3_investigatePrClosure(for: r) {
                group.leave()
            }
        }
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchReviewAssignmentsForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest], callback: @escaping Completion) {
        if prs.isEmpty {
            callback()
            return
        }
                
        let group = DispatchGroup()
        for p in prs {

            let repoFullName = S(p.repo.fullName)
            group.enter()
            RestAccess.getRawData(at: "/repos/\(repoFullName)/pulls/\(p.number)/requested_reviewers", from: p.apiServer) { data, resultCode in

                var reviewUsers = Set<String>()
                var reviewTeams = Set<String>()

                if let userList = data as? [[AnyHashable: Any]] {
                    // Legacy API results
                    for userName in userList.compactMap({ $0["login"] as? String }) {
                        reviewUsers.insert(userName)
                    }
                    p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams)

                } else if let data = data as? [AnyHashable: Any], let userList = data["users"] as? [[AnyHashable: Any]], let teamList = data["teams"] as? [[AnyHashable: Any]] {
                    // New API results
                    for userName in userList.compactMap({ $0["login"] as? String }) {
                        reviewUsers.insert(userName)
                    }
                    for teamName in teamList.compactMap({ $0["slug"] as? String }) {
                        reviewTeams.insert(teamName)
                    }
                    p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams)
                } else {
                    p.apiServer.lastSyncSucceeded = false
                }

                group.leave() // getRawData
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchLabelsForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest], callback: @escaping Completion) {
        if prs.isEmpty {
            callback()
            return
        }

        let group = DispatchGroup()

        for p in prs {
            for l in p.labels {
                l.postSyncAction = PostSyncAction.delete.rawValue
            }

            guard let link = p.labelsLink else {
                continue
            }
            
            group.enter()
            RestAccess.getPagedData(at: link, from: p.apiServer, perPageCallback: { data, lastPage in
                PRLabel.syncLabels(from: data, withParent: p)
                return false
            }) { success, resultCode in
                if !success {
                    // 404/410 means the label has been deleted
                    if !(resultCode==404 || resultCode==410) {
                        p.apiServer.lastSyncSucceeded = false
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchLabelsForCurrentIssues(to moc: NSManagedObjectContext, for issues: [Issue], callback: @escaping Completion) {
        if issues.isEmpty {
            callback()
            return
        }

        let group = DispatchGroup()

        for i in issues {
            for l in i.labels {
                l.postSyncAction = PostSyncAction.delete.rawValue
            }

            guard let link = i.labelsLink else {
                continue
            }
            
            group.enter()
            RestAccess.getPagedData(at: link, from: i.apiServer, perPageCallback: { data, lastPage in
                PRLabel.syncLabels(from: data, withParent: i)
                return false
            }) { success, resultCode in
                if !success {
                    // 404/410 means the label has been deleted
                    if !(resultCode==404 || resultCode==410) {
                        i.apiServer.lastSyncSucceeded = false
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }

    private static func V3_fetchStatusesForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

        let prs = PullRequest.statusCheckBatch(in: moc)
        
        if prs.isEmpty {
            callback()
            return
        }
        
        let group = DispatchGroup()
        let now = Date()

        for p in prs {
            for s in p.statuses {
                s.postSyncAction = PostSyncAction.delete.rawValue
            }

            let apiServer = p.apiServer

            if let statusLink = p.statusesLink {
                group.enter()
                RestAccess.getPagedData(at: statusLink, from: apiServer, perPageCallback: { data, lastPage in
                    PRStatus.syncStatuses(from: data, pullRequest: p)
                    return false
                }) { success, resultCode in
                    var allGood = success
                    if !success {
                        // 404/410 means the status has been deleted
                        if !(resultCode==404 || resultCode==410) {
                            apiServer.lastSyncSucceeded = false
                        } else {
                            allGood = true
                        }
                    }
                    if allGood {
                        p.lastStatusScan = now
                    }
                    group.leave()
                }
            } else {
                p.lastStatusScan = now
            }
        }
        
        group.notify(queue: .main, execute: callback)
    }
    
    private static func V3_detectAssignedPullRequests(in moc: NSManagedObjectContext, for prs: [PullRequest], callback: @escaping Completion) {
        if prs.isEmpty {
            callback()
            return
        }
                
        let group = DispatchGroup()
        for p in prs {
            let apiServer = p.apiServer
            if let issueLink = p.issueUrl {
                group.enter()
                RestAccess.getData(in: issueLink, from: apiServer) { data, lastPage, resultCode in
                    if resultCode == 200 || resultCode == 404 || resultCode == 410 {
                        if let d = data as? [AnyHashable : Any] {
                            p.processAssignmentStatus(from: d, idField: "node_id")
                        }
                    } else {
                        apiServer.lastSyncSucceeded = false
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: callback)
    }
}
