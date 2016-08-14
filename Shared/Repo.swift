
import CoreData

final class Repo: DataItem {

    @NSManaged var dirty: Bool
    @NSManaged var fork: Bool
    @NSManaged var fullName: String?
	@NSManaged var groupLabel: String?
    @NSManaged var inaccessible: Bool
    @NSManaged var lastDirtied: Date?
    @NSManaged var webUrl: String?
	@NSManaged var displayPolicyForPrs: Int64
	@NSManaged var displayPolicyForIssues: Int64
	@NSManaged var itemHidingPolicy: Int64
	@NSManaged var pullRequests: Set<PullRequest>
	@NSManaged var issues: Set<Issue>
	@NSManaged var ownerId: Int64

	class func syncRepos(from data: [[NSObject : AnyObject]]?, server: ApiServer) {
		var filteredData = [[NSObject : AnyObject]]()
		for info in data ?? [] {
			if (info["private"] as? NSNumber)?.boolValue ?? false {
				if let permissions = info["permissions"] as? [NSObject : AnyObject] {

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
		items(with: filteredData, type: "Repo", server: server) { item, info, newOrUpdated in
			if newOrUpdated {
				let r = item as! Repo
				r.fullName = info["full_name"] as? String
				r.fork = (info["fork"] as? NSNumber)?.boolValue ?? false
				r.webUrl = info["html_url"] as? String
				r.dirty = true
				r.inaccessible = false
				r.ownerId = (info["owner"]?["id"] as? NSNumber)?.int64Value ?? 0
				r.lastDirtied = Date()
			}
		}
	}

	var isMine: Bool {
		return ownerId == apiServer.userId
	}

	var shouldSync: Bool {
		return displayPolicyForPrs > 0 || displayPolicyForIssues > 0
	}

	override func resetSyncState() {
		super.resetSyncState()
		dirty = true
		lastDirtied = Date.distantPast
	}

	class func repos(for group: String, in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "groupLabel == %@", group)
		return try! moc.fetch(f)
	}

	class func anyVisibleRepos(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, excludeGrouped: Bool = false) -> Bool {

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
		if let aid = id, let a = existingObject(with: aid) as? ApiServer {
			all = Repo.allItems(ofType: "Repo", server: a) as! [Repo]
		} else {
			all = Repo.allItems(ofType: "Repo", in: mainObjectContext) as! [Repo]
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
		if let aid = id, let a = existingObject(with: aid) as? ApiServer {
			all = Repo.allItems(ofType: "Repo", server: a) as! [Repo]
		} else {
			all = Repo.allItems(ofType: "Repo", in: mainObjectContext) as! [Repo]
		}
		for r in all {
			if r.displayPolicyForPrs > 0 {
				return true
			}
		}
		return false
	}

	class var allGroupLabels: [String] {
		let allRepos = allItems(ofType: "Repo", in: mainObjectContext) as! [Repo]
		let labels = allRepos.flatMap { $0.shouldSync ? $0.groupLabel : nil }
		return Set<String>(labels).sorted()
	}

	class func syncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "dirty = YES and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0) and inaccessible != YES")
		return try! moc.fetch(f)
	}

	class func reposNotRecentlyDirtied(in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.predicate = NSPredicate(format: "dirty != YES and lastDirtied < %@ and postSyncAction != %lld and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)", Date(timeInterval: -3600, since: Date()), PostSyncAction.delete.rawValue)
		f.includesPropertyValues = false
		f.returnsObjectsAsFaults = false
		return try! moc.fetch(f)
	}

	class func unsyncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "(not (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)) or inaccessible = YES")
		return try! moc.fetch(f)
	}

	class func markDirtyReposWithIds(_ ids: NSSet, in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Repo>(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "serverId IN %@", ids)
		for repo in try! moc.fetch(f) {
			repo.dirty = repo.shouldSync
		}
	}

	class func reposFiltered(by filter: String?) -> [Repo] {
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

	class func countParentRepos(filter: String?) -> Int {
		let f = NSFetchRequest<Repo>(entityName: "Repo")

		if let fi = filter, !fi.isEmpty {
			f.predicate = NSPredicate(format: "fork == NO and fullName contains [cd] %@", fi)
		} else {
			f.predicate = NSPredicate(format: "fork == NO")
		}
		return try! mainObjectContext.count(for: f)
	}
}
