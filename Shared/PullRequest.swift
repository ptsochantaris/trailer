
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PullRequest: ListableItem {

	@NSManaged var issueCommentLink: String?
	@NSManaged var issueUrl: String?
	@NSManaged var mergeable: NSNumber?
	@NSManaged var pinned: NSNumber?
	@NSManaged var reviewCommentLink: String?
	@NSManaged var statusesLink: String?
	@NSManaged var lastStatusNotified: String?

	@NSManaged var statuses: Set<PRStatus>

	class func syncPullRequestsFromInfoArray(data: [[NSObject : AnyObject]]?, inRepo: Repo) {
		itemsWithInfo(data, type: "PullRequest", fromServer: inRepo.apiServer) { item, info, isNewOrUpdated in
			let p = item as! PullRequest
			if isNewOrUpdated {

				p.baseSyncFromInfo(info, inRepo: inRepo)

				p.mergeable = info["mergeable"] as? NSNumber ?? true

				if let linkInfo = info["_links"] as? [NSObject : AnyObject] {
					p.issueCommentLink = linkInfo["comments"]?["href"] as? String
					p.reviewCommentLink = linkInfo["review_comments"]?["href"] as? String
					p.statusesLink = linkInfo["statuses"]?["href"] as? String
					p.issueUrl = linkInfo["issue"]?["href"] as? String
				}

				api.refreshesSinceLastLabelsCheck[p.objectID] = nil
				api.refreshesSinceLastStatusCheck[p.objectID] = nil
			}
			p.reopened = ((p.condition?.integerValue ?? 0) == ItemCondition.Closed.rawValue)
			p.condition = ItemCondition.Open.rawValue
		}
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["PR","Pull Request","PRs","Pull Requests"] + super.searchKeywords
	}
	#endif

	class func activeInMoc(moc: NSManagedObjectContext, visibleOnly: Bool) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		if visibleOnly {
			f.predicate = NSPredicate(format: "sectionIndex == %d || sectionIndex == %d || sectionIndex == %d", Section.Mine.rawValue, Section.Participated.rawValue, Section.All.rawValue)
		} else {
			f.predicate = NSPredicate(format: "condition == %d", ItemCondition.Open.rawValue)
		}
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func allMergedInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", ItemCondition.Merged.rawValue)
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func allClosedInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", ItemCondition.Closed.rawValue)
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func countOpenInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "condition == %d or condition == nil", ItemCondition.Open.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countOpenAndVisibleInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex > 0 and (condition == %d or condition == nil)", ItemCondition.Open.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countAllInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex > 0")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countRequestsInSection(section: Section, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func markEverythingRead(section: Section, moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "PullRequest")
		if section != .None {
			f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		}
		for pr in try! moc.executeFetchRequest(f) as! [PullRequest] {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInSection(section: Section, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: -1)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	var markUnmergeable: Bool {
		if let m = mergeable?.boolValue where m == false {
			if let s = sectionIndex?.integerValue {
				if s == ItemCondition.Merged.rawValue || s == ItemCondition.Closed.rawValue {
					return false
				}
				if s == Section.All.rawValue && Settings.markUnmergeableOnUserSectionsOnly {
					return false
				}
				return true
			}
		}
		return false
	}

	class func reasonForEmptyWithFilter(filterValue: String?) -> NSAttributedString {
		let openRequests = PullRequest.countOpenInMoc(mainObjectContext)

		var color = COLOR_CLASS.lightGrayColor()
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if app.isRefreshing {
			message = "Refreshing PR information, please wait a moment..."
		} else if !S(filterValue).isEmpty {
			message = "There are no PRs matching this filter."
		} else if openRequests > 0 {
			message = "\(openRequests) PRs are hidden by your settings."
		} else if Repo.countVisibleReposInMoc(mainObjectContext)==0 {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
		} else if !Repo.interestedInPrs() && !Repo.interestedInIssues() {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if openRequests==0 {
			message = "No open PRs in your configured repositories."
		}

		return emptyMessage(message, color: color)
	}

	func subtitleWithFont(font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS) -> NSMutableAttributedString {
		let _subtitle = NSMutableAttributedString()
		let p = NSMutableParagraphStyle()
		#if os(iOS)
			p.lineHeightMultiple = 1.3
		#endif

		let lightSubtitle = [NSForegroundColorAttributeName: lightColor, NSFontAttributeName:font, NSParagraphStyleAttributeName: p]

		#if os(iOS)
			let separator = NSAttributedString(string:"\n", attributes:lightSubtitle)
		#elseif os(OSX)
			let separator = NSAttributedString(string:"   ", attributes:lightSubtitle)
		#endif

		if Settings.showReposInName {
			if let n = repo.fullName {
				var darkSubtitle = lightSubtitle
				darkSubtitle[NSForegroundColorAttributeName] = darkColor
				_subtitle.appendAttributedString(NSAttributedString(string: n, attributes: darkSubtitle))
				_subtitle.appendAttributedString(separator)
			}
		}

		if let l = userLogin {
			_subtitle.appendAttributedString(NSAttributedString(string: "@"+l, attributes: lightSubtitle))
			_subtitle.appendAttributedString(separator)
		}

		if Settings.showCreatedInsteadOfUpdated {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(updatedAt!), attributes: lightSubtitle))
		}

		#if os(iOS)
			if let m = mergeable?.boolValue where m == false {
				_subtitle.appendAttributedString(separator)
				var redSubtitle = lightSubtitle
				redSubtitle[NSForegroundColorAttributeName] = COLOR_CLASS.redColor()
				_subtitle.appendAttributedString(NSAttributedString(string: "Cannot be merged!", attributes:redSubtitle))
			}
		#endif

		return _subtitle
	}

	var accessibleSubtitle: String {
		var components = [String]()

		if Settings.showReposInName {
			components.append("Repository: \(S(repo.fullName))")
		}

		if let l = userLogin { components.append("Author: \(l)") }

		if Settings.showCreatedInsteadOfUpdated {
			components.append("Created \(itemDateFormatter.stringFromDate(createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.stringFromDate(updatedAt!))")
		}

		if let m = mergeable?.boolValue where m == false {
			components.append("Cannot be merged!")
		}

		return components.joinWithSeparator(",")
	}

	func shouldBeCheckedForRedStatusesInSection(targetSection: Section) -> Bool {
		if Settings.hidePrsThatArentPassing {
			if Settings.hidePrsThatDontPassOnlyInAll {
				return targetSection == .All
			} else {
				return targetSection == .Mine || targetSection == .Participated || targetSection == .All
			}
		}
		return false
	}

	var displayedStatuses: [PRStatus] {
		let f = NSFetchRequest(entityName: "PRStatus")
		f.returnsObjectsAsFaults = false
		let mode = Settings.statusFilteringMode
		if mode==StatusFilter.All.rawValue {
			f.predicate = NSPredicate(format: "pullRequest == %@", self)
		} else {
			let terms = Settings.statusFilteringTerms
			if terms.count > 0 {
				var subPredicates = [NSPredicate]()
				for t in terms {
					subPredicates.append(NSPredicate(format: "descriptionText contains[cd] %@", t))
				}
				let orPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
				let selfPredicate = NSPredicate(format: "pullRequest == %@", self)

				if mode==StatusFilter.Include.rawValue {
					f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [selfPredicate, orPredicate])
				} else {
					let notOrPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: orPredicate)
					f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [selfPredicate, notOrPredicate])
				}
			} else {
				f.predicate = NSPredicate(format: "pullRequest == %@", self)
			}
		}
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

		var result = [PRStatus]()
		var targetUrls = Set<String>()
		var descriptions = Set<String>()
		for s in try! managedObjectContext?.executeFetchRequest(f) as! [PRStatus] {
			let targetUrl = S(s.targetUrl)
			let desc = S(s.descriptionText)

			if !descriptions.contains(desc) {
				descriptions.insert(desc)
				if !targetUrls.contains(targetUrl) {
					targetUrls.insert(targetUrl)
					result.append(s)
				}
			}
		}
		return result
	}

	var labelsLink: String? {
		return issueUrl?.stringByAppendingPathComponent("labels")
	}

	var sectionName: String {
		return Section.prMenuTitles[sectionIndex?.integerValue ?? 0]
	}
}
