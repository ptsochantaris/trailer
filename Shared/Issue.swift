
import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	class func syncIssuesFromInfoArray(_ data: [[NSObject : AnyObject]]?, inRepo: Repo) {
		let filteredData = data?.filter { $0["pull_request"] == nil } // don't sync issues which are pull requests, they are already synced
		itemsWithInfo(filteredData, type: "Issue", fromServer: inRepo.apiServer) { item, info, isNewOrUpdated in
			let i = item as! Issue
			if isNewOrUpdated {

				i.baseSyncFromInfo(info, inRepo: inRepo)

				if let R = inRepo.fullName {
					i.commentsLink = "/repos/\(R)/issues/\(i.number)/comments"
				}

				for l in i.labels {
					l.postSyncAction = PostSyncAction.delete.rawValue
				}

				let labelList = info["labels"] as? [[NSObject: AnyObject]]
				PRLabel.syncLabelsWithInfo(labelList, withParent: i)
			}
			i.reopened = (i.condition == ItemCondition.closed.rawValue)
			i.condition = ItemCondition.open.rawValue
		}
	}

	class func reasonForEmptyWithFilter(_ filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {
		let openIssues = Issue.countOpenInMoc(mainObjectContext, criterion: criterion)

		var color = COLOR_CLASS.lightGray
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if appIsRefreshing {
			message = "Refreshing information, please wait a moment..."
		} else if !S(filterValue).isEmpty {
			message = "There are no issues matching this filter."
		} else if openIssues > 0 {
			message = "Some items are hidden by your settings."
		} else if !Repo.anyVisibleReposInMoc(mainObjectContext, criterion: criterion, excludeGrouped: true) {
			if Repo.anyVisibleReposInMoc(mainObjectContext) {
				message = "There are no repositories that are currently visible in this category."
			} else {
				color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
				message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
			}
		} else if !Repo.interestedInPrs(criterion?.apiServerId) && !Repo.interestedInIssues(criterion?.apiServerId) {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if openIssues==0 {
			message = "No open issues in your configured repositories."
		}

		return emptyMessage(message, color: color)
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["Issue","Issues"] + super.searchKeywords
	}
	#endif

	class func markEverythingRead(_ section: Section, moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		if section != .none {
			f.predicate = NSPredicate(format: "sectionIndex == %lld", section.rawValue)
		}
		for pr in try! moc.fetch(f) {
			pr.catchUpWithComments()
		}
	}

	class func badgeCountInMoc(_ moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex > 0 and unreadComments > 0")
		return badgeCountFromFetch(f, inMoc: moc)
	}

	class func badgeCountInMoc(_ moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Int {
		let f = requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCountFromFetch(f, inMoc: moc)
	}

	class func countOpenInMoc(_ moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		let p = NSPredicate(format: "condition == %lld or condition == nil", ItemCondition.open.rawValue)
		addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: moc)
		return try! moc.count(for: f)
	}

	func subtitleWithFont(_ font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS) -> NSMutableAttributedString {
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
				_subtitle.append(NSAttributedString(string: n, attributes: darkSubtitle))
				_subtitle.append(separator)
			}
		}

		if let l = userLogin {
			_subtitle.append(NSAttributedString(string: "@\(l)", attributes: lightSubtitle))
			_subtitle.append(separator)
		}

		if Settings.showCreatedInsteadOfUpdated {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: updatedAt!), attributes: lightSubtitle))
		}
		
		return _subtitle
	}

	var sectionName: String {
		return Section.issueMenuTitles[Int(sectionIndex)]
	}

	class func allClosedInMoc(_ moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		let p = NSPredicate(format: "condition == %lld", ItemCondition.closed.rawValue)
		addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	var accessibleSubtitle: String {
		var components = [String]()

		if Settings.showReposInName {
			components.append("Repository: \(S(repo.fullName))")
		}

		if let l = userLogin { components.append("Author: \(l)") }

		if Settings.showCreatedInsteadOfUpdated {
			components.append("Created \(itemDateFormatter.string(from: createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.string(from: updatedAt!))")
		}

		return components.joined(separator: ",")
	}
}
