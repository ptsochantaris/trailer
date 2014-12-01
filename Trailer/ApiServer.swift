
@objc(ApiServer)
class ApiServer: NSManagedObject {

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

    @NSManaged var comments: NSSet
    @NSManaged var labels: NSSet
    @NSManaged var pullRequests: NSSet
    @NSManaged var repos: NSSet
    @NSManaged var statuses: NSSet

	class func insertNewServerInMoc(moc: NSManagedObjectContext) -> ApiServer {
		let githubServer: ApiServer = NSEntityDescription.insertNewObjectForEntityForName("ApiServer", inManagedObjectContext: moc) as ApiServer
		githubServer.createdAt = NSDate()
		return githubServer
	}

	class func resetSyncSuccessInMoc(moc: NSManagedObjectContext) {
		for apiServer in allApiServersInMoc(moc) {
			if apiServer.goodToGo() {
				apiServer.lastSyncSucceeded = true
			}
		}
	}

	class func shouldReportRefreshFailureInMoc(moc: NSManagedObjectContext) -> Bool {
		for apiServer in allApiServersInMoc(moc) {

			var lastSyncSucceeded = apiServer.lastSyncSucceeded?.boolValue
			if(lastSyncSucceeded==nil) { lastSyncSucceeded!=false }

			if apiServer.goodToGo() && !(lastSyncSucceeded!) && (apiServer.reportRefreshFailures.boolValue) {
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
		return moc.executeFetchRequest(f, error: nil) as [ApiServer]
	}

	class func someServersHaveAuthTokensInMoc(moc: NSManagedObjectContext) -> Bool {
		for apiServer in self.allApiServersInMoc(moc) {
			if apiServer.authToken?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
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
		DLog("Rolling back changes for failed sync on API server %@",label);
		for set in [self.repos, self.pullRequests, self.comments, self.statuses, self.labels] {
			for dataItem: DataItem in set.allObjects as [DataItem] {
				if let action = dataItem.postSyncAction?.integerValue {
					switch action {
					case PostSyncAction.Delete.rawValue:
						dataItem.postSyncAction = PostSyncAction.DoNothing.rawValue
					case PostSyncAction.NoteNew.rawValue:
						moc.deleteObject(dataItem)
					case PostSyncAction.NoteUpdated.rawValue:
						moc.refreshObject(dataItem, mergeChanges: false)
					default: break;
					}
				}
			}
		}
		moc.refreshObject(self, mergeChanges: false)
	}

	func clearAllRelatedInfo() {
		if let moc = self.managedObjectContext {
			for repo in repos.allObjects as [Repo] {
				moc.deleteObject(repo)
			}
		}
	}

	func resetToGithub() {
		webPath = "https://github.com";
		apiPath = "https://api.github.com";
		label = "GitHub";
		latestReceivedEventDateProcessed! = NSDate.distantPast() as NSDate;
		latestUserEventDateProcessed! = NSDate.distantPast() as NSDate;
	}

	func goodToGo() -> Bool {
		return self.authToken?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0
	}
}
