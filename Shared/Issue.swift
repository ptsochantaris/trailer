
import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	class func syncIssues(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		let filteredData = data?.filter { $0["pull_request"] == nil } // don't sync issues which are pull requests, they are already synced
		items(with: filteredData, type: Issue.self, server: repo.apiServer, prefetchRelationships: ["labels"]) { item, info, isNewOrUpdated in

			if isNewOrUpdated {

				item.baseSync(from: info, in: repo)

				if let R = repo.fullName {
					item.commentsLink = "/repos/\(R)/issues/\(item.number)/comments"
				}

				for l in item.labels {
					l.postSyncAction = PostSyncAction.delete.rawValue
				}

				if Settings.showLabels, let labelList = info["labels"] as? [[AnyHashable : Any]] {
					PRLabel.syncLabels(from: labelList, withParent: item)
				}

				item.processReactions(from: info)
			}
			item.reopened = item.condition == ItemCondition.closed.rawValue
			item.condition = ItemCondition.open.rawValue
			API.refreshesSinceLastReactionsCheck[item.objectID] = 1
		}
	}

	class func issuesThatNeedReactionsToBeRefreshed(in moc: NSManagedObjectContext) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "requiresReactionRefreshFromUrl != nil")
		return try! moc.fetch(f)
	}

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {
		let openIssueCount = Issue.countOpen(in: DataManager.main, criterion: criterion)
		return reasonForEmpty(with: filterValue, criterion: criterion, openItemCount: openIssueCount)
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["Issue", "Issues"] + super.searchKeywords
	}
	#endif

	class func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if section != .none {
			f.predicate = section.matchingPredicate
		}
		for pr in try! moc.fetch(f) {
			pr.catchUpWithComments()
		}
	}

	class func badgeCount(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate])
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Int {
		let f = requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCount(from: f, in: moc)
	}

	class func countOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.isOpenPredicate, in: moc)
		return try! moc.count(for: f)
	}

	@objc var sectionName: String {
		return Section.issueMenuTitles[Int(sectionIndex)]
	}

	class func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = ItemCondition.closed.matchingPredicate
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}
}
