
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

	@NSManaged var snoozeUntil: Date?
	@NSManaged var snoozingPreset: SnoozePreset?

	@NSManaged var comments: Set<PRComment>
	@NSManaged var labels: Set<PRLabel>

	final func baseSync(from info: [AnyHashable : Any], in repo: Repo) {

		self.repo = repo

		url = info["url"] as? String
		webUrl = info["html_url"] as? String
		number = (info["number"] as? NSNumber)?.int64Value ?? 0
		state = info["state"] as? String
		title = info["title"] as? String
		body = info["body"] as? String
		milestone = (info["milestone"] as? [AnyHashable : Any])?["title"] as? String

		if let userInfo = info["user"] as? [AnyHashable : Any] {
			userId = (userInfo["id"] as? NSNumber)?.int64Value ?? 0
			userLogin = userInfo["login"] as? String
			userAvatarUrl = userInfo["avatar_url"] as? String
		}

		processAssignmentStatus(from: info)
	}

	final func processAssignmentStatus(from info: [AnyHashable : Any]?) {

		let myIdOnThisRepo = repo.apiServer.userId
		var assigneeNames = [String]()

		func checkAndStoreAssigneeName(from assignee: [AnyHashable : Any]) -> Bool {

			if let name = assignee["login"] as? String, let assigneeId = assignee["id"] as? NSNumber {
				let shouldBeAssignedToMe = assigneeId.int64Value == myIdOnThisRepo
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

	final override func resetSyncState() {
		super.resetSyncState()
		repo.resetSyncState()
	}

	final override func prepareForDeletion() {
		API.refreshesSinceLastLabelsCheck[objectID] = nil
		API.refreshesSinceLastStatusCheck[objectID] = nil
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
		}
	}

	final func catchUpWithComments() {
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
		snoozeUntil = nil
		snoozingPreset = nil
		wasAwokenFromSnooze = true
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
					snoozeUntil = autoSnoozeDate
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
		if snoozeUntil == autoSnoozeDate {
			snoozeUntil = nil
			wasAwokenFromSnooze = false
			snoozingPreset = nil
		}
	}

	final func snooze(using preset: SnoozePreset) {
		snoozeUntil = preset.wakeupDateFromNow
		snoozingPreset = preset
		wasAwokenFromSnooze = false
		muted = false
		postProcess()
	}

	final func postProcess() {

		if let s = snoozeUntil, s < Date() {
			snoozeUntil = nil
			snoozingPreset = nil
			wasAwokenFromSnooze = true
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

		var outsideMySectionsButAwake = (targetSection == .all || targetSection == .none)

		if outsideMySectionsButAwake && Int64(Settings.newMentionMovePolicy) > Section.none.rawValue
			&& contains(terms: ["@\(S(apiServer.userName))"]) {

			targetSection = Section(Settings.newMentionMovePolicy)!
			outsideMySectionsButAwake = false
		}

		if outsideMySectionsButAwake && Int64(Settings.teamMentionMovePolicy) > Section.none.rawValue
			&& contains(terms: apiServer.teams.flatMap { $0.calculatedReferral }) {

			targetSection = Section(Settings.teamMentionMovePolicy)!
			outsideMySectionsButAwake = false
		}

		if outsideMySectionsButAwake && Int64(Settings.newItemInOwnedRepoMovePolicy) > Section.none.rawValue && repo.isMine {
			targetSection = Section(Settings.newItemInOwnedRepoMovePolicy)!
			outsideMySectionsButAwake = false
		}

		////////// Apply viewing policies

		let policy = self is Issue ? repo.displayPolicyForIssues : repo.displayPolicyForPrs
		if let displayPolicy = RepoDisplayPolicy(policy) {
			switch displayPolicy {
			case .hide:
				targetSection = .none
			case .mine:
				if targetSection == .all || targetSection == .participated || targetSection == .mentioned {
					targetSection = .none
				}
			case .mineAndPaticipated:
				if targetSection == .all {
					targetSection = .none
				}
			case .all:
				break
			}
		}

		if let hidePolicy = RepoHidingPolicy(repo.itemHidingPolicy) {
			switch hidePolicy {
			case .noHiding:
				break
			case .hideMyAuthoredPrs:
				if isMine && self is PullRequest {
					targetSection = .none
				}
			case .hideMyAuthoredIssues:
				if isMine && self is Issue {
					targetSection = .none
				}
			case .hideAllMyAuthoredItems:
				if isMine {
					targetSection = .none
				}
			case .hideOthersPrs:
				if !isMine && self is PullRequest {
					targetSection = .none
				}
			case .hideOthersIssues:
				if !isMine && self is Issue {
					targetSection = .none
				}
			case .hideAllOthersItems:
				if !isMine {
					targetSection = .none
				}
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
				let f = NSFetchRequest<PRComment>(entityName: "PRComment")
				f.returnsObjectsAsFaults = false
				f.predicate = predicateForMyComments(since: latestDate)
				for c in try! managedObjectContext?.fetch(f) ?? [] {
					if let createdDate = c.createdAt, latestDate < createdDate {
						latestDate = createdDate
					}
				}
				latestReadCommentDate = latestDate
			}

			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.predicate = predicateForOthersComments(since: latestDate)
			unreadComments = Int64(try! managedObjectContext?.count(for: f) ?? 0)

		} else {
			unreadComments = 0
		}

		totalComments = Int64(comments.count)
		sectionIndex = targetSection.rawValue
		if title==nil { title = "(No title)" }
	}

	final var urlForOpening: String? {

		if unreadComments > 0 && Settings.openPrAtFirstUnreadComment {
			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.fetchLimit = 1
			f.predicate = predicateForOthersComments(since: latestReadCommentDate ?? .distantPast)
			f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
			let ret = try! managedObjectContext?.fetch(f) ?? []
			if let firstComment = ret.first, let url = firstComment.webUrl {
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
		if Settings.showLabels {
			components.append("\(labels.count) labels:")
			for l in sortedLabels {
				if let n = l.name {
					components.append(n)
				}
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
				let labelCount = labels.count
				if labelCount > 0 {

					_title.append(NSAttributedString(string: "\n", attributes: titleAttributes))

					let lp = NSMutableParagraphStyle()
					#if os(iOS)
						lp.lineHeightMultiple = 1.15
						let labelAttributes = [NSFontAttributeName: labelFont,
						                       NSBaselineOffsetAttributeName: 2.0,
						                       NSParagraphStyleAttributeName: lp] as [String : Any]
					#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize+6.0
						let labelAttributes = [NSFontAttributeName: labelFont,
						                       NSBaselineOffsetAttributeName: 1.0,
						                       NSParagraphStyleAttributeName: lp] as [String : Any]
					#endif

					func isDark(color: COLOR_CLASS) -> Bool {
						var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
						color.getRed(&r, green: &g, blue: &b, alpha: nil)
						let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
						return (lum < 0.5)
					}

					var count = 0
					for l in sortedLabels {
						var a = labelAttributes
						let color = l.colorForDisplay
						a[NSBackgroundColorAttributeName] = color
						a[NSForegroundColorAttributeName] = isDark(color: color) ? COLOR_CLASS.white : COLOR_CLASS.black
						let name = l.name!.replacingOccurrences(of: " ", with: "\u{a0}")
						_title.append(NSAttributedString(string: "\u{a0}", attributes: a))
						_title.append(NSAttributedString(string: name, attributes: a))
						_title.append(NSAttributedString(string: "\u{a0}", attributes: a))
						if count < labelCount-1 {
							_title.append(NSAttributedString(string: " ", attributes: labelAttributes))
                        }
                        count += 1
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

	final private func predicateForMyComments(since date: Date) -> NSPredicate {

		if self is PullRequest {
			return NSPredicate(format: "userId == %lld and pullRequest == %@ and createdAt > %@", apiServer.userId, self, date as CVarArg)
		} else {
			return NSPredicate(format: "userId == %lld and issue == %@ and createdAt > %@", apiServer.userId, self, date as CVarArg)
		}
	}

	final private func predicateForOthersComments(since date: Date) -> NSPredicate {

		if self is PullRequest {
			return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", apiServer.userId, self, date as CVarArg)
		} else {
			return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", apiServer.userId, self, date as CVarArg)
		}
	}

	final class func badgeCount<T: ListableItem>(from fetch: NSFetchRequest<T>, in moc: NSManagedObjectContext) -> Int {
		var badgeCount = 0
		fetch.returnsObjectsAsFaults = false
		for i in try! moc.fetch(fetch) {
			badgeCount += Int(i.unreadComments)
		}
		return badgeCount
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
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
		}

		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %lld", sectionIndex))
		}

		if Settings.hideSnoozedItems {
			andPredicates.append(NSPredicate(format: "sectionIndex != %lld", Section.snoozed.rawValue))
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
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
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

		let f = NSFetchRequest<T>(entityName: typeName(itemType))
		f.fetchBatchSize = 100
		let p = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		f.sortDescriptors = sortDescriptors
		return f
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
			_ = API.haveCachedAvatar(from: i) { _, cachePath in
				s.thumbnailURL = URL(string: "file://\(cachePath)")
				completeIndex(withSet: s)
			}
		} else {
			s.thumbnailURL = nil
			completeIndex(withSet: s)
		}
	}
	#endif

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
