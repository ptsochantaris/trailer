import CoreData
import CommonCrypto

final class API {

	static var currentNetworkStatus = NetworkStatus.NotReachable
    
    static let cacheDirectory: String = {
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer").path
	}()
    
	private static let reachability = Reachability()

	static func setup() {

		reachability.startNotifier()

		let n = reachability.status
		DLog("Network is %@", n.name)
		currentNetworkStatus = n

		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: cacheDirectory) {
			expireOldImageCacheEntries()
		} else {
			try! fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
		}

		NotificationCenter.default.addObserver(forName: ReachabilityChangedNotification, object: nil, queue: .main) { _ in
			checkNetworkAvailability()
			if currentNetworkStatus != .NotReachable {
				app.startRefreshIfItIsDue()
			}
		}
	}

	private static func checkNetworkAvailability() {
		let newStatus = reachability.status
		if newStatus != currentNetworkStatus {
			currentNetworkStatus = newStatus
			DLog("Network changed to %@", newStatus.name)
		}
	}

	static var hasNetworkConnection: Bool {
		DLog("Actively verifying reported network availability state…")
		let previousNetworkStatus = currentNetworkStatus
		checkNetworkAvailability()
		if previousNetworkStatus != currentNetworkStatus {
			DLog("Network state seems to have changed without having been notified, noted")
		} else {
			DLog("No change to network state")
		}
		return currentNetworkStatus != .NotReachable
	}

	/////////////////////////////////////////////////////// Utilities
    
    static var currentOperationName = lastSuccessfulSyncAt {
        didSet {
            assert(Thread.isMainThread)
            DLog("Status update: \(currentOperationName)")
            NotificationCenter.default.post(name: .SyncProgressUpdate, object: nil)
        }
    }
    static var currentOperationCount = 0 {
        didSet {
            let newValue = currentOperationCount
            if oldValue == 0 && newValue > 0 {
                #if os(iOS)
                BackgroundTask.registerForBackground()
                #endif
            } else if oldValue > 0 && newValue == 0 {
                #if os(iOS)
                BackgroundTask.unregisterForBackground()
                #endif
            }
            
            if isRefreshing && currentOperationName.hasPrefix("Fetching…") {
                if newValue > 1 {
                    currentOperationName = "Fetching… (\(newValue) calls queued)"
                } else {
                    currentOperationName = "Fetching…"
                }
            }
        }
    }
    
    static var isRefreshing = false {
        didSet {
            if oldValue == isRefreshing {
                return
            }
            if isRefreshing {
                DLog("Starting refresh")
                DataManager.postMigrationTasks()
                NotificationQueue.clear()
                NotificationCenter.default.post(name: .RefreshStarting, object: nil)
            } else {
                DLog("Refresh done")
                if ApiServer.shouldReportRefreshFailure(in: DataManager.main) {
                    currentOperationName = "Last update failed"
                    NotificationCenter.default.post(name: .RefreshEnded, object: false)
                } else {
                    Settings.lastSuccessfulRefresh = Date()
                    currentOperationName = lastSuccessfulSyncAt
                    NotificationCenter.default.post(name: .RefreshEnded, object: true)
                }
            }
        }
    }

    static var shouldSyncReactions: Bool {
        return Settings.notifyOnItemReactions || Settings.notifyOnCommentReactions
    }
    static var shouldSyncReviews: Bool {
        return Settings.displayReviewsOnItems || Settings.notifyOnReviewDismissals || Settings.notifyOnReviewAcceptances || Settings.notifyOnReviewChangeRequests
    }
    static var shouldSyncReviewAssignments: Bool {
        return Settings.displayReviewsOnItems || Settings.showRequestedTeamReviews || Settings.notifyOnReviewAssignments || (Int64(Settings.assignedReviewHandlingPolicy) != Section.none.rawValue)
    }

	///////////////////////////////////////////////////////// Images

	private static func expireOldImageCacheEntries() {
		let now = Date()
		let fileManager = FileManager.default
		for f in try! fileManager.contentsOfDirectory(atPath: cacheDirectory) where f.hasPrefix("imgc-") {
            do {
                let path = cacheDirectory.appending(pathComponent: f)
                let attributes = try fileManager.attributesOfItem(atPath: path)
                if let date = attributes[.creationDate] as? Date, now.timeIntervalSince(date) > 3600 * 24 {
                    try? fileManager.removeItem(atPath: path)
                }
            } catch {
                DLog("File error when removing old cached image: %@", error.localizedDescription)
            }
		}
	}

    private static func sha1(_ input: String) -> Data {
        return input.utf8CString.withUnsafeBytes { bytes -> Data in
            let len = Int(CC_SHA1_DIGEST_LENGTH)
            var digest = [UInt8](repeating: 0, count: len)
            CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count), &digest)
            return Data(bytes: digest, count: len)
        }
    }

	@discardableResult @MainActor
	static func avatar(from path: String) async throws -> (IMAGE_CLASS, String) {

		let connector = path.contains("?") ? "&" : "?"
        let absolutePath = "\(path)\(connector)s=128"
        let hash = sha1("\(absolutePath) \(currentAppVersion)").base64EncodedString()
		let cachePath = cacheDirectory.appending(pathComponent: "imgc-\(hash)")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cachePath) {
            if let imgData = try? Data(contentsOf: URL(fileURLWithPath: cachePath)), let r = IMAGE_CLASS(data: imgData) {
                return (r, cachePath)
            } else {
                try fileManager.removeItem(atPath: cachePath)
            }
        }

        guard let url = URL(string: absolutePath) else {
            throw apiError("Invalid URL")
        }

        #if os(iOS)
        BackgroundTask.registerForBackground()
        defer {
            BackgroundTask.unregisterForBackground()
        }
        #endif
        let data = try await HTTP.getData(from: url).0
        guard let i = IMAGE_CLASS(data: data) else {
            throw apiError("Invalid image data")
        }
        
        try data.write(to: URL(fileURLWithPath: cachePath))
        return (i, cachePath)
	}

	////////////////////////////////////// API interface

    @MainActor
	static func performSync() async {

        let syncContext = DataManager.buildChildContext()

        if Settings.useV4API && canUseV4API(for: syncContext) != nil {
            return
        }
        
        isRefreshing = true
        currentOperationCount += 1
        currentOperationName = "Fetching…"

		let shouldRefreshReposToo = lastRepoCheck == .distantPast
			|| (Date().timeIntervalSince(lastRepoCheck) > TimeInterval(Settings.newRepoCheckPeriod * 3600))
			|| !Repo.anyVisibleRepos(in: syncContext)
        
		if shouldRefreshReposToo {
			await fetchRepositories(to: syncContext)
            await sync(to: syncContext)

        } else {
			ApiServer.resetSyncSuccess(in: syncContext)
			await ensureApiServersHaveUserIds(in: syncContext)
            await sync(to: syncContext)
		}
	}
    
    @MainActor
    private static func sync(to moc: NSManagedObjectContext) async {
        
        let disabledRepos = Repo.unsyncableRepos(in: moc)
        disabledRepos.forEach {
            $0.pullRequests.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
            $0.issues.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        let repos = Repo.syncableRepos(in: moc)
        let v4Mode = Settings.useV4API

        assert(Thread.isMainThread)
        await withTaskGroup(of: Void.self) { group in
            if v4Mode {
                let servers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
                if !servers.isEmpty {
                    group.addTask {
                        await GraphQL.fetchAllAuthoredItems(from: servers)
                    }
                }
                if !repos.isEmpty {
                    group.addTask {
                        await GraphQL.fetchAllSubscribedItems(from: repos)
                    }
                }
            } else {
                group.addTask {
                    await v3_fetchItems(for: repos, to: moc)
                }
            }
        }
            
        let reposWithSomeItems = repos.filter { !$0.issues.isEmpty || !$0.pullRequests.isEmpty }
        if v4Mode {
            let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)
            let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)
            await v4Sync(to: moc, newOrUpdatedPrs: newOrUpdatedPrs, newOrUpdatedIssues: newOrUpdatedIssues)
        } else {
            await V3_markExtraUpdatedItems(from: reposWithSomeItems, to: moc)
            let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)
            let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)
            await v3Sync(to: moc, newOrUpdatedPrs: newOrUpdatedPrs, newOrUpdatedIssues: newOrUpdatedIssues)
        }
            
        completeSync(in: moc)
	}

	private static func completeSync(in moc: NSManagedObjectContext) {

        let processMoc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        processMoc.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        processMoc.undoManager = nil
        processMoc.parent = moc
        processMoc.perform {
            // discard any changes related to any failed API server
            for apiServer in ApiServer.allApiServers(in: processMoc) where !apiServer.lastSyncSucceeded {
                apiServer.rollBackAllUpdates(in: processMoc)
                apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
            }
            DataItem.nukeDeletedItems(in: processMoc)
            DataItem.nukeOrphanedItems(in: processMoc)
            DataManager.postProcessAllItems(in: processMoc)
            if processMoc.hasChanges {
                try? processMoc.save()
            }
            DispatchQueue.main.async {
                completeSync2(in: moc)
            }
        }

        let total = moc.updatedObjects.count + moc.insertedObjects.count + moc.deletedObjects.count
        if total > 1, let totalText = numberFormatter.string(for: total) {
            currentOperationName = "Processing \(totalText) items…"
        } else {
            currentOperationName = "Processing update…"
        }
        DLog("Caching \(numberFormatter.string(for: URLCache.shared.currentMemoryUsage) ?? "") bytes in memory")
        DLog("Caching \(numberFormatter.string(for: URLCache.shared.currentDiskUsage) ?? "") bytes on disk")
	}
    
    private static func completeSync2(in moc: NSManagedObjectContext) {
        do {
            if moc.hasChanges {
                DLog("Committing synced data")
                try moc.save()
                DLog("Synced data committed")
            } else {
                DLog("No changes, skipping commit")
            }
        } catch {
            DLog("Committing sync failed: %@", error.localizedDescription)
        }
        
        isRefreshing = false
        currentOperationCount -= 1
        
        DataManager.sendNotificationsIndexAndSave()
    }
    
    static var lastSuccessfulSyncAt: String {
        let last = Settings.lastSuccessfulRefresh ?? Date()
        return agoFormat(prefix: "updated", since: last).capitalFirstLetter
    }

    @MainActor
	private static func fetchUserTeams(from server: ApiServer) async {
		for t in server.teams {
			t.postSyncAction = PostSyncAction.delete.rawValue
		}

        let (success, _) = await RestAccess.getPagedData(at: "/user/teams", from: server) { data, _ in
            Team.syncTeams(from: data, server: server)
            return false
        }
        if !success {
            server.lastSyncSucceeded = false
        }
	}

    @MainActor
	static func fetchRepositories(to moc: NSManagedObjectContext) async {
        
        assert(Thread.isMainThread)
		ApiServer.resetSyncSuccess(in: moc)

        assert(Thread.isMainThread)
		await syncUserDetails(in: moc)
            
        assert(Thread.isMainThread)
        for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
            r.postSyncAction = r.shouldBeWipedIfNotInWatchlist ? PostSyncAction.delete.rawValue : PostSyncAction.doNothing.rawValue
        }

        let goodToGoServers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
        await withTaskGroup(of: Void.self) { group in
            for apiServer in goodToGoServers {
                
                group.addTask {
                    await syncWatchedRepos(from: apiServer)
                }
                
                group.addTask {
                    await syncManuallyAddedRepos(from: apiServer)
                }
                
                group.addTask {
                    await fetchUserTeams(from: apiServer)
                }
            }
        }
        
        assert(Thread.isMainThread)
        if Settings.hideArchivedRepos { Repo.hideArchivedRepos(in: moc) }
        for r in DataItem.newItems(of: Repo.self, in: moc) where r.shouldSync {
            NotificationQueue.add(type: .newRepoAnnouncement, for: r)
        }
        lastRepoCheck = Date()
        assert(Thread.isMainThread)
	}

    @MainActor
	private static func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext) async {
		var needToCheck = false
		for apiServer in ApiServer.allApiServers(in: moc) {
            if apiServer.userNodeId == nil || (apiServer.userName?.isEmpty ?? true) {
				needToCheck = true
				break
			}
		}

		if needToCheck {
			DLog("Some API servers don't have user details yet, will bring user credentials down for them")
			await syncUserDetails(in: moc)
		}
	}

    @MainActor
    private static func getRateLimit(from server: ApiServer) async -> ApiStats? {
        
        do {
            let (_, headers, _) = try await RestAccess.start(call: "/rate_limit", on: server, triggeredByUser: true)
            if let h = headers {
                return ApiStats.fromV3(headers: h)
            }
        } catch {
            let code = (error as NSError).code
            if code == 404 { // is GE account
                return ApiStats.noLimits
            }
        }
        return nil
    }

    @MainActor
	static func updateLimitsFromServer() async {
		let configuredServers = ApiServer.allApiServers(in: DataManager.main).filter { $0.goodToGo }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for apiServer in configuredServers {
                    if let l = await getRateLimit(from: apiServer) {
                        apiServer.updateApiStats(l)
                    }
                }
            }
        }
	}

    @MainActor
	private static func syncManuallyAddedRepos(from server: ApiServer) async {
		if !server.lastSyncSucceeded {
			return
		}

		let repos = server.repos.filter { $0.manuallyAdded }
        await withTaskGroup(of: Void.self) { group in
            for repo in repos {
                group.addTask {
                    do {
                        try await fetchRepo(fullName: repo.fullName ?? "", from: server)
                    } catch {
                        server.lastSyncSucceeded = false
                    }
                }
            }
        }
	}

    @MainActor
    private static func syncWatchedRepos(from server: ApiServer) async {
        if !server.lastSyncSucceeded {
            return
        }
        
        let createNewRepos = Settings.automaticallyRemoveDeletedReposFromWatchlist
        let (success, _) = await RestAccess.getPagedData(at: "/user/subscriptions", from: server) { data, _ in
            Repo.syncRepos(from: data, server: server, addNewRepos: createNewRepos, manuallyAdded: false)
            return false
        }
        if !success {
            server.lastSyncSucceeded = false
        } else if !Settings.automaticallyRemoveDeletedReposFromWatchlist { // Ignore any missing repos in all cases if deleteGoneRepos is false
            let reposThatWouldBeDeleted = Repo.items(of: Repo.self, surviving: false, in: server.managedObjectContext!)
            for r in reposThatWouldBeDeleted {
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
	}

    @MainActor
	static func fetchRepo(fullName: String, from server: ApiServer) async throws {
		let path = "\(server.apiPath ?? "")/repos/\(fullName)"
        do {
            let (data, _, _) = try await RestAccess.getData(in: path, from: server)
            if let repoData = data as? [AnyHashable: Any] {
                Repo.syncRepos(from: [repoData], server: server, addNewRepos: true, manuallyAdded: true)
            }
        } catch {
            let resultCode = (error as NSError).code
            throw apiError("Operation failed with code \(resultCode)")
        }
	}

    @MainActor
	static func fetchAllRepos(owner: String, from server: ApiServer) async throws {

        let userPath = "\(server.apiPath ?? "")/users/\(owner)/repos"
        let userTask = Task { () -> [[AnyHashable: Any]] in
            var userList = [[AnyHashable: Any]]()
            let (success, resultCode) = await RestAccess.getPagedData(at: userPath, from: server) { data, _ -> Bool in
                if let data = data {
                    userList.append(contentsOf: data)
                }
                return false
            }
            if success {
                return userList
            } else {
                throw apiError("Operation failed with code \(resultCode)")
            }
        }
        
        let orgPath = "\(server.apiPath ?? "")/orgs/\(owner)/repos"
        let orgTask = Task { () -> [[AnyHashable: Any]] in
            var orgList = [[AnyHashable: Any]]()
            let (success, resultCode) = await RestAccess.getPagedData(at: orgPath, from: server) { data, _ -> Bool in
                if let data = data {
                    orgList.append(contentsOf: data)
                }
                return false
            }
            if success {
                return orgList
            } else {
                throw apiError("Operation failed with code \(resultCode)")
            }
        }

        let userList = try await userTask.value
        let orgList = try await orgTask.value

        Repo.syncRepos(from: userList+orgList, server: server, addNewRepos: true, manuallyAdded: true)
	}

    @MainActor
	static func fetchRepo(named: String, owner: String, from server: ApiServer) async throws {
		try await fetchRepo(fullName: "\(owner)/\(named)", from: server)
	}

    @MainActor
	private static func syncUserDetails(in moc: NSManagedObjectContext) async {
		let configuredServers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
        assert(Thread.isMainThread)
        await withTaskGroup(of: Void.self) { group in
            for apiServer in configuredServers {
                group.addTask {
                    do {
                        let (data, _, _) = try await RestAccess.getData(in: "/user", from: apiServer)
                        assert(Thread.isMainThread)
                        if let d = data as? [AnyHashable: Any] {
                            apiServer.userName = d["login"] as? String
                            apiServer.userNodeId = d["node_id"] as? String
                        } else {
                            apiServer.lastSyncSucceeded = false
                        }
                    } catch {
                        apiServer.lastSyncSucceeded = false
                    }
                }
            }
        }
	}

    @MainActor
	static func testApi(to apiServer: ApiServer) async throws {
        let (_, _, data) = try await RestAccess.start(call: "/user", on: apiServer, triggeredByUser: true)
        if let d = data as? [AnyHashable: Any], let userName = d["login"] as? String, let userId = d["id"] as? Int64 {
            if userName.isEmpty || userId <= 0 {
                let localError = apiError("Could not read a valid user record from this endpoint")
                throw localError
            }
		}
	}

	static func apiError(_ message: String) -> Error {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}
}
