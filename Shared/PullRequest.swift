
import CoreData
#if os(iOS)
	import UIKit
#endif

@objc (PullRequest)
class PullRequest: ListableItem {

	@NSManaged var issueCommentLink: String?
	@NSManaged var issueUrl: String?
	@NSManaged var mergeable: NSNumber?
	@NSManaged var pinned: NSNumber?
	@NSManaged var reviewCommentLink: String?
	@NSManaged var statusesLink: String?
	@NSManaged var lastStatusNotified: String?

	@NSManaged var statuses: NSSet

	class func pullRequestWithInfo(info: NSDictionary, fromServer: ApiServer, inRepo: Repo) -> PullRequest {
		let p = DataItem.itemWithInfo(info, type: "PullRequest", fromServer: fromServer) as! PullRequest
		if p.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			p.url = info.ofk("url") as? String
			p.webUrl = info.ofk("html_url") as? String
			p.number = info.ofk("number") as? NSNumber
			p.state = info.ofk("state") as? String
			p.title = info.ofk("title") as? String
			p.body = info.ofk("body") as? String
			p.repo = inRepo
			p.mergeable = info.ofk("mergeable") as? NSNumber ?? true

			if let userInfo = info.ofk("user") as? NSDictionary {
				p.userId = userInfo.ofk("id") as? NSNumber
				p.userLogin = userInfo.ofk("login") as? String
				p.userAvatarUrl = userInfo.ofk("avatar_url") as? String
			}

			if let linkInfo = info.ofk("_links") as? NSDictionary {
				p.issueCommentLink = (linkInfo.ofk("comments") as? NSDictionary)?.ofk("href") as? String
				p.reviewCommentLink = (linkInfo.ofk("review_comments") as? NSDictionary)?.ofk("href") as? String
				p.statusesLink = (linkInfo.ofk("statuses") as? NSDictionary)?.ofk("href") as? String
				p.issueUrl = (linkInfo.ofk("issue") as? NSDictionary)?.ofk("href") as? String
			}

			api.refreshesSinceLastLabelsCheck[p.objectID] = nil
			api.refreshesSinceLastStatusCheck[p.objectID] = nil
		}
		p.reopened = ((p.condition?.integerValue ?? 0) == PullRequestCondition.Closed.rawValue)
		p.condition = PullRequestCondition.Open.rawValue
		return p
	}

	class func requestForPullRequestsWithFilter(filter: String?, sectionIndex: Int) -> NSFetchRequest {

		var andPredicates = [NSPredicate]()
		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex))
		}

		if let fi = filter {
			if !fi.isEmpty {

				var orPredicates = [NSPredicate]()
				orPredicates.append(NSPredicate(format: "title contains[cd] %@", fi))
				orPredicates.append(NSPredicate(format: "userLogin contains[cd] %@", fi))
				if Settings.includeReposInFilter {
					orPredicates.append(NSPredicate(format: "repo.fullName contains[cd] %@", fi))
				}
				if Settings.includeLabelsInFilter {
					orPredicates.append(NSPredicate(format: "any labels.name contains[cd] %@", fi))
				}
				if Settings.includeStatusesInFilter {
					orPredicates.append(NSPredicate(format: "any statuses.descriptionText contains[cd] %@", fi))
				}
				andPredicates.append(NSCompoundPredicate.orPredicateWithSubpredicates(orPredicates))
			}
		}

		if Settings.shouldHideUncommentedRequests {
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

		let f = NSFetchRequest(entityName: "PullRequest")
		f.fetchBatchSize = 100
		f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(andPredicates)
		f.sortDescriptors = sortDescriptiors
		return f
	}

	class func allMergedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Merged.rawValue)
		return moc.executeFetchRequest(f, error: nil) as! [PullRequest]
	}

	class func allClosedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Closed.rawValue)
		return moc.executeFetchRequest(f, error: nil) as! [PullRequest]
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
		for pr in moc.executeFetchRequest(f, error: nil) as! [PullRequest] {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as! [PullRequest] {
			if let sectionIndex = p.sectionIndex?.integerValue {
				if showCommentsEverywhere || sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue {
					if let c = p.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForPullRequestsWithFilter(nil, sectionIndex: -1)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as! [PullRequest] {
			if let sectionIndex = p.sectionIndex?.integerValue {
				if showCommentsEverywhere || sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue {
					if let c = p.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	func markUnmergeable() -> Bool {
		if let m = mergeable?.boolValue {
			if !m {
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
				_subtitle.appendAttributedString(NSAttributedString(string:n, attributes:darkSubtitle))
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
			if let m = mergeable?.boolValue {
				if !m {
					_subtitle.appendAttributedString(separator)
					var redSubtitle = lightSubtitle
					redSubtitle[NSForegroundColorAttributeName] = COLOR_CLASS.redColor()
					_subtitle.appendAttributedString(NSAttributedString(string: "Cannot be merged!", attributes:redSubtitle))
				}
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

		if let m = mergeable?.boolValue {
			if !m {
				components.append("Cannot be merged!")
			}
		}

		return ",".join(components)
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
				let orPredicate = NSCompoundPredicate.orPredicateWithSubpredicates(subPredicates)
				let selfPredicate = NSPredicate(format: "pullRequest == %@", self)

				if mode==StatusFilter.Include.rawValue {
					f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([selfPredicate, orPredicate])
				} else {
					let notOrPredicate = NSCompoundPredicate.notPredicateWithSubpredicate(orPredicate)
					f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([selfPredicate, notOrPredicate])
				}
			} else {
				f.predicate = NSPredicate(format: "pullRequest == %@", self)
			}
		}
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

		var result = [PRStatus]()
		var targetUrls = Set<String>()
		var descriptions = Set<String>()
		for s in managedObjectContext?.executeFetchRequest(f, error: nil) as! [PRStatus] {
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

	override func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {
		var userNumber = apiServer.userId?.longLongValue ?? 0
		if let date = optionalDate {
			return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", userNumber, self, date)
		} else {
			return NSPredicate(format: "userId != %lld and pullRequest == %@", userNumber, self)
		}
	}
}
