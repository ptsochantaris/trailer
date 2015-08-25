
import CoreData

final class ApiServer: NSManagedObject {

    @NSManaged var apiPath: String?
    @NSManaged var authToken: String?
    @NSManaged var label: String?
    @NSManaged var lastSyncSucceeded: NSNumber?
    @NSManaged var latestReceivedEventDateProcessed: NSDate?
    @NSManaged var latestReceivedEventEtag: String?
    @NSManaged var latestUserEventDateProcessed: NSDate?
    @NSManaged var latestUserEventEtag: String?
    @NSManaged var reportRefreshFailures: NSNumber
    @NSManaged var requestsLimit: NSNumber?
    @NSManaged var requestsRemaining: NSNumber?
    @NSManaged var resetDate: NSDate?
    @NSManaged var userId: NSNumber?
    @NSManaged var userName: String?
    @NSManaged var webPath: String?
	@NSManaged var createdAt: NSDate?

    @NSManaged var comments: Set<PRComment>
    @NSManaged var labels: Set<PRLabel>
    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var repos: Set<Repo>
    @NSManaged var statuses: Set<PRStatus>
	@NSManaged var teams: Set<Team>
    @NSManaged var issues: Set<Issue>

	var syncIsGood: Bool {
		return lastSyncSucceeded?.boolValue ?? true
	}

	var goodToGo: Bool {
		return !(authToken ?? "").isEmpty
	}

	class func resetSyncOfEverything() {
		DLog("RESETTING SYNC STATE OF ALL ITEMS")
		for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
			for p in r.pullRequests {
				p.resetSyncState()
			}
			for i in r.issues {
				i.resetSyncState()
			}
		}
		if app != nil {
			app.preferencesDirty = true
			api.clearAllBadLinks()
		}
	}

	class func insertNewServerInMoc(moc: NSManagedObjectContext) -> ApiServer {
		let githubServer: ApiServer = NSEntityDescription.insertNewObjectForEntityForName("ApiServer", inManagedObjectContext: moc) as! ApiServer
		githubServer.createdAt = NSDate()
		return githubServer
	}

	class func resetSyncSuccessInMoc(moc: NSManagedObjectContext) {
		for apiServer in allApiServersInMoc(moc) {
			if apiServer.goodToGo {
				apiServer.lastSyncSucceeded = true
			}
		}
	}

	class func shouldReportRefreshFailureInMoc(moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServersInMoc(moc) {

			var lastSyncSucceeded = apiServer.lastSyncSucceeded?.boolValue
			if lastSyncSucceeded==nil { lastSyncSucceeded!=false }

			if apiServer.goodToGo && !(lastSyncSucceeded!) && (apiServer.reportRefreshFailures.boolValue) {
				return true
			}
		}
		return false
	}

	class func ensureAtLeastGithubInMoc(moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "ApiServer")
		f.fetchLimit = 1
		let numberOfExistingApiServers = moc.countForFetchRequest(f, error: nil)
		if numberOfExistingApiServers==0 {
			addDefaultGithubInMoc(moc)
		}
	}

	class func addDefaultGithubInMoc(moc: NSManagedObjectContext) -> ApiServer {
		let githubServer = insertNewServerInMoc(moc)
		githubServer.resetToGithub()
		return githubServer
	}

	class func allApiServersInMoc(moc: NSManagedObjectContext) -> [ApiServer] {
		let f = NSFetchRequest(entityName: "ApiServer")
		f.returnsObjectsAsFaults = false
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
		return try! moc.executeFetchRequest(f) as! [ApiServer]
	}

	class func someServersHaveAuthTokensInMoc(moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServersInMoc(moc) {
			if !(apiServer.authToken ?? "").isEmpty {
				return true
			}
		}
		return false
	}

	class func countApiServersInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "ApiServer")
		return moc.countForFetchRequest(f, error: nil)
	}

	func rollBackAllUpdatesInMoc(moc: NSManagedObjectContext) {
		DLog("Rolling back changes for failed sync on API server '%@'",label)
		for set in [repos, pullRequests, comments, statuses, labels, issues, teams] {
			for dataItem: DataItem in set.allObjects as! [DataItem] {
				if let action = dataItem.postSyncAction?.integerValue {
					switch action {
					case PostSyncAction.Delete.rawValue:
						dataItem.postSyncAction = PostSyncAction.DoNothing.rawValue
					case PostSyncAction.NoteNew.rawValue:
						moc.deleteObject(dataItem)
					case PostSyncAction.NoteUpdated.rawValue:
						moc.refreshObject(dataItem, mergeChanges: false)
					default: break
					}
				}
			}
		}
		moc.refreshObject(self, mergeChanges: false)
	}

	func clearAllRelatedInfo() {
		if let moc = managedObjectContext {
			for r in repos {
				moc.deleteObject(r)
			}
		}
	}

	func resetToGithub() {
		webPath = "https://github.com"
		apiPath = "https://api.github.com"
		label = "GitHub"
		resetSyncState()
	}

	func resetSyncState() {
		if app != nil {
			app.lastRepoCheck = never()
		}
		lastSyncSucceeded = true
		latestReceivedEventDateProcessed = never()
		latestReceivedEventEtag = nil
		latestUserEventDateProcessed = never()
		latestUserEventEtag = nil
	}

	class func archiveApiServers() -> [String:[String:NSObject]] {
		var archivedData = [String:[String:NSObject]]()
		for a in ApiServer.allApiServersInMoc(mainObjectContext) {
			if let authToken = a.authToken where !authToken.isEmpty {
				var apiServerData = [String:NSObject]()
				for (k , _) in a.entity.attributesByName {
					if let v = a.valueForKey(k) as? NSObject {
						apiServerData[k] = v
					}
				}
				apiServerData["repos"] = a.archiveRepos()
				archivedData[authToken] = apiServerData
			}
		}
		return archivedData
	}

	func archiveRepos() -> [String : [String : NSObject]] {
		var archivedData = [String : [String : NSObject]]()
		for r in repos {
			if let sid = r.serverId {
				var repoData = [String : NSObject]()
				for (k , _) in r.entity.attributesByName {
					if let v = r.valueForKey(k) as? NSObject {
						repoData[k] = v
					}
				}
				archivedData[sid.stringValue] = repoData
			}
		}
		return archivedData
	}

	class func configureFromArchive(archive: [String : [String : NSObject]]) -> Bool {

		let tempMoc = DataManager.tempContext()

		for apiServer in allApiServersInMoc(tempMoc)
		{
			tempMoc.deleteObject(apiServer)
		}

		for (_, apiServerData) in archive {
			let a = insertNewServerInMoc(tempMoc)
			for (k,v) in apiServerData {
				if k=="repos" {
					a.configureReposFromArchive(v as! [String : [String : NSObject]])
				} else {
					let attributes = Array(a.entity.attributesByName.keys)
					if attributes.contains(k) {
						a.setValue(v, forKey: k)
					}
				}
			}
			a.resetSyncState()
		}

		do {
			try tempMoc.save()
			return true
		} catch _ {
			return false
		}
	}

	func configureReposFromArchive(archive: [String : [String : NSObject]]) {
		for (_, repoData) in archive {
			let r = NSEntityDescription.insertNewObjectForEntityForName("Repo", inManagedObjectContext: managedObjectContext!) as! Repo
			for (k,v) in repoData {
				let attributes = Array(r.entity.attributesByName.keys)
				if attributes.contains(k) {
					r.setValue(v, forKey: k)
				}
				r.apiServer = self
			}
			r.resetSyncState()
		}
	}

}
