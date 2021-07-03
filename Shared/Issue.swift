import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

    static func mostRecentItemUpdate(in repo: Repo) -> Date {
        return repo.issues.reduce(.distantPast) { max($0, $1.updatedAt ?? .distantPast) }
    }
    
    override var webUrl: String? {
        return super.webUrl?.appending(pathComponent: "issues").appending(pathComponent: String(number))
    }
    
    static func sync(from nodes: ContiguousArray<GQLNode>, on server: ApiServer) {
        syncItems(of: Issue.self, from: nodes, on: server) { issue, node in
            
            guard node.created || node.updated,
                let parentId = node.parent?.id ?? (node.jsonPayload["repository"] as? [AnyHashable: Any])?["id"] as? String,
                let moc = server.managedObjectContext,
                let parent = DataItem.item(of: Repo.self, with: parentId, in: moc)
                else { return }

            let json = node.jsonPayload
            issue.baseNodeSync(nodeJson: json, parent: parent)
        }
    }

	static func syncIssues(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		let filteredData = data?.filter { $0["pull_request"] == nil } // don't sync issues which are pull requests, they are already synced
		items(with: filteredData, type: Issue.self, server: repo.apiServer, prefetchRelationships: ["labels"]) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				item.baseSync(from: info, in: repo)

				for l in item.labels {
					l.postSyncAction = PostSyncAction.delete.rawValue
				}
			}
            if item.condition == ItemCondition.closed.rawValue {
                item.stateChanged = StateChange.reopened.rawValue
            }
			item.condition = ItemCondition.open.rawValue
		}
	}

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

    var labelsLink: String? {
        return issueUrl?.appending(pathComponent: "labels")
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
