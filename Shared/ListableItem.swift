
import CoreData
import CoreSpotlight
#if os(iOS)
	import UIKit
	import MobileCoreServices
	import UserNotifications
#endif

class ListableItem: DataItem {
    
    enum StateChange: Int64 {
        case none, reopened, merged, closed
    }

	@NSManaged var assignedToMe: Bool
	@NSManaged var assigneeName: String? // note: This now could be a list of names, delimited with a ","
	@NSManaged var body: String?
	@NSManaged var condition: Int64
	@NSManaged var isNewAssignment: Bool
	@NSManaged var repo: Repo
	@NSManaged var title: String?
	@NSManaged var totalComments: Int64
	@NSManaged var unreadComments: Int64
	@NSManaged var url: String?
	@NSManaged var userAvatarUrl: String?
    @NSManaged var userNodeId: String?
	@NSManaged var userLogin: String?
	@NSManaged var sectionIndex: Int64
	@NSManaged var latestReadCommentDate: Date?
	@NSManaged var stateChanged: Int64
	@NSManaged var number: Int64
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
        return repo.webUrl
    }

    var commentsLink: String? {
        return issueUrl?.appending(pathComponent: "comments")
    }

    var issueUrl: String? {
        return repo.apiUrl?.appending(pathComponent: "issues").appending(pathComponent: String(number))
    }
    
    var reactionsUrl: String? {
        return issueUrl?.appending(pathComponent: "reactions")
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
            .filter { $0.interestedInReactions }
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

    final func baseNodeSync(nodeJson info: [AnyHashable: Any], parent: Repo) {
        repo = parent
        url = info["url"] as? String
        number = info["number"] as? Int64 ?? 0
        title = info["title"] as? String ?? "(No title)"
        body = info["bodyText"] as? String
        milestone = (info["milestone"] as? [AnyHashable : Any])?["title"] as? String
        draft = info["isDraft"] as? Bool ?? false
        
        let newCondition: Int64
        switch (info["state"] as? String) ?? "" {
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

        if let user = info["author"] as? [AnyHashable:Any] {
            userLogin = user["login"] as? String
            userAvatarUrl = user["avatarUrl"] as? String
            userNodeId = user["id"] as? String
        }

        let i: [[AnyHashable: Any]]
        if let assignees = (info["assignees"] as? [AnyHashable: Any])?["edges"] as? [[AnyHashable: Any]] {
            i = assignees.compactMap { $0["node"] as? [AnyHashable: Any] }
        } else {
            i = []
        }
        
        processAssignmentStatus(from: ["assignees": i], idField: "id")
        
        mutableSetValue(forKey: "labels").removeAllObjects()
    }

	final func baseSync(from info: [AnyHashable : Any], in parentRepo: Repo) {
		repo = parentRepo
		url = info["url"] as? String
		number = info["number"] as? Int64 ?? 0
		title = info["title"] as? String ?? "(No title)"
		body = info["body"] as? String
		milestone = (info["milestone"] as? [AnyHashable : Any])?["title"] as? String
        draft = info["draft"] as? Bool ?? false

		if let userInfo = info["user"] as? [AnyHashable : Any] {
			userLogin = userInfo["login"] as? String
			userAvatarUrl = userInfo["avatar_url"] as? String
            userNodeId = userInfo["node_id"] as? String
		}

		processAssignmentStatus(from: info, idField: "node_id")
	}

    var interestedInReactions: Bool {
        return API.shouldSyncReactions && (Settings.showCommentsEverywhere || (Section(rawValue: sectionIndex)?.isLoud ?? false))
    }

    final func processAssignmentStatus(from info: [AnyHashable : Any]?, idField: String) {

		let myIdOnThisRepo = repo.apiServer.userNodeId
		var assigneeNames = [String]()

		func checkAndStoreAssigneeName(from assignee: [AnyHashable : Any]) -> Bool {

			if let name = assignee["login"] as? String, let assigneeId = assignee[idField] as? String {
				let shouldBeAssignedToMe = assigneeId == myIdOnThisRepo
				assigneeNames.append(name)
				return shouldBeAssignedToMe
			} else {
				return false
			}
		}

		var foundAssignmentToMe = false

		if let assignees = info?["assignees"] as? [[AnyHashable : Any]], !assignees.isEmpty {
			for assignee in assignees {
				if checkAndStoreAssigneeName(from: assignee) {
					foundAssignmentToMe = true
				}
			}
		} else if let assignee = info?["assignee"] as? [AnyHashable : Any] {
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

	static func active<T>(of type: T.Type, in moc: NSManagedObjectContext, visibleOnly: Bool) -> [T] where T : ListableItem {
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

	final override func resetSyncState() {
		super.resetSyncState()
		repo.resetSyncState()
	}

	final override func prepareForDeletion() {
        let uri = objectID.uriRepresentation().absoluteString
        hideFromSpotlightAndNotifications(uri: uri)
		super.prepareForDeletion()
	}

    private final func hideFromSpotlightAndNotifications(uri: String) {
        if CSSearchableIndex.isIndexingAvailable() {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uri], completionHandler: nil)
        }
		if Settings.removeNotificationsWhenItemIsRemoved {
			ListableItem.removeRelatedNotifications(uri: uri)
		}
	}

	final func sortedComments(using comparison: ComparisonResult) -> [PRComment] {
		return comments.sorted { c1, c2 -> Bool in
			let d1 = c1.createdAt ?? .distantPast
			let d2 = c2.createdAt ?? .distantPast
			return d1.compare(d2) == comparison
		}
	}

	final private func catchUpCommentDate() {
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

	final func shouldKeep(accordingTo policy: Int) -> Bool {
		let s = sectionIndex
		return policy == HandlingPolicy.keepAll.rawValue
			|| (policy == HandlingPolicy.keepMineAndParticipated.rawValue && (s == Section.mine.rawValue || s == Section.participated.rawValue))
			|| (policy == HandlingPolicy.keepMine.rawValue && s == Section.mine.rawValue)
	}

	final var shouldSkipNotifications: Bool {
		return isSnoozing || muted
	}

	final var assignedToMySection: Bool {
		return assignedToMe && Settings.assignedPrHandlingPolicy == AssignmentPolicy.moveToMine.rawValue
	}

	final var assignedToParticipated: Bool {
		return assignedToMe && Settings.assignedPrHandlingPolicy == AssignmentPolicy.moveToParticipated.rawValue
	}

	final var createdByMe: Bool {
		return userNodeId == apiServer.userNodeId
	}

	final private func contains(terms: [String]) -> Bool {
		if let b = body {
			for t in terms {
				if !t.isEmpty && b.localizedCaseInsensitiveContains(t) {
					return true
				}
			}
		}
		for c in comments {
			if c.contains(terms: terms) {
				return true
			}
		}
		return false
	}

	final private var commentedByMe: Bool {
		for c in comments {
			if c.isMine {
				return true
			}
		}
		return false
	}

	var reviewedByMe: Bool {
		return false
	}

	final var isVisibleOnMenu: Bool {
		return sectionIndex != Section.none.rawValue
	}

	final func wakeUp() {
		disableSnoozing(explicityAwoke: true)
		postProcess()
	}

	final var isSnoozing: Bool {
		return snoozeUntil != nil
	}
    
    final var appropriateStateForNotification: Bool {
        let shouldBeQuietBecauseOfState = !isVisibleOnMenu || ((sectionIndex == Section.closed.rawValue || sectionIndex == Section.merged.rawValue) && !Settings.scanClosedAndMergedItems)
        return !shouldBeQuietBecauseOfState
    }

	final func keep(as newCondition: ItemCondition, notification: NotificationType) {
		if sectionIndex == Section.all.rawValue && !Settings.showCommentsEverywhere {
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
	}

	private final var shouldMoveToSnoozing: Bool {
		if snoozeUntil == nil {
			let d = TimeInterval(Settings.autoSnoozeDuration)
			if d > 0 && !wasAwokenFromSnooze && updatedAt != .distantPast, let snoozeByDate = updatedAt?.addingTimeInterval(86400.0*d) {
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
		return snoozingPreset?.wakeOnComment ?? true
	}

	final var shouldWakeOnMention: Bool {
		return snoozingPreset?.wakeOnMention ?? true
	}

	final var shouldWakeOnStatusChange: Bool {
		return snoozingPreset?.wakeOnStatusChange ?? true
	}

	final func wakeIfAutoSnoozed() {
		if snoozeUntil == autoSnoozeSentinelDate {
			disableSnoozing(explicityAwoke: false)
		}
	}

	final func snooze(using preset: SnoozePreset) {
		snoozeUntil = preset.wakeupDateFromNow
		snoozingPreset = preset
		wasAwokenFromSnooze = false
		muted = false
		postProcess()
	}

	var hasUnreadCommentsOrAlert: Bool {
		return unreadComments > 0
	}

	private final func disableSnoozing(explicityAwoke: Bool) {
		snoozeUntil = nil
		snoozingPreset = nil
		wasAwokenFromSnooze = explicityAwoke
	}

	final func postProcess() {

		if let s = snoozeUntil, s < Date() { // our snooze-by date is past
			disableSnoozing(explicityAwoke: true)
		}

		let isMine = createdByMe
		let currentCondition = condition
        let hideDrafts = Settings.draftHandlingPolicy == DraftHandlingPolicy.hide.rawValue

        var targetSection: Section
		if currentCondition == ItemCondition.merged.rawValue            	{ targetSection = .merged }
		else if currentCondition == ItemCondition.closed.rawValue      		{ targetSection = .closed }
		else if isMine || assignedToMySection                        		{ targetSection = .mine }
		else if assignedToParticipated || commentedByMe || reviewedByMe     { targetSection = .participated }
		else                                                           		{ targetSection = .all }

		/////////// Pick out any items that need to move to "mentioned"

		if targetSection == .all || targetSection == .none {

			if let p = self as? PullRequest, Int64(Settings.assignedReviewHandlingPolicy) > Section.none.rawValue, p.assignedForReview {
				targetSection = Section(Settings.assignedReviewHandlingPolicy)!

			} else if Int64(Settings.newMentionMovePolicy) > Section.none.rawValue && contains(terms: ["@\(S(apiServer.userName))"]) {
				targetSection = Section(Settings.newMentionMovePolicy)!

			} else if Int64(Settings.teamMentionMovePolicy) > Section.none.rawValue && contains(terms: apiServer.teams.compactMap { $0.calculatedReferral }) {
				targetSection = Section(Settings.teamMentionMovePolicy)!

			} else if Int64(Settings.newItemInOwnedRepoMovePolicy) > Section.none.rawValue && repo.isMine {
				targetSection = Section(Settings.newItemInOwnedRepoMovePolicy)!
			}
		}

		////////// Apply visibility policies
        
        if hideDrafts && targetSection != .none && draft {
            targetSection = .none
        }

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
			switch repo.itemHidingPolicy {
			case RepoHidingPolicy.hideMyAuthoredPrs.rawValue        	where isMine && self is PullRequest,
			     RepoHidingPolicy.hideMyAuthoredIssues.rawValue        	where isMine && self is Issue,
			     RepoHidingPolicy.hideAllMyAuthoredItems.rawValue    	where isMine,
			     RepoHidingPolicy.hideOthersPrs.rawValue            	where !isMine && self is PullRequest,
			     RepoHidingPolicy.hideOthersIssues.rawValue            	where !isMine && self is Issue,
			     RepoHidingPolicy.hideAllOthersItems.rawValue        	where !isMine:

				targetSection = .none
			default: break
			}
		}
        
		if targetSection != .none,
            let p = self as? PullRequest, p.shouldBeCheckedForRedStatuses(in: targetSection),
            p.displayedStatuses.contains(where: { $0.state != "success" }) {
            targetSection = .none
		}
        
        if targetSection != .none && shouldMoveToSnoozing {
            targetSection = .snoozed
        }

		/////////// Comment counting

        let skipUnreadCommentCheck = (targetSection == .closed || targetSection == .merged) && !Settings.scanClosedAndMergedItems

		if !skipUnreadCommentCheck && !muted && (targetSection.isLoud || Settings.showCommentsEverywhere) && postSyncAction != PostSyncAction.isNew.rawValue {
			var latestDate = latestReadCommentDate ?? .distantPast

			if Settings.assumeReadItemIfUserHasNewerComments {
				for c in myComments(since: latestDate) {
					if let createdDate = c.createdAt, latestDate < createdDate {
						latestDate = createdDate
					}
				}
				latestReadCommentDate = latestDate
			}
			unreadComments = countOthersComments(since: latestDate)

		} else {
            catchUpCommentDate()
			unreadComments = 0
		}

		if snoozeUntil != nil, let p = self as? PullRequest, shouldWakeOnComment, p.hasNewCommits { // we wake on comments and have a new commit alarm
			wakeUp() // re-process as awake item
			return
		}

		let reviewCount: Int64
		if let p = self as? PullRequest, API.shouldSyncReviews || API.shouldSyncReviewAssignments {
			reviewCount = Int64(p.reviews.count)
		} else {
			reviewCount = 0
		}

		totalComments = Int64(comments.count)
			+ (Settings.notifyOnItemReactions ? Int64(reactions.count) : 0)
			+ (Settings.notifyOnCommentReactions ? countCommentReactions : 0)
			+ reviewCount

		sectionIndex = targetSection.rawValue
	}

	private var countCommentReactions: Int64 {
		var count: Int64 = 0
		for c in comments {
			count += Int64(c.reactions.count)
		}
		return count
	}

	private final func myComments(since: Date) -> [PRComment] {
		return comments.filter { $0.isMine && ($0.createdAt ?? .distantPast) > since }
	}

	private final func othersComments(since: Date) -> [PRComment] {
		return comments.filter { !$0.isMine && ($0.createdAt ?? .distantPast) > since }
	}

	private final func countOthersComments(since: Date) -> Int64 {
		var count: Int64 = 0
		for c in comments {
			if !c.isMine && (c.createdAt ?? .distantPast) > since {
				count += 1
			}
			if Settings.notifyOnCommentReactions {
				for r in c.reactions {
					if !r.isMine && (r.createdAt ?? .distantPast) > since {
						count += 1
					}
				}
			}
		}
		if Settings.notifyOnItemReactions {
			for r in reactions {
				if !r.isMine && (r.createdAt ?? .distantPast) > since {
					count += 1
				}
			}
		}
		return count
	}

	final var urlForOpening: String? {

		if unreadComments > 0 && Settings.openPrAtFirstUnreadComment {
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
		var components = [String]()
		if let t = title {
			components.append(t)
		}
        if draft && Settings.draftHandlingPolicy == DraftHandlingPolicy.display.rawValue {
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
        return Array(labels).sorted {
			return $0.name!.compare($1.name!) == .orderedAscending
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
            return (lum < 0.5)
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
        
        if draft && Settings.draftHandlingPolicy == DraftHandlingPolicy.display.rawValue {
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

		if Settings.showReposInName, let n = repo.fullName {
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
			components.append("Repository: \(S(repo.fullName))")
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
				NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)])
		#endif
	}

	class func badgeCount<T: ListableItem>(from fetch: NSFetchRequest<T>, in moc: NSManagedObjectContext) -> Int {
		var badgeCount: Int64 = 0
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
			if numeric, let n = UInt64(T) {
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
		if !notTerms.isEmpty && !orTerms.isEmpty {
			let n = NSCompoundPredicate(andPredicateWithSubpredicates: notTerms)
			let o = NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)
			return NSCompoundPredicate(andPredicateWithSubpredicates: [n,o])
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

	static func requestForItems<T: ListableItem>(of itemType: T.Type, withFilter: String?, sectionIndex: Int64, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false, excludeSnoozed: Bool = false) -> NSFetchRequest<T> {

		var andPredicates = [NSPredicate]()

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
				} while(foundOne)
			}

			check(forTag: "title")       	{ predicate(from: $0, termAt: $1, format: filterTitlePredicate, numeric: false) }
			check(forTag: "repo")        	{ predicate(from: $0, termAt: $1, format: filterRepoPredicate, numeric: false) }
			check(forTag: "server")        	{ predicate(from: $0, termAt: $1, format: filterServerPredicate, numeric: false) }
			check(forTag: "user")        	{ predicate(from: $0, termAt: $1, format: filterUserPredicate, numeric: false) }
			check(forTag: "number")        	{ predicate(from: $0, termAt: $1, format: filterNumberPredicate, numeric: true) }
			check(forTag: "milestone")    	{ predicate(from: $0, termAt: $1, format: filterMilestonePredicate, numeric: false) }
			check(forTag: "assignee")    	{ predicate(from: $0, termAt: $1, format: filterAssigneePredicate, numeric: false) }
			check(forTag: "label")        	{ predicate(from: $0, termAt: $1, format: filterLabelPredicate, numeric: false) }
			if itemType.self == PullRequest.self {
				check(forTag: "status")        	{ predicate(from: $0, termAt: $1, format: filterStatusPredicate, numeric: false) }
			}
			check(forTag: "state")			{ statePredicate(from: $0, termAt: $1) }

			if !fi.isEmpty {
				var predicates = [NSPredicate]()
				let negative = fi.hasPrefix("!")

				func appendPredicate(format: String, numeric: Bool) {
					if let p = predicate(from: fi, termAt: 0, format: format, numeric: numeric) {
						predicates.append(p)
					}
				}

				if Settings.includeTitlesInFilter {            	appendPredicate(format: filterTitlePredicate, numeric: false) }
				if Settings.includeReposInFilter {            	appendPredicate(format: filterRepoPredicate, numeric: false) }
				if Settings.includeServersInFilter {        	appendPredicate(format: filterServerPredicate, numeric: false) }
				if Settings.includeUsersInFilter {            	appendPredicate(format: filterUserPredicate, numeric: false) }
				if Settings.includeNumbersInFilter {        	appendPredicate(format: filterNumberPredicate, numeric: true) }
				if Settings.includeMilestonesInFilter {        	appendPredicate(format: filterMilestonePredicate, numeric: false) }
				if Settings.includeAssigneeNamesInFilter {    	appendPredicate(format: filterAssigneePredicate, numeric: false) }
				if Settings.includeLabelsInFilter {            	appendPredicate(format: filterLabelPredicate, numeric: false) }
				if itemType == PullRequest.self
					&& Settings.includeStatusesInFilter {    	appendPredicate(format: filterStatusPredicate, numeric: false) }

				if negative {
					andPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
				} else {
					andPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: predicates))
				}
			}
		}

		if Settings.hideUncommentedItems {
			andPredicates.append(itemType.includeInUnreadPredicate)
		}

		var sortDescriptors = [NSSortDescriptor]()
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

		//DLog("%@", andPredicates)

		let f = NSFetchRequest<T>(entityName: String(describing: itemType))
		f.fetchBatchSize = 50
		f.relationshipKeyPathsForPrefetching = (itemType == PullRequest.self) ? ["labels", "statuses", "reviews"] : ["labels"]
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		f.sortDescriptors = sortDescriptors
		return f
	}

	private static let _unreadPredicate = NSPredicate(format: "unreadComments > 0")
	class var includeInUnreadPredicate: NSPredicate {
		return _unreadPredicate
	}

	private static let isSnoozingPredicate = NSPredicate(format: "snoozeUntil != nil")

    private static let isDraftPredicate = NSPredicate(format: "draft == true")

    private static let isUnmergeablePredicate = NSPredicate(format: "isMergeable == false")
    
	static func relatedItems(from notificationUserInfo: [AnyHashable : Any]) -> (PRComment?, ListableItem)? {
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
				DispatchQueue.main.async {
					for n in notifications {
						let r = n.request.identifier
						let u = n.request.content.userInfo
						if let notificationUri = u[LISTABLE_URI_KEY] as? String, notificationUri == uri {
							DLog("Removing related notification: %@", r)
							nc.removeDeliveredNotifications(withIdentifiers: [r])
						}
					}
				}
			}
		#endif
	}

	var searchKeywords: [String] {
		let labelNames = labels.compactMap { $0.name }
		let orgAndRepo = repo.fullName?.components(separatedBy: "/") ?? []
		#if os(iOS)
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + orgAndRepo
		#else
		return [(userLogin ?? "NO_USERNAME"), "Trailer"] + labelNames + orgAndRepo
		#endif
	}
    
    final func handleSpotlight() {
        let uri = objectID.uriRepresentation().absoluteString
        if isVisibleOnMenu {
            indexForSpotlight(uri: uri)
        } else {
            hideFromSpotlightAndNotifications(uri: uri)
        }
    }

    private final func indexForSpotlight(uri: String) {
		
		guard CSSearchableIndex.isIndexingAvailable() else { return }

		let s = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)

        let group = DispatchGroup()
        
        if let i = userAvatarUrl, !Settings.hideAvatars {
            group.enter()
            API.haveCachedAvatar(from: i) { _, cachePath in
                s.thumbnailURL = URL(fileURLWithPath: cachePath)
                group.leave()
            }
        }
        
		let titleSuffix = labels.compactMap { $0.name }.reduce("") { $0 + " [\($1)]" }
		s.title = "#\(number) - \(S(title))\(titleSuffix)"
        
		s.contentCreationDate = createdAt
		s.contentModificationDate = updatedAt
		s.keywords = searchKeywords
		s.creator = userLogin
		s.contentDescription = "\(S(repo.fullName)) @\(S(userLogin)) - \(S(body?.trim))"
        
        group.notify(queue: .main) {
            let i = CSSearchableItem(uniqueIdentifier: uri, domainIdentifier: nil, attributeSet: s)
            CSSearchableIndex.default().indexSearchableItems([i], completionHandler: nil)
        }
	}

    override final class func shouldCreate(from node: GQLNode) -> Bool {
        if node.jsonPayload["state"] as? String == "OPEN" {
            return true
        }
        node.creationSkipped = true
        return false
    }

	final var shouldCheckForClosing: Bool {
		return repo.shouldSync && repo.postSyncAction != PostSyncAction.delete.rawValue && apiServer.lastSyncSucceeded
	}

	class func hasOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Bool {
		return false
	}

	static func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {

		let color: COLOR_CLASS
		let message: String

		if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if API.isRefreshing {
			color = COLOR_CLASS.appSecondaryLabel
			message = "Refreshing information, please wait a moment…"
		} else if !S(filterValue).isEmpty {
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
		} else if !Repo.mayProvidePrsForDisplay(fromServerWithId: criterion?.apiServerId) && !Repo.mayProvideIssuesForDisplay(fromServerWithId: criterion?.apiServerId) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs on at least one."
		} else {
			color = COLOR_CLASS.appSecondaryLabel
			message = "No open items in your configured repositories."
		}

		return styleForEmpty(message: message, color: color)
	}
    
    final func handleClosing() {
        DLog("Detected closed item: %@, handling policy is %@, coming from section %@",
             title,
             Settings.closeHandlingPolicy,
             sectionIndex)

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
		let text = "#\(number) - \(S(title))"
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
            case .wake(let date):
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
        return (self as? PullRequest)?.headRefName
    }

    var contextActions: [MenuAction] {
        var actions: [MenuAction] = [.copy, .openRepo]

        if !isSnoozing {
            if Settings.showCommentsEverywhere || sectionIndex != Section.all.rawValue {
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
