import CoreData
import Lista
import TrailerJson
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

    @NSManaged var closesIssueIds: String?
    @NSManaged var closesIssues: Set<Issue>

    override static var typeName: String { "PullRequest" }

    override var baseLabelText: String? { baseLabel }

    override var headLabelText: String? { headLabel }

    override var webUrl: String? {
        super.webUrl?.appending(pathComponent: "pull").appending(pathComponent: String(number))
    }

    static func mostRecentItemUpdate(in repo: Repo) -> Date {
        repo.pullRequests.reduce(.distantPast) { max($0, $1.updatedAt ?? .distantPast) }
    }

    var closesIssuesList: Set<String> {
        get {
            let list = closesIssueIds.orEmpty
            if list.isEmpty {
                return []
            } else {
                return Set(list.components(separatedBy: ",").map { String($0) })
            }
        }
        set {
            if newValue.isEmpty {
                closesIssueIds = nil
            } else {
                closesIssueIds = newValue.joined(separator: ",")
            }
        }
    }

    override func updateClosingInformation() {
        guard let moc = managedObjectContext else {
            return
        }
        if closesIssuesList.isEmpty {
            if !closesIssues.isEmpty {
                closesIssues.removeAll()
            }
        } else {
            let issues = closesIssuesList.compactMap { Issue.item(id: $0, in: moc) }
            closesIssues.formIntersection(issues)
            closesIssues.formUnion(issues)
        }
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PullRequest.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { pr, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id ?? node.jsonPayload.potentialObject(named: "repository")?.potentialString(named: "id"),
                  let parent = Repo.asParent(with: parentId, in: moc, parentCache: parentCache)
            else { return }

            let json = node.jsonPayload

            if let mergeField = json.potentialString(named: "mergeable") {
                pr.isMergeable = mergeField != "CONFLICTING"
            } else {
                pr.isMergeable = true
            }
            pr.linesAdded = json.potentialInt(named: "additions") ?? 0
            pr.linesRemoved = json.potentialInt(named: "deletions") ?? 0
            pr.mergeCommitSha = json.potentialString(named: "headRefOid")
            pr.mergedByNodeId = json.potentialObject(named: "mergedBy")?.potentialString(named: "id")
            pr.baseNodeSync(node: node, parent: parent)
            pr.reviewers = "" // will be populated by the review request API calls
            pr.teamReviewers = "" // will be populated by the review request API calls

            let headRefName = json.potentialString(named: "headRefName")
            if let headRefName,
               let headRepoName = json.potentialObject(named: "headRepository")?.potentialString(named: "nameWithOwner") {
                pr.headLabel = headRepoName + ":" + headRefName
            } else {
                pr.headLabel = nil
            }
            pr.headRefName = headRefName

            let baseRefName = json.potentialString(named: "baseRefName")
            if let baseRefName,
               let baseRepoName = json.potentialObject(named: "baseRepository")?.potentialString(named: "nameWithOwner") {
                pr.baseLabel = baseRepoName + ":" + baseRefName
            } else {
                pr.baseLabel = nil
            }
        }
    }

    override var isPr: Bool {
        true
    }

    override var asPr: PullRequest? {
        self
    }

    var reviewCommentLink: String? {
        repo.apiUrl?.appending(pathComponent: "pulls").appending(pathComponent: String(number)).appending(pathComponent: "comments")
    }

    var statusesLink: String? {
        repo.apiUrl?.appending(pathComponent: "statuses").appending(pathComponent: mergeCommitSha.orEmpty)
    }

    static func syncPullRequests(from data: [TypedJson.Entry]?, in repo: Repo, moc: NSManagedObjectContext) async {
        let apiServer = repo.apiServer
        let apiServerUserId = apiServer.userNodeId
        let repoId = repo.objectID
        await v3items(with: data, type: PullRequest.self, serverId: apiServer.objectID, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated {
                let repo = try! syncMoc.existingObject(with: repoId) as! Repo
                item.baseSync(from: info, in: repo)

                let baseInfo = info.potentialObject(named: "base")
                item.baseLabel = baseInfo?.potentialString(named: "label")

                let headInfo = info.potentialObject(named: "head")
                item.headRefName = headInfo?.potentialString(named: "ref")
                item.headLabel = headInfo?.potentialString(named: "label")

                item.reviewers = ""
                item.teamReviewers = ""

                if
                    let newHeadCommitSha = headInfo?.potentialString(named: "sha"),
                    let commitUserInfo = headInfo?.potentialObject(named: "user"),
                    let newHeadCommitUserId = commitUserInfo.potentialString(named: "node_id") {
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

    override var shouldHideBecauseOfRepoHidingPolicy: Section.HidingCause? {
        if createdByMe {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllMyAuthoredItems.rawValue:
                .hidingAllMyAuthoredItems
            case RepoHidingPolicy.hideMyAuthoredPrs.rawValue:
                .hidingMyAuthoredPrs
            default:
                nil
            }
        } else {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllOthersItems.rawValue:
                .hidingAllOthersItems
            case RepoHidingPolicy.hideOthersPrs.rawValue:
                .hidingOthersPrs
            default:
                nil
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

        if reviewerNames.contains(apiServer.userName.orEmpty) {
            setAssignedReviewStatus(to: .me)
        } else if reviewerTeams.isEmpty {
            setAssignedReviewStatus(to: .none)
        } else if apiServer.teams.compactMap(\.slug).contains(where: { reviewerTeams.contains($0) }) {
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

    override static func hasOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Bool {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.fetchLimit = 1
        add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.open.matchingPredicate, in: moc)
        return try! moc.count(for: f) > 0
    }

    static func markEverythingRead(in section: Section, in moc: NSManagedObjectContext, settings: Settings.Cache) {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if section.visible {
            f.predicate = section.matchingPredicate
        }
        for pr in try! moc.fetch(f) {
            pr.catchUpWithComments(settings: settings)
        }
    }

    override func catchUpWithComments(settings: Settings.Cache) {
        hasNewCommits = false
        super.catchUpWithComments(settings: settings)
    }

    override static func badgeCount(from fetch: NSFetchRequest<some ListableItem>, in moc: NSManagedObjectContext) -> Int {
        var badgeCount = super.badgeCount(from: fetch, in: moc)
        if Settings.markPrsAsUnreadOnNewCommits {
            for i in try! moc.fetch(fetch) {
                if let i = i.asPr, i.hasNewCommits {
                    badgeCount += 1
                }
            }
        }
        return badgeCount
    }

    static func badgeCount(in section: Section, in moc: NSManagedObjectContext, settings: Settings.Cache) -> Int {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, includeInUnreadPredicate(settings: settings)])
        return badgeCount(from: f, in: moc)
    }

    static func badgeCount(in moc: NSManagedObjectContext, settings: Settings.Cache) -> Int {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate(settings: settings)])
        return badgeCount(from: f, in: moc)
    }

    @MainActor
    static func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, settings: Settings.Cache) -> Int {
        let f = requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: criterion, settings: settings)
        return badgeCount(from: f, in: moc)
    }

    private static let _unreadOrNewCommitsPredicate = NSPredicate(format: "unreadComments > 0 or hasNewCommits == YES")
    override static func includeInUnreadPredicate(settings: Settings.Cache) -> NSPredicate {
        settings.markPrsAsUnreadOnNewCommits ? _unreadOrNewCommitsPredicate : super.includeInUnreadPredicate(settings: settings)
    }

    override var contextMenuTitle: String {
        muted ? "PR #\(number) (muted)" : "PR #\(number)"
    }

    override var contextMenuSubtitle: String? {
        headRefName
    }

    override func shouldHideBecauseOfRedStatuses(in section: Section, settings: Settings.Cache) -> Section.HidingCause? {
        guard settings.hidePrsThatArentPassing else {
            return nil
        }

        switch section {
        case .all:
            break

        case .mine, .participated:
            if settings.hidePrsThatDontPassOnlyInAll {
                return nil
            }

        case .closed, .hidden, .mentioned, .merged, .snoozed:
            return nil
        }

        let allSuccesses = displayedStatusLines(settings: settings).allSatisfy { $0.state == "success" }

        guard allSuccesses else {
            return .containsNonGreenStatuses
        }

        return nil
    }

    override func countReviews(settings: Settings.Cache) -> Int {
        guard settings.requiresReviewApis else {
            return 0
        }
        var count = 0
        for r in reviews where settings.commenterInclusionRule.shouldContributeToCount(isMine: r.isMine, userName: r.username, createdAt: r.createdAt, since: .distantPast, settings: settings) {
            count += 1
        }
        return count
    }

    static func statusCheckBatch(in moc: NSManagedObjectContext, settings: Settings.Cache) -> [PullRequest] {
        let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
        f.predicate = ApiServer.lastSyncSucceededPredicate
        f.sortDescriptors = [
            NSSortDescriptor(key: "lastStatusScan", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        let prs = try! moc.fetch(f)
            .filter { $0.section.shouldCheckStatuses(settings: settings) }
            .prefix(Settings.statusItemRefreshBatchSize)

        for pr in prs {
            for status in pr.statuses {
                status.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        return Array(prs)
    }

    func displayedStatusLines(settings: Settings.Cache) -> [PRStatus] {
        let red = settings.statusRed
        let yellow = settings.statusYellow
        let green = settings.statusGreen
        let gray = settings.statusGray
        let mode = settings.statusMode
        let terms = settings.statusTerms

        var contexts = [String: PRStatus]()
        let filteredStatuses: Set<PRStatus> = if red, yellow, green, gray {
            statuses
        } else {
            statuses.filter {
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

    func shouldAnnounceStatus(settings: Settings.Cache) -> Bool {
        canBadge(settings: settings)
            && (settings.notifyOnStatusUpdatesForAllPrs
                || createdByMe
                || shouldGo(to: .participated, settings: settings)
                || shouldGo(to: .mine, settings: settings)
                || shouldGo(to: .mentioned, settings: settings))
    }

    func linesAttributedString(labelFont: FONT_CLASS) -> NSAttributedString? {
        let added = linesAdded
        let removed = linesRemoved

        if added == 0, removed == 0 {
            return nil
        }

        let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)

        let res = NSMutableAttributedString()
        if added > 0 {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appGreen]
            res.append(NSAttributedString(string: "+\(added.formatted())", attributes: attributes))
            if removed > 0 {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.lightGray]
                res.append(NSAttributedString(string: "\u{a0}", attributes: attributes))
            }
        }
        if removed > 0 {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appRed]
            res.append(NSAttributedString(string: "-\(removed.formatted())", attributes: attributes))
        }
        return res
    }

    override var repoDisplayPolicy: Int {
        repo.displayPolicyForPrs
    }

    override func shouldHideDueToMyReview(settings: Settings.Cache) -> Section.HidingCause? {
        let hideIfApproved = settings.hidePrsIfApproved
        let hideIfRejected = settings.hidePrsIfRejected

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

    func reviewsAttributedString(labelFont: FONT_CLASS, settings: Settings.Cache) -> NSAttributedString? {
        if !Settings.displayReviewsOnItems {
            return nil
        }

        let res = NSMutableAttributedString()

        if settings.showRequestedTeamReviews {
            let teamReviewRequests = teamReviewers.components(separatedBy: ",")
            let names = teamReviewRequests.compactMap {
                if let moc = managedObjectContext {
                    Team.team(with: $0, in: moc)?.calculatedReferral
                } else {
                    nil
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

    override final func handleMerging(settings: Settings.Cache) {
        let byUserId = mergedByNodeId
        let myUserId = apiServer.userNodeId
        Logging.log("Detected merged PR: \(title.orEmpty) by user \(byUserId.orEmpty), local user id is: \(myUserId.orEmpty), handling policy is \(Settings.mergeHandlingPolicy), coming from section \(sectionIndex)")

        if !isVisibleOnMenu {
            Logging.log("Merged PR was hidden, won't announce")
            managedObjectContext?.delete(self)

        } else if byUserId == myUserId, Settings.dontKeepPrsMergedByMe {
            Logging.log("Will not keep PR merged by me")
            managedObjectContext?.delete(self)

        } else if shouldKeep(accordingTo: Settings.mergeHandlingPolicy, settings: settings) {
            Logging.log("Will keep merged PR")
            keep(as: .merged, notification: .prMerged, settings: settings)

        } else {
            Logging.log("Will not keep merged PR")
            managedObjectContext?.delete(self)
        }
    }
}
