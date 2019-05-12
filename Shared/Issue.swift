
import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	static func syncIssues(from data: [[AnyHashable : Any]]?, in repo: Repo) {
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

	static func issuesThatNeedReactionsToBeRefreshed(in moc: NSManagedObjectContext) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "requiresReactionRefreshFromUrl != nil")
		return try! moc.fetch(f)
	}

	@available(OSX 10.11, *)
	override var searchKeywords: [String] {
		return ["Issue", "Issues"] + super.searchKeywords
	}

	static func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
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

	static func badgeCount(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate])
		return badgeCount(from: f, in: moc)
	}

	static func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Int {
		let f = requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCount(from: f, in: moc)
	}

	override class func hasOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Bool {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		f.fetchLimit = 1
		add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.open.matchingPredicate, in: moc)
		return try! moc.count(for: f) > 0
	}

	@objc var sectionName: String {
		return Section.issueMenuTitles[Int(sectionIndex)]
	}

	static func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = ItemCondition.closed.matchingPredicate
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}
}
