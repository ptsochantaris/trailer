
import CoreData

final class Repo: DataItem {

    @NSManaged var fork: Bool
    @NSManaged var fullName: String?
	@NSManaged var groupLabel: String?
    @NSManaged var inaccessible: Bool
    @NSManaged var webUrl: String?
	@NSManaged var displayPolicyForPrs: Int64
	@NSManaged var displayPolicyForIssues: Int64
	@NSManaged var itemHidingPolicy: Int64
	@NSManaged var pullRequests: Set<PullRequest>
	@NSManaged var issues: Set<Issue>
	@NSManaged var ownerId: Int64
	@NSManaged var manuallyAdded: Bool
	@NSManaged var lastScannedIssueEventId: Int64

	override func resetSyncState() {
		super.resetSyncState()
		lastScannedIssueEventId = 0
	}

	class func syncRepos(from data: [[AnyHashable : Any]]?, server: ApiServer, addNewRepos: Bool, manuallyAdded: Bool) {
		let filteredData = data?.filter { info -> Bool in
			if info["private"] as? Bool ?? false {
				if let permissions = info["permissions"] as? [AnyHashable : Any] {

					let pull = permissions["pull"] as? Bool ?? false
					let push = permissions["push"] as? Bool ?? false
					let admin = permissions["admin"] as? Bool ?? false

					if pull || push || admin {
						return true
					} else if let fullName = info["full_name"] as? String {
						DLog("Watched private repository '%@' seems to be inaccessible, skipping", fullName)
					}
				}
				return false
			} else {
				return true
			}
		}

		items(with: filteredData, type: Repo.self, server: server, createNewItems: addNewRepos) { item, info, newOrUpdated in
			if newOrUpdated {
				item.fullName = info["full_name"] as? String
				item.fork = info["fork"] as? Bool ?? false
				item.webUrl = info["html_url"] as? String
				item.inaccessible = false
				item.ownerId = (info["owner"] as? [AnyHashable : Any])?["id"] as? Int64 ?? 0
				item.manuallyAdded = manuallyAdded
				if item.postSyncAction == PostSyncAction.isNew.rawValue {
					item.displayPolicyForPrs = Int64(Settings.displayPolicyForNewPrs)
					item.displayPolicyForIssues = Int64(Settings.displayPolicyForNewIssues)
				}
			}
		}
	}

	var isMine: Bool {
		return ownerId == apiServer.userId
	}

	var shouldSync: Bool {
		return displayPolicyForPrs > 0 || displayPolicyForIssues > 0
	}

	class func repos(for group: String, in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "groupLabel == %@", group)
		return try! moc.fetch(f)
	}

	class func anyVisibleRepos(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, excludeGrouped: Bool = false) -> Bool {

		func excludeGroupedRepos(_ p: NSPredicate) -> NSPredicate {
			let nilCheck = NSPredicate(format: "groupLabel == nil")
			return NSCompoundPredicate(andPredicateWithSubpredicates: [nilCheck, p])
		}

		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.includesSubentities = false
		f.fetchLimit = 1
		let p = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")
		if let c = criterion {
			if let g = c.repoGroup { // special case will never need exclusion
				let rp = NSPredicate(format: "groupLabel == %@", g)
				f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [rp, p])
			} else {
				let ep = c.addCriterion(to: p, in: moc)
				if excludeGrouped {
					f.predicate = excludeGroupedRepos(ep)
				} else {
					f.predicate = ep
				}
			}
		} else if excludeGrouped {
			f.predicate = excludeGroupedRepos(p)
		} else {
			f.predicate = p
		}
		let c = try! moc.count(for: f)
		return c > 0
	}

	class func interestedInIssues(fromServerWithId id: NSManagedObjectID? = nil) -> Bool {
		let all: [Repo]
		if let aid = id, let apiServer = existingObject(with: aid) as? ApiServer {
			all = Repo.allItems(of: Repo.self, in: apiServer)
		} else {
			all = Repo.allItems(of: Repo.self, in: DataManager.main)
		}
		for r in all {
			if r.displayPolicyForIssues > 0 {
				return true
			}
		}
		return false
	}

	class func interestedInPrs(fromServerWithId id: NSManagedObjectID? = nil) -> Bool {
		let all: [Repo]
		if let aid = id, let apiServer = existingObject(with: aid) as? ApiServer {
			all = Repo.allItems(of: Repo.self, in: apiServer)
		} else {
			all = Repo.allItems(of: Repo.self, in: DataManager.main)
		}
		for r in all {
			if r.displayPolicyForPrs > 0 {
				return true
			}
		}
		return false
	}

	class func allGroupLabels(in moc: NSManagedObjectContext) -> [String] {
		let allRepos = allItems(of: Repo.self, in: moc)
		let labels = allRepos.flatMap { $0.shouldSync ? $0.groupLabel : nil }
		return Set<String>(labels).sorted()
	}

	class func syncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "(displayPolicyForPrs > 0 or displayPolicyForIssues > 0) and inaccessible != YES")
		return try! moc.fetch(f)
	}

	class func unsyncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "(not (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)) or inaccessible = YES")
		return try! moc.fetch(f)
	}

	class func reposFiltered(by filter: String?) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if let filterText = filter, !filterText.isEmpty {
			f.predicate = NSPredicate(format: "fullName contains [cd] %@", filterText)
		}
		f.sortDescriptors = [
			NSSortDescriptor(key: "fork", ascending: true),
			NSSortDescriptor(key: "fullName", ascending: true)
		]
		return try! DataManager.main.fetch(f)
	}

	class func countParentRepos(filter: String?) -> Int {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.includesSubentities = false
		
		if let fi = filter, !fi.isEmpty {
			f.predicate = NSPredicate(format: "fork == NO and fullName contains [cd] %@", fi)
		} else {
			f.predicate = NSPredicate(format: "fork == NO")
		}
		return try! DataManager.main.count(for: f)
	}

	func markItemsAsUpdated(with numbers: Set<Int64>, reasons: Set<String>) {

		let predicate = NSPredicate(format: "(number IN %@) AND (repo == %@)", numbers, self)

		func mark<T>(type: T.Type) where T : ListableItem {
			let f = NSFetchRequest<T>(entityName: String(describing: type))
			f.returnsObjectsAsFaults = false
			f.includesSubentities = false
			f.predicate = predicate
			for i in try! managedObjectContext!.fetch(f) {
				//DLog("Ensuring item '%@' in repo '%@' is marked as updated - reasons: %@", S(i.title), S(i.repo.fullName), reasons.joined(separator: ", "))
				i.setToUpdatedIfIdle()
			}
		}

		mark(type: PullRequest.self)
		mark(type: Issue.self)
	}

}
