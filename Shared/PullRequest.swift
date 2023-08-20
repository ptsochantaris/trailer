import CoreData
import Lista
import TrailerQL
#if os(iOS)
    import UIKit
#endif

final class PullRequest: ListableItem {
    @NSManaged var lastStatusNotified: String?
    @NSManaged var mergeCommitSha: String?
    @NSManaged var hasNewCommits: Bool
    @NSManaged var reviewers: String
    @NSManaged var teamReviewers: String
    @NSManaged var mergedByNodeId: String?
    @NSManaged var linesAdded: Int
    @NSManaged var linesRemoved: Int
    @NSManaged var isMergeable: Bool
    @NSManaged var headRefName: String?
    @NSManaged var headLabel: String?
    @NSManaged var baseLabel: String?
    @NSManaged var assignedReviewStatus: Int

    @NSManaged var statuses: Set<PRStatus>
    @NSManaged var reviews: Set<Review>

    override class var typeName: String { "PullRequest" }

    override var baseLabelText: String? { baseLabel }

    override var headLabelText: String? { headLabel }

    override var webUrl: String? {
        super.webUrl?.appending(pathComponent: "pull").appending(pathComponent: String(number))
    }

    static func mostRecentItemUpdate(in repo: Repo) -> Date {
        repo.pullRequests.reduce(.distantPast) { max($0, $1.updatedAt ?? .distantPast) }
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PullRequest.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { pr, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id ?? (node.jsonPayload["repository"] as? JSON)?["id"] as? String,
                  let parent = Repo.asParent(with: parentId, in: moc, parentCache: parentCache)
            else { return }

            let json = node.jsonPayload

            if let mergeField = json["mergeable"] as? String {
                pr.isMergeable = mergeField != "CONFLICTING"
            } else {
                pr.isMergeable = true
            }
            pr.linesAdded = json["additions"] as? Int ?? 0
            pr.linesRemoved = json["deletions"] as? Int ?? 0
            pr.mergeCommitSha = json["headRefOid"] as? String
            pr.mergedByNodeId = (json["mergedBy"] as? JSON)?["id"] as? String
            pr.baseNodeSync(node: node, parent: parent)
            pr.reviewers = "" // will be populated by the review request API calls
            pr.teamReviewers = "" // will be populated by the review request API calls

            let headRefName = json["headRefName"] as? String
            if let headRefName,
               let headRepoName = (json["headRepository"] as? JSON)?["nameWithOwner"] as? String {
                pr.headLabel = headRepoName + ":" + headRefName
            } else {
                pr.headLabel = nil
            }
            pr.headRefName = headRefName

            let baseRefName = json["baseRefName"] as? String
            if let baseRefName,
               let baseRepoName = (json["baseRepository"] as? JSON)?["nameWithOwner"] as? String {
                pr.baseLabel = baseRepoName + ":" + baseRefName
            } else {
                pr.baseLabel = nil
            }
        }
    }

    var reviewCommentLink: String? {
        repo.apiUrl?.appending(pathComponent: "pulls").appending(pathComponent: String(number)).appending(pathComponent: "comments")
    }

    var statusesLink: String? {
        repo.apiUrl?.appending(pathComponent: "statuses").appending(pathComponent: mergeCommitSha ?? "")
    }

    static func syncPullRequests(from data: [JSON]?, in repo: Repo, moc: NSManagedObjectContext) async {
        let apiServer = repo.apiServer
        let apiServerUserId = apiServer.userNodeId
        let repoId = repo.objectID
        await v3items(with: data, type: PullRequest.self, serverId: apiServer.objectID, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated {
                let repo = try! syncMoc.existingObject(with: repoId) as! Repo
                item.baseSync(from: info, in: repo)

                let baseInfo = info["base"] as? JSON
                item.baseLabel = baseInfo?["label"] as? String

                let headInfo = info["head"] as? JSON
                item.headRefName = headInfo?["ref"] as? String
                item.headLabel = headInfo?["label"] as? String

                item.reviewers = ""
                item.teamReviewers = ""

                if
                    let newHeadCommitSha = headInfo?["sha"] as? String,
                    let commitUserInfo = headInfo?["user"] as? JSON,
                    let newHeadCommitUserId = commitUserInfo["node_id"] as? String {
                    let currentSha = item.mergeCommitSha
                    if currentSha != nil, currentSha != newHeadCommitSha, apiServerUserId != newHeadCommitUserId {
                        item.hasNewCommits = Settings.markPrsAsUnreadOnNewCommits && item.postSyncAction != PostSyncAction.isNew.rawValue
                    }
                    item.mergeCommitSha = newHeadCommitSha
                }
            }
            if item.condition == ItemCondition.closed.rawValue {
                item.stateChanged = StateChange.reopened.rawValue
            }
            item.condition = ItemCondition.open.rawValue
            item.isMergeable = true // always, for v3 API
        }
    }

    override var searchKeywords: [String] {
        ["PR", "Pull Request", "PRs", "Pull Requests"] + super.searchKeywords
    }

    override var hasUnreadCommentsOrAlert: Bool {
        super.hasUnreadCommentsOrAlert || hasNewCommits
    }

    override var reviewedByMe: Bool {
        reviews.contains { $0.isMine }
    }

    override var preferredSectionBasedOnReviewAssignment: Section? {
        switch AssignmentStatus(rawValue: assignedReviewStatus) {
        case nil, .none?, .others:
            break

        case .me:
            if Settings.assignedDirectReviewHandlingPolicy.visible,
               let section = Settings.assignedDirectReviewHandlingPolicy.preferredSection {
                return section.visible ? section : .hidden(cause: .assignedDirectReview)
            }

        case .myTeam:
            if Settings.assignedTeamReviewHandlingPolicy.visible,
               let section = Settings.assignedTeamReviewHandlingPolicy.preferredSection {
                return section.visible ? section : .hidden(cause: .assignedTeamReview)
            }
        }

        return nil
    }

    func shouldContributeToCount(since: Date, context: SettingsCache) -> Bool {
        guard !createdByMe,
              let userLogin,
              let createdAt,
              createdAt > since
        else {
            return false
        }
        return !context.excludedCommentAuthors.contains(userLogin.comparableForm)
    }

    override var shouldHideBecauseOfRepoHidingPolicy: Section.HidingCause? {
        if createdByMe {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllMyAuthoredItems.rawValue:
                return .hidingAllMyAuthoredItems
            case RepoHidingPolicy.hideMyAuthoredPrs.rawValue:
                return .hidingMyAuthoredPrs
            default:
                return nil
            }
        } else {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllOthersItems.rawValue:
                return .hidingAllOthersItems
            case RepoHidingPolicy.hideOthersPrs.rawValue:
                return .hidingOthersPrs
            default:
                return nil
            }
        }
    }

    override var shouldWakeBecauseOfCommit: Bool {
        snoozeUntil != nil && shouldWakeOnComment && hasNewCommits
    }

    private func setAssignedReviewStatus(to status: AssignmentStatus) {
        if assignedReviewStatus == status.rawValue {
            return
        }

        assignedReviewStatus = status.rawValue

        switch status {
        case .none, .others:
            break
        case .me:
            if Settings.notifyOnReviewAssignments {
                NotificationQueue.add(type: .assignedForReview, for: self)
            }
        case .myTeam:
            if Settings.notifyOnReviewAssignments {
                NotificationQueue.add(type: .assignedToTeamForReview, for: self)
            }
        }
    }

    func checkAndStoreReviewAssignments(_ reviewerNames: Set<String>, _ reviewerTeams: Set<String>) {
        reviewers = reviewerNames.joined(separator: ",")
        teamReviewers = reviewerTeams.joined(separator: ",")

        if reviewerNames.isEmpty {
            setAssignedReviewStatus(to: .none)
            return
        }

        if reviewerNames.contains(apiServer.userName.orEmpty) {
            setAssignedReviewStatus(to: .me)
            return
        }

        let myTeamNames = apiServer.teams.compactMap(\.slug)
        if myTeamNames.contains(where: { reviewerTeams.contains($0) }) {
            setAssignedReviewStatus(to: .myTeam)
        } else {
            setAssignedReviewStatus(to: .others)
        }
    }

    @MainActor
    static func allMerged(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let p = ItemCondition.merged.matchingPredicate
        add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
        return try! moc.fetch(f)
    }

    @MainActor
    static func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let p = ItemCondition.closed.matchingPredicate
        add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
        return try! moc.fetch(f)
    }

    override class func hasOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Bool {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.fetchLimit = 1
        add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.open.matchingPredicate, in: moc)
        return try! moc.count(for: f) > 0
    }

    static func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if section.visible {
            f.predicate = section.matchingPredicate
        }
        for pr in try! moc.fetch(f) {
            pr.catchUpWithComments()
        }
    }

    override func catchUpWithComments() {
        hasNewCommits = false
        super.catchUpWithComments()
    }

    override class func badgeCount(from fetch: NSFetchRequest<some ListableItem>, in moc: NSManagedObjectContext) -> Int {
        var badgeCount = super.badgeCount(from: fetch, in: moc)
        if Settings.markPrsAsUnreadOnNewCommits {
            for i in try! moc.fetch(fetch) {
                if let i = i as? PullRequest, i.hasNewCommits {
                    badgeCount += 1
                }
            }
        }
        return badgeCount
    }

    static func badgeCount(in section: Section, in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, includeInUnreadPredicate])
        return badgeCount(from: f, in: moc)
    }

    static func badgeCount(in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate])
        return badgeCount(from: f, in: moc)
    }

    @MainActor
    static func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
        let f = requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
        return badgeCount(from: f, in: moc)
    }

    private static let _unreadOrNewCommitsPredicate = NSPredicate(format: "unreadComments > 0 or hasNewCommits == YES")
    override class var includeInUnreadPredicate: NSPredicate {
        Settings.markPrsAsUnreadOnNewCommits ? _unreadOrNewCommitsPredicate : super.includeInUnreadPredicate
    }

    override var contextMenuTitle: String {
        muted ? "PR #\(number) (muted)" : "PR #\(number)"
    }

    override var contextMenuSubtitle: String? {
        headRefName
    }

    override func shouldHideBecauseOfRedStatuses(in section: Section, context: SettingsCache) -> Section.HidingCause? {
        guard context.hidePrsThatArentPassing else {
            return nil
        }

        switch section {
        case .all:
            break

        case .mine, .participated:
            if context.hidePrsThatDontPassOnlyInAll {
                return nil
            }

        case .closed, .hidden, .mentioned, .merged, .snoozed:
            return nil
        }
        
        let allSuccesses = displayedStatusLines(context: context).allSatisfy { $0.state == "success" }

        guard allSuccesses else {
            return .containsNonGreenStatuses
        }
        
        return nil
    }

    override func countReviews(context: SettingsCache) -> Int {
        guard context.shouldSyncReviews || context.shouldSyncReviewAssignments else {
            return 0
        }
        var count = 0
        for r in reviews where r.shouldContributeToCount(since: .distantPast, context: context) {
            count += 1
        }
        return count
    }

    static func statusCheckBatch(in moc: NSManagedObjectContext) -> [PullRequest] {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = NSPredicate(format: "apiServer.lastSyncSucceeded == YES")
        f.sortDescriptors = [
            NSSortDescriptor(key: "lastStatusScan", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        let prs = try! moc.fetch(f)
            .filter(\.section.shouldCheckStatuses)
            .prefix(Settings.statusItemRefreshBatchSize)

        prs.forEach {
            $0.statuses.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        return Array(prs)
    }

    var displayedStatusLines: [PRStatus] {
        let red = Settings.showStatusesRed
        let yellow = Settings.showStatusesYellow
        let green = Settings.showStatusesGreen
        let gray = Settings.showStatusesGray
        let mode = Settings.statusFilteringMode
        let terms = Settings.statusFilteringTerms
        return displayedStatuses(red: red, yellow: yellow, green: green, gray: gray, mode: mode, terms: terms)
    }

    func displayedStatusLines(context: SettingsCache) -> [PRStatus] {
        displayedStatuses(red: context.statusRed,
                          yellow: context.statusYellow,
                          green: context.statusGreen,
                          gray: context.statusGray,
                          mode: context.statusMode,
                          terms: context.statusTerms)
    }
    
    private func displayedStatuses(red: Bool, yellow: Bool, green: Bool, gray: Bool, mode: StatusFilter, terms: [String]) -> [PRStatus] {
        var contexts = [String: PRStatus]()
        let filteredStatuses: Set<PRStatus>
        if red, yellow, green, gray {
            filteredStatuses = statuses
        } else {
            filteredStatuses = statuses.filter {
                let c = $0.colorForDisplay
                if c == .appRed { return red }
                if c == .appYellow { return yellow }
                if c == .appGreen { return green }
                if c == .appSecondaryLabel { return gray }
                return false
            }
        }
        let sortedStatuses = filteredStatuses.sorted { $1.createdBefore($0) }
        for s in sortedStatuses {
            let context = s.context ?? "//NO CONTEXT/-/"
            if let latestStatusInContext = contexts[context] {
                if latestStatusInContext.createdBefore(s) {
                    contexts[context] = s
                }
            } else {
                contexts[context] = s
            }
        }

        var statusList = Array(contexts.values)

        if mode != .all {
            if !terms.isEmpty {
                let inclusive = mode == .include
                // contains(a) or contains(b) or contains(c)  -vs-  not(contains(a) or contains(b) or contains(c))

                statusList = statusList.filter {
                    for t in terms {
                        if let d = $0.descriptionText, d.localizedCaseInsensitiveContains(t) {
                            return inclusive
                        }
                    }
                    return !inclusive
                }
            }
        }

        return statusList.sorted { $0.createdBefore($1) }
    }

    var labelsLink: String? {
        issueUrl?.appending(pathComponent: "labels")
    }

    @objc var sectionName: String {
        Section(sectionIndex: sectionIndex).prMenuName
    }

    func shouldAnnounceStatus(context: SettingsCache) -> Bool {
        canBadge(context: context)
        && (context.notifyOnStatusUpdatesForAllPrs
            || createdByMe
            || shouldGo(to: .participated, context: context)
            || shouldGo(to: .mine, context: context)
            || shouldGo(to: .mentioned, context: context))
    }

    func linesAttributedString(labelFont: FONT_CLASS) -> NSAttributedString? {
        let added = linesAdded
        let removed = linesRemoved

        if added == 0, removed == 0 {
            return nil
        }

        let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)

        let res = NSMutableAttributedString()
        if added > 0, let addedString = numberFormatter.string(for: added) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appGreen]
            res.append(NSAttributedString(string: "+\(addedString)", attributes: attributes))
            if removed > 0 {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.lightGray]
                res.append(NSAttributedString(string: "\u{a0}", attributes: attributes))
            }
        }
        if removed > 0, let removedString = numberFormatter.string(for: removed) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appRed]
            res.append(NSAttributedString(string: "-\(removedString)", attributes: attributes))
        }
        return res
    }

    override var repoDisplayPolicy: Int {
        repo.displayPolicyForPrs
    }

    override func shouldHideDueToMyReview(context: SettingsCache) -> Section.HidingCause? {
        let hideIfApproved = context.hidePrsIfApproved
        let hideIfRejected = context.hidePrsIfRejected

        guard hideIfApproved || hideIfRejected,
              let myName = apiServer.userName,
              !reviewers.contains(myName)
        else {
            return nil
        }

        let latestReview = reviews.filter { $0.affectsBottomLine && $0.username == myName }.sorted { $0.createdBefore($1) }.last
        guard let latestReview else {
            return nil
        }

        if hideIfApproved, latestReview.state == Review.State.APPROVED.rawValue {
            return .approvedByMe
        }

        if hideIfRejected, latestReview.state == Review.State.CHANGES_REQUESTED.rawValue {
            return .rejectedByMe
        }

        return nil
    }

    func reviewsAttributedString(labelFont: FONT_CLASS) -> NSAttributedString? {
        if !Settings.displayReviewsOnItems {
            return nil
        }

        let res = NSMutableAttributedString()

        if Settings.showRequestedTeamReviews {
            let teamReviewRequests = teamReviewers.components(separatedBy: ",")
            let names = teamReviewRequests.compactMap {
                if let moc = managedObjectContext {
                    return Team.team(with: $0, in: moc)?.calculatedReferral
                } else {
                    return nil
                }
            }.joined(separator: ", ")
            if !names.isEmpty {
                let a = [NSAttributedString.Key.font: labelFont, NSAttributedString.Key.foregroundColor: COLOR_CLASS.appYellow]
                res.append(NSAttributedString(string: "Reviews asked from \(names)", attributes: a))
            }
        }

        var latestReviewByUser = [String: Review]()
        reviews.filter(\.affectsBottomLine).sorted { $0.createdBefore($1) }.forEach {
            if let userName = $0.username {
                // Do not take any review state into account if the user is still marked as a reviewer
                latestReviewByUser[userName] = reviewers.contains(userName) ? nil : $0
            }
        }

        if !latestReviewByUser.isEmpty || !reviewers.isEmpty {
            let reviews = latestReviewByUser.values.sorted { $0.createdBefore($1) }

            let approvers = reviews.filter { $0.state == Review.State.APPROVED.rawValue }
            if !approvers.isEmpty {
                let a = [NSAttributedString.Key.font: labelFont, NSAttributedString.Key.foregroundColor: COLOR_CLASS.appGreen]

                if res.length > 0 {
                    res.append(NSAttributedString(string: "\n", attributes: a))
                }

                var count = 0
                for r in approvers {
                    let name = r.username!.replacingOccurrences(of: " ", with: "\u{a0}")
                    res.append(NSAttributedString(string: "@\(name) ", attributes: a))
                    if count == approvers.count - 1 {
                        res.append(NSAttributedString(string: "approved changes", attributes: a))
                    }
                    count += 1
                }
            }

            let requesters = reviews.filter { $0.state == Review.State.CHANGES_REQUESTED.rawValue }
            if !requesters.isEmpty {
                let a = [NSAttributedString.Key.font: labelFont, NSAttributedString.Key.foregroundColor: COLOR_CLASS.appRed]

                if res.length > 0 {
                    res.append(NSAttributedString(string: "\n", attributes: a))
                }

                var count = 0
                for r in requesters {
                    let name = r.username!.replacingOccurrences(of: " ", with: "\u{a0}")
                    res.append(NSAttributedString(string: "@\(name) ", attributes: a))
                    if count == requesters.count - 1 {
                        res.append(NSAttributedString(string: requesters.count > 1 ? "request changes" : "requests changes", attributes: a))
                    }
                    count += 1
                }
            }

            let approverNames = approvers.compactMap(\.username)
            let requesterNames = requesters.compactMap(\.username)
            let otherReviewers = reviewers.components(separatedBy: ",").filter { !($0.isEmpty || approverNames.contains($0) || requesterNames.contains($0)) }
            if !otherReviewers.isEmpty {
                let a = [NSAttributedString.Key.font: labelFont, NSAttributedString.Key.foregroundColor: COLOR_CLASS.appYellow]

                if res.length > 0 {
                    res.append(NSAttributedString(string: "\n", attributes: a))
                }

                var count = 0
                for r in otherReviewers {
                    let name = r.replacingOccurrences(of: " ", with: "\u{a0}")
                    res.append(NSAttributedString(string: "@\(name) ", attributes: a))
                    if count == otherReviewers.count - 1 {
                        res.append(NSAttributedString(string: otherReviewers.count > 1 ? "haven't reviewed yet" : "hasn't reviewed yet", attributes: a))
                    }
                    count += 1
                }
            }
        }

        return res
    }

    override final func handleMerging() {
        let byUserId = mergedByNodeId
        let myUserId = apiServer.userNodeId
        Logging.log("Detected merged PR: \(title.orEmpty) by user \(byUserId.orEmpty), local user id is: \(myUserId.orEmpty), handling policy is \(Settings.mergeHandlingPolicy), coming from section \(sectionIndex)")

        if !isVisibleOnMenu {
            Logging.log("Merged PR was hidden, won't announce")
            managedObjectContext?.delete(self)

        } else if byUserId == myUserId, Settings.dontKeepPrsMergedByMe {
            Logging.log("Will not keep PR merged by me")
            managedObjectContext?.delete(self)

        } else if shouldKeep(accordingTo: Settings.mergeHandlingPolicy) {
            Logging.log("Will keep merged PR")
            keep(as: .merged, notification: .prMerged)

        } else {
            Logging.log("Will not keep merged PR")
            managedObjectContext?.delete(self)
        }
    }
}
