
import CoreData
#if os(iOS)
	import UIKit
	import CoreSpotlight
	import MobileCoreServices
	import UserNotifications
#endif

class ListableItem: DataItem {

	@NSManaged var assignedToMe: Bool
	@NSManaged var assigneeName: String? // note: This now could be a list of names, delimited with a ","
	@NSManaged var body: String?
	@NSManaged var webUrl: String?
	@NSManaged var condition: Int64
	@NSManaged var isNewAssignment: Bool
	@NSManaged var repo: Repo
	@NSManaged var title: String?
	@NSManaged var totalComments: Int64
	@NSManaged var unreadComments: Int64
	@NSManaged var url: String?
	@NSManaged var userAvatarUrl: String?
	@NSManaged var userId: Int64
	@NSManaged var userLogin: String?
	@NSManaged var sectionIndex: Int64
	@NSManaged var latestReadCommentDate: Date?
	@NSManaged var state: String?
	@NSManaged var reopened: Bool
	@NSManaged var number: Int64
	@NSManaged var announced: Bool
	@NSManaged var muted: Bool
	@NSManaged var wasAwokenFromSnooze: Bool
	@NSManaged var milestone: String?
	@NSManaged var dirty: Bool
	@NSManaged var requiresReactionRefreshFromUrl: String?

	@NSManaged var snoozeUntil: Date?
	@NSManaged var snoozingPreset: SnoozePreset?

	@NSManaged var comments: Set<PRComment>
	@NSManaged var labels: Set<PRLabel>
	@NSManaged var reactions: Set<Reaction>

	final func baseSync(from info: [AnyHashable : Any], in repo: Repo) {

		self.repo = repo

		url = info["url"] as? String
		webUrl = info["html_url"] as? String
		number = info["number"] as? Int64 ?? 0
		state = info["state"] as? String
		title = info["title"] as? String
		body = info["body"] as? String
		milestone = (info["milestone"] as? [AnyHashable : Any])?["title"] as? String

		if let userInfo = info["user"] as? [AnyHashable : Any] {
			userId = userInfo["id"] as? Int64 ?? 0
			userLogin = userInfo["login"] as? String
			userAvatarUrl = userInfo["avatar_url"] as? String
		}

		processAssignmentStatus(from: info)
	}

	final func processReactions(from info: [AnyHashable : Any]?) {

		if API.shouldSyncReactions, let info = info, let r = info["reactions"] as? [AnyHashable : Any] {
			requiresReactionRefreshFromUrl = Reaction.changesDetected(in: reactions, from: r)
		} else {
			reactions.forEach { $0.postSyncAction = PostSyncAction.delete.rawValue }
			requiresReactionRefreshFromUrl = nil
		}
	}

	final func processAssignmentStatus(from info: [AnyHashable : Any]?) {

		let myIdOnThisRepo = repo.apiServer.userId
		var assigneeNames = [String]()

		func checkAndStoreAssigneeName(from assignee: [AnyHashable : Any]) -> Bool {

			if let name = assignee["login"] as? String, let assigneeId = assignee["id"] as? Int64 {
				let shouldBeAssignedToMe = assigneeId == myIdOnThisRepo
				assigneeNames.append(name)
				return shouldBeAssignedToMe
			} else {
				return false
			}
		}

		var foundAssignmentToMe = false

		if let assignees = info?["assignees"] as? [[AnyHashable : Any]], assignees.count > 0 {
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

		if assigneeNames.count > 0 {
			assigneeName = assigneeNames.joined(separator: ",")
		} else {
			assigneeName = nil
		}
	}

	final func setToUpdatedIfIdle() {
		if postSyncAction == PostSyncAction.doNothing.rawValue {
			postSyncAction = PostSyncAction.isUpdated.rawValue
		}
	}

	class func active<T>(of type: T.Type, in moc: NSManagedObjectContext, visibleOnly: Bool) -> [T] where T : ListableItem {
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
		API.refreshesSinceLastStatusCheck[objectID] = nil
		API.refreshesSinceLastReactionsCheck[objectID] = nil
		ensureInvisible()
		super.prepareForDeletion()
	}

	final func ensureInvisible() {
		#if os(iOS)
			if CSSearchableIndex.isIndexingAvailable() {
				CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [objectID.uriRepresentation().absoluteString], completionHandler: nil)
			}
		#endif
		if Settings.removeNotificationsWhenItemIsRemoved {
			ListableItem.removeRelatedNotifications(uri: objectID.uriRepresentation().absoluteString)
		}
	}

	final func sortedComments(using comparison: ComparisonResult) -> [PRComment] {
		return Array(comments).sorted(by: { (c1, c2) -> Bool in
			let d1 = c1.createdAt ?? .distantPast
			let d2 = c2.createdAt ?? .distantPast
			return d1.compare(d2) == comparison
		})
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
			if Settings.notifyOnCommentReactions {
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
		}
		if Settings.notifyOnItemReactions {
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
		return userId == apiServer.userId
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

		//let D = Date()

		if let s = snoozeUntil, s < Date() { // our snooze-by date is past
			disableSnoozing(explicityAwoke: true)
		}

		let isMine = createdByMe
		var targetSection: Section
		let currentCondition = condition

		if currentCondition == ItemCondition.merged.rawValue		{ targetSection = .merged }
		else if currentCondition == ItemCondition.closed.rawValue	{ targetSection = .closed }
		else if shouldMoveToSnoozing								{ targetSection = .snoozed }
		else if isMine || assignedToMySection						{ targetSection = .mine }
		else if assignedToParticipated || commentedByMe				{ targetSection = .participated }
		else														{ targetSection = .all }

		/////////// Pick out any items that need to move to "mentioned"

		if targetSection == .all || targetSection == .none {

			if let p = self as? PullRequest, Int64(Settings.assignedReviewHandlingPolicy) > Section.none.rawValue, p.assignedForReview {
				targetSection = Section(Settings.assignedReviewHandlingPolicy)!

			} else if Int64(Settings.newMentionMovePolicy) > Section.none.rawValue && contains(terms: ["@\(S(apiServer.userName))"]) {
				targetSection = Section(Settings.newMentionMovePolicy)!

			} else if Int64(Settings.teamMentionMovePolicy) > Section.none.rawValue && contains(terms: apiServer.teams.flatMap { $0.calculatedReferral }) {
				targetSection = Section(Settings.teamMentionMovePolicy)!

			} else if Int64(Settings.newItemInOwnedRepoMovePolicy) > Section.none.rawValue && repo.isMine {
				targetSection = Section(Settings.newItemInOwnedRepoMovePolicy)!
			}
		}

		////////// Apply visibility policies

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
			case RepoHidingPolicy.hideMyAuthoredPrs.rawValue		where isMine && self is PullRequest,
				 RepoHidingPolicy.hideMyAuthoredIssues.rawValue		where isMine && self is Issue,
				 RepoHidingPolicy.hideAllMyAuthoredItems.rawValue	where isMine,
				 RepoHidingPolicy.hideOthersPrs.rawValue			where !isMine && self is PullRequest,
				 RepoHidingPolicy.hideOthersIssues.rawValue			where !isMine && self is Issue,
				 RepoHidingPolicy.hideAllOthersItems.rawValue		where !isMine:

				targetSection = .none
			default: break
			}
		}

		if targetSection != .none, let p = self as? PullRequest, p.shouldBeCheckedForRedStatuses(in: targetSection) {
			for s in p.displayedStatuses {
				if s.state != "success" {
					targetSection = .none
					break
				}
			}
		}

		/////////// Comment counting

		let inLoudSection = targetSection != .all && targetSection != .snoozed && targetSection != .none
		let showComments = !muted && (inLoudSection || Settings.showCommentsEverywhere)
		if showComments {

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
			unreadComments = 0
			if let p = self as? PullRequest {
				p.hasNewCommits = false
			}
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
		if title==nil { title = "(No title)" }

		//let T = D.timeIntervalSinceNow
		//print("postprocess: \(T * -1000)")
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
					if (c.createdAt ?? .distantPast) < (o.createdAt ?? .distantPast) {
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
		components.append("\(labels.count) labels:")
		for l in sortedLabels {
			if let n = l.name {
				components.append(n)
			}
		}
		return components.joined(separator: ",")
	}

	final var sortedLabels: [PRLabel] {
		return Array(labels).sorted(by: { (l1: PRLabel, l2: PRLabel) -> Bool in
			return l1.name!.compare(l2.name!) == .orderedAscending
		})
	}

	final func title(with font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS) -> NSMutableAttributedString {

		let p = NSMutableParagraphStyle()
		p.paragraphSpacing = 1.0
		let titleAttributes = [NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor, NSParagraphStyleAttributeName: p]

		let _title = NSMutableAttributedString()
		if let t = title {
			_title.append(NSAttributedString(string: t, attributes: titleAttributes))

			if Settings.showLabels {

				let sorted = sortedLabels
				let labelCount = sorted.count
				if labelCount > 0 {

					let lp = NSMutableParagraphStyle()
					#if os(iOS)
						lp.lineHeightMultiple = 1.15
						let labelAttributes = [NSFontAttributeName: labelFont,
						                       NSBaselineOffsetAttributeName: 2.0,
						                       NSParagraphStyleAttributeName: lp] as [String : Any]
					#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize + 4
						let labelAttributes = [NSFontAttributeName: labelFont,
						                       NSBaselineOffsetAttributeName: 2.0,
						                       NSParagraphStyleAttributeName: lp] as [String : Any]
					#endif

					func isDark(color: COLOR_CLASS) -> Bool {
						var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
						color.getRed(&r, green: &g, blue: &b, alpha: nil)
						let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
						return (lum < 0.5)
					}

					_title.append(NSAttributedString(string: "\n", attributes: titleAttributes))

					var count = 0
					for l in sorted {
						var a = labelAttributes
						let color = l.colorForDisplay
						a[NSBackgroundColorAttributeName] = color
						a[NSForegroundColorAttributeName] = isDark(color: color) ? COLOR_CLASS.white : COLOR_CLASS.black
						let name = l.name!.replacingOccurrences(of: " ", with: "\u{a0}")
						_title.append(NSAttributedString(string: "\u{a0}\(name)\u{a0}", attributes: a))
						if count < labelCount-1 {
							_title.append(NSAttributedString(string: " ", attributes: labelAttributes))
						}
						count += 1
					}
				}
			}

			if Settings.displayReviewChangeRequests, let p = self as? PullRequest {

				var latestReviewByUser = [String:Review]()
				for r in p.reviews.filter({ $0.shouldDisplay }) {
					let user = S(r.username)
					if let latestReview = latestReviewByUser[user] {
						if (latestReview.createdAt ?? .distantPast) < (r.createdAt ?? .distantPast) {
							latestReviewByUser[user] = r
						}
					} else {
						latestReviewByUser[user] = r
					}
				}

				if latestReviewByUser.count > 0 || !p.reviewers.isEmpty {

					let reviews = latestReviewByUser.values.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

					let lp = NSMutableParagraphStyle()
					#if os(iOS)
						lp.lineHeightMultiple = 1.15
					#else
						lp.minimumLineHeight = labelFont.pointSize + 5
					#endif

					let approvers = reviews.filter { $0.state == Review.State.APPROVED.rawValue }
					if approvers.count > 0 {

						let a = [NSFontAttributeName: labelFont,
								 NSForegroundColorAttributeName: COLOR_CLASS(red: 0, green: 0.5, blue: 0, alpha: 1.0),
								 NSParagraphStyleAttributeName: lp] as [String : Any]

						_title.append(NSAttributedString(string: "\n", attributes: a))

						var count = 0
						for r in approvers {
							let name = r.username!.replacingOccurrences(of: " ", with: "\u{a0}")
							_title.append(NSAttributedString(string: "@\(name) ", attributes: a))
							if count == approvers.count - 1 {
								_title.append(NSAttributedString(string: "approved changes", attributes: a))
							}
							count += 1
						}
					}

					let requesters = reviews.filter { $0.state == Review.State.CHANGES_REQUESTED.rawValue }
					if requesters.count > 0 {

						let a = [NSFontAttributeName: labelFont,
								 NSForegroundColorAttributeName: COLOR_CLASS(red: 0.7, green: 0, blue: 0, alpha: 1.0),
								 NSParagraphStyleAttributeName: lp] as [String : Any]

						_title.append(NSAttributedString(string: "\n", attributes: a))

						var count = 0
						for r in requesters {
							let name = r.username!.replacingOccurrences(of: " ", with: "\u{a0}")
							_title.append(NSAttributedString(string: "@\(name) ", attributes: a))
							if count == requesters.count - 1 {
								_title.append(NSAttributedString(string: requesters.count > 1 ? "request changes" : "requests changes", attributes: a))
							}
							count += 1
						}
					}

					let approverNames = approvers.flatMap { $0.username }
					let requesterNames = requesters.flatMap { $0.username }
					let otherReviewers = p.reviewers.components(separatedBy: ",").filter({ !($0.isEmpty || approverNames.contains($0) || requesterNames.contains($0)) })
					if otherReviewers.count > 0 {

						let a = [NSFontAttributeName: labelFont,
								 NSForegroundColorAttributeName: COLOR_CLASS(red: 0.7, green: 0.7, blue: 0, alpha: 1.0),
								 NSParagraphStyleAttributeName: lp] as [String : Any]

						_title.append(NSAttributedString(string: "\n", attributes: a))

						var count = 0
						for r in otherReviewers {
							let name = r.replacingOccurrences(of: " ", with: "\u{a0}")
							_title.append(NSAttributedString(string: "@\(name) ", attributes: a))
							if count == otherReviewers.count - 1 {
								_title.append(NSAttributedString(string: otherReviewers.count > 1 ? "haven't reviewed yet" : "hasn't reviewed yet", attributes: a))
							}
							count += 1
						}
					}
				}
			}
		}
		return _title
	}

	class final func styleForEmpty(message: String, color: COLOR_CLASS) -> NSAttributedString {
		let p = NSMutableParagraphStyle()
		p.lineBreakMode = .byWordWrapping
		p.alignment = .center
		#if os(OSX)
			return NSAttributedString(string: message, attributes: [
				NSForegroundColorAttributeName: color,
				NSParagraphStyleAttributeName: p
			])
		#elseif os(iOS)
			return NSAttributedString(string: message, attributes: [
				NSForegroundColorAttributeName: color,
				NSParagraphStyleAttributeName: p,
				NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)])
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

	private final class func predicate(from token: String, termAt: Int, format: String, numeric: Bool) -> NSPredicate? {
		if token.characters.count > termAt {
			let items = token.substring(from: token.index(token.startIndex, offsetBy: termAt))
			if !items.isEmpty {
				var orTerms = [NSPredicate]()
				var notTerms = [NSPredicate]()
				for term in items.components(separatedBy: ",") {
					let T: String
					let negative: Bool
					if term.hasPrefix("!") {
						T = term.substring(from: term.index(term.startIndex, offsetBy: 1))
						negative = true
					} else {
						T = term
						negative = false
					}
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
				let n = NSCompoundPredicate(andPredicateWithSubpredicates: notTerms)
				let o = NSCompoundPredicate(orPredicateWithSubpredicates: orTerms)
				if notTerms.count > 0 && orTerms.count > 0 {
					return NSCompoundPredicate(andPredicateWithSubpredicates: [n,o])
				} else if notTerms.count > 0 {
					return n
				} else if orTerms.count > 0 {
					return o
				} else {
					return nil
				}
			}
		}
		return nil
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

	final class func requestForItems<T: ListableItem>(of itemType: T.Type, withFilter: String?, sectionIndex: Int64, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false) -> NSFetchRequest<T> {

		var andPredicates = [NSPredicate]()

		if onlyUnread {
			andPredicates.append(itemType.includeInUnreadPredicate)
		}

		if sectionIndex < 0 {
			andPredicates.append(Section.nonZeroPredicate)
		} else if let s = Section(rawValue: sectionIndex) {
			andPredicates.append(s.matchingPredicate)
		}

		if Settings.hideSnoozedItems {
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
							if let p = process(token, prefix.characters.count) {
								andPredicates.append(p)
							}
							fi = fi.replacingOccurrences(of: token, with: "")
							fi = fi.trim
							foundOne = true
							break
						}
					}
				} while(foundOne)
            }

			check(forTag: "title")		{ predicate(from: $0, termAt: $1, format: filterTitlePredicate, numeric: false) }
			check(forTag: "repo")		{ predicate(from: $0, termAt: $1, format: filterRepoPredicate, numeric: false) }
			check(forTag: "server")		{ predicate(from: $0, termAt: $1, format: filterServerPredicate, numeric: false) }
			check(forTag: "user")		{ predicate(from: $0, termAt: $1, format: filterUserPredicate, numeric: false) }
			check(forTag: "number")		{ predicate(from: $0, termAt: $1, format: filterNumberPredicate, numeric: true) }
			check(forTag: "milestone")	{ predicate(from: $0, termAt: $1, format: filterMilestonePredicate, numeric: false) }
			check(forTag: "assignee")	{ predicate(from: $0, termAt: $1, format: filterAssigneePredicate, numeric: false) }
			check(forTag: "label")		{ predicate(from: $0, termAt: $1, format: filterLabelPredicate, numeric: false) }
			check(forTag: "status")		{ predicate(from: $0, termAt: $1, format: filterStatusPredicate, numeric: false) }

			if !fi.isEmpty {
				var predicates = [NSPredicate]()
				let negative = fi.hasPrefix("!")

				func appendPredicate(format: String, numeric: Bool) {
					if let p = predicate(from: fi, termAt: 0, format: format, numeric: numeric) {
						predicates.append(p)
					}
				}

				if Settings.includeTitlesInFilter {			appendPredicate(format: filterTitlePredicate, numeric: false) }
				if Settings.includeReposInFilter {			appendPredicate(format: filterRepoPredicate, numeric: false) }
                if Settings.includeServersInFilter {		appendPredicate(format: filterServerPredicate, numeric: false) }
                if Settings.includeUsersInFilter {			appendPredicate(format: filterUserPredicate, numeric: false) }
				if Settings.includeNumbersInFilter {		appendPredicate(format: filterNumberPredicate, numeric: true) }
				if Settings.includeMilestonesInFilter {		appendPredicate(format: filterMilestonePredicate, numeric: false) }
				if Settings.includeAssigneeNamesInFilter {	appendPredicate(format: filterAssigneePredicate, numeric: false) }
				if Settings.includeLabelsInFilter {			appendPredicate(format: filterLabelPredicate, numeric: false) }
				if itemType == PullRequest.self
					&& Settings.includeStatusesInFilter {	appendPredicate(format: filterStatusPredicate, numeric: false) }

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
		f.relationshipKeyPathsForPrefetching = (itemType == PullRequest.self) ? ["labels", "statuses"] : ["labels"]
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

	final class func relatedItems(from notificationUserInfo: [AnyHashable : Any]) -> (PRComment?, ListableItem)? {
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

	final class func removeRelatedNotifications(uri: String) {
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
				atNextEvent {
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

	#if os(iOS)
	var searchKeywords: [String] {
		let labelNames = labels.flatMap { $0.name }
		let orgAndRepo = repo.fullName?.components(separatedBy: "/") ?? []
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + orgAndRepo
	}
	final var searchTitle: String {
		let labelNames = labels.flatMap { $0.name }
		var suffix = ""
		if labelNames.count > 0 {
			for l in labelNames {
				suffix += " [\(l)]"
			}
		}
		let t = S(title)
		return "#\(number) - \(t)\(suffix)"
	}
	final func indexForSpotlight() {

		guard CSSearchableIndex.isIndexingAvailable() else { return }

		let s = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)
		s.title = searchTitle
		s.contentCreationDate = createdAt
		s.contentModificationDate = updatedAt
		s.keywords = searchKeywords
		s.creator = userLogin

		s.contentDescription = "\(S(repo.fullName)) @\(S(userLogin)) - \(S(body?.trim))"

		func completeIndex(withSet s: CSSearchableItemAttributeSet) {
			let i = CSSearchableItem(uniqueIdentifier: objectID.uriRepresentation().absoluteString, domainIdentifier: nil, attributeSet: s)
			CSSearchableIndex.default().indexSearchableItems([i], completionHandler: nil)
		}

		if let i = userAvatarUrl, !Settings.hideAvatars {
			API.haveCachedAvatar(from: i) { _, cachePath in
				s.thumbnailURL = URL(string: "file://\(cachePath)")
				completeIndex(withSet: s)
			}
		} else {
			s.thumbnailURL = nil
			completeIndex(withSet: s)
		}
	}
	#endif

	final var shouldCheckForClosing: Bool {
		return repo.shouldSync && repo.postSyncAction != PostSyncAction.delete.rawValue && apiServer.lastSyncSucceeded
	}

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?, openItemCount: Int) -> NSAttributedString {

		let color: COLOR_CLASS
		let message: String

		if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if appIsRefreshing {
			color = COLOR_CLASS.lightGray
			message = "Refreshing information, please wait a moment..."
		} else if !S(filterValue).isEmpty {
			color = COLOR_CLASS.lightGray
			message = "There are no items matching this filter."
		} else if openItemCount > 0 {
			color = COLOR_CLASS.lightGray
			message = "Some items are hidden by your settings."
		} else if !Repo.anyVisibleRepos(in: DataManager.main, criterion: criterion, excludeGrouped: true) {
			if Repo.anyVisibleRepos(in: DataManager.main) {
				color = COLOR_CLASS.lightGray
				message = "There are no repositories that are currently visible in this category."
			} else {
				color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
				message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
			}
		} else if !Repo.interestedInPrs(fromServerWithId: criterion?.apiServerId) && !Repo.interestedInIssues(fromServerWithId: criterion?.apiServerId) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs on at least one."
		} else if openItemCount==0 {
			color = COLOR_CLASS.lightGray
			message = "No open items in your configured repositories."
		} else {
			color = COLOR_CLASS.lightGray
			message = ""
		}

		return styleForEmpty(message: message, color: color)
	}
}
