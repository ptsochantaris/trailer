import Foundation
import CoreData

extension API {
    @MainActor
    private static func v3_handleRepoSyncFailure(repo: Repo, resultCode: Int) {
        if resultCode == 404 { // repo disabled
            repo.inaccessible = true
            repo.postSyncAction = PostSyncAction.doNothing.rawValue
            for p in repo.pullRequests {
                p.postSyncAction = PostSyncAction.delete.rawValue
            }
            for i in repo.issues {
                i.postSyncAction = PostSyncAction.delete.rawValue
            }
        } else if resultCode==410 { // repo gone for good
            repo.postSyncAction = PostSyncAction.delete.rawValue
        } else { // fetch problem
            repo.apiServer.lastSyncSucceeded = false
        }
    }

    @MainActor
    static func v3_fetchItems(for repos: [Repo], to moc: NSManagedObjectContext) async {        
        for r in repos {
            for p in r.pullRequests {
                if p.condition == ItemCondition.open.rawValue {
                    p.postSyncAction = PostSyncAction.delete.rawValue
                }
            }

            for i in r.issues {
                if i.condition == ItemCondition.open.rawValue {
                    i.postSyncAction = PostSyncAction.delete.rawValue
                }
            }

            let apiServer = r.apiServer
            guard apiServer.lastSyncSucceeded else { continue }

            await withTaskGroup(of: Void.self) { group  in
                if r.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue {
                    let repoFullName = S(r.fullName)
                    group.addTask {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls", from: apiServer) { data, lastPage in
                                PullRequest.syncPullRequests(from: data, in: r)
                                return false
                            } finalCallback: { success, resultCode in
                                if !success {
                                    await v3_handleRepoSyncFailure(repo: r, resultCode: resultCode)
                                }
                                continuation.resume()
                            }
                        }
                    }
                }

                if r.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue {
                    let repoFullName = S(r.fullName)
                    group.addTask {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues", from: apiServer) { data, lastPage in
                                Issue.syncIssues(from: data, in: r)
                                return false
                            } finalCallback: { success, resultCode in
                                if !success {
                                    await v3_handleRepoSyncFailure(repo: r, resultCode: resultCode)
                                }
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    static func V3_markExtraUpdatedItems(from repos: [Repo], to moc: NSManagedObjectContext) async {
        await withTaskGroup(of: Void.self) { group in
            for r in repos {
                let repoFullName = S(r.fullName)
                let lastLocalEvent = r.lastScannedIssueEventId
                let isFirstEventSync = lastLocalEvent == 0
                r.lastScannedIssueEventId = 0
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues/events", from: r.apiServer) { data, lastPage in
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
                        } finalCallback: { success, resultCode in
                            if !success {
                                r.apiServer.lastSyncSucceeded = false
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    static func v3Sync(to moc: NSManagedObjectContext, newOrUpdatedPrs: [PullRequest], newOrUpdatedIssues: [Issue]) async {
        
        let group = DispatchGroup()
        
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
        
        var tasks = [Task<Void, Never>]()

        tasks.append(Task {
            await V3_checkPrClosures(in: moc)
        })
        
        tasks.append(Task {
            await V3_detectAssignedPullRequests(in: moc, for: newOrUpdatedPrs)
        })
        
        if shouldSyncReviewAssignments {
            tasks.append(Task {
                await V3_fetchReviewAssignmentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs)
            })
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

        for task in tasks {
            _ = await task.value
        }
        
        await withCheckedContinuation { continuation in
            group.notify(queue: .main) {
                continuation.resume()
            }
        }
    }
    
    @MainActor
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
            i.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide
        }
    }

    @MainActor
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

    @MainActor
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
    
    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    private static func V3_investigatePrClosure(for pullRequest: PullRequest) async {
        DLog("Checking closed PR to see if it was merged: %@", pullRequest.title)

        let repoFullName = S(pullRequest.repo.fullName)
        let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

        do {
            let (data, _, _) = try await RestAccess.getData(in: path, from: pullRequest.apiServer)
            if let d = data as? [AnyHashable : Any] {
                if let mergeInfo = d["merged_by"] as? [AnyHashable : Any], let mergeUserId = mergeInfo["node_id"] as? String {
                    pullRequest.mergedByNodeId = mergeUserId
                    pullRequest.stateChanged = ListableItem.StateChange.merged.rawValue
                    pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleMerging() decide

                } else {
                    pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
                    pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide

                }
            }
        } catch {
            let resultCode = (error as NSError).code
            if resultCode == 404 || resultCode == 410 { // PR gone for good
                pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
                pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide

            } else { // fetch/server problem
                pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // keep since we don't know what's going on here
                pullRequest.apiServer.lastSyncSucceeded = false
            }
        }
    }

    @MainActor
    private static func V3_checkPrClosures(in moc: NSManagedObjectContext) async {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false

        let prsToCheck = try! moc.fetch(f).filter { $0.shouldCheckForClosing }

        await withTaskGroup(of: Void.self) { group in
            for r in prsToCheck {
                group.addTask {
                    await V3_investigatePrClosure(for: r)
                }
            }
        }
    }

    @MainActor
    private static func V3_fetchReviewAssignmentsForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest]) async {
        await withThrowingTaskGroup(of: Void.self) { group in
            for p in prs {
                group.addTask {
                    let repoFullName = S(p.repo.fullName)
                    let (data, _) = try await RestAccess.getRawData(at: "/repos/\(repoFullName)/pulls/\(p.number)/requested_reviewers", from: p.apiServer)
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
                }
            }
        }
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
    
    @MainActor
    private static func V3_detectAssignedPullRequests(in moc: NSManagedObjectContext, for prs: [PullRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for p in prs {
                let apiServer = p.apiServer
                if let issueLink = p.issueUrl {
                    group.addTask {
                        do {
                            let (data, _, resultCode) = try await RestAccess.getData(in: issueLink, from: apiServer)
                            if resultCode == 200 || resultCode == 404 || resultCode == 410 {
                                if let d = data as? [AnyHashable : Any] {
                                    p.processAssignmentStatus(from: d, idField: "node_id")
                                }
                            } else {
                                apiServer.lastSyncSucceeded = false
                            }
                        } catch {
                            apiServer.lastSyncSucceeded = false
                        }
                    }
                }
            }
        }
    }
}
