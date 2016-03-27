
import CoreData
#if os(iOS)
	import UIKit
	import CoreSpotlight
	import MobileCoreServices
#endif

class ListableItem: DataItem {

	@NSManaged var assignedToMe: NSNumber?
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

	@NSManaged var comments: Set<PRComment>
	@NSManaged var labels: Set<PRLabel>

	final override func resetSyncState() {
		super.resetSyncState()
		repo.resetSyncState()
	}

	final override func prepareForDeletion() {
		api.refreshesSinceLastLabelsCheck[objectID] = nil
		api.refreshesSinceLastStatusCheck[objectID] = nil
		#if os(iOS)
		deIndexFromSpotlight()
		#endif
		super.prepareForDeletion()
	}

	final class func sortField() -> String? {
		switch (Settings.sortMethod) {
		case PRSortingMethod.CreationDate.rawValue: return "createdAt"
		case PRSortingMethod.RecentActivity.rawValue: return "updatedAt"
		case PRSortingMethod.Title.rawValue: return "title"
		default: return nil
		}
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
					if latestRead.compare(creation) == NSComparisonResult.OrderedAscending {
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
		return policy==PRHandlingPolicy.KeepAll.rawValue
			|| (policy==PRHandlingPolicy.KeepMineAndParticipated.rawValue && (index==Section.Mine.rawValue || index==Section.Participated.rawValue))
			|| (policy==PRHandlingPolicy.KeepMine.rawValue && index==Section.Mine.rawValue)
	}

	final func assignedToMySection() -> Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==PRAssignmentPolicy.MoveToMine.rawValue
	}

	final func assignedToParticipated() -> Bool {
		return (assignedToMe?.boolValue ?? false) && Settings.assignedPrHandlingPolicy==PRAssignmentPolicy.MoveToParticipated.rawValue
	}

	final func createdByMe() -> Bool {
		if let userId = userId, apiId = apiServer.userId {
			return userId == apiId
		}
		return false
	}

	final func refersToMe() -> Bool {
		if let apiName = apiServer.userName, b = body {
			let range = b.rangeOfString("@"+apiName, options: [NSStringCompareOptions.CaseInsensitiveSearch, NSStringCompareOptions.DiacriticInsensitiveSearch])
			return range != nil
		}
		return false
	}

	final func commentedByMe() -> Bool {
		for c in comments {
			if c.isMine() {
				return true
			}
		}
		return false
	}

	final func refersToMyTeams() -> Bool {
		if let b = body {
			for t in apiServer.teams {
				if let r = t.calculatedReferral {
					let range = b.rangeOfString(r, options: [NSStringCompareOptions.CaseInsensitiveSearch, NSStringCompareOptions.DiacriticInsensitiveSearch])
					if range != nil { return true }
				}
			}
		}
		for c in comments {
			if c.refersToMyTeams() {
				return true
			}
		}
		return false
	}

	final func isVisibleOnMenu() -> Bool {
		return self.sectionIndex?.integerValue != Section.None.rawValue
	}

	final func showNewComments() -> Bool {
		return Settings.showCommentsEverywhere || sectionIndex?.integerValue == Section.Mine.rawValue || sectionIndex?.integerValue == Section.Participated.rawValue
	}

	final func postProcess() {
		var targetSection: Section
		let currentCondition = condition?.integerValue ?? PullRequestCondition.Open.rawValue
		let isMine = createdByMe()

		if currentCondition == PullRequestCondition.Merged.rawValue			{ targetSection = .Merged }
		else if currentCondition == PullRequestCondition.Closed.rawValue	{ targetSection = .Closed }
		else if isMine || assignedToMySection()								{ targetSection = .Mine }
		else if assignedToParticipated() || commentedByMe()					{ targetSection = .Participated }
		else																{ targetSection = .All }

		var needsManualCount = false
		var moveToParticipated = false
		let outsideMySections = (targetSection == .All || targetSection == .None)

		if outsideMySections && Settings.autoParticipateOnTeamMentions {
			if refersToMyTeams() {
				moveToParticipated = true
			} else {
				needsManualCount = true
			}
		}

		if !moveToParticipated && outsideMySections && Settings.autoParticipateInMentions {
			if refersToMe() {
				moveToParticipated = true
			} else {
				needsManualCount = true
			}
		}

		let f = NSFetchRequest(entityName: "PRComment")
		f.returnsObjectsAsFaults = false
		let latestDate = latestReadCommentDate

		let isMuted = muted?.boolValue ?? false

		if moveToParticipated {
			targetSection = .Participated
			if isMuted {
				unreadComments = 0
			} else {
				f.predicate = predicateForOthersCommentsSinceDate(latestDate)
				unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
			}
		} else if needsManualCount {
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount: Int = 0
			if !isMuted {
				for c in try! managedObjectContext?.executeFetchRequest(f) as! [PRComment] {
					if c.refersToMe() {
						targetSection = .Participated
					}
					if let l = latestDate {
						if c.createdAt?.compare(l)==NSComparisonResult.OrderedDescending {
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

		if let displayPolicy = RepoDisplayPolicy(rawValue: self is Issue ? (repo.displayPolicyForIssues?.integerValue ?? 0) : (repo.displayPolicyForPrs?.integerValue ?? 0)) {
			switch displayPolicy {
			case .Hide:
				targetSection = .None
			case .Mine:
				if targetSection == .All || targetSection == .Participated {
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
			for s in p.displayedStatuses() {
				if s.state != "success" {
					targetSection = Section.None
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
			return l1.name!.compare(l2.name!)==NSComparisonResult.OrderedAscending
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
						let color = l.colorForDisplay()
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
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for i in try! inMoc.executeFetchRequest(f) as! [ListableItem] {
			if let sectionIndex = i.sectionIndex?.integerValue {
				if showCommentsEverywhere || sectionIndex==Section.Mine.rawValue || sectionIndex==Section.Participated.rawValue {
					if let c = i.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	final class func buildOrPredicate(string: String, expectedLength: Int, format: String, numeric: Bool) -> NSPredicate? {
		if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > expectedLength {
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

		if let fieldName = sortField() {
			if fieldName == "title" {
				sortDescriptors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending, selector: #selector(NSString.caseInsensitiveCompare(_:))))
			} else if !fieldName.isEmpty {
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

	#if os(iOS)
	func searchKeywords() -> [String] {
		var labelNames = [String]()
		for l in labels {
			if let l = l.name {
				labelNames.append(l)
			}
		}
		return [(userLogin ?? "NO_USERNAME"), "Trailer", "PocketTrailer", "Pocket Trailer"] + labelNames + (repo.fullName?.componentsSeparatedByString("/") ?? [])
	}
	final func searchTitle() -> String {
		var labelNames = [String]()
		for l in labels {
			if let l = l.name {
				labelNames.append(l)
			}
		}
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
		s.keywords = searchKeywords()
		s.creator = userLogin

		s.contentDescription = (repo.fullName ?? "") +
			" @" + (userLogin ?? "") +
			" - " + (body?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) ?? "")

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
	final func deIndexFromSpotlight() {
		CSSearchableIndex.defaultSearchableIndex().deleteSearchableItemsWithIdentifiers([objectID.URIRepresentation().absoluteString], completionHandler: nil)
	}
	#endif
}
