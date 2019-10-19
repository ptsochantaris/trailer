
import CoreData

final class ApiServer: NSManagedObject {

    @NSManaged var apiPath: String?
    @NSManaged var authToken: String?
    @NSManaged var label: String?
    @NSManaged var lastSyncSucceeded: Bool
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
	@NSManaged var reviews: Set<Review>
	@NSManaged var reactions: Set<Reaction>

	static var lastReportedOverLimit = Set<NSManagedObjectID>()
	static var lastReportedNearLimit = Set<NSManagedObjectID>()

	var shouldReportOverTheApiLimit: Bool {
		if requestsRemaining == 0 {
			if !ApiServer.lastReportedOverLimit.contains(objectID) {
				ApiServer.lastReportedOverLimit.insert(objectID)
				ApiServer.lastReportedNearLimit.insert(objectID) // so if we start over the limit, we don't also warn about being near the limit
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

	static func resetSyncOfEverything() {
		DLog("RESETTING SYNC STATE OF ALL ITEMS")
		for r in DataItem.allItems(of: Repo.self, in: DataManager.main, prefetchRelationships: ["pullRequests", "issues"]) {
			for p in r.pullRequests {
				p.resetSyncState()
			}
			for i in r.issues {
				i.resetSyncState()
			}
		}
		if app != nil {
			preferencesDirty = true
			API.clearAllBadLinks()
		}
	}

	static func insertNewServer(in moc: NSManagedObjectContext) -> ApiServer {
		let githubServer: ApiServer = NSEntityDescription.insertNewObject(forEntityName: "ApiServer", into: moc) as! ApiServer
		githubServer.createdAt = Date()
		return githubServer
	}

	static func resetSyncSuccess(in moc: NSManagedObjectContext) {
		for apiServer in allApiServers(in: moc) {
			if apiServer.goodToGo {
				apiServer.lastSyncSucceeded = true
			}
		}
	}

	static func shouldReportRefreshFailure(in moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServers(in: moc) {
			if apiServer.goodToGo && !apiServer.lastSyncSucceeded && apiServer.reportRefreshFailures {
				return true
			}
		}
		return false
	}

	static func ensureAtLeastGithub(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		f.fetchLimit = 1
		let numberOfExistingApiServers = try! moc.count(for: f)
		if numberOfExistingApiServers==0 {
			addDefaultGithub(in: moc)
		}
	}

	@discardableResult
	static func addDefaultGithub(in moc: NSManagedObjectContext) -> ApiServer {
		let githubServer = insertNewServer(in: moc)
		githubServer.resetToGithub()
		return githubServer
	}

	static func allApiServers(in moc: NSManagedObjectContext) -> [ApiServer] {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
		return try! moc.fetch(f)
	}

	static func someServersHaveAuthTokens(in moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServers(in: moc) {
			if !S(apiServer.authToken).isEmpty {
				return true
			}
		}
		return false
	}

	static func countApiServers(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
		f.includesSubentities = false
		return try! moc.count(for: f)
	}

	func rollBackAllUpdates(in moc: NSManagedObjectContext) {
		DLog("Rolling back changes for failed sync on API server '%@'",label)
		for set in [repos, pullRequests, comments, statuses, labels, issues, teams, reviews, reactions] as [Set<DataItem>] {
			var i = set.makeIterator()
			while let dataItem = i.next() {
				switch dataItem.postSyncAction {
				case PostSyncAction.delete.rawValue:
					dataItem.postSyncAction = PostSyncAction.doNothing.rawValue
				case PostSyncAction.isNew.rawValue:
					moc.delete(dataItem)
				case PostSyncAction.isUpdated.rawValue:
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

	func updateApiLimits(_ limits: ApiRateLimits) {
		requestsRemaining = limits.requestsRemaining
		requestsLimit = limits.requestLimit
		resetDate = limits.resetDate
        NotificationCenter.default.post(name: .ApiUsageUpdate, object: self, userInfo: nil)
	}

	func resetToGithub() {
		webPath = "https://github.com"
		apiPath = "https://api.github.com"
		label = "GitHub"
		resetSyncState()
	}

	func resetSyncState() {
		if app != nil {
			lastRepoCheck = .distantPast
		}
		lastSyncSucceeded = true
	}

	var isGitHub: Bool {
		return apiPath?.hasPrefix("https://api.github.com") ?? true
	}

	static func server(host: String, moc: NSManagedObjectContext) -> ApiServer? {
		for s in ApiServer.allApiServers(in: moc) {
			if let apiBase = s.apiPath,
				let c = URLComponents(string: apiBase),
				let serverHost = c.host {

				if serverHost == host {
					return s
				}
			}
			if let webBase = s.webPath,
				let c = URLComponents(string: webBase),
				let serverHost = c.host {

				if serverHost == host {
					return s
				}
			}
		}
		return nil
	}

	static var archivedApiServers: [AnyHashable : [AnyHashable : Any]] {
		var archivedData = [AnyHashable : [AnyHashable : Any]]()
		for a in ApiServer.allApiServers(in: DataManager.main) {
			if let authToken = a.authToken, !authToken.isEmpty {
				var apiServerData = [AnyHashable : Any]()
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

	var archivedRepos: [AnyHashable : [AnyHashable : Any]] {
		var archivedData = [AnyHashable : [AnyHashable : Any]]()
		for r in repos {
			var repoData = [AnyHashable : Any]()
			for (k , _) in r.entity.attributesByName {
				if let v = r.value(forKey: k) as? NSObject {
					repoData[k] = v
				}
			}
			archivedData["\(r.serverId)"] = repoData
		}
		return archivedData
	}

	static func configure(from archive: [String : [String : NSObject]]) -> Bool {

		let tempMoc = DataManager.buildChildContext()

		for apiServer in allApiServers(in: tempMoc) {
			tempMoc.delete(apiServer)
		}

		for (_, apiServerData) in archive {
			let a = insertNewServer(in: tempMoc)
			for (k,v) in apiServerData {
				if k == "repos" {
					let archive = v as! [String : [String : NSObject]]
					a.configureRepos(from: archive)
				} else {
					if a.entity.attributesByName.keys.contains(k) {
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
		guard let moc = managedObjectContext else { return }
		for (_, repoData) in archive {
			let r = NSEntityDescription.insertNewObject(forEntityName: "Repo", into: moc) as! Repo
			for (k,v) in repoData {
				if r.entity.attributesByName.keys.contains(k) {
					r.setValue(v, forKey: k)
				}
			}
			r.apiServer = self
			r.resetSyncState()
			r.postSyncAction = PostSyncAction.isUpdated.rawValue
		}
	}

}
