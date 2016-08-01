
import CoreData
#if os(iOS)
	import UIKit
	import CoreSpotlight
	import MobileCoreServices
#endif

class ListableItem: DataItem {

	@NSManaged var assignedToMe: NSNumber?
	@NSManaged var assigneeName: String?
	@NSManaged var body: String?
	@NSManaged var webUrl: String?
	@NSManaged var condition: NSNumber?
	@NSManaged var isNewAssignment: NSNumber?
	@NSManaged var repo: Repo
	@NSManaged var title: String?
	@NSManaged var totalComments: NSNumber?
	@NSManaged var unreadComments: NSNumber?
	@NSManaged var url: String?
	@NSManaged var userAvatarUrl: String?
	@NSManaged var userId: NSNumber?
	@NSManaged var userLogin: String?
	@NSManaged var sectionIndex: NSNumber?
	@NSManaged var latestReadCommentDate: Date?
	@NSManaged var state: String?
	@NSManaged var reopened: NSNumber?
	@NSManaged var number: NSNumber?
	@NSManaged var announced: NSNumber?
	@NSManaged var muted: NSNumber?
	@NSManaged var snoozeUntil: Date?
	@NSManaged var wasAwokenFromSnooze: Bool
	@NSManaged var milestone: String?

	@NSManaged var comments: Set<PRComment>
	@NSManaged var labels: Set<PRLabel>

	final func baseSyncFromInfo(_ info: [NSObject: AnyObject], inRepo: Repo) {

		repo = inRepo

		url = info["url"] as? String
		webUrl = info["html_url"] as? String
		number = info["number"] as? NSNumber
		state = info["state"] as? String
		title = info["title"] as? String
		body = info["body"] as? String
		milestone = info["milestone"]?["title"] as? String

		if let userInfo = info["user"] as? [NSObject: AnyObject] {
			userId = userInfo["id"] as? NSNumber
			userLogin = userInfo["login"] as? String
			userAvatarUrl = userInfo["avatar_url"] as? String
		}

		if let assignee = info["assignee"] as? [NSObject: AnyObject], let name = assignee["login"] as? String, let id = assignee["id"] as? NSNumber {
			let currentlyAssigned = (id == inRepo.apiServer.userId)
			let previouslyAssigned = assignedToMe?.boolValue ?? false
			isNewAssignment = currentlyAssigned && !previouslyAssigned && !createdByMe
			assignedToMe = currentlyAssigned
			assigneeName = name
		} else {
			isNewAssignment = false
			assignedToMe = false
			assigneeName = nil
		}
	}

	final override func resetSyncState() {
		super.resetSyncState()
		repo.resetSyncState()
	}

	final override func prepareForDeletion() {
		api.refreshesSinceLastLabelsCheck[objectID] = nil
		api.refreshesSinceLastStatusCheck[objectID] = nil
		ensureInvisible()
		super.prepareForDeletion()
	}

	final func ensureInvisible() {
		#if os(iOS)
			if CSSearchableIndex.isIndexingAvailable() {
				CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [objectID.uriRepresentation().absoluteString], completionHandler: nil)
			}
		#endif
		#if os(OSX)
			if Settings.removeNotificationsWhenItemIsRemoved {
				removeRelatedNotifications()
			}
		#endif
	}

	final func sortedComments(_ comparison: ComparisonResult) -> [PRComment] {
		return Array(comments).sorted(by: { (c1, c2) -> Bool in
			let d1 = c1.createdAt ?? Date.distantPast
			let d2 = c2.createdAt ?? Date.distantPast
			return d1.compare(d2) == comparison
		})
	}

	final private func catchUpCommentDate() {
		for c in comments {
			if let commentCreation = c.createdAt {
				if let latestRead = latestReadCommentDate {
					if latestRead.compare(commentCreation) == .orderedAscending {
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

	final func shouldKeepForPolicy(_ policy: Int) -> Bool {
		let s = sectionIndex?.intValue
		return policy == HandlingPolicy.keepAll.rawValue
			|| (policy == HandlingPolicy.keepMineAndParticipated.rawValue && (s == Section.mine.rawValue || s == Section.participated.rawValue))
			|| (policy == HandlingPolicy.keepMine.rawValue && s == Section.mine.rawValue)
	}

	final var shouldSkipNotifications: Bool {
		return isSnoozing || (muted?.boolValue ?? false)
	}

	final var assignedToMySection: Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==AssignmentPolicy.moveToMine.rawValue
	}

	final var assignedToParticipated: Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==AssignmentPolicy.moveToParticipated.rawValue
	}

	final var createdByMe: Bool {
		if let userId = userId, let apiId = apiServer.userId {
			return userId == apiId
		}
		return false
	}

	final var refersToMe: Bool {
		if let apiName = apiServer.userName, let b = body {
			return b.localizedCaseInsensitiveContains("@\(apiName)")
		}
		return false
	}

	final var commentedByMe: Bool {
		for c in comments {
			if c.isMine {
				return true
			}
		}
		return false
	}

	final private var refersToMyTeams: Bool {
		if let b = body {
			for t in apiServer.teams {
				if let r = t.calculatedReferral {
					if b.localizedCaseInsensitiveContains(r) { return true }
				}
			}
		}
		return false
	}

	final var isVisibleOnMenu: Bool {
		return self.sectionIndex?.intValue != Section.none.rawValue
	}

	final func wakeUp() {
		snoozeUntil = nil
		wasAwokenFromSnooze = true
		postProcess()
	}

	final var isSnoozing: Bool {
		return snoozeUntil != nil
	}

	final func keepWithCondition(_ newCondition: ItemCondition, notification: NotificationType) {
		if sectionIndex?.intValue == Section.all.rawValue && !Settings.showCommentsEverywhere {
			catchUpCommentDate()
		}
		postSyncAction = PostSyncAction.doNothing.rawValue
		condition = newCondition.rawValue
		if snoozeUntil != nil {
			snoozeUntil = nil
		} else {
			app.postNotificationOfType(type: notification, forItem: self)
		}
	}

	private final func shouldMoveToSnoozing() -> Bool {
		if snoozeUntil == nil {
			let d = TimeInterval(Settings.autoSnoozeDuration)
			if d > 0 && !wasAwokenFromSnooze, let autoSnoozeDate = updatedAt?.addingTimeInterval(86400.0*d) {
				if autoSnoozeDate.compare(Date()) == .orderedAscending {
					snoozeUntil = autoSnoozeDate
					return true
				}
			}
			return false
		} else {
			return true
		}
	}

	final func wakeIfAutoSnoozed() {
		if snoozeUntil == autoSnoozeDate && !wasAwokenFromSnooze {
			snoozeUntil = nil
			wasAwokenFromSnooze = false
		}
	}

	final func postProcess() {

		if let s = snoozeUntil, s.compare(Date()) == .orderedAscending {
			snoozeUntil = nil
			wasAwokenFromSnooze = true
		}

		let isMine = createdByMe
		var targetSection: Section
		let currentCondition = condition?.intValue ?? ItemCondition.open.rawValue

		if currentCondition == ItemCondition.merged.rawValue		{ targetSection = .merged }
		else if currentCondition == ItemCondition.closed.rawValue	{ targetSection = .closed }
		else if shouldMoveToSnoozing()								{ targetSection = .snoozed }
		else if isMine || assignedToMySection						{ targetSection = .mine }
		else if assignedToParticipated || commentedByMe				{ targetSection = .participated }
		else														{ targetSection = .all }

		let outsideMySectionsButAwake = (targetSection == .all || targetSection == .none)
		var moveToMentioned = false
		var autoMoveOnTeamMentions = false
		var autoMoveOnCommentMentions = false
		var doReferralCheckInComments = false

		if outsideMySectionsButAwake && Settings.moveNewItemsInOwnReposToMentioned && repo.isMine {
			moveToMentioned = true
		}

		if !moveToMentioned && outsideMySectionsButAwake && Settings.autoMoveOnTeamMentions {
			if refersToMyTeams {
				moveToMentioned = true
			} else {
				doReferralCheckInComments = true
				autoMoveOnTeamMentions = true
			}
		}

		if !moveToMentioned && outsideMySectionsButAwake && Settings.autoMoveOnCommentMentions {
			if refersToMe {
				moveToMentioned = true
			} else {
				doReferralCheckInComments = true
				autoMoveOnCommentMentions = true
			}
		}

		var latestDate = latestReadCommentDate ?? Date.distantPast
		let isMuted = muted?.boolValue ?? false

		if Settings.assumeReadItemIfUserHasNewerComments {
			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.predicate = predicateForMyCommentsSinceDate(latestDate)
			for c in try! managedObjectContext?.fetch(f) ?? [] {
				if let createdDate = c.createdAt, createdDate.compare(latestDate) == .orderedDescending {
					latestDate = createdDate
				}
			}
			latestReadCommentDate = latestDate
		}

		func unreadFromOtherCommentsSinceLatestDate() -> Int {
			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			return try! managedObjectContext?.count(for: f) ?? 0
		}

		let dontCountComments = isMuted || ((targetSection == .all || targetSection == .snoozed) && !Settings.showCommentsEverywhere)

		if moveToMentioned {
			targetSection = .mentioned
			unreadComments = dontCountComments ? 0 : unreadFromOtherCommentsSinceLatestDate()
		} else if doReferralCheckInComments {
			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount = 0
			for c in try! managedObjectContext?.fetch(f) ?? [] {
				if (autoMoveOnCommentMentions && c.refersToMe) || (autoMoveOnTeamMentions && c.refersToMyTeams) {
					targetSection = .mentioned
				}
				if !dontCountComments {
					if c.createdAt?.compare(latestDate) == .orderedDescending {
						unreadCommentCount += 1
					}
				}
			}
			unreadComments = unreadCommentCount
		} else {
			unreadComments = dontCountComments ? 0 : unreadFromOtherCommentsSinceLatestDate()
		}

		totalComments = comments.count

		let policy = (self is Issue ? repo.displayPolicyForIssues : repo.displayPolicyForPrs)?.intValue ?? 0
		if let displayPolicy = RepoDisplayPolicy(rawValue: policy) {
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

		if let hidePolicy = RepoHidingPolicy(rawValue: repo.itemHidingPolicy?.intValue ?? 0) {
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

		if targetSection != .none, let p = self as? PullRequest, p.shouldBeCheckedForRedStatusesInSection(targetSection) {
			for s in p.displayedStatuses {
				if s.state != "success" {
					targetSection = .none
					break
				}
			}
		}

		sectionIndex = targetSection.rawValue

		if title==nil { title = "(No title)" }
	}

	final func urlForOpening() -> String? {
		let unreadCount = unreadComments?.intValue ?? 0

		if unreadCount > 0 && Settings.openPrAtFirstUnreadComment {
			let f = NSFetchRequest<PRComment>(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.fetchLimit = 1
			f.predicate = predicateForOthersCommentsSinceDate(latestReadCommentDate)
			f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
			let ret = try! managedObjectContext?.fetch(f) ?? []
			if let firstComment = ret.first, let url = firstComment.webUrl {
				return url
			}
		}

		return webUrl
	}

	final func accessibleTitle() -> String {
		var components = [String]()
		if let t = title {
			components.append(t)
		}
		if Settings.showLabels {
			components.append("\(labels.count) labels:")
			for l in sortedLabels() {
				if let n = l.name {
					components.append(n)
				}
			}
		}
		return components.joined(separator: ",")
	}

	final func sortedLabels() -> [PRLabel] {
		return Array(labels).sorted(by: { (l1: PRLabel, l2: PRLabel) -> Bool in
			return l1.name!.compare(l2.name!) == .orderedAscending
		})
	}

	final func titleWithFont(_ font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS) -> NSMutableAttributedString {
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
						NSParagraphStyleAttributeName: lp]
					#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize+6.0
						let labelAttributes = [NSFontAttributeName: labelFont,
							NSBaselineOffsetAttributeName: 1.0,
							NSParagraphStyleAttributeName: lp]
					#endif

					var count = 0
					for l in sortedLabels() {
						var a = labelAttributes
						let color = l.colorForDisplay
						a[NSBackgroundColorAttributeName] = color
						a[NSForegroundColorAttributeName] = isDarkColor(color) ? COLOR_CLASS.white : COLOR_CLASS.black
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

	class final func emptyMessage(_ message: String, color: COLOR_CLASS) -> NSAttributedString {
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

	final private func predicateForMyCommentsSinceDate(_ optionalDate: Date?) -> NSPredicate {

		let userNumber = apiServer.userId?.int64Value ?? 0

		if self is PullRequest {
			if let date = optionalDate {
				return NSPredicate(format: "userId == %lld and pullRequest == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId == %lld and pullRequest == %@", userNumber, self)
			}
		} else {
			if let date = optionalDate {
				return NSPredicate(format: "userId == %lld and issue == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId == %lld and issue == %@", userNumber, self)
			}
		}
	}

	final private func predicateForOthersCommentsSinceDate(_ optionalDate: Date?) -> NSPredicate {

		let userNumber = apiServer.userId?.int64Value ?? 0

		if self is PullRequest {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and pullRequest == %@", userNumber, self)
			}
		} else {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and issue == %@", userNumber, self)
			}
		}
	}

	final class func badgeCountFromFetch<T: ListableItem>(_ f: NSFetchRequest<T>, inMoc: NSManagedObjectContext) -> Int {
		var badgeCount = 0
		f.returnsObjectsAsFaults = false
		for i in try! inMoc.fetch(f) {
			badgeCount += (i.unreadComments?.intValue ?? 0)
		}
		return badgeCount
	}

	final class func buildOrPredicate(_ string: String, expectedLength: Int, format: String, numeric: Bool) -> NSPredicate? {
		if string.characters.count > expectedLength {
			let items = string.substring(from: string.characters.index(string.startIndex, offsetBy: expectedLength))
			if !items.characters.isEmpty {
				var orTerms = [NSPredicate]()
				var notTerms = [NSPredicate]()
				for term in items.components(separatedBy: ",") {
					let T: String
					let negative: Bool
					if term.characters.first == "!" {
						T = term.substring(from: term.characters.index(term.startIndex, offsetBy: 1))
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

	final class func serverPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "apiServer.label contains[cd] %@", numeric: false)
	}

	final class func titlePredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 6, format: "title contains[cd] %@", numeric: false)
	}

	final class func milestonePredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 10, format: "milestone contains[cd] %@", numeric: false)
	}

	final class func assigneePredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 9, format: "assigneeName contains[cd] %@", numeric: false)
	}

	final class func numberPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "number == %llu", numeric: true)
	}

    final class func repoPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 5, format: "repo.fullName contains[cd] %@", numeric: false)
    }

    final class func labelPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 6, format: "SUBQUERY(labels, $label, $label.name contains[cd] %@).@count > 0", numeric: false)
    }

    final class func statusPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "SUBQUERY(statuses, $status, $status.descriptionText contains[cd] %@).@count > 0", numeric: false)
    }

    final class func userPredicateFromFilterString(_ string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 5, format: "userLogin contains[cd] %@", numeric: false)
    }

	final class func requestForItemsOfType(_ itemType: String, withFilter: String?, sectionIndex: Int, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false) -> NSFetchRequest<ListableItem> {

		var andPredicates = [NSPredicate]()

		if onlyUnread {
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
		}

		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex))
		}

		if Settings.hideSnoozedItems {
			andPredicates.append(NSPredicate(format: "sectionIndex != %d", Section.snoozed.rawValue))
		}

		if var fi = withFilter, !fi.isEmpty {

            func checkForPredicates(_ tagString: String, _ process: (String)->NSPredicate?) {
				var foundOne: Bool
				repeat {
					foundOne = false
					for word in fi.components(separatedBy: " ") {
						if word.characters.starts(with: "\(tagString):".characters) {
							if let p = process(word) {
								andPredicates.append(p)
							}
							fi = fi.replacingOccurrences(of: word, with: "")
							fi = fi.trim()
							foundOne = true
							break
						}
					}
				} while(foundOne)
            }

			checkForPredicates("title", titlePredicateFromFilterString)
            checkForPredicates("server", serverPredicateFromFilterString)
            checkForPredicates("repo", repoPredicateFromFilterString)
            checkForPredicates("label", labelPredicateFromFilterString)
            checkForPredicates("status", statusPredicateFromFilterString)
            checkForPredicates("user", userPredicateFromFilterString)
			checkForPredicates("number", numberPredicateFromFilterString)
			checkForPredicates("milestone", milestonePredicateFromFilterString)
			checkForPredicates("assignee", assigneePredicateFromFilterString)

			if !fi.isEmpty {
				var orPredicates = [NSPredicate]()
				let negative = (fi.characters.first == "!")

				func checkOr(_ format: String, numeric: Bool) {
					let predicate: NSPredicate
					let string = negative ? fi.substring(from: fi.index(fi.startIndex, offsetBy: 1)) : fi
					if numeric {
						if let number = Int64(fi) {
							predicate = NSPredicate(format: format, number)
						} else {
							return
						}
					} else {
						predicate = NSPredicate(format: format, string)
					}
					if negative {
						orPredicates.append(NSCompoundPredicate(notPredicateWithSubpredicate: predicate))
					} else {
						orPredicates.append(predicate)
					}
				}

				if Settings.includeTitlesInFilter {
					checkOr("title contains[cd] %@", numeric: false)
				}
				if Settings.includeReposInFilter {
					checkOr("repo.fullName contains[cd] %@", numeric: false)
				}
                if Settings.includeServersInFilter {
					checkOr("apiServer.label contains [cd] %@", numeric: false)
                }
                if Settings.includeUsersInFilter {
					checkOr("userLogin contains[cd] %@", numeric: false)
                }
				if Settings.includeNumbersInFilter {
					checkOr("number == %llu", numeric: true)
				}
				if Settings.includeMilestonesInFilter {
					checkOr("milestone contains[cd] %@", numeric: false)
				}
				if Settings.includeAssigneeNamesInFilter {
					checkOr("assigneeName contains[cd] %@", numeric: false)
				}
				if Settings.includeLabelsInFilter {
					checkOr("SUBQUERY(labels, $label, $label.name contains[cd] %@).@count > 0", numeric: false)
				}
				if itemType == "PullRequest" && Settings.includeStatusesInFilter {
					checkOr("SUBQUERY(statuses, $status, $status.descriptionText contains[cd] %@).@count > 0", numeric: false)
				}

				if negative {
					andPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: orPredicates))
				} else {
					andPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: orPredicates))
				}
			}
		}

		if Settings.hideUncommentedItems {
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
		}

		var sortDescriptors = [NSSortDescriptor]()
		sortDescriptors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))
		if Settings.groupByRepo {
			sortDescriptors.append(NSSortDescriptor(key: "repo.fullName", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:))))
		}

		if let fieldName = SortingMethod(rawValue: Settings.sortMethod)?.field() {
			if fieldName == "title" {
				sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending, selector: #selector(NSString.caseInsensitiveCompare(_:))))
			} else {
				sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending))
			}
		}

		//DLog("%@", andPredicates)

		let f = NSFetchRequest<ListableItem>(entityName: itemType)
		f.fetchBatchSize = 100
		let p = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		f.sortDescriptors = sortDescriptors
		return f
	}

	final class func relatedItemsFromNotificationInfo(_ userInfo: [String : AnyObject?]) -> (PRComment?, ListableItem)? {
		var item: ListableItem?
		var comment: PRComment?
		if let itemId = DataManager.idForUriPath(userInfo[COMMENT_ID_KEY] as? String), let c = existingObjectWithID(itemId) as? PRComment {
			comment = c
			item = c.pullRequest ?? c.issue
		} else if let itemId = DataManager.idForUriPath(userInfo[PULL_REQUEST_ID_KEY] as? String) {
			item = existingObjectWithID(itemId) as? ListableItem
		} else if let itemId = DataManager.idForUriPath(userInfo[ISSUE_ID_KEY] as? String) {
			item = existingObjectWithID(itemId) as? ListableItem
		}
		if let i = item {
			return (comment, i)
		} else {
			return nil
		}
	}

	final func setMute(_ mute: Bool) {
		muted = mute
		postProcess()
		if mute {
			removeRelatedNotifications()
		}
	}

	final func removeRelatedNotifications() {
		#if os(OSX)
		let nc = NSUserNotificationCenter.default
		for n in nc.deliveredNotifications {
			if let u = n.userInfo, let (_, item) = ListableItem.relatedItemsFromNotificationInfo(u), item.serverId == serverId {
				nc.removeDeliveredNotification(n)
			}
		}
		#endif
		// iOS won't allow access notifications after presenting if the app gets restarted, so behaviour of this would be inconsistent.
	}

	#if os(iOS)
	var searchKeywords: [String] {
		let labelNames = labels.flatMap { $0.name }
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + (repo.fullName?.components(separatedBy: "/") ?? [])
	}
	final func searchTitle() -> String {
		let labelNames = labels.flatMap { $0.name }
		var suffix = ""
		if labelNames.count > 0 {
			for l in labelNames {
				suffix += " [\(l)]"
			}
		}
		let n = number?.intValue ?? 0
		let t = S(title)
		return "#\(n) - \(t)\(suffix)"
	}
	final func indexForSpotlight() {

		guard CSSearchableIndex.isIndexingAvailable() else { return }

		let s = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)
		s.title = searchTitle()
		s.contentCreationDate = createdAt
		s.contentModificationDate = updatedAt
		s.keywords = searchKeywords
		s.creator = userLogin

		s.contentDescription = "\(S(repo.fullName)) @\(S(userLogin)) - \(S(body?.trim()))"

		func completeIndex(_ s: CSSearchableItemAttributeSet) {
			let i = CSSearchableItem(uniqueIdentifier:objectID.uriRepresentation().absoluteString, domainIdentifier: nil, attributeSet: s)
			CSSearchableIndex.default().indexSearchableItems([i], completionHandler: nil)
		}

		if let i = self.userAvatarUrl, !Settings.hideAvatars {
			_ = api.haveCachedAvatar(i) { _, cachePath in
				s.thumbnailURL = URL(string: "file://\(cachePath)")
				completeIndex(s)
			}
		} else {
			s.thumbnailURL = nil
			completeIndex(s)
		}
	}
	#endif
}
