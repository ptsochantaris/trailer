import CoreData
import Foundation

extension API {
    private static func handleRepoSync(for repo: Repo, result: DataResult) {
        switch result {
        case .success:
            break // all good
        case .notFound:
            repo.inaccessible = true
            repo.postSyncAction = PostSyncAction.doNothing.rawValue
            for p in repo.pullRequests {
                p.postSyncAction = PostSyncAction.delete.rawValue
            }
            for i in repo.issues {
                i.postSyncAction = PostSyncAction.delete.rawValue
            }
        case .deleted:
            repo.postSyncAction = PostSyncAction.delete.rawValue
        case .failed:
            repo.apiServer.lastSyncSucceeded = false
        }
    }

    private static func fetchItems(for repos: [Repo], in moc: NSManagedObjectContext) async {
        for r in repos {
            for p in r.pullRequests where p.condition == ItemCondition.open.rawValue {
                p.postSyncAction = PostSyncAction.delete.rawValue
            }

            for i in r.issues where i.condition == ItemCondition.open.rawValue {
                i.postSyncAction = PostSyncAction.delete.rawValue
            }

            let apiServer = r.apiServer
            guard apiServer.lastSyncSucceeded else { continue }

            await withTaskGroup(of: Void.self) { group in
                if r.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue {
                    let repoFullName = S(r.fullName)
                    group.addTask { @MainActor in
                        let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls", from: apiServer) { data, _ in
                            await PullRequest.syncPullRequests(from: data, in: r, moc: moc)
                            return false
                        }
                        handleRepoSync(for: r, result: result)
                    }
                }

                if r.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue {
                    let repoFullName = S(r.fullName)
                    group.addTask { @MainActor in
                        let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues", from: apiServer) { data, _ in
                            await Issue.syncIssues(from: data, in: r, moc: moc)
                            return false
                        }
                        handleRepoSync(for: r, result: result)
                    }
                }
            }
        }
    }

    private static func markExtraUpdatedItems(from repos: [Repo]) async {
        await withTaskGroup(of: Void.self) { group in
            for r in repos {
                let repoFullName = S(r.fullName)
                let lastLocalEvent = r.lastScannedIssueEventId
                let isFirstEventSync = lastLocalEvent == 0
                r.lastScannedIssueEventId = 0
                group.addTask { @MainActor in
                    let apiServer = r.apiServer
                    let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues/events", from: apiServer) { data, _ in
                        guard let data, !data.isEmpty else { return true }

                        if isFirstEventSync {
                            DLog("First event check for this repo. Let's ensure all items are marked as updated")
                            for i in r.pullRequests { i.setToUpdatedIfIdle() }
                            for i in r.issues { i.setToUpdatedIfIdle() }
                            r.lastScannedIssueEventId = data.first!["id"] as? Int64 ?? 0
                            return true

                        } else {
                            var numbers = Set<Int64>()
                            var foundLastEvent = false
                            for event in data {
                                if let eventId = event["id"] as? Int64, let issue = event["issue"] as? JSON, let issueNumber = issue["number"] as? Int64 {
                                    if r.lastScannedIssueEventId == 0 {
                                        r.lastScannedIssueEventId = eventId
                                    }
                                    if eventId == lastLocalEvent {
                                        foundLastEvent = true
                                        DLog("Parsed all repo issue events up to the one we already have")
                                        break // we're done
                                    }
                                    if event["event"] as? String != nil {
                                        numbers.insert(issueNumber)
                                    }
                                }
                            }
                            if r.lastScannedIssueEventId == 0 {
                                r.lastScannedIssueEventId = lastLocalEvent
                            }
                            if !numbers.isEmpty {
                                r.markItemsAsUpdated(with: numbers)
                            }
                            return foundLastEvent
                        }
                    }
                    switch result {
                    case .success: break
                    case .deleted, .failed, .notFound:
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    static func v3Sync(_ repos: [Repo], to moc: NSManagedObjectContext) async {
        await fetchItems(for: repos, in: moc)
        let reposWithSomeItems = repos.filter { !$0.issues.isEmpty || !$0.pullRequests.isEmpty }
        await markExtraUpdatedItems(from: reposWithSomeItems)
        let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)
        let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)

        await withTaskGroup(of: Void.self) { group in

            if Settings.showStatusItems {
                group.addTask { @MainActor in
                    await fetchStatusesForCurrentPullRequests(to: moc)
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
                    await fetchItemReactionsIfNeeded(for: PullRequest.self, to: moc)
                }

                group.addTask { @MainActor in
                    await fetchItemReactionsIfNeeded(for: Issue.self, to: moc)
                }
            }

            if Settings.showLabels {
                group.addTask { @MainActor in
                    await fetchLabelsForCurrentPullRequests(for: newOrUpdatedPrs)
                }
                group.addTask { @MainActor in
                    await fetchLabelsForCurrentIssues(for: newOrUpdatedIssues)
                }
            } else {
                for l in DataItem.allItems(of: PRLabel.self, in: moc) {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }
            }

            group.addTask { @MainActor in
                await checkPrClosures(in: moc)
            }

            group.addTask { @MainActor in
                await detectAssignedPullRequests(for: newOrUpdatedPrs)
            }

            if shouldSyncReviewAssignments {
                group.addTask { @MainActor in
                    await fetchReviewAssignmentsForCurrentPullRequests(for: newOrUpdatedPrs)
                }
            }

            await withTaskGroup(of: Void.self) { commentGroup in
                if shouldSyncReviews {
                    commentGroup.addTask { @MainActor in
                        await fetchReviewsForForCurrentPullRequests(to: moc, for: newOrUpdatedPrs)
                        await fetchCommentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs)
                    }
                } else {
                    for r in DataItem.allItems(of: Review.self, in: moc) {
                        r.postSyncAction = PostSyncAction.delete.rawValue
                    }
                    commentGroup.addTask { @MainActor in
                        await fetchCommentsForCurrentPullRequests(to: moc, for: newOrUpdatedPrs)
                    }
                }

                commentGroup.addTask { @MainActor in
                    await fetchCommentsForCurrentIssues(to: moc, for: newOrUpdatedIssues)
                    checkIssueClosures(in: moc)
                }
            }

            if Settings.notifyOnCommentReactions {
                group.addTask { @MainActor in
                    await fetchCommentReactionsIfNeeded(to: moc)
                }
            }
        }
    }

    private static func checkIssueClosures(in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.predicate =
            NSCompoundPredicate(type: .and, subpredicates: [
                ItemCondition.closed.matchingPredicate,
                NSCompoundPredicate(type: .or, subpredicates: [
                    PostSyncAction.isUpdated.matchingPredicate,
                    PostSyncAction.delete.matchingPredicate
                ])
            ])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let items = try! moc.fetch(f)
        for i in items.filter(\.shouldCheckForClosing) {
            i.stateChanged = ListableItem.StateChange.closed.rawValue
            i.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide
        }
    }

    private static func fetchCommentReactionsIfNeeded(to moc: NSManagedObjectContext) async {
        let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)

        if comments.isEmpty {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for c in comments {
                for r in c.reactions {
                    r.postSyncAction = PostSyncAction.delete.rawValue
                }
                guard let reactionUrl = c.reactionsUrl else { continue }
                group.addTask { @MainActor in
                    let result = await RestAccess.getPagedData(at: reactionUrl, from: c.apiServer) { data, _ in
                        await Reaction.syncReactions(from: data, commentId: c.objectID, serverId: c.apiServer.objectID, moc: moc)
                        return false
                    }
                    switch result {
                    case .success:
                        c.pendingReactionScan = false
                    case .deleted, .failed, .notFound:
                        c.apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    private static func fetchItemReactionsIfNeeded<T: ListableItem>(for type: T.Type, to moc: NSManagedObjectContext) async {
        let items = T.reactionCheckBatch(for: type, in: moc)
        if items.isEmpty {
            return
        }

        let now = Date()
        await withTaskGroup(of: Void.self) { group in
            for i in items {
                i.lastReactionScan = now
                for r in i.reactions {
                    r.postSyncAction = PostSyncAction.delete.rawValue
                }
                guard let reactionsUrl = i.reactionsUrl else {
                    continue
                }
                let oid = i.objectID
                let serverId = i.apiServer.objectID
                group.addTask { @MainActor in
                    let apiServer = i.apiServer
                    let result = await RestAccess.getPagedData(at: reactionsUrl, from: apiServer) { data, _ in
                        await Reaction.syncReactions(from: data, parentId: oid, serverId: serverId, moc: moc)
                        return false
                    }
                    switch result {
                    case .success: break
                    case .deleted, .failed, .notFound:
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    private static func fetchCommentsForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest]) async {
        if prs.isEmpty {
            return
        }

        for p in prs {
            for c in p.comments {
                c.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        @MainActor
        @Sendable func _fetchComments(issues: Bool) async {
            await withTaskGroup(of: Void.self) { group in
                for p in prs {
                    if let link = (issues ? p.commentsLink : p.reviewCommentLink) {
                        let apiServer = p.apiServer
                        group.addTask { @MainActor in
                            let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
                                await PRComment.syncComments(from: data, parent: p, moc: moc)
                                return false
                            }
                            switch result {
                            case .success: break
                            case .deleted, .failed, .notFound:
                                apiServer.lastSyncSucceeded = false
                            }
                        }
                    }
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await _fetchComments(issues: true)
            }
            group.addTask { @MainActor in
                await _fetchComments(issues: false)
            }
        }
    }

    private static func fetchCommentsForCurrentIssues(to moc: NSManagedObjectContext, for issues: [Issue]) async {
        if issues.isEmpty {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for i in issues {
                for c in i.comments {
                    c.postSyncAction = PostSyncAction.delete.rawValue
                }

                if let link = i.commentsLink {
                    let apiServer = i.apiServer

                    group.addTask { @MainActor in
                        let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
                            await PRComment.syncComments(from: data, parent: i, moc: moc)
                            return false
                        }
                        switch result {
                        case .success: break
                        case .deleted, .failed, .notFound:
                            apiServer.lastSyncSucceeded = false
                        }
                    }
                }
            }
        }
    }

    private static func fetchReviewsForForCurrentPullRequests(to moc: NSManagedObjectContext, for prs: [PullRequest]) async {
        if prs.isEmpty {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for p in prs {
                for l in p.reviews {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }
                let repoFullName = S(p.repo.fullName)
                group.addTask { @MainActor in
                    let apiServer = p.apiServer
                    let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls/\(p.number)/reviews", from: apiServer) { data, _ in
                        await Review.syncReviews(from: data, withParent: p, moc: moc)
                        return false
                    }
                    switch result {
                    case .success: break
                    case .deleted, .failed, .notFound:
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    private static func investigatePrClosure(for pullRequest: PullRequest) async {
        DLog("Checking closed PR to see if it was merged: %@", pullRequest.title)

        let repoFullName = S(pullRequest.repo.fullName)
        let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

        do {
            let (data, _, result) = try await RestAccess.getData(in: path, from: pullRequest.apiServer)
            switch result {
            case .success:
                if let d = data as? JSON {
                    if let mergeInfo = d["merged_by"] as? JSON, let mergeUserId = mergeInfo["node_id"] as? String {
                        pullRequest.mergedByNodeId = mergeUserId
                        pullRequest.stateChanged = ListableItem.StateChange.merged.rawValue
                        pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleMerging() decide

                    } else {
                        pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
                        pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide
                    }
                }
            case .deleted, .notFound:
                pullRequest.stateChanged = ListableItem.StateChange.closed.rawValue
                pullRequest.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide
            case .failed:
                pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // keep since we don't know what's going on here
                pullRequest.apiServer.lastSyncSucceeded = false
            }
        } catch {
            pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // keep since we don't know what's going on here
            pullRequest.apiServer.lastSyncSucceeded = false
        }
    }

    private static func checkPrClosures(in moc: NSManagedObjectContext) async {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false

        let prsToCheck = try! moc.fetch(f).filter(\.shouldCheckForClosing)

        await withTaskGroup(of: Void.self) { group in
            for r in prsToCheck {
                group.addTask { @MainActor in
                    await investigatePrClosure(for: r)
                }
            }
        }
    }

    private static func fetchReviewAssignmentsForCurrentPullRequests(for prs: [PullRequest]) async {
        await withThrowingTaskGroup(of: Void.self) { group in
            for p in prs {
                group.addTask { @MainActor in
                    let repoFullName = S(p.repo.fullName)
                    let (data, _) = try await RestAccess.getRawData(at: "/repos/\(repoFullName)/pulls/\(p.number)/requested_reviewers", from: p.apiServer)
                    var reviewUsers = Set<String>()
                    var reviewTeams = Set<String>()

                    if let userList = data as? [JSON] {
                        // Legacy API results
                        for userName in userList.compactMap({ $0["login"] as? String }) {
                            reviewUsers.insert(userName)
                        }
                        p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams)

                    } else if let data = data as? JSON, let userList = data["users"] as? [JSON], let teamList = data["teams"] as? [JSON] {
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

    private static func fetchLabelsForCurrentPullRequests(for prs: [PullRequest]) async {
        if prs.isEmpty {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for p in prs {
                for l in p.labels {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }

                guard let link = p.labelsLink else {
                    continue
                }

                group.addTask { @MainActor in
                    let apiServer = p.apiServer
                    let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
                        PRLabel.syncLabels(from: data, withParent: p)
                        return false
                    }
                    switch result {
                    case .deleted, .notFound, .success:
                        break
                    case .failed:
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    private static func fetchLabelsForCurrentIssues(for issues: [Issue]) async {
        if issues.isEmpty {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for i in issues {
                for l in i.labels {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }

                guard let link = i.labelsLink else {
                    continue
                }

                group.addTask { @MainActor in
                    let apiServer = i.apiServer
                    let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
                        PRLabel.syncLabels(from: data, withParent: i)
                        return false
                    }
                    switch result {
                    case .deleted, .notFound, .success:
                        break
                    case .failed:
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
    }

    private static func fetchStatusesForCurrentPullRequests(to moc: NSManagedObjectContext) async {
        let prs = PullRequest.statusCheckBatch(in: moc)
        if prs.isEmpty {
            return
        }

        let now = Date()
        await withTaskGroup(of: Void.self) { group in

            for p in prs {
                for s in p.statuses {
                    s.postSyncAction = PostSyncAction.delete.rawValue
                }

                let apiServer = p.apiServer

                if let statusLink = p.statusesLink {
                    group.addTask { @MainActor in
                        let result = await RestAccess.getPagedData(at: statusLink, from: apiServer) { data, _ in
                            await PRStatus.syncStatuses(from: data, pullRequest: p, moc: moc)
                            return false
                        }
                        switch result {
                        case .deleted, .notFound, .success:
                            p.lastStatusScan = now
                        case .failed:
                            apiServer.lastSyncSucceeded = false
                        }
                    }
                } else {
                    p.lastStatusScan = now
                }
            }
        }
    }

    private static func detectAssignedPullRequests(for prs: [PullRequest]) async {
        await withTaskGroup(of: Void.self) { group in
            for p in prs {
                let apiServer = p.apiServer
                if let issueLink = p.issueUrl {
                    group.addTask { @MainActor in
                        do {
                            let (data, _, _) = try await RestAccess.getData(in: issueLink, from: apiServer)
                            if let d = data as? JSON {
                                p.processAssignmentStatus(from: d, idField: "node_id")
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
