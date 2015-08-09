
import CoreData

final class Repo: DataItem {

    @NSManaged var dirty: NSNumber?
    @NSManaged var fork: NSNumber?
    @NSManaged var fullName: String?
    @NSManaged var hidden: NSNumber?
    @NSManaged var inaccessible: NSNumber?
    @NSManaged var lastDirtied: NSDate?
    @NSManaged var webUrl: String?
	@NSManaged var displayPolicyForPrs: NSNumber?
	@NSManaged var displayPolicyForIssues: NSNumber?
	@NSManaged var pullRequests: Set<PullRequest>
	@NSManaged var issues: Set<Issue>

	class func repoWithInfo(info: [NSObject : AnyObject], fromServer: ApiServer) -> Repo {
		let r = DataItem.itemWithInfo(info, type: "Repo", fromServer: fromServer) as! Repo
		if r.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			r.fullName = N(info, "full_name") as? String
			r.fork = (N(info, "fork") as? NSNumber)?.boolValue
			r.webUrl = N(info, "html_url") as? String
			r.dirty = true
			r.inaccessible = false
			r.lastDirtied = NSDate()
		}
		return r
	}

	func shouldSync() -> Bool {
		return (self.displayPolicyForPrs?.integerValue ?? 0) > 0 || (self.displayPolicyForIssues?.integerValue ?? 0) > 0
	}

	override func resetSyncState() {
		super.resetSyncState()
		dirty = true
		lastDirtied = never()
	}

	class func visibleReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")
		return try! moc.executeFetchRequest(f) as! [Repo]
	}

	class func countVisibleReposInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Repo")
		f.predicate = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func interestedInIssues() -> Bool {
		for r in Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
			if r.displayPolicyForIssues?.integerValue > 0 {
				return true
			}
		}
		return false
	}

	class func interestedInPrs() -> Bool {
		for r in Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
			if r.displayPolicyForPrs?.integerValue > 0 {
				return true
			}
		}
		return false
	}

	class func syncableReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "dirty = YES and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0) and inaccessible != YES")
		return try! moc.executeFetchRequest(f) as! [Repo]
	}

	class func reposNotRecentlyDirtied(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.predicate = NSPredicate(format: "dirty != YES and lastDirtied < %@ and postSyncAction != %d and (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)", NSDate(timeInterval: -3600, sinceDate: NSDate()), PostSyncAction.Delete.rawValue)
		f.includesPropertyValues = false
		f.returnsObjectsAsFaults = false
		return try! moc.executeFetchRequest(f) as! [Repo]
	}

	class func unsyncableReposInMoc(moc: NSManagedObjectContext) -> [Repo] {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "(not (displayPolicyForPrs > 0 or displayPolicyForIssues > 0)) or inaccessible = YES")
		return try! moc.executeFetchRequest(f) as! [Repo]
	}

	class func markDirtyReposWithIds(ids: NSSet, inMoc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Repo")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "serverId IN %@", ids)
		for repo in try! inMoc.executeFetchRequest(f) as! [Repo] {
			repo.dirty = repo.shouldSync()
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
		return try! mainObjectContext.executeFetchRequest(f) as! [Repo]
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
