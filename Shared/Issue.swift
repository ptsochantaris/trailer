
import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	class func issueWithInfo(info: [NSObject : AnyObject], inRepo: Repo) -> Issue {
		let i = DataItem.itemWithInfo(info, type: "Issue", fromServer: inRepo.apiServer) as! Issue
		if i.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			i.url = N(info, "url") as? String
			i.webUrl = N(info, "html_url") as? String
			i.number = N(info, "number") as? NSNumber
			i.state = N(info, "state") as? String
			i.title = N(info, "title") as? String
			i.body = N(info, "body") as? String
			i.repo = inRepo

			if let userInfo = N(info, "user") as? [NSObject: AnyObject] {
				i.userId = N(userInfo, "id") as? NSNumber
				i.userLogin = N(userInfo, "login") as? String
				i.userAvatarUrl = N(userInfo, "avatar_url") as? String
			}

			if let N = i.number, R = inRepo.fullName {
				i.commentsLink = "/repos/\(R)/issues/\(N)/comments"
			}

			for l in i.labels {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let labelsList = N(info, "labels") as? [[NSObject: AnyObject]] {
				for labelInfo in labelsList {
					PRLabel.labelWithInfo(labelInfo, withParent: i)
				}
			}

			if let assignee = N(info, "assignee") as? [NSObject: AnyObject] {
				let assigneeName = N(assignee, "login") as? String ?? "NoAssignedUserName"
				let assigned = (assigneeName == (inRepo.apiServer.userName ?? "NoApiUser"))
				i.isNewAssignment = (assigned && !i.createdByMe() && !(i.assignedToMe?.boolValue ?? false))
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

	#if os(iOS)
	override func searchKeywords() -> [String] {
		return ["Issue","Issues"]+super.searchKeywords()
	}
	#endif

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
		for pr in try! moc.executeFetchRequest(f) as! [Issue] {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	class func badgeCountInSection(section: PullRequestSection, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section.rawValue)
		return badgeCountFromFetch(f, inMoc: moc)
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
		
		return _subtitle
	}

	func sectionName() -> String {
		return PullRequestSection.issueMenuTitles[sectionIndex?.integerValue ?? 0]
	}

	class func allClosedIssuesInMoc(moc: NSManagedObjectContext) -> [Issue] {
		let f = NSFetchRequest(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Closed.rawValue)
		return try! moc.executeFetchRequest(f) as! [Issue]
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

		return components.joinWithSeparator(",")
	}
}
