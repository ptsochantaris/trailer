
import CoreData

@objc (Repo)
class Repo: DataItem {

    @NSManaged var dirty: NSNumber?
    @NSManaged var fork: NSNumber?
    @NSManaged var fullName: String?
    @NSManaged var hidden: NSNumber?
    @NSManaged var inaccessible: NSNumber?
    @NSManaged var lastDirtied: NSDate?
    @NSManaged var webUrl: String?

	@NSManaged var pullRequests: Set<PullRequest>
	@NSManaged var issues: Set<Issue>

	class func repoWithInfo(info: NSDictionary, fromServer: ApiServer) -> Repo {
		let r = DataItem.itemWithInfo(info, type: "Repo", fromServer: fromServer) as! Repo
		if r.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			r.fullName = info.ofk("full_name") as? String
			r.fork = (info.ofk("fork") as? NSNumber)?.boolValue
			r.webUrl = info.ofk("html_url") as? String
			r.dirty = true
			r.lastDirtied = NSDate()
		}
		return r
	}

	override func resetSyncState() {
		super.resetSyncState()
		dirty = true
		inaccessible = false
		lastDirtied = never()
	}

	class func visibleReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "hidden = NO")
		return moc.executeFetchRequest(f, error: nil) as! [Repo]
	}

	class func countVisibleReposInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Repo")
		f.predicate = NSPredicate(format: "hidden = NO")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func syncableReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "dirty = YES and hidden = NO and inaccessible != YES")
		return moc.executeFetchRequest(f, error: nil) as! [Repo]
	}

	class func unsyncableReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "hidden = YES or inaccessible = YES")
		return moc.executeFetchRequest(f, error: nil) as! [Repo]
	}

	class func inaccessibleReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "inaccessible = YES")
		return moc.executeFetchRequest(f, error: nil) as! [Repo]
	}

	class func markDirtyReposWithIds(ids: Set<NSNumber>, inMoc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "serverId IN %@", ids)
		for repo in inMoc.executeFetchRequest(f, error: nil) as! [Repo] {
			repo.dirty = !(repo.hidden?.boolValue ?? false)
		}
	}

	class func reposForFilter(filter: String?) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		if let filterText = filter where !filterText.isEmpty {
			f.predicate = NSPredicate(format: "fullName contains [cd] %@", filterText)
		}
		f.sortDescriptors = [
			NSSortDescriptor(key: "fork", ascending: true),
			NSSortDescriptor(key: "fullName", ascending: true)
		]
		return mainObjectContext.executeFetchRequest(f, error: nil) as! [Repo]
	}

	class func countParentRepos(filter: String?) -> Int {
		let f = NSFetchRequest(entityName: "Repo")

		if let fi = filter where !fi.isEmpty {
			f.predicate = NSPredicate(format: "fork == NO and fullName contains [cd] %@", fi)
		} else {
			f.predicate = NSPredicate(format: "fork == NO")
		}
		return mainObjectContext.countForFetchRequest(f, error:nil)
	}
}
