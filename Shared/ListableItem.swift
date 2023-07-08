import CoreData
import CoreSpotlight
import TrailerQL

#if os(iOS)
    import MobileCoreServices
    import UIKit
    import UserNotifications
#else
    import Cocoa
#endif

struct PostProcessContext {
    let excludedLabels = Set(Settings.labelBlacklist.map(\.comparableForm))
    let excludedAuthors = Set(Settings.itemAuthorBlacklist.map(\.comparableForm))
    let assumeReadItemIfUserHasNewerComments = Settings.assumeReadItemIfUserHasNewerComments
    let hideUncommentedItems = Settings.hideUncommentedItems
    let shouldSyncReviews = API.shouldSyncReviews
    let shouldSyncReviewAssignments = API.shouldSyncReviewAssignments
    let notifyOnItemReactions = Settings.notifyOnItemReactions
    let notifyOnCommentReactions = Settings.notifyOnCommentReactions
}

class ListableItem: DataItem {
    enum StateChange: Int {
        case none, reopened, merged, closed
    }

    @NSManaged var assignedToMe: Bool
    @NSManaged var assigneeName: String? // note: This now could be a list of names, delimited with a ","
    @NSManaged var body: String?
    @NSManaged var condition: Int
    @NSManaged var isNewAssignment: Bool
    @NSManaged var repo: Repo
    @NSManaged var title: String?
    @NSManaged var totalComments: Int
    @NSManaged var unreadComments: Int
    @NSManaged var url: String?
    @NSManaged var userAvatarUrl: String?
    @NSManaged var userNodeId: String?
    @NSManaged var userLogin: String?
    @NSManaged var sectionIndex: Int
    @NSManaged var latestReadCommentDate: Date?
    @NSManaged var stateChanged: Int
    @NSManaged var number: Int
    @NSManaged var announced: Bool
    @NSManaged var muted: Bool
    @NSManaged var wasAwokenFromSnooze: Bool
    @NSManaged var milestone: String?
    @NSManaged var dirty: Bool
    @NSManaged var draft: Bool

    @NSManaged var lastStatusScan: Date?
    @NSManaged var lastReactionScan: Date?

    @NSManaged var snoozeUntil: Date?
    @NSManaged var snoozingPreset: SnoozePreset?

    @NSManaged var comments: Set<PRComment>
    @NSManaged var labels: Set<PRLabel>
    @NSManaged var reactions: Set<Reaction>

    var webUrl: String? {
        repo.webUrl
    }

    var commentsLink: String? {
        issueUrl?.appending(pathComponent: "comments")
    }

    var issueUrl: String? {
        repo.apiUrl?.appending(pathComponent: "issues").appending(pathComponent: String(number))
    }

    var reactionsUrl: String? {
        issueUrl?.appending(pathComponent: "reactions")
    }

    static func reactionCheckBatch<T: ListableItem>(for type: T.Type, in moc: NSManagedObjectContext) -> [T] {
        let entityName = String(describing: type)
        let f = NSFetchRequest<T>(entityName: entityName)
        f.predicate = NSPredicate(format: "apiServer.lastSyncSucceeded == YES")
        f.sortDescriptors = [
            NSSortDescriptor(key: "lastReactionScan", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        let items = try! moc.fetch(f)
            .filter(\.section.shouldListReactions)
            .prefix(Settings.reactionScanningBatchSize)

        items.forEach {
            $0.comments.forEach {
                $0.pendingReactionScan = $0.isMine
            }
            $0.reactions.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        return Array(items)
    }

    final func baseNodeSync(node: TrailerQL.Node, parent: Repo) {
        repo = parent

        let info = node.jsonPayload
        url = info["url"] as? String
        number = info["number"] as? Int ?? 0
        title = info["title"] as? String ?? "(No title)"
        body = info["bodyText"] as? String
        milestone = (info["milestone"] as? JSON)?["title"] as? String
        draft = info["isDraft"] as? Bool ?? false

        let newCondition: Int
        switch info["state"] as? String {
        case "MERGED": newCondition = ItemCondition.merged.rawValue
        case "CLOSED": newCondition = ItemCondition.closed.rawValue
        default: newCondition = ItemCondition.open.rawValue
        }

        switch condition {
        case ItemCondition.closed.rawValue where newCondition == ItemCondition.open.rawValue,
             ItemCondition.merged.rawValue where newCondition == ItemCondition.open.rawValue:
            stateChanged = StateChange.reopened.rawValue
        case ItemCondition.open.rawValue where newCondition == ItemCondition.merged.rawValue:
            stateChanged = StateChange.merged.rawValue
        case ItemCondition.open.rawValue where newCondition == ItemCondition.closed.rawValue:
            stateChanged = StateChange.closed.rawValue
        default: break
        }

        condition = newCondition

        if let user = info["author"] as? JSON {
            userLogin = user["login"] as? String
            userAvatarUrl = user["avatarUrl"] as? String
            userNodeId = user["id"] as? String
        }

        let i: [JSON]
        if let assignees = (info["assignees"] as? JSON)?["edges"] as? [JSON] {
            i = assignees.compactMap { $0["node"] as? JSON }
        } else {
            i = []
        }

        processAssignmentStatus(from: ["assignees": i], idField: "id")

        if node.updated {
            labels.removeAll() // so not set delete post sync action, as label may not just be a child to this item. Orphaned labels are nuked afterwards
        }
    }

    final func baseSync(from info: JSON, in parentRepo: Repo) {
        repo = parentRepo
        url = info["url"] as? String
        number = info["number"] as? Int ?? 0
        title = info["title"] as? String ?? "(No title)"
        body = info["body"] as? String
        milestone = (info["milestone"] as? JSON)?["title"] as? String
        draft = info["draft"] as? Bool ?? false

        if let userInfo = info["user"] as? JSON {
            userLogin = userInfo["login"] as? String
            userAvatarUrl = userInfo["avatar_url"] as? String
            userNodeId = userInfo["node_id"] as? String
        }

        processAssignmentStatus(from: info, idField: "node_id")
    }

    var section: Section {
        Section(rawValue: sectionIndex) ?? .none
    }

    final func processAssignmentStatus(from info: JSON?, idField: String) {
        let myIdOnThisRepo = repo.apiServer.userNodeId
        var assigneeNames = [String]()

        func checkAndStoreAssigneeName(from assignee: JSON) -> Bool {
            if let name = assignee["login"] as? String, let assigneeId = assignee[idField] as? String {
                let shouldBeAssignedToMe = assigneeId == myIdOnThisRepo
                assigneeNames.append(name)
                return shouldBeAssignedToMe
            } else {
                return false
            }
        }

        var foundAssignmentToMe = false

        if let assignees = info?["assignees"] as? [JSON], !assignees.isEmpty {
            for assignee in assignees where checkAndStoreAssigneeName(from: assignee) {
                foundAssignmentToMe = true
            }
        } else if let assignee = info?["assignee"] as? JSON {
            foundAssignmentToMe = checkAndStoreAssigneeName(from: assignee)
        }

        isNewAssignment = foundAssignmentToMe && !assignedToMe && !createdByMe
        assignedToMe = foundAssignmentToMe

        if assigneeNames.isEmpty {
            assigneeName = nil
        } else {
            assigneeName = assigneeNames.joined(separator: ",")
        }
    }

    final func setToUpdatedIfIdle() {
        if postSyncAction == PostSyncAction.doNothing.rawValue {
            postSyncAction = PostSyncAction.isUpdated.rawValue
        }
    }

    static func active<T>(of type: T.Type, in moc: NSManagedObjectContext, visibleOnly: Bool) -> [T] where T: ListableItem {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if visibleOnly {
            f.predicate = NSCompoundPredicate(type: .or, subpredicates: [Section.mine.matchingPredicate, Section.participated.matchingPredicate, Section.all.matchingPredicate])
        } else {
            f.predicate = ItemCondition.open.matchingPredicate
        }
        return try! moc.fetch(f)
    }

    override final func resetSyncState() {
        super.resetSyncState()
        repo.resetSyncState()
    }

    override final func prepareForDeletion() {
        let uri = objectID.uriRepresentation().absoluteString
        Task { @MainActor in
            hideFromNotifications(uri: uri)
        }
        super.prepareForDeletion()
    }

    private final func hideFromNotifications(uri: String) {
        if Settings.removeNotificationsWhenItemIsRemoved {
            ListableItem.removeRelatedNotifications(uri: uri)
        }
    }

    final func sortedComments(using comparison: ComparisonResult) -> [PRComment] {
        comments.sorted { c1, c2 -> Bool in
            let d1 = c1.createdAt ?? .distantPast
            let d2 = c2.createdAt ?? .distantPast
            return d1.compare(d2) == comparison
        }
    }

    private final func catchUpCommentDate() {
        for c in comments {
            if let commentCreation = c.createdAt {
                if let latestRead = latestReadCommentDate {
                    if latestRead < commentCreation {
                        latestReadCommentDate = commentCreation
                    }
                } else {
                    latestReadCommentDate = commentCreation
                }
            }
            for r in c.reactions {
                if let reactionCreation = r.createdAt {
                    if let latestRead = latestReadCommentDate {
                        if latestRead < reactionCreation {
                            latestReadCommentDate = reactionCreation
                        }
                    } else {
                        latestReadCommentDate = reactionCreation
                    }
                }
            }
        }
        for r in reactions {
            if let reactionCreation = r.createdAt {
                if let latestRead = latestReadCommentDate {
                    if latestRead < reactionCreation {
                        latestReadCommentDate = reactionCreation
                    }
                } else {
                    latestReadCommentDate = reactionCreation
                }
            }
        }
        if let p = self as? PullRequest {
            p.hasNewCommits = false
            for r in p.reviews {
                if let reviewCreation = r.createdAt {
                    if let latestRead = latestReadCommentDate {
                        if latestRead < reviewCreation {
                            latestReadCommentDate = reviewCreation
                        }
                    } else {
                        latestReadCommentDate = reviewCreation
                    }
                }
            }
        }
    }

    func catchUpWithComments() {
        catchUpCommentDate()
        postProcess()
    }

    final func shouldKeep(accordingTo policy: Int) -> Bool { // issue: item has already been moved at this point
        let policy = HandlingPolicy(rawValue: policy)

        switch policy {
        case .keepAll:
            return true

        case .keepMineAndParticipated:
            let preConditionSection = preferredSection(takingItemConditionIntoAccount: false)
            return preConditionSection == .mine || preConditionSection == .participated

        case .keepMine:
            let preConditionSection = preferredSection(takingItemConditionIntoAccount: false)
            return preConditionSection == .mine

        case .keepNone, .none:
            return false
        }
    }

    final var shouldSkipNotifications: Bool {
        isSnoozing || muted
    }

    final var assignedToMySection: Bool {
        assignedToMe && Settings.assignedPrHandlingPolicy == AssignmentPolicy.moveToMine.rawValue
    }

    final var assignedToParticipated: Bool {
        assignedToMe && Settings.assignedPrHandlingPolicy == AssignmentPolicy.moveToParticipated.rawValue
    }

    final var createdByMe: Bool {
        userNodeId == apiServer.userNodeId
    }

    private final func contains(terms: [String]) -> Bool {
        if let b = body {
            for t in terms where !t.isEmpty && b.localizedCaseInsensitiveContains(t) {
                return true
            }
        }
        for c in comments where c.contains(terms: terms) {
            return true
        }
        return false
    }

    private final var commentedByMe: Bool {
        comments.contains { $0.isMine }
    }

    var reviewedByMe: Bool {
        false
    }

    final var isVisibleOnMenu: Bool {
        sectionIndex != Section.none.rawValue
    }

    final func wakeUp() {
        disableSnoozing(explicityAwoke: true)
        postProcess()
    }

    final var isSnoozing: Bool {
        snoozeUntil != nil
    }

    final var canBadge: Bool {
        if let section = Section(rawValue: sectionIndex) {
            return canBadge(in: section)
        }
        return false
    }

    final func keep(as newCondition: ItemCondition, notification: NotificationType) {
        if sectionIndex == Section.all.rawValue, !Section.all.shouldBadgeComments {
            catchUpCommentDate()
        }
        postSyncAction = PostSyncAction.doNothing.rawValue
        condition = newCondition.rawValue
        if snoozeUntil != nil {
            snoozeUntil = nil
            snoozingPreset = nil
        } else {
            NotificationQueue.add(type: notification, for: self)
        }
        postProcess() // make sure it's in the right section and updated correctly for its new status
    }

    private final var shouldMoveToSnoozing: Bool {
        if snoozeUntil == nil {
            let d = TimeInterval(Settings.autoSnoozeDuration)
            if d > 0, !wasAwokenFromSnooze, updatedAt != .distantPast, let snoozeByDate = updatedAt?.addingTimeInterval(86400.0 * d) {
                if snoozeByDate < Date() {
                    snoozeUntil = autoSnoozeSentinelDate
                    return true
                }
            }
            return false
        } else {
            return true
        }
    }

    final var shouldWakeOnComment: Bool {
        snoozingPreset?.wakeOnComment ?? true
    }

    final var shouldWakeOnMention: Bool {
        snoozingPreset?.wakeOnMention ?? true
    }

    final var shouldWakeOnStatusChange: Bool {
        snoozingPreset?.wakeOnStatusChange ?? true
    }

    final func wakeIfAutoSnoozed() {
        if snoozeUntil == autoSnoozeSentinelDate {
            disableSnoozing(explicityAwoke: false)
        }
    }

    @MainActor
    final func snooze(using preset: SnoozePreset) {
        snoozeUntil = preset.wakeupDateFromNow
        snoozingPreset = preset
        wasAwokenFromSnooze = false
        muted = false
        postProcess()
    }

    var hasUnreadCommentsOrAlert: Bool {
        unreadComments > 0
    }

    private final func disableSnoozing(explicityAwoke: Bool) {
        snoozeUntil = nil
        snoozingPreset = nil
        wasAwokenFromSnooze = explicityAwoke
    }

    private func preferredSection(takingItemConditionIntoAccount: Bool) -> Section {
        if Settings.draftHandlingPolicy == DraftHandlingPolicy.hide.rawValue && draft {
            return .none

        } else if takingItemConditionIntoAccount && condition == ItemCondition.merged.rawValue {
            return .merged

        } else if takingItemConditionIntoAccount && condition == ItemCondition.closed.rawValue {
            return .closed

        } else if createdByMe || assignedToMySection {
            return .mine

        } else if assignedToParticipated || commentedByMe || reviewedByMe {
            return .participated

        } else if let p = self as? PullRequest, Settings.assignedReviewHandlingPolicy > Section.none.rawValue, p.assignedForReview {
            return Section(rawValue: Settings.assignedReviewHandlingPolicy)!

        } else if Settings.newMentionMovePolicy > Section.none.rawValue, contains(terms: ["@\(apiServer.userName.orEmpty)"]) {
            return Section(rawValue: Settings.newMentionMovePolicy)!

        } else if Settings.teamMentionMovePolicy > Section.none.rawValue, contains(terms: apiServer.teams.compactMap(\.calculatedReferral)) {
            return Section(rawValue: Settings.teamMentionMovePolicy)!

        } else if Settings.newItemInOwnedRepoMovePolicy > Section.none.rawValue, repo.isMine {
            return Section(rawValue: Settings.newItemInOwnedRepoMovePolicy)!

        } else {
            return .all
        }
    }

    private func canBadge(in targetSection: Section) -> Bool {
        if !targetSection.shouldBadgeComments || muted || postSyncAction == PostSyncAction.isNew.rawValue {
            return false
        }

        if targetSection == .closed || targetSection == .merged {
            return preferredSection(takingItemConditionIntoAccount: false).shouldBadgeComments
        }

        return true
    }

    final func postProcess(context: PostProcessContext = PostProcessContext()) {
        if let s = snoozeUntil, s < Date() { // our snooze-by date is past
            disableSnoozing(explicityAwoke: true)
        }

        var targetSection = preferredSection(takingItemConditionIntoAccount: true)

        if targetSection != .none {
            switch self is Issue ? repo.displayPolicyForIssues : repo.displayPolicyForPrs {
            case RepoDisplayPolicy.hide.rawValue,
                 RepoDisplayPolicy.mine.rawValue where targetSection == .all || targetSection == .participated || targetSection == .mentioned,
                 RepoDisplayPolicy.mineAndPaticipated.rawValue where targetSection == .all:
                targetSection = .none
            default: break
            }
        }

        if targetSection != .none {
            let isMine = createdByMe

            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideMyAuthoredPrs.rawValue where isMine && self is PullRequest,
                 RepoHidingPolicy.hideMyAuthoredIssues.rawValue where isMine && self is Issue,
                 RepoHidingPolicy.hideAllMyAuthoredItems.rawValue where isMine,
                 RepoHidingPolicy.hideOthersPrs.rawValue where !isMine && self is PullRequest,
                 RepoHidingPolicy.hideOthersIssues.rawValue where !isMine && self is Issue,
                 RepoHidingPolicy.hideAllOthersItems.rawValue where !isMine:

                targetSection = .none
            default: break
            }
        }

        if targetSection != .none,
           let p = self as? PullRequest, p.shouldBeCheckedForRedStatuses(in: targetSection),
           p.displayedStatuses.contains(where: { $0.state != "success" }) {
            targetSection = .none
        }

        if targetSection != .none {
            let excluded = context.excludedLabels
            if !excluded.isEmpty {
                let mine = Set(labels.compactMap { $0.name?.comparableForm })
                if !excluded.isDisjoint(with: mine) {
                    targetSection = .none
                }
            }
        }

        if targetSection != .none {
            let excludeAuthors = context.excludedAuthors
            if !excludeAuthors.isEmpty, let login = userLogin?.comparableForm {
                if excludeAuthors.contains(login) {
                    targetSection = .none
                }
            }
        }

        if targetSection != .none, shouldMoveToSnoozing {
            targetSection = .snoozed
        }

        if canBadge(in: targetSection) {
            var latestDate = latestReadCommentDate ?? .distantPast

            if context.assumeReadItemIfUserHasNewerComments {
                for c in myComments(since: latestDate) {
                    if let createdDate = c.createdAt, latestDate < createdDate {
                        latestDate = createdDate
                    }
                }
                latestReadCommentDate = latestDate
            }
            unreadComments = countOthersComments(since: latestDate, context: context)

        } else {
            catchUpCommentDate()
            unreadComments = 0
        }

        if targetSection != .none, context.hideUncommentedItems, unreadComments == 0 {
            targetSection = .none
        }

        if snoozeUntil != nil, let p = self as? PullRequest, shouldWakeOnComment, p.hasNewCommits { // we wake on comments and have a new commit alarm
            wakeUp() // re-process as awake item
            return
        }

        if targetSection != .none {
            let reviewCount: Int
            if let p = self as? PullRequest, context.shouldSyncReviews || context.shouldSyncReviewAssignments {
                reviewCount = p.reviews.count
            } else {
                reviewCount = 0
            }

            totalComments = comments.count
                + (context.notifyOnItemReactions ? reactions.count : 0)
                + (context.notifyOnCommentReactions ? countCommentReactions : 0)
                + reviewCount
        }

        sectionIndex = targetSection.rawValue
    }

    private var countCommentReactions: Int {
        var count = 0
        for c in comments {
            count += c.reactions.count
        }
        return count
    }

    private final func myComments(since: Date) -> [PRComment] {
        comments.filter { $0.isMine && ($0.createdAt ?? .distantPast) > since }
    }

    private final func othersComments(since: Date) -> [PRComment] {
        comments.filter { !$0.isMine && ($0.createdAt ?? .distantPast) > since }
    }

    private final func countOthersComments(since: Date, context: PostProcessContext) -> Int {
        var count = 0
        for c in comments {
            if !c.isMine, (c.createdAt ?? .distantPast) > since {
                count += 1
            }
            if context.notifyOnCommentReactions {
                for r in c.reactions where !r.isMine && (r.createdAt ?? .distantPast) > since {
                    count += 1
                }
            }
        }
        if context.notifyOnItemReactions {
            for r in reactions where !r.isMine && (r.createdAt ?? .distantPast) > since {
                count += 1
            }
        }
        return count
    }

    final var urlForOpening: String? {
        if unreadComments > 0, Settings.openPrAtFirstUnreadComment {
            var oldestComment: PRComment?
            for c in othersComments(since: latestReadCommentDate ?? .distantPast) {
                if let o = oldestComment {
                    if c.createdBefore(o) {
                        oldestComment = c
                    }
                } else {
                    oldestComment = c
                }
            }
            if let c = oldestComment, let url = c.webUrl {
                return url
            }
        }

        return webUrl
    }

    final var accessibleTitle: String {
        let components = LinkedList<String>()
        if let t = title {
            components.append(t)
        }
        if draft, Settings.draftHandlingPolicy == DraftHandlingPolicy.display.rawValue {
            components.append("draft")
        }
        components.append("\(labels.count) labels:")
        for l in sortedLabels {
            if let n = l.name {
                components.append(n)
            }
        }
        return components.joined(separator: ",")
    }

    final var sortedLabels: [PRLabel] {
        Array(labels).sorted {
            $0.name!.compare($1.name!) == .orderedAscending
        }
    }

    final func labelsAttributedString(labelFont: FONT_CLASS) -> NSAttributedString? {
        if !Settings.showLabels {
            return nil
        }

        let sorted = sortedLabels
        if sorted.isEmpty {
            return nil
        }

        func isDark(color: COLOR_CLASS) -> Bool {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: nil)
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return lum < 0.5
        }

        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .baselineOffset: 0]
        let res = NSMutableAttributedString()
        for l in sorted {
            var a = labelAttributes
            let color = l.colorForDisplay
            a[.backgroundColor] = color
            a[.foregroundColor] = isDark(color: color) ? COLOR_CLASS.white : COLOR_CLASS.black
            let name = l.name!.replacingOccurrences(of: " ", with: "\u{a0}")
            res.append(NSAttributedString(string: "\u{a0}\(name)\u{a0}", attributes: a))
            res.append(NSAttributedString(string: " ", attributes: labelAttributes))
        }
        return res
    }

    final func title(with font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS, numberColor: COLOR_CLASS) -> NSMutableAttributedString {
        let _title = NSMutableAttributedString()
        guard let t = title else {
            return _title
        }

        if Settings.displayNumbersForItems {
            let numberAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
            _title.append(NSAttributedString(string: "#\(number) ", attributes: numberAttributes))
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: titleColor]
        _title.append(NSAttributedString(string: t, attributes: titleAttributes))

        if let p = self as? PullRequest {
            if Settings.showPrLines, let l = p.linesAttributedString(labelFont: labelFont) {
                _title.append(NSAttributedString(string: " ", attributes: titleAttributes))
                _title.append(l)
            }
            if Settings.markUnmergeablePrs, !p.isMergeable {
                _title.append(NSAttributedString(string: " ", attributes: titleAttributes))

                let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)
                let unmergeableAttributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appRed]
                _title.append(NSAttributedString(string: "CONFLICT", attributes: unmergeableAttributes))
            }
        }

        if draft, Settings.draftHandlingPolicy == DraftHandlingPolicy.display.rawValue {
            _title.append(NSAttributedString(string: " ", attributes: titleAttributes))

            let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)
            let draftAttributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.systemOrange]
            _title.append(NSAttributedString(string: "DRAFT", attributes: draftAttributes))
        }
        return _title
    }

    func subtitle(with font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS, separator: String) -> NSMutableAttributedString {
        let _subtitle = NSMutableAttributedString()

        let lightSubtitle = [NSAttributedString.Key.foregroundColor: lightColor,
                             NSAttributedString.Key.font: font]

        let separatorString = NSAttributedString(string: separator, attributes: lightSubtitle)

        var darkSubtitle = lightSubtitle
        darkSubtitle[NSAttributedString.Key.foregroundColor] = darkColor

        if Settings.showBaseAndHeadBranches, let p = self as? PullRequest, let b = p.baseLabel, let h = p.headLabel {
            let splitB = b.components(separatedBy: ":")
            let splitH = h.components(separatedBy: ":")
            let repoB, repoH, branchB, branchH: String?
            if splitB.count == 2 && splitH.count == 2 {
                repoB = splitB.first ?? repo.fullName
                if splitB.first == splitH.first { // same repo
                    repoH = nil
                } else {
                    repoH = splitH.first
                }
            } else {
                repoH = splitH.first
                repoB = splitB.first
            }
            branchB = splitB.last
            branchH = splitH.last

            if let repoB {
                _subtitle.append(NSAttributedString(string: repoB, attributes: darkSubtitle))
                if branchB != nil {
                    _subtitle.append(NSAttributedString(string: ":", attributes: lightSubtitle))
                }
            }
            if let branchB {
                _subtitle.append(NSAttributedString(string: branchB, attributes: lightSubtitle))
            }

            if repoH != nil || branchH != nil {
                _subtitle.append(NSAttributedString(string: " ← ", attributes: lightSubtitle))
            }

            if let repoH {
                _subtitle.append(NSAttributedString(string: repoH, attributes: lightSubtitle))
                if branchH != nil {
                    _subtitle.append(NSAttributedString(string: ":", attributes: lightSubtitle))
                }
            }
            if let branchH {
                _subtitle.append(NSAttributedString(string: branchH, attributes: lightSubtitle))
            }
            _subtitle.append(separatorString)

        } else if Settings.showReposInName, let n = repo.fullName {
            _subtitle.append(NSAttributedString(string: n, attributes: darkSubtitle))
            _subtitle.append(separatorString)
        }

        if Settings.showMilestones, let m = milestone, !m.isEmpty {
            _subtitle.append(NSAttributedString(string: m, attributes: darkSubtitle))
            _subtitle.append(separatorString)
        }

        if let l = userLogin {
            _subtitle.append(NSAttributedString(string: "@\(l)", attributes: lightSubtitle))
            _subtitle.append(separatorString)
        }

        _subtitle.append(NSAttributedString(string: displayDate, attributes: lightSubtitle))

        return _subtitle
    }

    var accessibleSubtitle: String {
        var components = [String]()

        if Settings.showReposInName {
            components.append("Repository: \(repo.fullName.orEmpty)")
        }

        if let l = userLogin {
            components.append("Author: \(l)")
        }

        components.append(displayDate)

        return components.joined(separator: ",")
    }

    var displayDate: String {
        if Settings.showRelativeDates {
            if Settings.showCreatedInsteadOfUpdated {
                return agoFormat(prefix: "created", since: createdAt)
            } else {
                return agoFormat(prefix: "updated", since: updatedAt)
            }
        } else {
            if Settings.showCreatedInsteadOfUpdated {
                return "created " + itemDateFormatter.string(from: createdAt!)
            } else {
                return "updated " + itemDateFormatter.string(from: updatedAt!)
            }
        }
    }

    static func styleForEmpty(message: String, color: COLOR_CLASS) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.alignment = .center
        #if os(OSX)
            return NSAttributedString(string: message, attributes: [
                NSAttributedString.Key.foregroundColor: color,
                NSAttributedString.Key.paragraphStyle: p
            ])
        #elseif os(iOS)
            return NSAttributedString(string: message, attributes: [
                NSAttributedString.Key.foregroundColor: color,
                NSAttributedString.Key.paragraphStyle: p,
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
            ])
        #endif
    }

    class func badgeCount(from fetch: NSFetchRequest<some ListableItem>, in moc: NSManagedObjectContext) -> Int {
        var badgeCount = 0
        fetch.returnsObjectsAsFaults = false
        for i in try! moc.fetch(fetch) {
            badgeCount += i.unreadComments
        }
        return Int(badgeCount)
    }

    private static func predicate(from token: String, termAt: Int, format: String, numeric: Bool) -> NSPredicate? {
        if token.count <= termAt {
            return nil
        }

        let items = token.dropFirst(termAt)
        if items.isEmpty {
            return nil
        }

        var orTerms = [NSPredicate]()
        var notTerms = [NSPredicate]()
        for term in items.components(separatedBy: ",") {
            let negative = term.hasPrefix("!")
            let T = negative ? String(term.dropFirst()) : term
            let P: NSPredicate
            if numeric, let n = UInt(T) {
                P = NSPredicate(format: format, n)
            } else {
                P = NSPredicate(format: format, T)
            }
            if negative {
                notTerms.append(NSCompoundPredicate(notPredicateWithSubpredicate: P))
            } else {
                orTerms.append(P)
            }
        }
        return predicate(notTerms: notTerms, orTerms: orTerms)
    }

    private static func statePredicate(from token: String, termAt: Int) -> NSPredicate? {
        if token.count <= termAt {
            return nil
        }

        let items = token.dropFirst(termAt)
        if items.isEmpty {
            return nil
        }

        var orTerms = [NSPredicate]()
        var notTerms = [NSPredicate]()
        for term in items.components(separatedBy: ",") {
            let negative = term.hasPrefix("!")
            let T = negative ? String(term.dropFirst()) : term

            let P: NSPredicate
            switch T {
            case "open":
                P = ItemCondition.open.matchingPredicate
            case "closed":
                P = ItemCondition.closed.matchingPredicate
            case "merged":
                P = ItemCondition.merged.matchingPredicate
            case "unread":
                P = includeInUnreadPredicate
            case "snoozed":
                P = isSnoozingPredicate
            case "draft":
                P = isDraftPredicate
            case "conflict":
                P = isUnmergeablePredicate
            default:
                continue
            }

            if negative {
                notTerms.append(NSCompoundPredicate(notPredicateWithSubpredicate: P))
            } else {
                orTerms.append(P)
            }
        }
        return predicate(notTerms: notTerms, orTerms: orTerms)
    }

    private static func predicate(notTerms: [NSPredicate], orTerms: [NSPredicate]) -> NSPredicate? {
        if !notTerms.isEmpty, !orTerms.isEmpty {
            return NSCompoundPredicate(andPredicateWithSubpredicates:
                [NSCompoundPredicate(andPredicateWithSubpredicates: notTerms),
                 NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)])
        } else if !notTerms.isEmpty {
            return NSCompoundPredicate(andPredicateWithSubpredicates: notTerms)
        } else if !orTerms.isEmpty {
            return NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)
        } else {
            return nil
        }
    }

    private static let filterTitlePredicate = "title contains[cd] %@"
    private static let filterRepoPredicate = "repo.fullName contains[cd] %@"
    private static let filterServerPredicate = "apiServer.label contains[cd] %@"
    private static let filterUserPredicate = "userLogin contains[cd] %@"
    private static let filterNumberPredicate = "number == %lld"
    private static let filterMilestonePredicate = "milestone contains[cd] %@"
    private static let filterAssigneePredicate = "assigneeName contains[cd] %@"
    private static let filterLabelPredicate = "SUBQUERY(labels, $label, $label.name contains[cd] %@).@count > 0"
    private static let filterStatusPredicate = "SUBQUERY(statuses, $status, $status.descriptionText contains[cd] %@).@count > 0"

    @MainActor
    static func requestForItems<T: ListableItem>(of itemType: T.Type, withFilter: String?, sectionIndex: Int, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false, excludeSnoozed: Bool = false) -> NSFetchRequest<T> {
        let andPredicates = LinkedList<NSPredicate>()

        if onlyUnread {
            andPredicates.append(itemType.includeInUnreadPredicate)
        }

        if sectionIndex < 0 {
            andPredicates.append(Section.nonZeroPredicate)

        } else if let s = Section(rawValue: sectionIndex) {
            andPredicates.append(s.matchingPredicate)
        }

        if excludeSnoozed || Settings.hideSnoozedItems {
            andPredicates.append(Section.snoozed.excludingPredicate)
        }

        if var fi = withFilter, !fi.isEmpty {
            func check(forTag tag: String, process: (String, Int) -> NSPredicate?) {
                var foundOne: Bool
                repeat {
                    foundOne = false
                    for token in fi.components(separatedBy: " ") {
                        let prefix = "\(tag):"
                        if token.hasPrefix(prefix) {
                            if let p = process(token, prefix.count) {
                                andPredicates.append(p)
                            }
                            fi = fi.replacingOccurrences(of: token, with: "").trim
                            foundOne = true
                            break
                        }
                    }
                } while foundOne
            }

            check(forTag: "title") { predicate(from: $0, termAt: $1, format: filterTitlePredicate, numeric: false) }
            check(forTag: "repo") { predicate(from: $0, termAt: $1, format: filterRepoPredicate, numeric: false) }
            check(forTag: "server") { predicate(from: $0, termAt: $1, format: filterServerPredicate, numeric: false) }
            check(forTag: "user") { predicate(from: $0, termAt: $1, format: filterUserPredicate, numeric: false) }
            check(forTag: "number") { predicate(from: $0, termAt: $1, format: filterNumberPredicate, numeric: true) }
            check(forTag: "milestone") { predicate(from: $0, termAt: $1, format: filterMilestonePredicate, numeric: false) }
            check(forTag: "assignee") { predicate(from: $0, termAt: $1, format: filterAssigneePredicate, numeric: false) }
            check(forTag: "label") { predicate(from: $0, termAt: $1, format: filterLabelPredicate, numeric: false) }
            if itemType.self == PullRequest.self {
                check(forTag: "status") { predicate(from: $0, termAt: $1, format: filterStatusPredicate, numeric: false) }
            }
            check(forTag: "state") { statePredicate(from: $0, termAt: $1) }

            if !fi.isEmpty {
                let predicates = LinkedList<NSPredicate>()
                let negative = fi.hasPrefix("!")

                func appendPredicate(format: String, numeric: Bool) {
                    if let p = predicate(from: fi, termAt: 0, format: format, numeric: numeric) {
                        predicates.append(p)
                    }
                }

                if Settings.includeTitlesInFilter { appendPredicate(format: filterTitlePredicate, numeric: false) }
                if Settings.includeReposInFilter { appendPredicate(format: filterRepoPredicate, numeric: false) }
                if Settings.includeServersInFilter { appendPredicate(format: filterServerPredicate, numeric: false) }
                if Settings.includeUsersInFilter { appendPredicate(format: filterUserPredicate, numeric: false) }
                if Settings.includeNumbersInFilter { appendPredicate(format: filterNumberPredicate, numeric: true) }
                if Settings.includeMilestonesInFilter { appendPredicate(format: filterMilestonePredicate, numeric: false) }
                if Settings.includeAssigneeNamesInFilter { appendPredicate(format: filterAssigneePredicate, numeric: false) }
                if Settings.includeLabelsInFilter { appendPredicate(format: filterLabelPredicate, numeric: false) }
                if itemType == PullRequest.self,
                   Settings.includeStatusesInFilter { appendPredicate(format: filterStatusPredicate, numeric: false) }

                if negative {
                    andPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: Array(predicates)))
                } else {
                    andPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: Array(predicates)))
                }
            }
        }

        let sortDescriptors = LinkedList<NSSortDescriptor>()
        sortDescriptors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))
        if Settings.groupByRepo {
            sortDescriptors.append(NSSortDescriptor(key: "repo.fullName", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare)))
        }

        if let fieldName = SortingMethod(Settings.sortMethod)?.field {
            if fieldName == "title" {
                sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending, selector: #selector(NSString.localizedCaseInsensitiveCompare)))
            } else {
                sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending))
            }
        }

        // DLog("%@", andPredicates)

        let f = NSFetchRequest<T>(entityName: String(describing: itemType))
        f.fetchBatchSize = 50
        f.relationshipKeyPathsForPrefetching = (itemType == PullRequest.self) ? ["labels", "statuses", "reviews"] : ["labels"]
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let p = NSCompoundPredicate(andPredicateWithSubpredicates: Array(andPredicates))
        add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
        f.sortDescriptors = Array(sortDescriptors)
        return f
    }

    private static let _unreadPredicate = NSPredicate(format: "unreadComments > 0")
    class var includeInUnreadPredicate: NSPredicate {
        _unreadPredicate
    }

    private static let isSnoozingPredicate = NSPredicate(format: "snoozeUntil != nil")

    private static let isDraftPredicate = NSPredicate(format: "draft == true")

    private static let isUnmergeablePredicate = NSPredicate(format: "isMergeable == false")

    @MainActor
    static func relatedItems(from notificationUserInfo: JSON) -> (PRComment?, ListableItem)? {
        var item: ListableItem?
        var comment: PRComment?
        if let cid = notificationUserInfo[COMMENT_ID_KEY] as? String, let itemId = DataManager.id(for: cid), let c = existingObject(with: itemId) as? PRComment {
            comment = c
            item = c.parent
        } else if let pid = notificationUserInfo[LISTABLE_URI_KEY] as? String, let itemId = DataManager.id(for: pid) {
            item = existingObject(with: itemId) as? ListableItem
        }
        if let i = item {
            return (comment, i)
        } else {
            return nil
        }
    }

    final func setMute(to newValue: Bool) {
        muted = newValue
        postProcess()
        if newValue {
            ListableItem.removeRelatedNotifications(uri: objectID.uriRepresentation().absoluteString)
        }
    }

    static func removeRelatedNotifications(uri: String) {
        #if os(OSX)
            let nc = NSUserNotificationCenter.default
            for n in nc.deliveredNotifications {
                if let u = n.userInfo, let notificationUri = u[LISTABLE_URI_KEY] as? String, notificationUri == uri {
                    nc.removeDeliveredNotification(n)
                }
            }
        #elseif os(iOS)
            let nc = UNUserNotificationCenter.current()
            nc.getDeliveredNotifications { notifications in
                Task { @MainActor in
                    for n in notifications {
                        let r = n.request.identifier
                        let u = n.request.content.userInfo
                        if let notificationUri = u[LISTABLE_URI_KEY] as? String, notificationUri == uri {
                            DLog("Removing related notification: \(r)")
                            nc.removeDeliveredNotifications(withIdentifiers: [r])
                        }
                    }
                }
            }
        #endif
    }

    var searchKeywords: [String] {
        let labelNames = labels.compactMap(\.name)
        let orgAndRepo = repo.fullName?.components(separatedBy: "/") ?? []
        #if os(iOS)
            return [userLogin ?? "NO_USERNAME", "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + orgAndRepo
        #else
            return [userLogin ?? "NO_USERNAME", "Trailer"] + labelNames + orgAndRepo
        #endif
    }

    enum SpotLightResult {
        case needsIndexing(CSSearchableItem), needsRemoval(String)
    }

    final func handleSpotlight() async -> SpotLightResult {
        let uri = objectID.uriRepresentation().absoluteString
        if isVisibleOnMenu {
            let item = await indexForSpotlight(uri: uri)
            return .needsIndexing(item)
        } else {
            hideFromNotifications(uri: uri)
            return .needsRemoval(uri)
        }
    }

    private final func indexForSpotlight(uri: String) async -> CSSearchableItem {
        let s = CSSearchableItemAttributeSet(itemContentType: "public.text")

        if let i = userAvatarUrl, !Settings.hideAvatars, let cachePath = try? await HTTP.avatar(from: i).1 {
            s.thumbnailURL = URL(fileURLWithPath: cachePath)
        }

        let titleSuffix = labels.compactMap(\.name).reduce("") { $0 + " [\($1)]" }
        s.title = "#\(number) - \(title.orEmpty)\(titleSuffix)"

        s.contentCreationDate = createdAt
        s.contentModificationDate = updatedAt
        s.keywords = searchKeywords
        s.creator = userLogin
        s.contentDescription = "\(repo.fullName.orEmpty) @\(userLogin.orEmpty) - \((body?.trim).orEmpty)"

        return CSSearchableItem(uniqueIdentifier: uri, domainIdentifier: nil, attributeSet: s)
    }

    override final class func shouldCreate(from node: TrailerQL.Node) -> Bool {
        if node.jsonPayload["state"] as? String == "OPEN" {
            return true
        }
        node.creationSkipped = true
        return false
    }

    final var shouldCheckForClosing: Bool {
        repo.shouldSync && repo.postSyncAction != PostSyncAction.delete.rawValue && apiServer.lastSyncSucceeded
    }

    @MainActor
    class func hasOpen(in _: NSManagedObjectContext, criterion _: GroupingCriterion?) -> Bool {
        false
    }

    @MainActor
    static func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {
        let color: COLOR_CLASS
        let message: String

        if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
            message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
        } else if API.isRefreshing {
            color = COLOR_CLASS.appSecondaryLabel
            message = "Refreshing information, please wait a moment…"
        } else if !filterValue.isEmpty {
            color = COLOR_CLASS.appSecondaryLabel
            message = "There are no items matching this filter."
        } else if hasOpen(in: DataManager.main, criterion: criterion) {
            color = COLOR_CLASS.appSecondaryLabel
            message = "Some items are hidden by your settings."
        } else if !Repo.anyVisibleRepos(in: DataManager.main, criterion: criterion, excludeGrouped: true) {
            if Repo.anyVisibleRepos(in: DataManager.main) {
                color = COLOR_CLASS.appSecondaryLabel
                message = "There are no repositories that are currently visible in this category."
            } else {
                color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
                message = "You have no repositories in your watchlist, or they are all currently marked as hidden.\n\nYou can change their status from the repositories section in your settings."
            }
        } else if !Repo.mayProvidePrsForDisplay(fromServerWithId: criterion?.apiServerId), !Repo.mayProvideIssuesForDisplay(fromServerWithId: criterion?.apiServerId) {
            color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
            message = "All your watched repositories are marked as hidden, please enable issues or PRs on at least one."
        } else {
            color = COLOR_CLASS.appSecondaryLabel
            message = "No open items in your configured repositories."
        }

        return styleForEmpty(message: message, color: color)
    }

    final func handleClosing() {
        DLog("Detected closed item: \(title.orEmpty), handling policy is \(Settings.closeHandlingPolicy), coming from section \(sectionIndex)")

        if !isVisibleOnMenu {
            DLog("Closed item was hidden, won't announce")
            managedObjectContext?.delete(self)

        } else if shouldKeep(accordingTo: Settings.closeHandlingPolicy) {
            DLog("Will keep closed item")
            keep(as: .closed, notification: self is Issue ? .issueClosed : .prClosed)

        } else {
            DLog("Will not keep closed item")
            managedObjectContext?.delete(self)
        }
    }

    #if os(iOS)
        var dragItemForUrl: UIDragItem {
            let url = URL(string: urlForOpening ?? repo.webUrl ?? "") ?? URL(string: "https://github.com")!
            let text = "#\(number) - \(title.orEmpty)"
            let provider = NSItemProvider(object: url as NSURL)
            provider.registerObject(text as NSString, visibility: .all)
            provider.suggestedName = text
            return UIDragItem(itemProvider: provider)
        }
    #endif

    enum MenuAction: Hashable {
        case remove, copy, markRead, markUnread, mute, unmute, snooze(presets: [SnoozePreset]), wake(date: Date?), openRepo

        var title: String {
            switch self {
            case .remove: return "Remove"
            case .copy: return "Copy URL"
            case .markRead: return "Mark as Read"
            case .markUnread: return "Mark as Unread"
            case .openRepo: return "Open Repo"
            case .mute: return "Mute"
            case .unmute: return "Un-Mute"
            case .snooze: return "Snooze"
            case let .wake(date):
                if let snooze = date, snooze != .distantFuture, snooze != autoSnoozeSentinelDate {
                    return "Wake (auto: " + itemDateFormatter.string(from: snooze) + ")"
                } else {
                    return "Wake"
                }
            }
        }
    }

    var contextMenuTitle: String {
        if self is PullRequest {
            return muted ? "PR #\(number) (muted)" : "PR #\(number)"
        } else {
            return muted ? "Issue #\(number) (muted)" : "Issue #\(number)"
        }
    }

    var contextMenuSubtitle: String? {
        (self as? PullRequest)?.headRefName
    }

    @MainActor
    var contextActions: [MenuAction] {
        var actions: [MenuAction] = [.copy, .openRepo]

        if !isSnoozing {
            let section = Section(rawValue: sectionIndex) ?? .none
            if section.shouldBadgeComments {
                if hasUnreadCommentsOrAlert {
                    actions.append(.markRead)
                } else {
                    actions.append(.markUnread)
                }
            }

            if muted {
                actions.append(.unmute)
            } else {
                actions.append(.mute)
            }
        }

        if sectionIndex == Section.merged.rawValue || sectionIndex == Section.closed.rawValue {
            actions.append(.remove)
        }

        if isSnoozing {
            actions.append(.wake(date: snoozeUntil))
        } else {
            let presets = SnoozePreset.allSnoozePresets(in: DataManager.main)
            if !presets.isEmpty {
                actions.append(.snooze(presets: presets))
            }
        }

        return actions
    }
}
