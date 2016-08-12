
import CoreData

final class ApiServer: NSManagedObject {

    @NSManaged var apiPath: String?
    @NSManaged var authToken: String?
    @NSManaged var label: String?
    @NSManaged var lastSyncSucceeded: Bool
    @NSManaged var latestReceivedEventDateProcessed: Date?
    @NSManaged var latestUserEventDateProcessed: Date?
    @NSManaged var reportRefreshFailures: Bool
    @NSManaged var requestsLimit: Int64
    @NSManaged var requestsRemaining: Int64
    @NSManaged var resetDate: Date?
    @NSManaged var userId: Int64
    @NSManaged var userName: String?
    @NSManaged var webPath: String?
	@NSManaged var createdAt: Date?

    @NSManaged var comments: Set<PRComment>
    @NSManaged var labels: Set<PRLabel>
    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var repos: Set<Repo>
    @NSManaged var statuses: Set<PRStatus>
	@NSManaged var teams: Set<Team>
    @NSManaged var issues: Set<Issue>

	static var lastReportedOverLimit = Set<NSManagedObjectID>()
	static var lastReportedNearLimit = Set<NSManagedObjectID>()

	var shouldReportOverTheApiLimit: Bool {
		if requestsRemaining == 0 {
			if !ApiServer.lastReportedOverLimit.contains(objectID) {
				ApiServer.lastReportedOverLimit.insert(objectID)
				return true
			}
		} else {
			ApiServer.lastReportedOverLimit.remove(objectID)
		}
		return false
	}

	var shouldReportCloseToApiLimit: Bool {
		if (100 * requestsRemaining / requestsLimit) < 20 {
			if !ApiServer.lastReportedNearLimit.contains(objectID) {
				ApiServer.lastReportedNearLimit.insert(objectID)
				return true
			}
		} else {
			ApiServer.lastReportedNearLimit.remove(objectID)
		}
		return false
	}

	var hasApiLimit: Bool {
		return requestsLimit > 0
	}

	var goodToGo: Bool {
		return !S(authToken).isEmpty
	}

	class func resetSyncOfEverything() {
		DLog("RESETTING SYNC STATE OF ALL ITEMS")
		for r in DataItem.allItems(ofType: "Repo", in: mainObjectContext) as! [Repo] {
			for p in r.pullRequests {
				p.resetSyncState()
			}
			for i in r.issues {
				i.resetSyncState()
			}
		}
		if app != nil {
			preferencesDirty = true
			api.clearAllBadLinks()
		}
	}

	class func insertNewServer(in moc: NSManagedObjectContext) -> ApiServer {
		let githubServer: ApiServer = NSEntityDescription.insertNewObject(forEntityName: "ApiServer", into: moc) as! ApiServer
		githubServer.createdAt = Date()
		return githubServer
	}

	class func resetSyncSuccess(in moc: NSManagedObjectContext) {
		for apiServer in allApiServers(in: moc) {
			if apiServer.goodToGo {
				apiServer.lastSyncSucceeded = true
			}
		}
	}

	class func shouldReportRefreshFailure(in moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServers(in: moc) {
			if apiServer.goodToGo && !apiServer.lastSyncSucceeded && apiServer.reportRefreshFailures {
				return true
			}
		}
		return false
	}

	class func ensureAtLeastGithub(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		f.fetchLimit = 1
		let numberOfExistingApiServers = try! moc.count(for: f)
		if numberOfExistingApiServers==0 {
			_ = addDefaultGithub(in: moc)
		}
	}

	class func addDefaultGithub(in moc: NSManagedObjectContext) -> ApiServer {
		let githubServer = insertNewServer(in: moc)
		githubServer.resetToGithub()
		return githubServer
	}

	class func allApiServers(in moc: NSManagedObjectContext) -> [ApiServer] {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		f.returnsObjectsAsFaults = false
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
		return try! moc.fetch(f)
	}

	class func someServersHaveAuthTokens(in moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServers(in: moc) {
			if !S(apiServer.authToken).isEmpty {
				return true
			}
		}
		return false
	}

	class func countApiServers(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		return try! moc.count(for: f)
	}

	func rollBackAllUpdates(in moc: NSManagedObjectContext) {
		DLog("Rolling back changes for failed sync on API server '%@'",label)
		for set in [repos, pullRequests, comments, statuses, labels, issues, teams] {
			for dataItem: DataItem in set.allObjects as! [DataItem] {
				switch dataItem.postSyncAction {
				case PostSyncAction.delete.rawValue:
					dataItem.postSyncAction = PostSyncAction.doNothing.rawValue
				case PostSyncAction.noteNew.rawValue:
					moc.delete(dataItem)
				case PostSyncAction.noteUpdated.rawValue:
					moc.refresh(dataItem, mergeChanges: false)
				default: break
				}
			}
		}
		moc.refresh(self, mergeChanges: false)
	}

	func clearAllRelatedInfo() {
		if let moc = managedObjectContext {
			for r in repos {
				moc.delete(r)
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
			lastRepoCheck = Date.distantPast
		}
		lastSyncSucceeded = true
		latestReceivedEventDateProcessed = Date.distantPast
		latestUserEventDateProcessed = Date.distantPast
	}

	class var archivedApiServers: [String : [String : NSObject]] {
		var archivedData = [String:[String : NSObject]]()
		for a in ApiServer.allApiServers(in: mainObjectContext) {
			if let authToken = a.authToken, !authToken.isEmpty {
				var apiServerData = [String : NSObject]()
				for (k , _) in a.entity.attributesByName {
					if let v = a.value(forKey: k) as? NSObject {
						apiServerData[k] = v
					}
				}
				apiServerData["repos"] = a.archivedRepos
				archivedData[authToken] = apiServerData
			}
		}
		return archivedData
	}

	var archivedRepos: [String : [String : NSObject]] {
		var archivedData = [String : [String : NSObject]]()
		for r in repos {
			var repoData = [String : NSObject]()
			for (k , _) in r.entity.attributesByName {
				if let v = r.value(forKey: k) as? NSObject {
					repoData[k] = v
				}
			}
			archivedData["\(r.serverId)"] = repoData
		}
		return archivedData
	}

	class func configure(from archive: [String : [String : NSObject]]) -> Bool {

		let tempMoc = DataManager.buildChildContext()

		for apiServer in allApiServers(in: tempMoc)
		{
			tempMoc.delete(apiServer)
		}

		for (_, apiServerData) in archive {
			let a = insertNewServer(in: tempMoc)
			for (k,v) in apiServerData {
				if k=="repos" {
					let archive = v as! [String : [String : NSObject]]
					a.configureRepos(from: archive)
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
		} catch {
			return false
		}
	}

	func configureRepos(from archive: [String : [String : NSObject]]) {
		for (_, repoData) in archive {
			let r = NSEntityDescription.insertNewObject(forEntityName: "Repo", into: managedObjectContext!) as! Repo
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
