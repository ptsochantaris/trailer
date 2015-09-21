
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
			|| (policy==PRHandlingPolicy.KeepMineAndParticipated.rawValue && (index==PullRequestSection.Mine.rawValue || index==PullRequestSection.Participated.rawValue))
			|| (policy==PRHandlingPolicy.KeepMine.rawValue && index==PullRequestSection.Mine.rawValue)
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
		return self.sectionIndex?.integerValue != PullRequestSection.None.rawValue
	}

	final func showNewComments() -> Bool {
		return Settings.showCommentsEverywhere || sectionIndex?.integerValue == PullRequestSection.Mine.rawValue || sectionIndex?.integerValue == PullRequestSection.Participated.rawValue
	}

	final func postProcess() {
		var targetSection: PullRequestSection
		let currentCondition = condition?.integerValue ?? PullRequestCondition.Open.rawValue

		if currentCondition == PullRequestCondition.Merged.rawValue			{ targetSection = PullRequestSection.Merged }
		else if currentCondition == PullRequestCondition.Closed.rawValue	{ targetSection = PullRequestSection.Closed }
		else if createdByMe() || assignedToMySection()						{ targetSection = PullRequestSection.Mine }
		else if assignedToParticipated() || commentedByMe()					{ targetSection = PullRequestSection.Participated }
		else																{ targetSection = PullRequestSection.All }

		var needsManualCount = false
		var moveToParticipated = false
		let outsideMySections = (targetSection == PullRequestSection.All || targetSection == PullRequestSection.None)

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

		if moveToParticipated {
			targetSection = PullRequestSection.Participated
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
		} else if needsManualCount {
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount: Int = 0
			for c in try! managedObjectContext?.executeFetchRequest(f) as! [PRComment] {
				if c.refersToMe() {
					targetSection = PullRequestSection.Participated
				}
				if let l = latestDate {
					if c.createdAt?.compare(l)==NSComparisonResult.OrderedDescending {
						unreadCommentCount++
					}
				} else {
					unreadCommentCount++;
				}
			}
			unreadComments = unreadCommentCount
		} else {
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
		}

		totalComments = comments.count

		if let displayPolicy = RepoDisplayPolicy(rawValue: self is Issue ? (repo.displayPolicyForIssues?.integerValue ?? 0) : (repo.displayPolicyForPrs?.integerValue ?? 0)) {
			switch displayPolicy {
			case .Hide:
				targetSection = PullRequestSection.None
			case .Mine:
				if targetSection == PullRequestSection.All || targetSection == PullRequestSection.Participated {
					targetSection = PullRequestSection.None
				}
			case .MineAndPaticipated:
				if targetSection == PullRequestSection.All {
					targetSection = PullRequestSection.None
				}
			case .All:
				break
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
                        count++
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
				if showCommentsEverywhere || sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue {
					if let c = i.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	final class func serverPredicateFromFilterString(string: String) -> NSPredicate? {
		if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 7 {
			let serverNames = string.substringFromIndex(string.startIndex.advancedBy(7))
			if !serverNames.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in serverNames.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "apiServer.label contains [cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
			}
		}
		return nil
	}

	final class func titlePredicateFromFilterString(string: String) -> NSPredicate? {
		if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 6 {
			let titleTerms = string.substringFromIndex(string.startIndex.advancedBy(6))
			if !titleTerms.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in titleTerms.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "title contains [cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
			}
		}
		return nil
	}

    final class func repoPredicateFromFilterString(string: String) -> NSPredicate? {
        if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 5 {
            let repoNames = string.substringFromIndex(string.startIndex.advancedBy(5))
            if !repoNames.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in repoNames.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "repo.fullName contains [cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
            }
        }
        return nil
    }

    final class func labelPredicateFromFilterString(string: String) -> NSPredicate? {
        if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 6 {
            let labelNames = string.substringFromIndex(string.startIndex.advancedBy(6))
            if !labelNames.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in labelNames.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "any labels.name contains[cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
            }
        }
        return nil
    }

    final class func statusPredicateFromFilterString(string: String) -> NSPredicate? {
        if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 7 {
            let statusNames = string.substringFromIndex(string.startIndex.advancedBy(7))
            if !statusNames.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in statusNames.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "any statuses.descriptionText contains[cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
            }
        }
        return nil
    }

    final class func userPredicateFromFilterString(string: String) -> NSPredicate? {
        if string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 5 {
            let userNames = string.substringFromIndex(string.startIndex.advancedBy(5))
            if !userNames.characters.isEmpty {
				var orTerms = [NSPredicate]()
				for term in userNames.componentsSeparatedByString(",") {
					orTerms.append(NSPredicate(format: "userLogin contains[cd] %@", term))
				}
				return NSCompoundPredicate(type: NSCompoundPredicateType.OrPredicateType, subpredicates: orTerms)
            }
        }
        return nil
    }

	final class func requestForItemsOfType(itemType: String, withFilter: String?, sectionIndex: Int) -> NSFetchRequest {

		var andPredicates = [NSPredicate]()
		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex))
		}

		if let f = withFilter where !f.isEmpty {

			var fi = f

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

			if !fi.isEmpty {
				var orPredicates = [NSPredicate]()
				if Settings.includeTitlesInFilter {
					orPredicates.append(NSPredicate(format: "title contains[cd] %@", fi))
				}
				if Settings.includeReposInFilter {
					orPredicates.append(NSPredicate(format: "repo.fullName contains[cd] %@", fi))
				}
				if Settings.includeLabelsInFilter {
					orPredicates.append(NSPredicate(format: "any labels.name contains[cd] %@", fi))
				}
                if Settings.includeServersInFilter {
                    orPredicates.append(NSPredicate(format: "apiServer.label contains [cd] %@", fi))
                }
                if Settings.includeUsersInFilter {
                    orPredicates.append(NSPredicate(format: "userLogin contains[cd] %@", fi))
                }
				if itemType == "PullRequest" && Settings.includeStatusesInFilter {
					orPredicates.append(NSPredicate(format: "any statuses.descriptionText contains[cd] %@", fi))
				}
				andPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: orPredicates))
			}
		}

		if Settings.hideUncommentedItems {
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
		}

		var sortDescriptiors = [NSSortDescriptor]()
		sortDescriptiors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))
		if Settings.groupByRepo {
			sortDescriptiors.append(NSSortDescriptor(key: "repo.fullName", ascending: true, selector: Selector("caseInsensitiveCompare:")))
		}

		if let fieldName = sortField() {
			if fieldName == "title" {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending, selector: Selector("caseInsensitiveCompare:")))
			} else if !fieldName.isEmpty {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending))
			}
		}

		let f = NSFetchRequest(entityName: itemType)
		f.fetchBatchSize = 100
		f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		f.sortDescriptors = sortDescriptiors
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
		return (title ?? "NO TITLE") + suffix
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
