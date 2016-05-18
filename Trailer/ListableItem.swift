
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
	@NSManaged var latestReadCommentDate: NSDate?
	@NSManaged var state: String?
	@NSManaged var reopened: NSNumber?
	@NSManaged var number: NSNumber?
	@NSManaged var announced: NSNumber?
	@NSManaged var muted: NSNumber?
	@NSManaged var snoozeUntil: NSDate?
	@NSManaged var milestone: String?

	@NSManaged var comments: Set<PRComment>
	@NSManaged var labels: Set<PRLabel>

	final func baseSyncFromInfo(info: [NSObject: AnyObject], inRepo: Repo) {

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

		if let assignee = info["assignee"] as? [NSObject: AnyObject], name = assignee["login"] as? String, id = assignee["id"] as? NSNumber {
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
			CSSearchableIndex.defaultSearchableIndex().deleteSearchableItemsWithIdentifiers([objectID.URIRepresentation().absoluteString], completionHandler: nil)
		#endif
		#if os(OSX)
			if Settings.removeNotificationsWhenItemIsRemoved {
				removeRelatedNotifications()
			}
		#endif
	}

	final func sortedComments(comparison: NSComparisonResult) -> [PRComment] {
		return Array(comments).sort({ (c1, c2) -> Bool in
			let d1 = c1.createdAt ?? never()
			let d2 = c2.createdAt ?? never()
			return d1.compare(d2) == comparison
		})
	}

	final func catchUpWithComments() {
		for c in comments {
			if let creation = c.createdAt {
				if let latestRead = latestReadCommentDate {
					if latestRead.compare(creation) == .OrderedAscending {
						latestReadCommentDate = creation
					}
				} else {
					latestReadCommentDate = creation
				}
			}
		}
		postProcess()
	}

	final func shouldKeepForPolicy(policy: Int) -> Bool {
		let index = (sectionIndex?.integerValue ?? 0)
		return policy==HandlingPolicy.KeepAll.rawValue
			|| (policy==HandlingPolicy.KeepMineAndParticipated.rawValue && (index==Section.Mine.rawValue || index==Section.Participated.rawValue))
			|| (policy==HandlingPolicy.KeepMine.rawValue && index==Section.Mine.rawValue)
	}

	final var shouldSkipNotifications: Bool {
		return isSnoozing || (muted?.boolValue ?? false)
	}

	final var assignedToMySection: Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==AssignmentPolicy.MoveToMine.rawValue
	}

	final var assignedToParticipated: Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==AssignmentPolicy.MoveToParticipated.rawValue
	}

	final var createdByMe: Bool {
		if let userId = userId, apiId = apiServer.userId {
			return userId == apiId
		}
		return false
	}

	final var refersToMe: Bool {
		if let apiName = apiServer.userName, b = body {
			let range = b.rangeOfString("@"+apiName, options: [.CaseInsensitiveSearch, .DiacriticInsensitiveSearch])
			return range != nil
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
					let range = b.rangeOfString(r, options: [.CaseInsensitiveSearch, .DiacriticInsensitiveSearch])
					if range != nil { return true }
				}
			}
		}
		return false
	}

	final var isVisibleOnMenu: Bool {
		return self.sectionIndex?.integerValue != Section.None.rawValue
	}

	final var showNewComments: Bool {
		return Settings.showCommentsEverywhere || sectionIndex?.integerValue == Section.Mine.rawValue || sectionIndex?.integerValue == Section.Participated.rawValue || sectionIndex?.integerValue == Section.Mentioned.rawValue
	}

	final func wakeUp() {
		snoozeUntil = nil
		postProcess()
	}

	final var isSnoozing: Bool {
		return snoozeUntil != nil
	}

	final func keepWithCondition(newCondition: ItemCondition, notification: NotificationType) {
		postSyncAction = PostSyncAction.DoNothing.rawValue
		condition = newCondition.rawValue
		if snoozeUntil != nil {
			snoozeUntil = nil
		} else {
			app.postNotificationOfType(notification, forItem: self)
		}
	}

	final func postProcess() {

		if let s = snoozeUntil where s.compare(NSDate()) == .OrderedAscending {
			snoozeUntil = nil
		}

		let isMine = createdByMe
		var targetSection: Section
		let currentCondition = condition?.integerValue ?? ItemCondition.Open.rawValue

		if currentCondition == ItemCondition.Merged.rawValue		{ targetSection = .Merged }
		else if currentCondition == ItemCondition.Closed.rawValue	{ targetSection = .Closed }
		else if snoozeUntil != nil									{ targetSection = .Snoozed }
		else if isMine || assignedToMySection						{ targetSection = .Mine }
		else if assignedToParticipated || commentedByMe				{ targetSection = .Participated }
		else														{ targetSection = .All }

		let outsideMySectionsButAwake = (targetSection == .All || targetSection == .None)
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

		let f = NSFetchRequest(entityName: "PRComment")
		f.returnsObjectsAsFaults = false

		let latestDate = latestReadCommentDate
		let isMuted = muted?.boolValue ?? false

		if moveToMentioned {
			targetSection = .Mentioned
			if isMuted {
				unreadComments = 0
			} else {
				f.predicate = predicateForOthersCommentsSinceDate(latestDate)
				unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
			}
		} else if doReferralCheckInComments {
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount: Int = 0
			for c in try! managedObjectContext?.executeFetchRequest(f) as! [PRComment] {
				if (autoMoveOnCommentMentions && c.refersToMe) || (autoMoveOnTeamMentions && c.refersToMyTeams) {
					targetSection = .Mentioned
				}
				if !isMuted {
					if let l = latestDate {
						if c.createdAt?.compare(l) == .OrderedDescending {
							unreadCommentCount += 1
						}
					} else {
						unreadCommentCount += 1;
					}
				}
			}
			unreadComments = unreadCommentCount
		} else {
			if isMuted {
				unreadComments = 0
			} else {
				f.predicate = predicateForOthersCommentsSinceDate(latestDate)
				unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
			}
		}

		totalComments = comments.count

		let policy = (self is Issue ? repo.displayPolicyForIssues : repo.displayPolicyForPrs)?.integerValue ?? 0
		if let displayPolicy = RepoDisplayPolicy(rawValue: policy) {
			switch displayPolicy {
			case .Hide:
				targetSection = .None
			case .Mine:
				if targetSection == .All || targetSection == .Participated || targetSection == .Mentioned {
					targetSection = .None
				}
			case .MineAndPaticipated:
				if targetSection == .All {
					targetSection = .None
				}
			case .All:
				break
			}
		}

		if let hidePolicy = RepoHidingPolicy(rawValue: repo.itemHidingPolicy?.integerValue ?? 0) {
			switch hidePolicy {
			case .NoHiding:
				break
			case .HideMyAuthoredPrs:
				if isMine && self is PullRequest {
					targetSection = .None
				}
			case .HideMyAuthoredIssues:
				if isMine && self is Issue {
					targetSection = .None
				}
			case .HideAllMyAuthoredItems:
				if isMine {
					targetSection = .None
				}
			case .HideOthersPrs:
				if !isMine && self is PullRequest {
					targetSection = .None
				}
			case .HideOthersIssues:
				if !isMine && self is Issue {
					targetSection = .None
				}
			case .HideAllOthersItems:
				if !isMine {
					targetSection = .None
				}
			}
		}

		if targetSection != .None, let p = self as? PullRequest where p.shouldBeCheckedForRedStatusesInSection(targetSection) {
			for s in p.displayedStatuses {
				if s.state != "success" {
					targetSection = .None
					break
				}
			}
		}

		sectionIndex = targetSection.rawValue

		if title==nil { title = "(No title)" }
	}

	final func urlForOpening() -> String? {
		let unreadCount = unreadComments?.integerValue ?? 0

		if unreadCount > 0 && Settings.openPrAtFirstUnreadComment {
			let f = NSFetchRequest(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.fetchLimit = 1
			f.predicate = predicateForOthersCommentsSinceDate(latestReadCommentDate)
			f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
			let ret = try! managedObjectContext?.executeFetchRequest(f) as! [PRComment]
			if let firstComment = ret.first, url = firstComment.webUrl {
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
		return components.joinWithSeparator(",")
	}

	final func sortedLabels() -> [PRLabel] {
		return Array(labels).sort({ (l1: PRLabel, l2: PRLabel) -> Bool in
			return l1.name!.compare(l2.name!) == .OrderedAscending
		})
	}

	final func titleWithFont(font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS) -> NSMutableAttributedString {
		let p = NSMutableParagraphStyle()
		p.paragraphSpacing = 1.0

		let titleAttributes = [NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor, NSParagraphStyleAttributeName: p]
		let _title = NSMutableAttributedString()
		if let t = title {
			_title.appendAttributedString(NSAttributedString(string: t, attributes: titleAttributes))
			if Settings.showLabels {
				let labelCount = labels.count
				if labelCount > 0 {

					_title.appendAttributedString(NSAttributedString(string: "\n", attributes: titleAttributes))

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
						a[NSForegroundColorAttributeName] = isDarkColor(color) ? COLOR_CLASS.whiteColor() : COLOR_CLASS.blackColor()
						let name = l.name!.stringByReplacingOccurrencesOfString(" ", withString: "\u{a0}")
						_title.appendAttributedString(NSAttributedString(string: "\u{a0}", attributes: a))
						_title.appendAttributedString(NSAttributedString(string: name, attributes: a))
						_title.appendAttributedString(NSAttributedString(string: "\u{a0}", attributes: a))
						if count < labelCount-1 {
							_title.appendAttributedString(NSAttributedString(string: " ", attributes: labelAttributes))
                        }
                        count += 1
					}
				}
			}
		}
		return _title
	}

	class final func emptyMessage(message: String, color: COLOR_CLASS) -> NSAttributedString {
		let p = NSMutableParagraphStyle()
		p.lineBreakMode = .ByWordWrapping
		p.alignment = .Center
		#if os(OSX)
			return NSAttributedString(string: message, attributes: [
				NSForegroundColorAttributeName: color,
				NSParagraphStyleAttributeName: p
			])
		#elseif os(iOS)
			return NSAttributedString(string: message, attributes: [
				NSForegroundColorAttributeName: color,
				NSParagraphStyleAttributeName: p,
				NSFontAttributeName: FONT_CLASS.systemFontOfSize(FONT_CLASS.smallSystemFontSize())
			])
		#endif
	}

	final func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {

		let userNumber = apiServer.userId?.longLongValue ?? 0

		if self is Issue {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and issue == %@", userNumber, self)
			}
		} else if self is PullRequest {
			if let date = optionalDate {
				return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", userNumber, self, date)
			} else {
				return NSPredicate(format: "userId != %lld and pullRequest == %@", userNumber, self)
			}
		} else {
			abort()
		}
	}

	final class func badgeCountFromFetch(f: NSFetchRequest, inMoc: NSManagedObjectContext) -> Int {
		var badgeCount:Int = 0
		for i in try! inMoc.executeFetchRequest(f) as! [ListableItem] {
			if i.showNewComments {
				badgeCount += (i.unreadComments?.integerValue ?? 0)
			}
		}
		return badgeCount
	}

	final class func buildOrPredicate(string: String, expectedLength: Int, format: String, numeric: Bool) -> NSPredicate? {
		if string.characters.count > expectedLength {
			let items = string.substringFromIndex(string.startIndex.advancedBy(expectedLength))
			if !items.characters.isEmpty {
				var orTerms = [NSPredicate]()
				var notTerms = [NSPredicate]()
				for term in items.componentsSeparatedByString(",") {
					let T: String
					let negative: Bool
					if term.characters.first == "!" {
						T = term.substringFromIndex(term.startIndex.advancedBy(1))
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

	final class func serverPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "apiServer.label contains[cd] %@", numeric: false)
	}

	final class func titlePredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 6, format: "title contains[cd] %@", numeric: false)
	}

	final class func milestonePredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 10, format: "milestone contains[cd] %@", numeric: false)
	}

	final class func assigneePredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 9, format: "assigneeName contains[cd] %@", numeric: false)
	}

	final class func numberPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "number == %llu", numeric: true)
	}

    final class func repoPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 5, format: "repo.fullName contains[cd] %@", numeric: false)
    }

    final class func labelPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 6, format: "SUBQUERY(labels, $label, $label.name contains[cd] %@).@count > 0", numeric: false)
    }

    final class func statusPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 7, format: "SUBQUERY(statuses, $status, $status.descriptionText contains[cd] %@).@count > 0", numeric: false)
    }

    final class func userPredicateFromFilterString(string: String) -> NSPredicate? {
		return buildOrPredicate(string, expectedLength: 5, format: "userLogin contains[cd] %@", numeric: false)
    }

	final class func requestForItemsOfType(itemType: String, withFilter: String?, sectionIndex: Int) -> NSFetchRequest {

		var andPredicates = [NSPredicate]()
		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex))
		}

		if Settings.hideSnoozedItems {
			andPredicates.append(NSPredicate(format: "sectionIndex != %d", Section.Snoozed.rawValue))
		}

		if var fi = withFilter where !fi.isEmpty {

            func checkForPredicates(tagString: String, _ process: String->NSPredicate?) {
				var foundOne: Bool
				repeat {
					foundOne = false
					for word in fi.componentsSeparatedByString(" ") {
						if word.characters.startsWith((tagString+":").characters) {
							if let p = process(word) {
								andPredicates.append(p)
							}
							fi = fi.stringByReplacingOccurrencesOfString(word, withString: "")
							fi = fi.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
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

				func checkOr(format: String, numeric: Bool) {
					let predicate: NSPredicate
					let string = negative ? fi.substringFromIndex(fi.startIndex.advancedBy(1)) : fi
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

		let f = NSFetchRequest(entityName: itemType)
		f.fetchBatchSize = 100
		f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		f.sortDescriptors = sortDescriptors
		return f
	}

	final class func relatedItemsFromNotificationInfo(userInfo: [String : AnyObject?]) -> (PRComment?, ListableItem)? {
		var item: ListableItem?
		var comment: PRComment?
		if let itemId = DataManager.idForUriPath(userInfo[COMMENT_ID_KEY] as? String), c = existingObjectWithID(itemId) as? PRComment {
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

	final func setMute(mute: Bool) {
		muted = mute
		postProcess()
		if mute {
			removeRelatedNotifications()
		}
	}

	final func removeRelatedNotifications() {
		#if os(OSX)
		let nc = NSUserNotificationCenter.defaultUserNotificationCenter()
		for n in nc.deliveredNotifications {
			if let u = n.userInfo, (_, item) = ListableItem.relatedItemsFromNotificationInfo(u) where item.serverId == serverId {
				nc.removeDeliveredNotification(n)
			}
		}
		#endif
		// iOS won't allow access notifications after presenting if the app gets restarted, so behaviour of this would be inconsistent.
	}

	#if os(iOS)
	var searchKeywords: [String] {
		let labelNames = labels.flatMap { $0.name }
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + (repo.fullName?.componentsSeparatedByString("/") ?? [])
	}
	final func searchTitle() -> String {
		let labelNames = labels.flatMap { $0.name }
		var suffix = ""
		if labelNames.count > 0 {
			for l in labelNames {
				suffix += " ["+l+"]"
			}
		}
		return "#\(self.number ?? 0) - " + (title ?? "NO TITLE") + suffix
	}
	final func indexForSpotlight() {
		let s = CSSearchableItemAttributeSet(itemContentType: kUTTypeText as String)
		s.title = searchTitle()
		s.contentCreationDate = createdAt
		s.contentModificationDate = updatedAt
		s.keywords = searchKeywords
		s.creator = userLogin

		s.contentDescription = S(repo.fullName) +
			" @" + S(userLogin) +
			" - " + S(body?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()))

		func completeIndex(s: CSSearchableItemAttributeSet) {
			let i = CSSearchableItem(uniqueIdentifier:objectID.URIRepresentation().absoluteString, domainIdentifier: nil, attributeSet: s)
			CSSearchableIndex.defaultSearchableIndex().indexSearchableItems([i], completionHandler: nil)
		}

		if let i = self.userAvatarUrl where !Settings.hideAvatars {
			api.haveCachedAvatar(i) { _, cachePath in
				s.thumbnailURL = NSURL(string: "file://"+cachePath)
				completeIndex(s)
			}
		} else {
			s.thumbnailURL = nil
			completeIndex(s)
		}
	}
	#endif
}
