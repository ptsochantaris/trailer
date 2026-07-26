import CoreData
import Foundation
import TrailerJson

extension API {
    static func v3Sync(_ repos: [Repo], to moc: NSManagedObjectContext, settings: Settings.Cache) async {
        await V3Sync(moc: moc, settings: settings).run(repos: repos)
    }
}

// The V3 sync fan-out. This is a main-actor class rather than a family of static functions for a
// concurrency reason. `TaskGroup.addTask` takes a `sending` closure, meaning its captures must form
// a region disconnected from the enclosing actor; a managed object, or the context it lives in, can
// never satisfy that, because both stay reachable from the main actor. A main-actor-isolated class,
// however, is implicitly Sendable, so a child task can capture `self` and reach `moc` and `settings`
// through it. Managed objects cross the boundary as `NSManagedObjectID` and are re-materialised on
// the main actor inside each method — the same idiom the model layer already uses in `v3items`.
//
// Two conventions make that work, and both matter:
//
// - Every `addTask` closure is a single call to a method here, and captures nothing but `self` plus
//   Sendable scalars. Anything the closure used to do inline now lives in the method it calls.
// - Those closures deliberately carry no `@MainActor` annotation; isolation is declared on the
//   methods instead. Annotating the closure trips a region-isolation checker bug ("pattern that the
//   region-based isolation checker does not understand how to check"), which is a hard error in the
//   Swift 6 language mode. Calling a `@MainActor` method from an unannotated closure is equivalent —
//   every Core Data access still happens on the main actor — and compiles cleanly.
//
// Nothing here blocks the main thread: the awaits are network I/O, which suspends and releases the
// actor, so the fan-out keeps exactly the request concurrency it always had.
@MainActor
private final class V3Sync {
    private let moc: NSManagedObjectContext
    private let settings: Settings.Cache

    // Populated once, after the item fetch, then read by the second-stage fan-out. These are stored
    // rather than passed so that the child task closures need only capture `self`.
    private var newOrUpdatedPrs: [PullRequest] = []
    private var newOrUpdatedIssues: [Issue] = []

    init(moc: NSManagedObjectContext, settings: Settings.Cache) {
        self.moc = moc
        self.settings = settings
    }

    private func object<T: NSManagedObject>(with id: NSManagedObjectID) async -> T? {
        await moc.syncObject(with: id)
    }

    func run(repos: [Repo]) async {
        await fetchItems(for: repos)
        let reposWithSomeItems = repos.filter { !$0.issues.isEmpty || !$0.pullRequests.isEmpty }
        await markExtraUpdatedItems(from: reposWithSomeItems)

        newOrUpdatedPrs = PullRequest.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)
        newOrUpdatedIssues = Issue.newOrUpdatedItems(in: moc, fromSuccessfulSyncOnly: true)

        await withTaskGroup { group in
            if Settings.showStatusItems {
                group.addTask { [self] in
                    await fetchStatusesForCurrentPullRequests()
                }
            } else {
                for p in PullRequest.allItems(in: moc) {
                    p.lastStatusScan = nil
                    for status in p.statuses {
                        status.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }

            if Settings.notifyOnItemReactions {
                group.addTask { [self] in
                    await fetchPullRequestReactionsIfNeeded()
                }

                group.addTask { [self] in
                    await fetchIssueReactionsIfNeeded()
                }
            }

            if Settings.showLabels {
                group.addTask { [self] in
                    await fetchLabelsForCurrentPullRequests()
                }
                group.addTask { [self] in
                    await fetchLabelsForCurrentIssues()
                }
            } else {
                for l in PRLabel.allItems(in: moc) {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }
            }

            group.addTask { [self] in
                await checkPrClosures()
            }

            group.addTask { [self] in
                await detectAssignedPullRequests()
            }

            if settings.shouldSyncReviewAssignments {
                group.addTask { [self] in
                    await fetchReviewAssignmentsForCurrentPullRequests()
                }
            }

            await withTaskGroup { commentGroup in
                if settings.shouldSyncReviews {
                    commentGroup.addTask { [self] in
                        await fetchReviewsThenCommentsForCurrentPullRequests()
                    }
                } else {
                    for r in Review.allItems(in: moc) {
                        r.postSyncAction = PostSyncAction.delete.rawValue
                    }
                    commentGroup.addTask { [self] in
                        await fetchCommentsForCurrentPullRequests()
                    }
                }

                commentGroup.addTask { [self] in
                    await fetchCommentsForCurrentIssuesThenCheckClosures()
                }
            }

            if Settings.notifyOnCommentReactions {
                group.addTask { [self] in
                    await fetchCommentReactionsIfNeeded()
                }
            }
        }
    }

    // MARK: - Items

    private func handleRepoSync(for repo: Repo, result: DataResult) {
        switch result {
        case .cancelled, .ignored, .success:
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

    private func fetchItems(for repos: [Repo]) async {
        for r in repos {
            for p in r.pullRequests where p.condition == ItemCondition.open.rawValue {
                p.postSyncAction = PostSyncAction.delete.rawValue
            }

            for i in r.issues where i.condition == ItemCondition.open.rawValue {
                i.postSyncAction = PostSyncAction.delete.rawValue
            }

            guard r.apiServer.lastSyncSucceeded else { continue }

            let repoId = r.objectID
            let repoFullName = r.fullName.orEmpty

            await withTaskGroup { group in
                if r.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue {
                    group.addTask { [self] in
                        await fetchPullRequests(repoId: repoId, repoFullName: repoFullName)
                    }
                }

                if r.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue {
                    group.addTask { [self] in
                        await fetchIssues(repoId: repoId, repoFullName: repoFullName)
                    }
                }
            }
        }
    }

    private func fetchPullRequests(repoId: NSManagedObjectID, repoFullName: String) async {
        guard let r: Repo = await object(with: repoId) else { return }
        let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls", from: r.apiServer) { [moc, settings] data, _ in
            await PullRequest.syncPullRequests(from: data, in: r, moc: moc, settings: settings)
            return false
        }
        handleRepoSync(for: r, result: result)
    }

    private func fetchIssues(repoId: NSManagedObjectID, repoFullName: String) async {
        guard let r: Repo = await object(with: repoId) else { return }
        let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues", from: r.apiServer) { [moc] data, _ in
            await Issue.syncIssues(from: data, in: r, moc: moc)
            return false
        }
        handleRepoSync(for: r, result: result)
    }

    private func markExtraUpdatedItems(from repos: [Repo]) async {
        await withTaskGroup { group in
            for r in repos {
                let repoId = r.objectID
                let repoFullName = r.fullName.orEmpty
                let lastLocalEvent = r.lastScannedIssueEventId
                let isFirstEventSync = lastLocalEvent == 0
                r.lastScannedIssueEventId = 0
                group.addTask { [self] in
                    await scanIssueEvents(repoId: repoId, repoFullName: repoFullName, lastLocalEvent: lastLocalEvent, isFirstEventSync: isFirstEventSync)
                }
            }
        }
    }

    private func scanIssueEvents(repoId: NSManagedObjectID, repoFullName: String, lastLocalEvent: Int, isFirstEventSync: Bool) async {
        guard let r: Repo = await object(with: repoId) else { return }
        let apiServer = r.apiServer
        let result = await RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues/events", from: apiServer) { data, _ in
            guard let data, !data.isEmpty else { return true }

            if isFirstEventSync {
                await Logging.shared.log("First event check for this repo. Let's ensure all items are marked as updated")
                for i in r.pullRequests {
                    i.setToUpdatedIfIdle()
                }
                for i in r.issues {
                    i.setToUpdatedIfIdle()
                }
                r.lastScannedIssueEventId = data.first!.potentialInt(named: "id") ?? 0
                return true

            } else {
                var numbers = Set<Int>()
                var foundLastEvent = false
                for event in data {
                    if let eventId = event.potentialInt(named: "id"), let issue = event.potentialObject(named: "issue"), let issueNumber = issue.potentialInt(named: "number") {
                        if r.lastScannedIssueEventId == 0 {
                            r.lastScannedIssueEventId = eventId
                        }
                        if eventId == lastLocalEvent {
                            foundLastEvent = true
                            await Logging.shared.log("Parsed all repo issue events up to the one we already have")
                            break // we're done
                        }
                        if event.potentialString(named: "event") != nil {
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
        case .cancelled, .ignored, .success:
            break
        case .deleted, .failed, .notFound:
            apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Closures

    private func checkIssueClosures() {
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
        let items = try! moc.fetch(f)
        for i in items.filter(\.shouldCheckForClosing) {
            i.stateChanged = ListableItem.StateChange.closed.rawValue
            i.postSyncAction = PostSyncAction.isUpdated.rawValue // let handleClosing() decide
        }
    }

    private func checkPrClosures() async {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
        f.returnsObjectsAsFaults = false

        let prsToCheck = try! moc.fetch(f).filter(\.shouldCheckForClosing)

        await withTaskGroup { group in
            for r in prsToCheck {
                let prId = r.objectID
                group.addTask { [self] in
                    await investigatePrClosure(prId: prId)
                }
            }
        }
    }

    private func investigatePrClosure(prId: NSManagedObjectID) async {
        guard let pullRequest: PullRequest = await object(with: prId) else { return }

        let prTitle = pullRequest.title.orEmpty
        await Logging.shared.log("Checking closed PR to see if it was merged: \(prTitle)")

        let repoFullName = pullRequest.repo.fullName.orEmpty
        let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

        do {
            let (data, _, result) = try await RestAccess.getData(in: path, from: pullRequest.apiServer)
            switch result {
            case .success:
                if let data {
                    if let mergeInfo = data.potentialObject(named: "merged_by"), let mergeUserId = mergeInfo.potentialString(named: "node_id") {
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
            case .cancelled, .failed, .ignored:
                pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // keep since we don't know what's going on here
                pullRequest.apiServer.lastSyncSucceeded = false
            }
        } catch {
            pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // keep since we don't know what's going on here
            pullRequest.apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Reactions

    private func fetchPullRequestReactionsIfNeeded() async {
        await fetchItemReactionsIfNeeded(for: PullRequest.reactionCheckBatch(in: moc, settings: settings))
    }

    private func fetchIssueReactionsIfNeeded() async {
        await fetchItemReactionsIfNeeded(for: Issue.reactionCheckBatch(in: moc, settings: settings))
    }

    private func fetchItemReactionsIfNeeded(for items: [some ListableItem]) async {
        if items.isEmpty {
            return
        }

        let now = Date()
        await withTaskGroup { group in
            for i in items {
                i.lastReactionScan = now
                for r in i.reactions {
                    r.postSyncAction = PostSyncAction.delete.rawValue
                }
                guard let reactionsUrl = i.reactionsUrl else {
                    continue
                }
                let itemId = i.objectID
                let serverId = i.apiServer.objectID
                group.addTask { [self] in
                    await syncItemReactions(itemId: itemId, serverId: serverId, reactionsUrl: reactionsUrl)
                }
            }
        }
    }

    private func syncItemReactions(itemId: NSManagedObjectID, serverId: NSManagedObjectID, reactionsUrl: String) async {
        guard let i: ListableItem = await object(with: itemId) else { return }
        let apiServer = i.apiServer
        let result = await RestAccess.getPagedData(at: reactionsUrl, from: apiServer) { [moc] data, _ in
            await Reaction.syncReactions(from: data, parentId: itemId, serverId: serverId, moc: moc)
            return false
        }
        switch result {
        case .cancelled, .ignored, .success:
            break
        case .deleted, .failed, .notFound:
            apiServer.lastSyncSucceeded = false
        }
    }

    private func fetchCommentReactionsIfNeeded() async {
        let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc)

        if comments.isEmpty {
            return
        }

        await withTaskGroup { group in
            for c in comments {
                for r in c.reactions {
                    r.postSyncAction = PostSyncAction.delete.rawValue
                }
                guard let reactionUrl = c.reactionsUrl else { continue }
                let commentId = c.objectID
                group.addTask { [self] in
                    await syncCommentReactions(commentId: commentId, reactionUrl: reactionUrl)
                }
            }
        }
    }

    private func syncCommentReactions(commentId: NSManagedObjectID, reactionUrl: String) async {
        guard let c: PRComment = await object(with: commentId) else { return }
        let serverId = c.apiServer.objectID
        let result = await RestAccess.getPagedData(at: reactionUrl, from: c.apiServer) { [moc] data, _ in
            await Reaction.syncReactions(from: data, commentId: commentId, serverId: serverId, moc: moc)
            return false
        }
        switch result {
        case .cancelled:
            break
        case .ignored, .success:
            c.pendingReactionScan = false
        case .deleted, .failed, .notFound:
            c.apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Comments

    private func fetchReviewsThenCommentsForCurrentPullRequests() async {
        await fetchReviewsForCurrentPullRequests()
        await fetchCommentsForCurrentPullRequests()
    }

    private func fetchCommentsForCurrentPullRequests() async {
        let prs = newOrUpdatedPrs
        if prs.isEmpty {
            return
        }

        for p in prs {
            for c in p.comments {
                c.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        await withTaskGroup { group in
            group.addTask { [self] in
                await fetchPullRequestComments(issues: true)
            }
            group.addTask { [self] in
                await fetchPullRequestComments(issues: false)
            }
        }
    }

    private func fetchPullRequestComments(issues: Bool) async {
        await withTaskGroup { group in
            for p in newOrUpdatedPrs {
                if let link = (issues ? p.commentsLink : p.reviewCommentLink) {
                    let parentId = p.objectID
                    group.addTask { [self] in
                        await syncComments(parentId: parentId, link: link)
                    }
                }
            }
        }
    }

    private func fetchCommentsForCurrentIssuesThenCheckClosures() async {
        await fetchCommentsForCurrentIssues()
        checkIssueClosures()
    }

    private func fetchCommentsForCurrentIssues() async {
        let issues = newOrUpdatedIssues
        if issues.isEmpty {
            return
        }

        await withTaskGroup { group in
            for i in issues {
                for c in i.comments {
                    c.postSyncAction = PostSyncAction.delete.rawValue
                }

                if let link = i.commentsLink {
                    let parentId = i.objectID
                    group.addTask { [self] in
                        await syncComments(parentId: parentId, link: link)
                    }
                }
            }
        }
    }

    private func syncComments(parentId: NSManagedObjectID, link: String) async {
        guard let parent: ListableItem = await object(with: parentId) else { return }
        let apiServer = parent.apiServer
        let result = await RestAccess.getPagedData(at: link, from: apiServer) { [moc] data, _ in
            await PRComment.syncComments(from: data, parent: parent, moc: moc)
            return false
        }
        switch result {
        case .cancelled, .ignored, .success:
            break
        case .deleted, .failed, .notFound:
            apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Reviews

    private func fetchReviewsForCurrentPullRequests() async {
        let prs = newOrUpdatedPrs
        if prs.isEmpty {
            return
        }

        await withTaskGroup { group in
            for p in prs {
                for l in p.reviews {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }
                let prId = p.objectID
                let repoFullName = p.repo.fullName.orEmpty
                let path = "/repos/\(repoFullName)/pulls/\(p.number)/reviews"
                group.addTask { [self] in
                    await syncReviews(prId: prId, path: path)
                }
            }
        }
    }

    private func syncReviews(prId: NSManagedObjectID, path: String) async {
        guard let p: PullRequest = await object(with: prId) else { return }
        let apiServer = p.apiServer
        let result = await RestAccess.getPagedData(at: path, from: apiServer) { [moc] data, _ in
            await Review.syncReviews(from: data, withParent: p, moc: moc)
            return false
        }
        switch result {
        case .cancelled, .ignored, .success:
            break
        case .deleted, .failed, .notFound:
            apiServer.lastSyncSucceeded = false
        }
    }

    private func fetchReviewAssignmentsForCurrentPullRequests() async {
        await withThrowingTaskGroup { group in
            for p in newOrUpdatedPrs {
                let prId = p.objectID
                let repoFullName = p.repo.fullName.orEmpty
                let path = "/repos/\(repoFullName)/pulls/\(p.number)/requested_reviewers"
                group.addTask { [self] in
                    try await syncReviewAssignments(prId: prId, path: path)
                }
            }
        }
    }

    private func syncReviewAssignments(prId: NSManagedObjectID, path: String) async throws {
        guard let p: PullRequest = await object(with: prId) else { return }

        let (data, _) = try await RestAccess.getRawData(at: path, from: p.apiServer)
        var reviewUsers = Set<String>()
        var reviewTeams = Set<String>()

        if let userList = data?.potentialArray {
            // Legacy API results
            for userName in userList.compactMap({ $0.potentialString(named: "login") }) {
                reviewUsers.insert(userName)
            }
            p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams, settings: settings)

        } else if let data, let userList = data.potentialArray(named: "users"), let teamList = data.potentialArray(named: "teams") {
            // New API results
            for userName in userList.compactMap({ $0.potentialString(named: "login") }) {
                reviewUsers.insert(userName)
            }
            for teamName in teamList.compactMap({ $0.potentialString(named: "slug") }) {
                reviewTeams.insert(teamName)
            }
            p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams, settings: settings)

        } else {
            p.apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Labels

    private func fetchLabelsForCurrentPullRequests() async {
        let prs = newOrUpdatedPrs
        if prs.isEmpty {
            return
        }

        await withTaskGroup { group in
            for p in prs {
                for l in p.labels {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }

                guard let link = p.labelsLink else {
                    continue
                }

                let prId = p.objectID
                group.addTask { [self] in
                    await syncPullRequestLabels(prId: prId, link: link)
                }
            }
        }
    }

    private func syncPullRequestLabels(prId: NSManagedObjectID, link: String) async {
        guard let p: PullRequest = await object(with: prId) else { return }
        let apiServer = p.apiServer
        let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
            PRLabel.syncLabels(from: data, withParent: p)
            return false
        }
        switch result {
        case .cancelled, .deleted, .ignored, .notFound, .success:
            break
        case .failed:
            apiServer.lastSyncSucceeded = false
        }
    }

    private func fetchLabelsForCurrentIssues() async {
        let issues = newOrUpdatedIssues
        if issues.isEmpty {
            return
        }

        await withTaskGroup { group in
            for i in issues {
                for l in i.labels {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }

                guard let link = i.labelsLink else {
                    continue
                }

                let issueId = i.objectID
                group.addTask { [self] in
                    await syncIssueLabels(issueId: issueId, link: link)
                }
            }
        }
    }

    private func syncIssueLabels(issueId: NSManagedObjectID, link: String) async {
        guard let i: Issue = await object(with: issueId) else { return }
        let apiServer = i.apiServer
        let result = await RestAccess.getPagedData(at: link, from: apiServer) { data, _ in
            PRLabel.syncLabels(from: data, withParent: i)
            return false
        }
        switch result {
        case .cancelled, .deleted, .ignored, .notFound, .success:
            break
        case .failed:
            apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Statuses

    private func fetchStatusesForCurrentPullRequests() async {
        let prs = PullRequest.statusCheckBatch(in: moc, settings: settings)
        if prs.isEmpty {
            return
        }

        let now = Date()
        await withTaskGroup { group in
            for p in prs {
                for s in p.statuses {
                    s.postSyncAction = PostSyncAction.delete.rawValue
                }

                if let statusLink = p.statusesLink {
                    let prId = p.objectID
                    group.addTask { [self] in
                        await syncStatuses(prId: prId, statusLink: statusLink, now: now)
                    }
                } else {
                    p.lastStatusScan = now
                }
            }
        }
    }

    private func syncStatuses(prId: NSManagedObjectID, statusLink: String, now: Date) async {
        guard let p: PullRequest = await object(with: prId) else { return }
        let apiServer = p.apiServer
        let result = await RestAccess.getPagedData(at: statusLink, from: apiServer) { [moc] data, _ in
            await PRStatus.syncStatuses(from: data, pullRequest: p, moc: moc)
            return false
        }
        switch result {
        case .cancelled, .ignored:
            break
        case .deleted, .notFound, .success:
            p.lastStatusScan = now
        case .failed:
            apiServer.lastSyncSucceeded = false
        }
    }

    // MARK: - Assignment

    private func detectAssignedPullRequests() async {
        await withTaskGroup { group in
            for p in newOrUpdatedPrs {
                if let issueLink = p.issueUrl {
                    let prId = p.objectID
                    group.addTask { [self] in
                        await detectAssignment(prId: prId, issueLink: issueLink)
                    }
                }
            }
        }
    }

    private func detectAssignment(prId: NSManagedObjectID, issueLink: String) async {
        guard let p: PullRequest = await object(with: prId) else { return }
        let apiServer = p.apiServer
        do {
            let (data, _, _) = try await RestAccess.getData(in: issueLink, from: apiServer)
            if let data {
                p.processAssignmentStatus(from: data, idField: "node_id")
            }
        } catch {
            apiServer.lastSyncSucceeded = false
        }
    }
}
