
import CoreData
#if os(iOS)
	import UIKit
#endif

@objc (Issue)
class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	class func issueWithInfo(info: NSDictionary, fromServer: ApiServer, inRepo: Repo) -> Issue {
		let i = DataItem.itemWithInfo(info, type: "Issue", fromServer: fromServer) as! Issue
		if i.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			i.url = info.ofk("url") as? String
			i.webUrl = info.ofk("html_url") as? String
			i.number = info.ofk("number") as? NSNumber
			i.state = info.ofk("state") as? String
			i.title = info.ofk("title") as? String
			i.body = info.ofk("body") as? String
			i.repo = inRepo

			if let userInfo = info.ofk("user") as? NSDictionary {
				i.userId = userInfo.ofk("id") as? NSNumber
				i.userLogin = userInfo.ofk("login") as? String
				i.userAvatarUrl = userInfo.ofk("avatar_url") as? String
			}

			if let N = i.number {
				if let R = inRepo.fullName {
					i.commentsLink = "/repos/\(R)/issues/\(N)/comments"
				}
			}

			for l in i.labels {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let labelsList = info.ofk("labels") as? [NSDictionary] {
				for labelInfo in labelsList {
					PRLabel.labelWithInfo(labelInfo, withParent: i)
				}
			}

			if let assignee = info.ofk("assignee") as? NSDictionary {
				let assigneeName = assignee.ofk("login") as? String ?? "NoAssignedUserName"
				let assigned = (assigneeName == (fromServer.userName ?? "NoApiUser"))
				i.isNewAssignment = (assigned && !(i.assignedToMe?.boolValue ?? false))
				i.assignedToMe = assigned
			} else {
				i.assignedToMe = false
				i.isNewAssignment = false
			}
		}
		i.reopened = ((i.condition?.integerValue ?? 0) == PullRequestCondition.Closed.rawValue)
		i.condition = PullRequestCondition.Open.rawValue
		return i
	}

	class func requestForIssuesWithFilter(filter: String?, sectionIndex: Int) -> NSFetchRequest {

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

		let f = NSFetchRequest(entityName: "Issue")
		f.fetchBatchSize = 100
		f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(andPredicates)
		f.sortDescriptors = sortDescriptiors
		return f
	}

	class func countAllIssuesInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex > 0")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countIssuesInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func markEverythingRead(section: PullRequestSection, moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Issue")
		if section != PullRequestSection.None {
			f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		}
		for pr in moc.executeFetchRequest(f, error: nil) as! [Issue] {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForIssuesWithFilter(nil, sectionIndex: -1)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for i in moc.executeFetchRequest(f, error: nil) as! [Issue] {
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

	class func badgeCountInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as! [Issue] {
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

	class func countOpenIssuesInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "condition == %d or condition == nil", PullRequestCondition.Open.rawValue)
		return moc.countForFetchRequest(f, error: nil)
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
		
		return _subtitle
	}

	func sectionName() -> String {
		return PullRequestSection.prMenuTitles[sectionIndex?.integerValue ?? 0]
	}

	override func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {
		var userNumber = apiServer.userId?.longLongValue ?? 0
		if let date = optionalDate {
			return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", userNumber, self, date)
		} else {
			return NSPredicate(format: "userId != %lld and issue == %@", userNumber, self)
		}
	}

	class func allClosedIssuesInMoc(moc: NSManagedObjectContext) -> [Issue] {
		let f = NSFetchRequest(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Closed.rawValue)
		return moc.executeFetchRequest(f, error: nil) as! [Issue]
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

		return ",".join(components)
	}
}
