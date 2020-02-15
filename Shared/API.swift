
import CoreData
#if os(iOS)
	import UIKit
#endif

final class API {

	static var currentNetworkStatus = NetworkStatus.NotReachable
    
	private static let cacheDirectory = { ()->String in
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer").path
	}()

	private static let sessionCallbackQueue: OperationQueue = {
		let o = OperationQueue()
        o.qualityOfService = .utility
		o.maxConcurrentOperationCount = 1 // has to be one, as per API spec
		return o
	}()
        
    private static var urlSessionConfig: URLSessionConfiguration {
        #if DEBUG
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Development"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Development"
            #endif
        #else
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Release"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Release"
            #endif
        #endif

        let config = URLSessionConfiguration.default
        config.httpShouldUsePipelining = true
        config.httpAdditionalHeaders = ["User-Agent" : userAgent]
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, diskPath: cacheDirectory)
        return config
    }

    private static let urlSession: URLSession = {
        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: sessionCallbackQueue)
    }()
    
    private static let imageQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 8
        q.qualityOfService = .background
        return q
    }()
    
    static func task(for request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return urlSession.dataTask(with: request, completionHandler: completion)
    }
    
    private final class ApiOperation: BlockOperation {
        var onRun: (()->Void)?
        override func start() {
            onRun?()
            super.start()
        }
    }
    
    static func submitDataTask(_ task: URLSessionDataTask, on queue: OperationQueue, onRun: (()->Void)? = nil) {
        currentOperationCount += 1
        let group = DispatchGroup()
        group.enter()
        
        var previousState = task.state
        let o = task.observe(\.state) { t, _ in
            let newState = t.state
            if previousState != newState {
                if previousState == .running && newState != .running {
                    group.leave()
                } else if previousState != .running && newState == .running {
                    onRun?()
                }
                previousState = newState
            }
        }
        
        queue.addOperation {
            task.resume()
            group.wait()
            withExtendedLifetime(o) {
                currentOperationCount -= 1
            }
        }
    }

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

		NotificationCenter.default.addObserver(forName: ReachabilityChangedNotification, object: nil, queue: .main) { n in
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
			RestAccess.clearAllBadLinks()
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
    private static var currentOperationCount = 0 {
        didSet {
            let newValue = currentOperationCount
            DispatchQueue.main.async {
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
    }
    static var isRefreshing = false

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
		for f in try! fileManager.contentsOfDirectory(atPath: cacheDirectory) {
			if f.hasPrefix("imgcache-") {
				do {
					let path = cacheDirectory.appending(pathComponent: f)
					let attributes = try fileManager.attributesOfItem(atPath: path)
					let date = attributes[.creationDate] as! Date
					if now.timeIntervalSince(date) > (3600.0*24.0) {
						try? fileManager.removeItem(atPath: path)
					}
				} catch {
					DLog("File error when cleaning old cached image: %@", error.localizedDescription)
				}
			}
		}
	}

	@discardableResult
	static func haveCachedAvatar(from path: String, callback: @escaping (IMAGE_CLASS?, String) -> Void) -> Bool {

		func getImage(at imagePath: String, completion: @escaping (Data?) -> Void) {

			guard let url = URL(string: imagePath) else {
				completion(nil)
				return
			}
            
			let task = urlSession.dataTask(with: url) { data, response, error in
				if error == nil, let d = data, let r = response as? HTTPURLResponse, r.statusCode < 300, r.expectedContentLength == Int64(d.count) {
					completion(d)
				} else {
					completion(nil)
				}
			}
            
            submitDataTask(task, on: imageQueue)
		}

		let connector = path.contains("?") ? "&" : "?"
        let absolutePath = "\(path)\(connector)s=256"
		let md5 = MD5Hashing.md5(str: "\(absolutePath) \(currentAppVersion)")
		let cachePath = cacheDirectory.appending(pathComponent: "imgc-\(md5)")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cachePath) {
            if let imgData = try? Data(contentsOf: URL(fileURLWithPath: cachePath)), let r = IMAGE_CLASS(data: imgData) {
                DispatchQueue.main.async {
                    callback(r, cachePath)
                }
                return true
            } else {
                try? fileManager.removeItem(atPath: cachePath)
            }
        }

        #if os(iOS)
        BackgroundTask.registerForBackground()
        #endif
		getImage(at: absolutePath) { data in
			// in thread
			var result: IMAGE_CLASS?
            if let d = data, let i = IMAGE_CLASS(data: d) {
                result = i
                try? d.write(to: URL(fileURLWithPath: cachePath))
            }
            DispatchQueue.main.async {
				callback(result, cachePath)
				#if os(iOS)
                BackgroundTask.unregisterForBackground()
				#endif
			}
		}
		return false
	}

	////////////////////////////////////// API interface

	static func performSync(callback: @escaping (Bool)->Void) {

        let syncContext = DataManager.buildChildContext()

        if Settings.useV4API && canUseV4API(for: syncContext) != nil {
            callback(false)
            return
        }
        
        isRefreshing = true
        currentOperationCount += 1
        currentOperationName = "Fetching…"

		let shouldRefreshReposToo = lastRepoCheck == .distantPast
			|| (Date().timeIntervalSince(lastRepoCheck) > TimeInterval(Settings.newRepoCheckPeriod * 3600))
			|| !Repo.anyVisibleRepos(in: syncContext)
        
		if shouldRefreshReposToo {
			fetchRepositories(to: syncContext) {
				sync(to: syncContext, callback: callback)
			}
		} else {
			ApiServer.resetSyncSuccess(in: syncContext)
			ensureApiServersHaveUserIds(in: syncContext) {
				sync(to: syncContext, callback: callback)
			}
		}
	}
    
    private static func sync(to moc: NSManagedObjectContext, callback: @escaping (Bool)->Void) {
                
        let repos = Repo.syncableRepos(in: moc)
        let itemGroup = DispatchGroup()
        let v4Mode = Settings.useV4API

        if v4Mode {
            let disabledRepos = Repo.unsyncableRepos(in: moc)
            disabledRepos.forEach {
                $0.pullRequests.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
                $0.issues.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
            
            GraphQL.fetchAllPrsAndIssues(from: repos, group: itemGroup)
        } else {
            itemGroup.enter()
            fetchIssues(for: repos, to: moc) {
                itemGroup.leave()
            }

            itemGroup.enter()
            fetchPullRequests(for: repos, to: moc) {
                itemGroup.leave()
            }
        }
        
        let postItemGroup = DispatchGroup()
        postItemGroup.enter()
        itemGroup.notify(queue: .main) {
            let reposWithSomeItems = repos.filter { !$0.issues.isEmpty || !$0.pullRequests.isEmpty }
            if v4Mode {
                let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)
                let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)
                v4Sync(to: moc, newOrUpdatedPrs: newOrUpdatedPrs, newOrUpdatedIssues: newOrUpdatedIssues, with: postItemGroup)
            } else {
                V3_markExtraUpdatedItems(from: reposWithSomeItems, to: moc) {
                    let newOrUpdatedPrs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc, fromSuccessfulSyncOnly: true)
                    let newOrUpdatedIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc, fromSuccessfulSyncOnly: true)
                    v3Sync(to: moc, newOrUpdatedPrs: newOrUpdatedPrs, newOrUpdatedIssues: newOrUpdatedIssues, with: postItemGroup)
                }
            }
        }
        
        postItemGroup.notify(queue: .main) {
            completeSync(in: moc, andCallback: callback)
        }
	}

	private static func completeSync(in moc: NSManagedObjectContext, andCallback: @escaping (Bool) -> Void) {

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
                completeSync2(in: moc, andCallback: andCallback)
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
    
    private static func completeSync2(in moc: NSManagedObjectContext, andCallback: @escaping (Bool) -> Void) {
        var success = false
        
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
        
        if ApiServer.shouldReportRefreshFailure(in: DataManager.main) {
            currentOperationName = "Last update failed"
        } else {
            Settings.lastSuccessfulRefresh = Date()
            currentOperationName = lastSuccessfulSyncAt
            success = true
        }
        isRefreshing = false
        currentOperationCount -= 1
        
        DataManager.sendNotificationsIndexAndSave()
        andCallback(success)
    }
    
    static var lastSuccessfulSyncAt: String {
        let last = Settings.lastSuccessfulRefresh ?? Date()
        return agoFormat(prefix: "updated", since: last).capitalFirstLetter
    }

	private static func fetchUserTeams(from server: ApiServer, callback: @escaping Completion) {
		for t in server.teams {
			t.postSyncAction = PostSyncAction.delete.rawValue
		}

        RestAccess.getPagedData(at: "/user/teams", from: server, perPageCallback: { data, lastPage in
			Team.syncTeams(from: data, server: server)
			return false
		}) { success, resultCode in
			if !success {
				server.lastSyncSucceeded = false
			}
			callback()
		}
	}

	static func fetchRepositories(to moc: NSManagedObjectContext, callback: @escaping Completion) {
        
		ApiServer.resetSyncSuccess(in: moc)
        RestAccess.clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

        let group = DispatchGroup()
        
        group.enter()
		syncUserDetails(in: moc) {
            
			for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
				r.postSyncAction = r.manuallyAdded ? PostSyncAction.doNothing.rawValue : PostSyncAction.delete.rawValue
			}

            let goodToGoServers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
			for apiServer in goodToGoServers {
                
                group.enter()
                syncWatchedRepos(from: apiServer) {
                    group.leave()
                }
                
                group.enter()
				syncManuallyAddedRepos(from: apiServer) {
                    group.leave()
                }
                
                group.enter()
				fetchUserTeams(from: apiServer) {
                    group.leave()
                }
			}
            
            group.leave() // syncUserDetails
		}
        
        group.notify(queue: .main) {
            if Settings.hideArchivedRepos { Repo.hideArchivedRepos(in: moc) }
            for r in DataItem.newItems(of: Repo.self, in: moc) {
                if r.shouldSync {
                    NotificationQueue.add(type: .newRepoAnnouncement, for: r)
                }
            }
            lastRepoCheck = Date()
            callback()
        }
	}

	private static func fetchPullRequests(for repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

		for r in Repo.unsyncableRepos(in: moc) {
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

        let group = DispatchGroup()
        
		for r in repos {
			for p in r.pullRequests {
				if p.condition == ItemCondition.open.rawValue {
					p.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer
			if apiServer.lastSyncSucceeded && r.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue {
				let repoFullName = S(r.fullName)
                group.enter()
				RestAccess.getPagedData(at: "/repos/\(repoFullName)/pulls", from: apiServer, perPageCallback: { data, lastPage in
					PullRequest.syncPullRequests(from: data, in: r)
					return false
				}) { success, resultCode in
					if !success {
						handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
                    group.leave()
				}
			}
		}
        
        group.notify(queue: .main, execute: callback)
	}

	private static func handleRepoSyncFailure(repo: Repo, resultCode: Int64) {
		if resultCode == 404 { // repo disabled
			repo.inaccessible = true
			repo.postSyncAction = PostSyncAction.doNothing.rawValue
			for p in repo.pullRequests {
				p.postSyncAction = PostSyncAction.delete.rawValue
			}
			for i in repo.issues {
				i.postSyncAction = PostSyncAction.delete.rawValue
			}
		} else if resultCode==410 { // repo gone for good
			repo.postSyncAction = PostSyncAction.delete.rawValue
		} else { // fetch problem
			repo.apiServer.lastSyncSucceeded = false
		}
	}

	private static func fetchIssues(for repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

		for r in Repo.unsyncableRepos(in: moc) {
			for i in r.issues {
				i.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

        let group = DispatchGroup()

        for r in repos {
			for i in r.issues {
				if i.condition == ItemCondition.open.rawValue {
					i.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer
			if apiServer.lastSyncSucceeded && r.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue {
				let repoFullName = S(r.fullName)
                group.enter()
				RestAccess.getPagedData(at: "/repos/\(repoFullName)/issues", from: apiServer, perPageCallback: { data, lastPage in
					Issue.syncIssues(from: data, in: r)
					return false
				}) { success, resultCode in
					if !success {
						handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
                    group.leave()
				}
			}
		}
        
        group.notify(queue: .main, execute: callback)
	}

	private static func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext, callback: @escaping Completion) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServers(in: moc) {
            if apiServer.userNodeId == nil || (apiServer.userName?.isEmpty ?? true) {
				needToCheck = true
				break
			}
		}

		if needToCheck {
			DLog("Some API servers don't have user details yet, will bring user credentials down for them")
			syncUserDetails(in: moc, callback: callback)
		} else {
			callback()
		}
	}

	private static func getRateLimit(from server: ApiServer, callback: @escaping (_ limits: ApiStats?)->Void) {

        RestAccess.start(call: "/rate_limit", on: server, triggeredByUser: true) { code, headers, data, error, shouldRetry in

			if error == nil, let h = headers {
				callback(ApiStats.fromV3(headers: h))
			} else if code == 404, let d = data as? [AnyHashable : Any], let m = d["message"] as? String, m != "Not Found" { // is GE account
				callback(ApiStats.noLimits)
			} else {
				callback(nil)
			}
		}
	}

	static func updateLimitsFromServer() {
		let configuredServers = ApiServer.allApiServers(in: DataManager.main).filter { $0.goodToGo }
		for apiServer in configuredServers {
			getRateLimit(from: apiServer) { limits in
				if let l = limits {
					apiServer.updateApiStats(l)
				}
			}
		}
	}

	private static func syncManuallyAddedRepos(from server: ApiServer, callback: @escaping Completion) {
		if !server.lastSyncSucceeded {
			callback()
			return
		}

		let repos = server.repos.filter { $0.manuallyAdded }
        let group = DispatchGroup()
		for repo in repos {
            group.enter()
            fetchRepo(fullName: repo.fullName ?? "", from: server) { error in
                if error != nil {
                    server.lastSyncSucceeded = false
                }
                group.leave()
            }
		}
        group.notify(queue: .main, execute: callback)
	}

	private static func syncWatchedRepos(from server: ApiServer, callback: @escaping Completion) {

		if !server.lastSyncSucceeded {
			callback()
			return
		}

		let createNewRepos = Settings.automaticallyRemoveDeletedReposFromWatchlist
		RestAccess.getPagedData(at: "/user/subscriptions", from: server, perPageCallback: { data, lastPage in
			Repo.syncRepos(from: data, server: server, addNewRepos: createNewRepos, manuallyAdded: false)
			return false
		}) { success, resultCode in
			if !success {
				server.lastSyncSucceeded = false
			} else if !Settings.automaticallyRemoveDeletedReposFromWatchlist { // Ignore any missing repos in all cases if deleteGoneRepos is false
				let reposThatWouldBeDeleted = Repo.items(of: Repo.self, surviving: false, in: server.managedObjectContext!)
				for r in reposThatWouldBeDeleted {
					r.postSyncAction = PostSyncAction.doNothing.rawValue
				}
			}
			callback()
		}
	}

	static func fetchRepo(fullName: String, from server: ApiServer, completion: @escaping (Error?) -> Void) {
		let path = "\(server.apiPath ?? "")/repos/\(fullName)"
        RestAccess.getData(in: path, from: server) { data, lastPage, resultCode in
			if let repoData = data as? [AnyHashable : Any] {
				Repo.syncRepos(from: [repoData], server: server, addNewRepos: true, manuallyAdded: true)
				completion(nil)
			} else {
				let error = apiError("Operation failed with code \(resultCode)")
				completion(error)
			}
		}
	}

	static func fetchAllRepos(owner: String, from server: ApiServer, completion: @escaping (Error?) -> Void) {
		let group = DispatchGroup()

		group.enter()
		var userError: Error?
		var userList = [[AnyHashable : Any]]()
		let userPath = "\(server.apiPath ?? "")/users/\(owner)/repos"
		RestAccess.getPagedData(at: userPath, from: server, perPageCallback: { data, lastPage -> Bool in
			if let data = data {
				userList.append(contentsOf: data)
			}
			return false
		}, finalCallback: { success, resultCode in
			if !success {
				userError = apiError("Operation failed with code \(resultCode)")
			}
			group.leave()
		})

		group.enter()
		var orgError: Error?
		var orgList = [[AnyHashable : Any]]()
		let orgPath = "\(server.apiPath ?? "")/orgs/\(owner)/repos"
		RestAccess.getPagedData(at: orgPath, from: server, perPageCallback: { data, lastPage -> Bool in
			if let data = data {
				orgList.append(contentsOf: data)
			}
			return false
		}, finalCallback: { success, resultCode in
			if !success {
				orgError = apiError("Operation failed with code \(resultCode)")
			}
			group.leave()
		})

		group.notify(queue: .main) {
			if let orgError = orgError as NSError?, let userError = userError as NSError? {
				if orgError.code == 404 {
					completion(userError)
				} else {
					completion(orgError)
				}
			} else {
				Repo.syncRepos(from: userList+orgList, server: server, addNewRepos: true, manuallyAdded: true)
				completion(nil)
			}
		}
	}

	static func fetchRepo(named: String, owner: String, from server: ApiServer, completion: @escaping (Error?) -> Void) {
		fetchRepo(fullName: "\(owner)/\(named)", from: server, completion: completion)
	}

	private static func syncUserDetails(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let configuredServers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
        let group = DispatchGroup()
		for apiServer in configuredServers {
            group.enter()
            RestAccess.getData(in: "/user", from: apiServer) { data, lastPage, resultCode in

				if let d = data as? [AnyHashable : Any] {
					apiServer.userName = d["login"] as? String
                    apiServer.userNodeId = d["node_id"] as? String
				} else {
					apiServer.lastSyncSucceeded = false
				}
                group.leave()
			}
		}
        group.notify(queue: .main, execute: callback)
	}

	static func testApi(to apiServer: ApiServer, callback: @escaping (Error?) -> Void) {

        RestAccess.start(call: "/user", on: apiServer, triggeredByUser: true) { code, headers, data, error, shouldRetry in
			if let d = data as? [AnyHashable : Any], let userName = d["login"] as? String, let userId = d["id"] as? Int64, error == nil {
				if userName.isEmpty || userId <= 0 {
					let localError = apiError("Could not read a valid user record from this endpoint")
					callback(localError)
				} else {
					callback(error)
				}
			} else {
				callback(error)
			}
		}
	}

	static func apiError(_ message: String) -> Error {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}
}
