
import CoreData

final class Repo: DataItem {

    @NSManaged var dirty: NSNumber?
    @NSManaged var fork: NSNumber?
    @NSManaged var fullName: String?
	@NSManaged var groupLabel: String?
    @NSManaged var hidden: NSNumber?
    @NSManaged var inaccessible: NSNumber?
    @NSManaged var lastDirtied: Date?
    @NSManaged var webUrl: String?
	@NSManaged var displayPolicyForPrs: NSNumber?
	@NSManaged var displayPolicyForIssues: NSNumber?
	@NSManaged var itemHidingPolicy: NSNumber?
	@NSManaged var pullRequests: Set<PullRequest>
	@NSManaged var issues: Set<Issue>
	@NSManaged var ownerId: NSNumber?

	class func syncReposFromInfo(_ data: [[NSObject : AnyObject]]?, apiServer: ApiServer) {
		var filteredData = [[NSObject : AnyObject]]()
		for info in data ?? [] {
			if (info["private"] as? NSNumber)?.boolValue ?? false {
				if let permissions = info["permissions"] as? [NSObject: AnyObject] {

					let pull = (permissions["pull"] as? NSNumber)?.boolValue ?? false
					let push = (permissions["push"] as? NSNumber)?.boolValue ?? false
					let admin = (permissions["admin"] as? NSNumber)?.boolValue ?? false

					if	pull || push || admin {
						filteredData.append(info)
					} else {
						DLog("Watched private repository '%@' seems to be inaccessible, skipping", info["full_name"] as? String)
					}
				}
			} else {
				filteredData.append(info)
			}
		}
		itemsWithInfo(filteredData, type: "Repo", fromServer: apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let r = item as! Repo
				r.fullName = info["full_name"] as? String
				r.fork = (info["fork"] as? NSNumber)?.boolValue
				r.webUrl = info["html_url"] as? String
				r.dirty = true
				r.inaccessible = false
				r.ownerId = info["owner"]?["id"] as? NSNumber
				r.lastDirtied = Date()
			}
		}
	}

	var isMine: Bool {
		if let o = ownerId {
			return o == apiServer.userId
		}
		return false
	}

	var shouldSync: Bool {
		return (displayPolicyForPrs?.intValue ?? 0) > 0 || (displayPolicyForIssues?.intValue ?? 0) > 0
	}

	override func resetSyncState() {
		super.resetSyncState()
		dirty = true
		lastDirtied = Date.distantPast
	}

	class func reposForGroup(_ group: String, inMoc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "groupLabel == %@", group)
		return try! inMoc.fetch(f)
	}

	class func anyVisibleReposInMoc(_ moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, excludeGrouped: Bool = false) -> Bool {

		func excludeGroupedRepos(_ p: NSPredicate) -> NSPredicate {
			let nilCheck = NSPredicate(format: "groupLabel == nil")
			return NSCompoundPredicate(andPredicateWithSubpredicates: [nilCheck, p])
		}

		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.fetchLimit = 1
		let p = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")
		if let c = criterion {
			if let g = c.repoGroup { // special case will never need exclusion
				let rp = NSPredicate(format: "groupLabel == %@", g)
				f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [rp, p])
			} else {
				let ep = c.addCriterionToPredicate(p, inMoc: moc)
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

	class func interestedInIssues(_ apiServerId: NSManagedObjectID? = nil) -> Bool {
		let all: [Repo]
		if let aid = apiServerId, let a = existingObjectWithID(aid) as? ApiServer {
			all = Repo.allItemsOfType("Repo", fromServer: a) as! [Repo]
		} else {
			all = Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo]
		}
		for r in all {
			if r.displayPolicyForIssues?.intValue > 0 {
				return true
			}
		}
		return false
	}

	class func interestedInPrs(_ apiServerId: NSManagedObjectID? = nil) -> Bool {
		let all: [Repo]
		if let aid = apiServerId, let a = existingObjectWithID(aid) as? ApiServer {
			all = Repo.allItemsOfType("Repo", fromServer: a) as! [Repo]
		} else {
			all = Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo]
		}
		for r in all {
			if r.displayPolicyForPrs?.intValue > 0 {
				return true
			}
		}
		return false
	}

	class var allGroupLabels: [String] {
		let allRepos = allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo]
		let labels = allRepos.flatMap { $0.shouldSync ? $0.groupLabel : nil }
		return Set<String>(labels).sorted()
	}

	class func syncableReposInMoc(_ moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "dirty = YES and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0) and inaccessible != YES")
		return try! moc.fetch(f)
	}

	class func reposNotRecentlyDirtied(_ moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.predicate = NSPredicate(format: "dirty != YES and lastDirtied < %@ and postSyncAction != %d and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)", Date(timeInterval: -3600, since: Date()), PostSyncAction.delete.rawValue)
		f.includesPropertyValues = false
		f.returnsObjectsAsFaults = false
		return try! moc.fetch(f)
	}

	class func unsyncableReposInMoc(_ moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "(not (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)) or inaccessible = YES")
		return try! moc.fetch(f)
	}

	class func markDirtyReposWithIds(_ ids: NSSet, inMoc: NSManagedObjectContext) {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "serverId IN %@", ids)
		for repo in try! inMoc.fetch(f) {
			repo.dirty = repo.shouldSync
		}
	}

	class func reposForFilter(_ filter: String?) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		if let filterText = filter, !filterText.isEmpty {
			f.predicate = NSPredicate(format: "fullName contains [cd] %@", filterText)
		}
		f.sortDescriptors = [
			NSSortDescriptor(key: "fork", ascending: true),
			NSSortDescriptor(key: "fullName", ascending: true)
		]
		return try! mainObjectContext.fetch(f)
	}

	class func countParentRepos(_ filter: String?) -> Int {
		let f = NSFetchRequest<Repo>(entityName: "Repo")

		if let fi = filter, !fi.isEmpty {
			f.predicate = NSPredicate(format: "fork == NO and fullName contains [cd] %@", fi)
		} else {
			f.predicate = NSPredicate(format: "fork == NO")
		}
		return try! mainObjectContext.count(for: f)
	}
}
