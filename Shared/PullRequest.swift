
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

	class func pullRequestWithInfo(info: [NSObject : AnyObject], inRepo: Repo) -> PullRequest {
		let p = DataItem.itemWithInfo(info, type: "PullRequest", fromServer: inRepo.apiServer) as! PullRequest
		if p.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			p.url = N(info, "url") as? String
			p.webUrl = N(info, "html_url") as? String
			p.number = N(info, "number") as? NSNumber
			p.state = N(info, "state") as? String
			p.title = N(info, "title") as? String
			p.body = N(info, "body") as? String
			p.repo = inRepo
			p.mergeable = N(info, "mergeable") as? NSNumber ?? true

			if let userInfo = N(info, "user") as? [NSObject : AnyObject] {
				p.userId = N(userInfo, "id") as? NSNumber
				p.userLogin = N(userInfo, "login") as? String
				p.userAvatarUrl = N(userInfo, "avatar_url") as? String
			}

			if let linkInfo = N(info, "_links") as? [NSObject : AnyObject] {
				p.issueCommentLink = N(N(linkInfo, "comments"), "href") as? String
				p.reviewCommentLink = N(N(linkInfo, "review_comments"), "href") as? String
				p.statusesLink = N(N(linkInfo, "statuses"), "href") as? String
				p.issueUrl = N(N(linkInfo, "issue"), "href") as? String
			}

			api.refreshesSinceLastLabelsCheck[p.objectID] = nil
			api.refreshesSinceLastStatusCheck[p.objectID] = nil
		}
		p.reopened = ((p.condition?.integerValue ?? 0) == PullRequestCondition.Closed.rawValue)
		p.condition = PullRequestCondition.Open.rawValue
		return p
	}

	#if os(iOS)
	override func searchKeywords() -> [String] {
		return ["PR","Pull Request","PRs","Pull Requests"]+super.searchKeywords()
	}
	#endif

	class func visibleAndActivePullRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "sectionIndex == %d || sectionIndex == %d || sectionIndex == %d", PullRequestSection.Mine.rawValue, PullRequestSection.Participated.rawValue, PullRequestSection.All.rawValue)
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func allMergedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Merged.rawValue)
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func allClosedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Closed.rawValue)
		return try! moc.executeFetchRequest(f) as! [PullRequest]
	}

	class func countOpenRequestsInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "condition == %d or condition == nil", PullRequestCondition.Open.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countAllRequestsInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex > 0")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countRequestsInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func markEverythingRead(section: PullRequestSection, moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "PullRequest")
		if section != PullRequestSection.None {
			f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		}
		for pr in try! moc.executeFetchRequest(f) as! [PullRequest] {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: -1)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	func markUnmergeable() -> Bool {
		if let m = mergeable?.boolValue where m == false {
			if let s = sectionIndex?.integerValue {
				if s == PullRequestCondition.Merged.rawValue || s == PullRequestCondition.Closed.rawValue {
					return false
				}
				if s == PullRequestSection.All.rawValue && Settings.markUnmergeableOnUserSectionsOnly {
					return false
				}
				return true
			}
		}
		return false
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

	func accessibleSubtitle() -> String {
		var components = [String]()

		if Settings.showReposInName {
			let repoFullName = repo.fullName ?? "NoRepoFullName"
			components.append("Repository: \(repoFullName)")
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

	func displayedStatuses() -> [PRStatus] {
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
			let targetUrl = s.targetUrl ?? ""
			let desc = s.descriptionText ?? "(No status description)"

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

	func labelsLink() -> String? {
		return issueUrl?.stringByAppendingPathComponent("labels")
	}

	func sectionName() -> String {
		return PullRequestSection.prMenuTitles[sectionIndex?.integerValue ?? 0]
	}
}
