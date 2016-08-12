
import CoreData
#if os(iOS)
	import UIKit
	import CoreSpotlight
	import MobileCoreServices
	import UserNotifications
#endif

class ListableItem: DataItem {

	@NSManaged var assignedToMe: Bool
	@NSManaged var assigneeName: String?
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

	final func baseSync(from info: [NSObject: AnyObject], in repo: Repo) {

		self.repo = repo

		url = info["url"] as? String
		webUrl = info["html_url"] as? String
		number = (info["number"] as? NSNumber)?.int64Value ?? 0
		state = info["state"] as? String
		title = info["title"] as? String
		body = info["body"] as? String
		milestone = info["milestone"]?["title"] as? String

		if let userInfo = info["user"] as? [NSObject: AnyObject] {
			userId = (userInfo["id"] as? NSNumber)?.int64Value ?? 0
			userLogin = userInfo["login"] as? String
			userAvatarUrl = userInfo["avatar_url"] as? String
		}

		if let assignee = info["assignee"] as? [NSObject: AnyObject], let name = assignee["login"] as? String, let id = assignee["id"] as? NSNumber {
			let currentlyAssigned = id.int64Value == repo.apiServer.userId
			isNewAssignment = currentlyAssigned && !assignedToMe && !createdByMe
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
		if Settings.removeNotificationsWhenItemIsRemoved {
			ListableItem.removeRelatedNotifications(uri: objectID.uriRepresentation().absoluteString)
		}
	}

	final func sortedComments(using comparison: ComparisonResult) -> [PRComment] {
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
				if b.localizedCaseInsensitiveContains(t) {
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
			app.postNotification(type: notification, for: self)
		}
	}

	private final var shouldMoveToSnoozing: Bool {
		if snoozeUntil == nil {
			let d = TimeInterval(Settings.autoSnoozeDuration)
			if d > 0 && !wasAwokenFromSnooze && updatedAt != NSDate.distantPast, let snoozeByDate = updatedAt?.addingTimeInterval(86400.0*d) {
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
			&& contains(terms: ["@\(apiServer.userName!)"]) {

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

			var latestDate = latestReadCommentDate ?? Date.distantPast

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
			f.predicate = predicateForOthersComments(since: latestReadCommentDate)
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
						NSParagraphStyleAttributeName: lp]
					#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize+6.0
						let labelAttributes = [NSFontAttributeName: labelFont,
							NSBaselineOffsetAttributeName: 1.0,
							NSParagraphStyleAttributeName: lp]
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

	final private func predicateForMyComments(since optionalDate: Date?) -> NSPredicate {

		if self is PullRequest {
			if let date = optionalDate {
				return NSPredicate(format: "userId == %lld and pullRequest == %@ and createdAt > %@", apiServer.userId, self, date)
			} else {
				return NSPredicate(format: "userId == %lld and pullRequest == %@", apiServer.userId, self)
			}
		} else {
			if let date = optionalDate {
				return NSPredicate(format: "userId == %lld and issue == %@ and createdAt > %@", apiServer.userId, self, date)
			} else {
				return NSPredicate(format: "userId == %lld and issue == %@", apiServer.userId, self)
			}
		}
	}

	final private func predicateForOthersComments(since optionalDate: Date?) -> NSPredicate {

		if self is PullRequest {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", apiServer.userId, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and pullRequest == %@", apiServer.userId, self)
			}
		} else {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", apiServer.userId, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and issue == %@", apiServer.userId, self)
			}
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

	final class func buildOrPredicate(fromFilter string: String, expectedLength: Int, format: String, numeric: Bool) -> NSPredicate? {
		if string.characters.count > expectedLength {
			let items = string.substring(from: string.index(string.startIndex, offsetBy: expectedLength))
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

	final class func serverPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 7, format: "apiServer.label contains[cd] %@", numeric: false)
	}

	final class func titlePredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 6, format: "title contains[cd] %@", numeric: false)
	}

	final class func milestonePredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 10, format: "milestone contains[cd] %@", numeric: false)
	}

	final class func assigneePredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 9, format: "assigneeName contains[cd] %@", numeric: false)
	}

	final class func numberPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 7, format: "number == %llu", numeric: true)
	}

    final class func repoPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 5, format: "repo.fullName contains[cd] %@", numeric: false)
    }

    final class func labelPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 6, format: "SUBQUERY(labels, $label, $label.name contains[cd] %@).@count > 0", numeric: false)
    }

    final class func statusPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 7, format: "SUBQUERY(statuses, $status, $status.descriptionText contains[cd] %@).@count > 0", numeric: false)
    }

    final class func userPredicate(fromFilter string: String) -> NSPredicate? {
		return buildOrPredicate(fromFilter: string, expectedLength: 5, format: "userLogin contains[cd] %@", numeric: false)
    }

	final class func requestForItems(ofType itemType: String, withFilter: String?, sectionIndex: Int64, criterion: GroupingCriterion? = nil, onlyUnread: Bool = false) -> NSFetchRequest<ListableItem> {

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

            func check(forPredicate tagString: String, _ process: (String)->NSPredicate?) {
				var foundOne: Bool
				repeat {
					foundOne = false
					for word in fi.components(separatedBy: " ") {
						if word.hasPrefix("\(tagString):") {
							if let p = process(word) {
								andPredicates.append(p)
							}
							fi = fi.replacingOccurrences(of: word, with: "")
							fi = fi.trim
							foundOne = true
							break
						}
					}
				} while(foundOne)
            }

			check(forPredicate: "title", titlePredicate)
            check(forPredicate: "server", serverPredicate)
            check(forPredicate: "repo", repoPredicate)
            check(forPredicate: "label", labelPredicate)
            check(forPredicate: "status", statusPredicate)
            check(forPredicate: "user", userPredicate)
			check(forPredicate: "number", numberPredicate)
			check(forPredicate: "milestone", milestonePredicate)
			check(forPredicate: "assignee", assigneePredicate)

			if !fi.isEmpty {
				var orPredicates = [NSPredicate]()
				let negative = fi.hasPrefix("!")

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

		let f = NSFetchRequest<ListableItem>(entityName: itemType)
		f.fetchBatchSize = 100
		let p = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: mainObjectContext)
		f.sortDescriptors = sortDescriptors
		return f
	}

	final class func relatedItems(from notificationUserInfo: [NSObject : AnyObject]) -> (PRComment?, ListableItem)? {
		var item: ListableItem?
		var comment: PRComment?
		if let cid = notificationUserInfo[COMMENT_ID_KEY] as? String, let itemId = DataManager.id(for: cid), let c = existingObject(with: itemId) as? PRComment {
			comment = c
			item = c.pullRequest ?? c.issue
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
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + (repo.fullName?.components(separatedBy: "/") ?? [])
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
			_ = api.haveCachedAvatar(from: i) { _, cachePath in
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

		var color = COLOR_CLASS.lightGray
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokens(in: mainObjectContext) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if appIsRefreshing {
			message = "Refreshing information, please wait a moment..."
		} else if !S(filterValue).isEmpty {
			message = "There are no items matching this filter."
		} else if openItemCount > 0 {
			message = "Some items are hidden by your settings."
		} else if !Repo.anyVisibleRepos(in: mainObjectContext, criterion: criterion, excludeGrouped: true) {
			if Repo.anyVisibleRepos(in: mainObjectContext) {
				message = "There are no repositories that are currently visible in this category."
			} else {
				color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
				message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
			}
		} else if !Repo.interestedInPrs(fromServerWithId: criterion?.apiServerId) && !Repo.interestedInIssues(fromServerWithId: criterion?.apiServerId) {
			color = COLOR_CLASS(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs on at least one."
		} else if openItemCount==0 {
			message = "No open items in your configured repositories."
		}

		return styleForEmpty(message: message, color: color)
	}
}
