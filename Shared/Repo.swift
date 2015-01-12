
@objc (Repo)
class Repo: DataItem {

    @NSManaged var dirty: NSNumber?
    @NSManaged var fork: NSNumber?
    @NSManaged var fullName: String?
    @NSManaged var hidden: NSNumber
    @NSManaged var inaccessible: NSNumber?
    @NSManaged var lastDirtied: NSDate?
    @NSManaged var webUrl: String?

	@NSManaged var pullRequests: NSSet

	class func repoWithInfo(info: NSDictionary, fromServer: ApiServer) -> Repo {
		let r = DataItem.itemWithInfo(info, type: "Repo", fromServer: fromServer) as Repo
		if r.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			r.fullName = info.ofk("full_name") as? String
			r.fork = (info.ofk("fork") as? NSNumber)?.boolValue
			r.webUrl = info.ofk("html_url") as? String
			r.dirty = true
			r.lastDirtied = NSDate()
		}
		return r
	}

	class func visibleReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "hidden = NO")
		return moc.executeFetchRequest(f, error: nil) as [Repo]
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
		return moc.executeFetchRequest(f, error: nil) as [Repo]
	}

	class func unsyncableReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "hidden = YES or inaccessible = YES")
		return moc.executeFetchRequest(f, error: nil) as [Repo]
	}

	class func inaccessibleReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "inaccessible = YES")
		return moc.executeFetchRequest(f, error: nil) as [Repo]
	}

	class func markDirtyReposWithIds(ids: NSSet, inMoc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "serverId IN %@", ids)
		for repo in inMoc.executeFetchRequest(f, error: nil) as [Repo] {
			repo.dirty = !repo.hidden.boolValue
		}
	}

	class func reposForFilter(filter: String?) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		if let filterText = filter {
			if !filterText.isEmpty {
				f.predicate = NSPredicate(format: "fullName contains [cd] %@", filterText)
			}
		}
		f.sortDescriptors = [
			NSSortDescriptor(key: "fork", ascending: true),
			NSSortDescriptor(key: "fullName", ascending: true)
		]
		return mainObjectContext.executeFetchRequest(f, error: nil) as [Repo]
	}
}
