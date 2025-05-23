import CoreData
@preconcurrency import CoreSpotlight
import Lista
import TrailerJson
import TrailerQL

#if canImport(UIKit)
    import UIKit
#elseif canImport(Cocoa)
    import Cocoa
#endif

protocol Listable: Querying {
    var section: Section { get }
    var sectionIndex: Int { get }
    var comments: Set<PRComment> { get }
    var reactions: Set<Reaction> { get }
}

extension Listable {
    static func reactionCheckBatch(in moc: NSManagedObjectContext, settings: Settings.Cache) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.predicate = ApiServer.lastSyncSucceededPredicate
        f.sortDescriptors = [
            NSSortDescriptor(key: "lastReactionScan", ascending: true),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        let items = try! moc.fetch(f)
            .filter { $0.section.shouldListReactions(settings: settings) }
            .prefix(Settings.reactionScanningBatchSize)

        for item in items {
            for comment in item.comments {
                comment.pendingReactionScan = comment.createdByMe
            }
            for reaction in item.reactions {
                reaction.postSyncAction = PostSyncAction.delete.rawValue
            }
        }
        return Array(items)
    }

    var section: Section {
        Section(sectionIndex: sectionIndex)
    }
}

class ListableItem: DataItem, Listable {
    enum StateChange: Int {
        case none, reopened, merged, closed
    }

    @NSManaged var assignedStatus: Int
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

    @NSManaged var labels: Set<PRLabel>
    @NSManaged var comments: Set<PRComment>
    @NSManaged var reactions: Set<Reaction>

    var webUrl: String? {
        repo.webUrl
    }

    final var commentsLink: String? {
        issueUrl?.appending(pathComponent: "comments")
    }

    final var issueUrl: String? {
        repo.apiUrl?.appending(pathComponent: "issues").appending(pathComponent: String(number))
    }

    final var reactionsUrl: String? {
        issueUrl?.appending(pathComponent: "reactions")
    }

    func handleMerging(settings _: Settings.Cache) {}

    final func baseNodeSync(node: Node, parent: Repo) {
        repo = parent

        let info = node.jsonPayload
        url = info.potentialString(named: "url")
        number = info.potentialInt(named: "number") ?? 0
        title = info.potentialString(named: "title") ?? "(No title)"
        body = info.potentialString(named: "bodyText")
        milestone = info.potentialObject(named: "milestone")?.potentialString(named: "title")
        draft = info.potentialBool(named: "isDraft") ?? false

        let newCondition: Int = switch info.potentialString(named: "state") {
        case "MERGED": ItemCondition.merged.rawValue
        case "CLOSED": ItemCondition.closed.rawValue
        default: ItemCondition.open.rawValue
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

        if let user = info.potentialObject(named: "author") {
            userLogin = user.potentialString(named: "login")
            userAvatarUrl = user.potentialString(named: "avatarUrl")
            userNodeId = user.potentialString(named: "id")
        }

        let i: [TypedJson.Entry] = if let assignees = info.potentialObject(named: "assignees")?.potentialArray(named: "edges") {
            assignees.compactMap { $0.potentialObject(named: "node") }
        } else {
            []
        }

        processAssignmentStatus(from: .object(["assignees": .array(i)]), idField: "id")

        if node.updated {
            labels.removeAll() // so not set delete post sync action, as label may not just be a child to this item. Orphaned labels are nuked afterwards
        }
    }

    final func baseSync(from info: TypedJson.Entry, in parentRepo: Repo) {
        repo = parentRepo
        url = info.potentialString(named: "url")
        number = info.potentialInt(named: "number") ?? 0
        title = info.potentialString(named: "title") ?? "(No title)"
        body = info.potentialString(named: "body")
        milestone = info.potentialObject(named: "milestone")?.potentialString(named: "title")
        draft = info.potentialBool(named: "draft") ?? false

        if let userInfo = info.potentialObject(named: "user") {
            userLogin = userInfo.potentialString(named: "login")
            userAvatarUrl = userInfo.potentialString(named: "avatar_url")
            userNodeId = userInfo.potentialString(named: "node_id")
        }

        processAssignmentStatus(from: info, idField: "node_id")
    }

    final func processAssignmentStatus(from info: TypedJson.Entry?, idField: String) {
        let assigneeJson: [TypedJson.Entry]? = if let assignees = info?.potentialArray(named: "assignees") {
            assignees
        } else if let assignee = info?.potentialObject(named: "assignee") {
            [assignee]
        } else {
            nil
        }

        var directAssignmentToMe = false
        var teamAssignmentToMe = false
        var directAssigneeNames = [String]()
        var teamAssigneeNames = [String]()

        if let assigneeJson, !assigneeJson.isEmpty {
            let myIdOnThisRepo = repo.apiServer.userNodeId
            let myTeamNames = Set(apiServer.teams.compactMap(\.slug))

            for assignee in assigneeJson {
                if let name = assignee.potentialString(named: "login"), let assigneeId = assignee.potentialString(named: idField) {
                    if !directAssignmentToMe, assigneeId == myIdOnThisRepo {
                        directAssignmentToMe = true
                    }
                    directAssigneeNames.append(name)
                } else if let name = assignee.potentialString(named: "slug") {
                    if !teamAssignmentToMe, myTeamNames.contains(name) {
                        teamAssignmentToMe = true
                    }
                    teamAssigneeNames.append(name)
                }
            }
        }

        let allSigneeNames = teamAssigneeNames + directAssigneeNames
        assigneeName = allSigneeNames.isEmpty ? nil : allSigneeNames.joined(separator: ",")

        if createdByMe {
            isNewAssignment = false
        } else {
            let previousStatus = assignedStatus

            let wasAssignedToMe = previousStatus == AssignmentStatus.me.rawValue
            let wasAssignedToMyTeam = previousStatus == AssignmentStatus.myTeam.rawValue
            let wasAssigned = wasAssignedToMe || wasAssignedToMyTeam

            let isNewDirectAssignment = directAssignmentToMe && !wasAssignedToMe
            let isNewTeamAssignment = teamAssignmentToMe && !wasAssignedToMyTeam
            let isAssigned = isNewDirectAssignment || isNewTeamAssignment

            isNewAssignment = isAssigned && !wasAssigned
        }

        if directAssignmentToMe {
            assignedStatus = AssignmentStatus.me.rawValue
        } else if teamAssignmentToMe {
            assignedStatus = AssignmentStatus.myTeam.rawValue
        } else {
            assignedStatus = AssignmentStatus.none.rawValue
        }
    }

    final func setToUpdatedIfIdle() {
        if postSyncAction == PostSyncAction.doNothing.rawValue {
            postSyncAction = PostSyncAction.isUpdated.rawValue
        }
    }

    override final func resetSyncState() {
        super.resetSyncState()
        repo.resetSyncState()
    }

    override final func prepareForDeletion() {
        let uri = objectID.uriRepresentation().absoluteString
        Task { @MainActor in
            ListableItem.hideFromNotifications(uri: uri, settings: Settings.cache)
        }
        super.prepareForDeletion()
    }

    @MainActor
    private static func hideFromNotifications(uri: String, settings: Settings.Cache) {
        if settings.removeNotificationsWhenItemIsRemoved {
            NotificationManager.shared.removeRelatedNotifications(for: uri)
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
        if let p = asPr {
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

    func catchUpWithComments(settings: Settings.Cache) {
        catchUpCommentDate()
        postProcess(settings: settings)
    }

    final func shouldKeep(accordingTo policy: KeepPolicy, settings: Settings.Cache) -> Bool {
        switch policy {
        case .everything:
            return true

        case .mineAndParticipated:
            let preConditionSection = highestPreferredSection(takingItemConditionIntoAccount: false, settings: settings)
            return preConditionSection == .mine || preConditionSection == .participated

        case .mine:
            let preConditionSection = highestPreferredSection(takingItemConditionIntoAccount: false, settings: settings)
            return preConditionSection == .mine

        case .nothing:
            return false
        }
    }

    final var shouldSkipNotifications: Bool {
        isSnoozing || muted
    }

    final func shouldGo(to section: Section, settings: Settings.Cache) -> Bool {
        switch AssignmentStatus(rawValue: assignedStatus) {
        case nil, .none?, .others:
            return false

        case .me:
            let policy = settings.assignedItemDirectHandlingPolicy
            return policy.visible && section == policy

        case .myTeam:
            let policy = settings.assignedItemTeamHandlingPolicy
            return policy.visible && section == policy
        }
    }

    final var createdByMe: Bool {
        userNodeId == apiServer.userNodeId
    }

    private final func contains(terms: [String]) -> Bool {
        if let body, terms.contains(where: { !$0.isEmpty && body.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return comments.contains(where: { $0.contains(terms: terms) })
    }

    private final var commentedByMe: Bool {
        comments.contains { $0.createdByMe }
    }

    var reviewedByMe: Bool {
        false
    }

    final var isVisibleOnMenu: Bool {
        sectionIndex != Section.hidden(cause: .unknown).sectionIndex
    }

    @discardableResult
    final func wakeUp(settings: Settings.Cache) -> Section {
        disableSnoozing(explicityAwoke: true)
        return postProcess(settings: settings)
    }

    final var isSnoozing: Bool {
        snoozeUntil != nil
    }

    final func keep(as newCondition: ItemCondition, notification: NotificationType, settings: Settings.Cache) {
        if sectionIndex == Section.all.sectionIndex, !Section.all.shouldBadgeComments(settings: settings) {
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
        postProcess(settings: settings) // make sure it's in the right section and updated correctly for its new status
    }

    private final func shouldMoveToSnoozing(settings: Settings.Cache) -> Bool {
        if snoozeUntil == nil {
            let d = settings.autoSnoozeDuration
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
    final func snooze(using preset: SnoozePreset, settings: Settings.Cache) {
        snoozeUntil = preset.wakeupDateFromNow
        snoozingPreset = preset
        wasAwokenFromSnooze = false
        muted = false
        postProcess(settings: settings)
    }

    var hasUnreadCommentsOrAlert: Bool {
        unreadComments > 0
    }

    private final func disableSnoozing(explicityAwoke: Bool) {
        snoozeUntil = nil
        snoozingPreset = nil
        wasAwokenFromSnooze = explicityAwoke
    }

    var preferredSectionBasedOnReviewAssignment: Section? {
        nil
    }

    private func highestPreferredSection(takingItemConditionIntoAccount: Bool, settings: Settings.Cache) -> Section {
        if takingItemConditionIntoAccount {
            if condition == ItemCondition.merged.rawValue {
                return .merged
            }
            if condition == ItemCondition.closed.rawValue {
                return .closed
            }
        }

        if shouldMoveToSnoozing(settings: settings) {
            return .snoozed
        }

        if createdByMe || shouldGo(to: .mine, settings: settings) {
            return .mine
        }

        var targetSection = Section.all

        if targetSection.sectionIndex > Section.participated.sectionIndex,
           shouldGo(to: .participated, settings: settings) || commentedByMe || reviewedByMe {
            targetSection = .participated
        }

        if targetSection.sectionIndex > Section.mentioned.sectionIndex,
           shouldGo(to: .mentioned, settings: settings) {
            targetSection = .mentioned
        }

        if let potentialSection = settings.preferredMovePolicySection,
           potentialSection.sectionIndex < targetSection.sectionIndex,
           contains(terms: ["@\(apiServer.userName.orEmpty)"]) {
            targetSection = potentialSection
        }

        if let potentialSection = settings.preferredTeamMentionPolicy,
           potentialSection.sectionIndex < targetSection.sectionIndex,
           contains(terms: apiServer.teams.compactMap(\.calculatedReferral)) {
            targetSection = potentialSection
        }

        if let potentialSection = settings.newItemInOwnedRepoMovePolicy,
           potentialSection.sectionIndex < targetSection.sectionIndex,
           repo.isMine {
            targetSection = potentialSection
        }

        if let potentialSection = preferredSectionBasedOnReviewAssignment,
           potentialSection.sectionIndex < targetSection.sectionIndex {
            targetSection = potentialSection
        }

        return targetSection
    }

    func canBadge(in targetSection: Section? = nil, settings: Settings.Cache) -> Bool {
        let targetSection = targetSection ?? Section(sectionIndex: sectionIndex)

        if !targetSection.shouldBadgeComments(settings: settings) || muted || postSyncAction == PostSyncAction.isNew.rawValue {
            return false
        }

        if targetSection == .closed || targetSection == .merged {
            return highestPreferredSection(takingItemConditionIntoAccount: false, settings: settings).shouldBadgeComments(settings: settings)
        }

        return true
    }

    var shouldHideBecauseOfRepoHidingPolicy: Section.HidingCause? {
        nil
    }

    var shouldWakeBecauseOfCommit: Bool {
        false
    }

    var repoDisplayPolicy: Int {
        repo.displayPolicyForIssues
    }

    private func shouldHideBecauseOfRepoDisplayPolicy(targetSection: Section) -> Section.HidingCause? {
        switch repoDisplayPolicy {
        case RepoDisplayPolicy.hide.rawValue:
            return .repoHideAllItems
        case RepoDisplayPolicy.mine.rawValue:
            if targetSection == .all || targetSection == .participated || targetSection == .mentioned {
                return .repoShowMineOnly
            }
        case RepoDisplayPolicy.mineAndPaticipated.rawValue:
            if targetSection == .all {
                return .repoShowMineAndParticipated
            }
        default:
            break
        }

        return nil
    }

    private func shouldHideBecauseOfInclusionRules(settings: Settings.Cache) -> Section.HidingCause? {
        let labelFilterList = settings.labelFilterList
        if !labelFilterList.isEmpty {
            let mine = Set(labels.compactMap { $0.name?.comparableForm })

            switch settings.labelsIncludionRule {
            case .excludeIfAny:
                if !labelFilterList.isDisjoint(with: mine) {
                    return .containsLabel
                }
            case .includeIfAny:
                if labelFilterList.isDisjoint(with: mine) {
                    return .doesntContainLabel
                }
            case .excludeIfAll:
                if labelFilterList.isSubset(of: mine) {
                    return .containsAllLabels
                }
            case .includeIfAll:
                if !labelFilterList.isSubset(of: mine) {
                    return .doesntContainAllLabels
                }
            }
        }

        let authorFilterList = settings.authorFilterList
        if !authorFilterList.isEmpty,
           let login = userLogin?.comparableForm {
            switch settings.authorsIncludionRule {
            case .excludeIfAll, .excludeIfAny:
                if authorFilterList.contains(login) {
                    return .containsAuthor
                }
            case .includeIfAll, .includeIfAny:
                if !authorFilterList.contains(login) {
                    return .doesntContainAuthor
                }
            }
        }

        return nil
    }

    func shouldHideBecauseOfRedStatuses(in _: Section, settings _: Settings.Cache) -> Section.HidingCause? {
        nil
    }

    private func shouldHideBecauseOfDraftStatus(settings: Settings.Cache) -> Section.HidingCause? {
        if settings.shouldHideDrafts, draft {
            return .hidingDrafts
        }
        return nil
    }

    func updateClosingInformation() {}

    @discardableResult
    final func postProcess(settings: Settings.Cache) -> Section {
        if let snoozeUntil, snoozeUntil < Date() { // our snooze-by date is past
            disableSnoozing(explicityAwoke: true)
        }

        if shouldWakeBecauseOfCommit { // we wake on comments and have a new commit alarm
            return wakeUp(settings: settings) // re-process as awake item
        }

        var targetSection: Section

        if let cause = shouldHideBecauseOfDraftStatus(settings: settings)
            ?? shouldHideBecauseOfRepoHidingPolicy
            ?? shouldHideDueToMyReview(settings: settings)
            ?? shouldHideBecauseOfInclusionRules(settings: settings) {
            targetSection = .hidden(cause: cause)
        } else {
            targetSection = highestPreferredSection(takingItemConditionIntoAccount: true, settings: settings)

            if targetSection.visible, let cause
                = shouldHideBecauseOfRepoDisplayPolicy(targetSection: targetSection)
                ?? shouldHideBecauseOfRedStatuses(in: targetSection, settings: settings) {
                targetSection = .hidden(cause: cause)
            }
        }

        if canBadge(in: targetSection, settings: settings) {
            var latestDate = latestReadCommentDate ?? .distantPast

            if settings.assumeReadItemIfUserHasNewerComments {
                for c in myComments(since: latestDate) {
                    if let createdDate = c.createdAt, latestDate < createdDate {
                        latestDate = createdDate
                    }
                }
                latestReadCommentDate = latestDate
            }
            unreadComments = countOthersComments(since: latestDate, settings: settings)

        } else {
            catchUpCommentDate()
            unreadComments = 0
        }

        if targetSection.visible {
            if settings.hideUncommentedItems, unreadComments == 0 {
                targetSection = .hidden(cause: .wasUncommented)
            } else {
                totalComments = countComments(settings: settings)
                    + (settings.notifyOnItemReactions ? countReactions(settings: settings) : 0)
                    + (settings.notifyOnCommentReactions ? countCommentReactions(settings: settings) : 0)
                    + countReviews(settings: settings)

                updateClosingInformation()
            }
        }

        sectionIndex = targetSection.sectionIndex

        return targetSection
    }

    func countReviews(settings _: Settings.Cache) -> Int {
        0
    }

    private func countComments(settings: Settings.Cache) -> Int {
        var count = 0
        for c in comments where settings.commenterInclusionRule.shouldContributeToCount(isMine: c.createdByMe, userName: c.userName, createdAt: c.createdAt, since: .distantPast, settings: settings) {
            count += 1
        }
        return count
    }

    private func countReactions(settings: Settings.Cache) -> Int {
        var count = 0
        for r in reactions where settings.commenterInclusionRule.shouldContributeToCount(isMine: r.isMine, userName: r.userName, createdAt: r.createdAt, since: .distantPast, settings: settings) {
            count += 1
        }
        return count
    }

    private func countCommentReactions(settings: Settings.Cache) -> Int {
        var count = 0
        for c in comments where settings.commenterInclusionRule.shouldContributeToCount(isMine: c.createdByMe, userName: c.userName, createdAt: c.createdAt, since: .distantPast, settings: settings) {
            for r in c.reactions where settings.commenterInclusionRule.shouldContributeToCount(isMine: r.isMine, userName: r.userName, createdAt: r.createdAt, since: .distantPast, settings: settings) {
                count += 1
            }
        }
        return count
    }

    private final func myComments(since: Date) -> [PRComment] {
        comments.filter { $0.createdByMe && ($0.createdAt ?? .distantPast) > since }
    }

    private final func othersComments(since: Date) -> [PRComment] {
        comments.filter { !$0.createdByMe && ($0.createdAt ?? .distantPast) > since }
    }

    private final func countOthersComments(since startDate: Date, settings: Settings.Cache) -> Int {
        var count = 0
        for c in comments {
            if settings.commenterInclusionRule.shouldContributeToCount(isMine: c.createdByMe, userName: c.userName, createdAt: c.createdAt, since: startDate, settings: settings) {
                count += 1
            }
            if settings.notifyOnCommentReactions {
                for r in c.reactions where settings.commenterInclusionRule.shouldContributeToCount(isMine: r.isMine, userName: r.userName, createdAt: r.createdAt, since: startDate, settings: settings) {
                    count += 1
                }
            }
        }
        if settings.notifyOnItemReactions {
            for r in reactions where settings.commenterInclusionRule.shouldContributeToCount(isMine: r.isMine, userName: r.userName, createdAt: r.createdAt, since: startDate, settings: settings) {
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
            if let url = oldestComment?.webUrl {
                return url
            }
        }

        return webUrl
    }

    final func accessibleTitle(settings: Settings.Cache) -> String {
        let components = Lista<String>()
        if let title {
            components.append(title)
        }
        if draft, settings.draftHandlingPolicy == .display {
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

    final func labelsAttributedString(labelFont: FONT_CLASS, settings: Settings.Cache) -> NSAttributedString? {
        if !settings.showLabels {
            return nil
        }

        let sorted = sortedLabels
        if sorted.isEmpty {
            return nil
        }

        let res = NSMutableAttributedString()
        let labelAttributes: [NSAttributedString.Key: Any]
        #if os(macOS)
            labelAttributes = [.font: labelFont, .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = 1.55
                return p
            }()]
        #else
            labelAttributes = [.font: labelFont]
        #endif
        for l in sorted {
            let color = l.colorForDisplay
            var a = labelAttributes
            #if os(macOS)
                a[.trailerTagBackgroundColour] = color
            #else
                a[.backgroundColor] = color
            #endif
            a[.foregroundColor] = color.isDark ? COLOR_CLASS.white : COLOR_CLASS.black
            let name = l.name!.replacingOccurrences(of: " ", with: "\u{a0}")

            #if os(macOS)
                res.append(NSAttributedString(string: name, attributes: a))
                res.append(NSAttributedString(string: "     ", attributes: labelAttributes))
            #else
                res.append(NSAttributedString(string: "\u{a0}\(name)\u{a0}", attributes: a))
                res.append(NSAttributedString(string: " ", attributes: labelAttributes))
            #endif
        }
        return res
    }

    final func title(with font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS, numberColor: COLOR_CLASS, settings: Settings.Cache) -> NSMutableAttributedString {
        let _title = NSMutableAttributedString()
        guard let title else {
            return _title
        }

        if settings.displayNumbersForItems {
            let numberAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
            _title.append(NSAttributedString(string: "#\(number) ", attributes: numberAttributes))
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: titleColor]
        _title.append(NSAttributedString(string: title, attributes: titleAttributes))

        if let p = asPr {
            if settings.showPrLines, let l = p.linesAttributedString(labelFont: labelFont) {
                _title.append(NSAttributedString(string: " ", attributes: titleAttributes))
                _title.append(l)
            }
            if settings.markUnmergeablePrs, !p.isMergeable {
                _title.append(NSAttributedString(string: " ", attributes: titleAttributes))

                let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)
                let unmergeableAttributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.appRed]
                _title.append(NSAttributedString(string: "CONFLICT", attributes: unmergeableAttributes))
            }
        }

        if draft, settings.draftHandlingPolicy == .display {
            _title.append(NSAttributedString(string: " ", attributes: titleAttributes))

            let font = FONT_CLASS.boldSystemFont(ofSize: labelFont.pointSize - 3)
            let draftAttributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 4, .foregroundColor: COLOR_CLASS.systemOrange]
            _title.append(NSAttributedString(string: "DRAFT", attributes: draftAttributes))
        }
        return _title
    }

    var baseLabelText: String? { nil }

    var headLabelText: String? { nil }

    func subtitle(with font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS, separator: String, settings: Settings.Cache) -> NSMutableAttributedString {
        let components = Lista<String>()
        if settings.showBaseAndHeadBranches, let baseLabelText, let headLabelText {
            let splitB = baseLabelText.components(separatedBy: ":")
            let splitH = headLabelText.components(separatedBy: ":")

            let repoH: String? = if splitB.count == 2 && splitH.count == 2, splitB.first == splitH.first { // same repo
                nil
            } else {
                splitH.first
            }

            if let baseName = splitB.first ?? repo.fullName {
                components.append(baseName)
            }

            if let branchB = splitB.last {
                components.append(":")
                components.append(branchB)
            }

            let branchH = splitH.last

            if repoH != nil || branchH != nil {
                components.append(" ← ")
            }

            if let repoH {
                components.append(repoH)
                if branchH != nil {
                    components.append(":")
                }
            }

            if let branchH {
                components.append(branchH)
            }

        } else if settings.showReposInName, let repoFullName = repo.fullName {
            components.append(repoFullName)
        }

        let _subtitle = NSMutableAttributedString(string: components.joined(), attributes: [.foregroundColor: darkColor, .font: font])

        components.removeAll()
        components.append(separator)

        if settings.showMilestones, let m = milestone, !m.isEmpty {
            components.append(m)
            components.append(separator)
        }

        if let userLogin {
            components.append("@")
            components.append(userLogin)
            components.append(separator)
        }

        _subtitle.append(NSAttributedString(string: components.joined(), attributes: [.foregroundColor: lightColor, .font: font]))

        return _subtitle
    }

    func accessibleSubtitle(settings: Settings.Cache) -> String {
        var components = [String]()

        if settings.showReposInName {
            components.append("Repository: \(repo.fullName.orEmpty)")
        }

        if let userLogin {
            components.append("Author: \(userLogin)")
        }

        components.append(displayDate(settings: settings))

        return components.joined(separator: ",")
    }

    final func displayDate(settings: Settings.Cache) -> String {
        if settings.showRelativeDates {
            if settings.showCreatedInsteadOfUpdated {
                agoFormat(prefix: "created", since: createdAt)
            } else {
                agoFormat(prefix: "updated", since: updatedAt)
            }
        } else {
            if settings.showCreatedInsteadOfUpdated {
                "Created " + Date.Formatters.itemDateFormat.format(createdAt!)
            } else {
                "Updated " + Date.Formatters.itemDateFormat.format(updatedAt!)
            }
        }
    }

    static func styleForEmpty(message: String, color: COLOR_CLASS) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.alignment = .center
        #if os(macOS)
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
            let P = if numeric, let n = UInt(T) {
                NSPredicate(format: format, n)
            } else {
                NSPredicate(format: format, T)
            }
            if negative {
                notTerms.append(NSCompoundPredicate(notPredicateWithSubpredicate: P))
            } else {
                orTerms.append(P)
            }
        }
        return predicate(notTerms: notTerms, orTerms: orTerms)
    }

    private static func statePredicate(from token: String, termAt: Int, settings: Settings.Cache) -> NSPredicate? {
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
                P = includeInUnreadPredicate(settings: settings)
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
            NSCompoundPredicate(andPredicateWithSubpredicates:
                [NSCompoundPredicate(andPredicateWithSubpredicates: notTerms),
                 NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)])
        } else if !notTerms.isEmpty {
            NSCompoundPredicate(andPredicateWithSubpredicates: notTerms)
        } else if !orTerms.isEmpty {
            NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)
        } else {
            nil
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
    static func requestForItems<T: ListableItem>(of itemType: T.Type, withFilter: String?, sectionIndex: Int, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false, excludeSnoozed: Bool = false, settings: Settings.Cache) -> NSFetchRequest<T> {
        let andPredicates = Lista<NSPredicate>()

        if onlyUnread {
            andPredicates.append(itemType.includeInUnreadPredicate(settings: settings))
        }

        if sectionIndex < 0 {
            andPredicates.append(Section.nonZeroPredicate)

        } else {
            let s = Section(sectionIndex: sectionIndex)
            andPredicates.append(s.matchingPredicate)
        }

        if excludeSnoozed || settings.hideSnoozedItems {
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
            check(forTag: "state") { statePredicate(from: $0, termAt: $1, settings: settings) }

            if !fi.isEmpty {
                let predicates = Lista<NSPredicate>()
                let negative = fi.hasPrefix("!")

                func appendPredicate(format: String, numeric: Bool) {
                    if let p = predicate(from: fi, termAt: 0, format: format, numeric: numeric) {
                        predicates.append(p)
                    }
                }

                if settings.includeTitlesInFilter { appendPredicate(format: filterTitlePredicate, numeric: false) }
                if settings.includeReposInFilter { appendPredicate(format: filterRepoPredicate, numeric: false) }
                if settings.includeServersInFilter { appendPredicate(format: filterServerPredicate, numeric: false) }
                if settings.includeUsersInFilter { appendPredicate(format: filterUserPredicate, numeric: false) }
                if settings.includeNumbersInFilter { appendPredicate(format: filterNumberPredicate, numeric: true) }
                if settings.includeMilestonesInFilter { appendPredicate(format: filterMilestonePredicate, numeric: false) }
                if settings.includeAssigneeNamesInFilter { appendPredicate(format: filterAssigneePredicate, numeric: false) }
                if settings.includeLabelsInFilter { appendPredicate(format: filterLabelPredicate, numeric: false) }
                if itemType == PullRequest.self,
                   settings.includeStatusesInFilter { appendPredicate(format: filterStatusPredicate, numeric: false) }

                if negative {
                    andPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: Array(predicates)))
                } else {
                    andPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: Array(predicates)))
                }
            }
        }

        let sortDescriptors = Lista<NSSortDescriptor>()
        sortDescriptors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))
        if settings.groupByRepo {
            sortDescriptors.append(NSSortDescriptor(key: "repo.fullName", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare)))
        }

        let fieldName = settings.sortField
        if fieldName == "title" {
            sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !settings.sortDescending, selector: #selector(NSString.localizedCaseInsensitiveCompare)))
        } else {
            sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !settings.sortDescending))
        }

        // Logging.shared.log("%@", andPredicates)

        let f = NSFetchRequest<T>(entityName: itemType.typeName)
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
    class func includeInUnreadPredicate(settings _: Settings.Cache) -> NSPredicate { _unreadPredicate }

    private static let isSnoozingPredicate = NSPredicate(format: "snoozeUntil != nil")

    private static let isDraftPredicate = NSPredicate(format: "draft == true")

    private static let isUnmergeablePredicate = NSPredicate(format: "isMergeable == false")

    final func setMute(to newValue: Bool, settings: Settings.Cache) {
        muted = newValue
        postProcess(settings: settings)
        if newValue {
            Task {
                await NotificationManager.shared.removeRelatedNotifications(for: objectID.uriRepresentation().absoluteString)
            }
        }
    }

    func shouldHideDueToMyReview(settings _: Settings.Cache) -> Section.HidingCause? {
        nil
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

    enum SpotLightResult: Sendable {
        case needsIndexing(CSSearchableItem), needsRemoval(String)
    }

    final func handleSpotlight(settings: Settings.Cache) async -> SpotLightResult {
        let uri = objectID.uriRepresentation().absoluteString
        if isVisibleOnMenu {
            let item = await indexForSpotlight(uri: uri, settings: settings)
            return .needsIndexing(item)
        } else {
            Task { @MainActor in
                ListableItem.hideFromNotifications(uri: uri, settings: settings)
            }
            return .needsRemoval(uri)
        }
    }

    private final func indexForSpotlight(uri: String, settings: Settings.Cache) async -> CSSearchableItem {
        let s = CSSearchableItemAttributeSet(itemContentType: "public.text")

        if let userAvatarUrl, !settings.hideAvatars {
            s.thumbnailURL = try? await ImageCache.shared.store(HTTP.avatar(from: userAvatarUrl), from: userAvatarUrl)
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

    override static func shouldCreate(from node: Node) -> Bool {
        if node.jsonPayload.potentialString(named: "state") == "OPEN" {
            return true
        }
        node.creationSkipped = true
        return false
    }

    final var shouldCheckForClosing: Bool {
        condition == ItemCondition.open.rawValue && repo.shouldSync && repo.postSyncAction != PostSyncAction.delete.rawValue && apiServer.lastSyncSucceeded
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

    final func handleClosing(settings: Settings.Cache) {
        let title = title.orEmpty
        let sectionIndex = sectionIndex
        Task {
            await Logging.shared.log("Detected closed item: \(title), handling policy is \(Settings.closeHandlingPolicy), coming from section \(sectionIndex)")
        }

        if !isVisibleOnMenu {
            Task {
                await Logging.shared.log("Closed item was hidden, won't announce")
            }
            managedObjectContext?.delete(self)

        } else if shouldKeep(accordingTo: Settings.closeHandlingPolicy, settings: settings) {
            Task {
                await Logging.shared.log("Will keep closed item")
            }
            keep(as: .closed, notification: isPr ? .prClosed : .issueClosed, settings: settings)

        } else {
            Task {
                await Logging.shared.log("Will not keep closed item")
            }
            managedObjectContext?.delete(self)
        }
    }

    #if os(iOS)
        var dragItemForUrl: UIDragItem {
            let url = URL(string: urlForOpening ?? repo.webUrl.orEmpty) ?? URL(string: "https://github.com")!
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
            case .remove: "Remove"
            case .copy: "Copy URL"
            case .markRead: "Mark as Read"
            case .markUnread: "Mark as Unread"
            case .openRepo: "Open Repo"
            case .mute: "Mute"
            case .unmute: "Un-Mute"
            case .snooze: "Snooze"
            case let .wake(date):
                if let date, date != .distantFuture, date != autoSnoozeSentinelDate {
                    "Wake (auto: " + Date.Formatters.itemDateFormat.format(date) + ")"
                } else {
                    "Wake"
                }
            }
        }
    }

    var contextMenuTitle: String {
        muted ? "Issue #\(number) (muted)" : "Issue #\(number)"
    }

    var contextMenuSubtitle: String? {
        nil
    }

    @MainActor
    func contextActions(settings: Settings.Cache) -> [MenuAction] {
        var actions: [MenuAction] = [.copy, .openRepo]

        if !isSnoozing {
            let section = Section(sectionIndex: sectionIndex)
            if section.shouldBadgeComments(settings: settings) {
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

        if sectionIndex == Section.merged.sectionIndex || sectionIndex == Section.closed.sectionIndex {
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
