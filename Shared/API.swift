
import CoreData
#if os(iOS)
	import UIKit
#endif

final class API {

	typealias ApiCompletion = (_ code: Int64?, _ headers: [AnyHashable : Any]?, _ data: Any?, _ error: Error?, _ shouldRetry: Bool) -> Void

	private final class ApiOperation: Operation {

		private let path: String
		private let server: ApiServer
		private let ignoreLastSync: Bool
		private let completion: ApiCompletion
		private var _isFinished = false
		private var _isExecuting = false

		init(call path: String,
		     on server: ApiServer,
		     ignoreLastSync: Bool,
		     completion: @escaping ApiCompletion) {

			self.server = server
			self.path = path
			self.ignoreLastSync = ignoreLastSync
			self.completion = completion

			super.init()
		}

		override func start() {

			willChangeValue(forKey: "isExecuting")
			_isExecuting = true
			didChangeValue(forKey: "isExecuting")

			#if os(iOS)
				API.networkIndicationStart()
			#endif

			API.start(call: path, on: server, ignoreLastSync: ignoreLastSync) { code, headers, data, error, shouldRetry in

				self.completion(code, headers, data, error, shouldRetry)
                NotificationCenter.default.post(name: .SyncProgressUpdate, object: nil)

				#if os(iOS)
					API.networkIndicationEnd()
				#endif

				self.willChangeValue(forKey: "isFinished")
				self._isFinished = true
				self.didChangeValue(forKey: "isFinished")
			}
		}

		override var isFinished: Bool {
			return _isFinished
		}

		override var isExecuting: Bool {
			return _isExecuting
		}

		override var isAsynchronous: Bool {
			return true
		}
	}

	private struct UrlBackOffEntry {
		var nextAttemptAt: Date
		var nextIncrement: TimeInterval
	}

	static var refreshesSinceLastStatusCheck = [NSManagedObjectID : Int]()
	static var refreshesSinceLastReactionsCheck = [NSManagedObjectID : Int]()
	static var currentNetworkStatus = NetworkStatus.NotReachable

	private static let cacheDirectory = { ()->String in
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer").path
	}()

	private static let sessionCallbackQueue: OperationQueue = {
		let o = OperationQueue()
		o.maxConcurrentOperationCount = 2
		return o
	}()
	private static let urlSession: URLSession = {

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
		config.requestCachePolicy = .useProtocolCachePolicy
		config.timeoutIntervalForRequest = 60
		config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, diskPath: cacheDirectory)
		config.httpAdditionalHeaders = ["User-Agent" : userAgent]
		return URLSession(configuration: config, delegate: nil, delegateQueue: sessionCallbackQueue)
	}()

	private static var badLinks = [String : UrlBackOffEntry]()
	private static let reachability = Reachability()
	private static let backOffIncrement: TimeInterval = 120

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
			clearAllBadLinks()
		}
	}

	class var hasNetworkConnection: Bool {
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

	class var pendingCallCount: Int {
		return apiQueue.operationCount
	}

	class var lastUpdateDescription: String {
		if appIsRefreshing {
			let operations = pendingCallCount
			if operations < 2 {
				return "Refreshing…"
			} else {
				return "Refreshing… (\(operations) calls remaining)"
			}
		} else if ApiServer.shouldReportRefreshFailure(in: DataManager.main) {
			return "Last update failed"
		} else {
			let lastSuccess = Settings.lastSuccessfulRefresh ?? Date()
			let ago = Date().timeIntervalSince(lastSuccess)
			if ago<10 {
				return "Just updated"
			} else {
				return "Updated \(Int(ago)) seconds ago"
			}
		}
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

			#if os(iOS)
				task.priority = URLSessionTask.highPriority // this blows up in OSX for some reason
				delay(0.1) {
					networkIndicationStart()
				}
			#endif

			task.resume()
		}

		let connector = path.contains("?") ? "&" : "?"
		#if os(iOS)
			let side = 40.0*GLOBAL_SCREEN_SCALE
			let absolutePath = "\(path)\(connector)s=\(side)"
		#else
			let absolutePath = "\(path)\(connector)s=104"
		#endif
		let md5 = MD5Hashing.md5(str: "\(absolutePath) \(currentAppVersion)")
		let cachePath = cacheDirectory.appending(pathComponent: "imgcache-\(md5)")

		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: cachePath) {
			#if os(iOS)
				let imgData = try? Data(contentsOf: URL(fileURLWithPath: cachePath)) as CFData
				let imgDataProvider = CGDataProvider(data: imgData!)
				var ret: UIImage?
				if let cfImage = CGImage(jpegDataProviderSource: imgDataProvider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
					ret = UIImage(cgImage: cfImage, scale: GLOBAL_SCREEN_SCALE, orientation: .up)
				}
			#else
				let ret = NSImage(contentsOfFile: cachePath)
			#endif
			if let r = ret {
				atNextEvent {
					callback(r, cachePath)
				}
				return true
			} else {
				try! fileManager.removeItem(atPath: cachePath)
			}
		}


		getImage(at: absolutePath) { data in
			// in thread
			var result: IMAGE_CLASS?
			#if os(iOS)
				if let d = data, let i = UIImage(data: d, scale: GLOBAL_SCREEN_SCALE) {
					result = i
					if let imageData = i.jpegData(compressionQuality: 1) {
						try? imageData.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
					}
				}
			#else
				if let d = data, let i = IMAGE_CLASS(data: d) {
					result = i
					_ = try? i.tiffRepresentation?.write(to: URL(fileURLWithPath: cachePath), options: [.atomic])
				}
			#endif
			atNextEvent {
				callback(result, cachePath)
				#if os(iOS)
					networkIndicationEnd()
				#endif
			}
		}
		return false
	}

	////////////////////////////////////// API interface

	private static let sustainedConcurrency = 3
	private static let burstConcurrency = 8

	private static let apiQueue: OperationQueue = {
		let n = OperationQueue()
		n.underlyingQueue = DispatchQueue.main
		n.maxConcurrentOperationCount = API.sustainedConcurrency
		return n
	}()

	static func syncItemsForActiveReposAndCallback(callback: @escaping Completion) {

		let syncContext = DataManager.buildChildContext()

		let shouldRefreshReposToo = lastRepoCheck == .distantPast
			|| (Date().timeIntervalSince(lastRepoCheck) > TimeInterval(Settings.newRepoCheckPeriod*3600.0))
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

	private static func markItemsForPeriodicReactionsCheck(in moc: NSManagedObjectContext) {

		func markItemsNeedingReactionsCheck(items: [ListableItem]) {

			for item in items {
				guard item.apiServer.lastSyncSucceeded else { continue }

				let oid = item.objectID
				let refreshes = refreshesSinceLastReactionsCheck[oid]
				if refreshes == nil || refreshes! >= Settings.reactionScanningInterval {
					//DLog("Will check reactions for item: '%@'", item.title)
					item.updatedAt = item.updatedAt?.addingTimeInterval(-1) ?? .distantPast
					item.postSyncAction = PostSyncAction.isUpdated.rawValue
				} else {
					//DLog("No need to get reactions for item: '%@' (%@ refreshes since last check)", item.title, refreshes)
					refreshesSinceLastReactionsCheck[oid] = (refreshes ?? 0) + 1
				}
			}
		}

		let prItems = PullRequest.active(of: PullRequest.self, in: moc, visibleOnly: true)
		markItemsNeedingReactionsCheck(items: prItems)

		let issueItems = Issue.active(of: Issue.self, in: moc, visibleOnly: true)
		markItemsNeedingReactionsCheck(items: issueItems)
	}

	private static func sync(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let repos = Repo.syncableRepos(in: moc)

		let willSyncCommentReactions = Settings.notifyOnCommentReactions
		let willSyncItemReactions = Settings.notifyOnItemReactions

		var completionCount = 0
		let totalOperations = 2 + (willSyncItemReactions ? 2 : 0)
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				if willSyncCommentReactions {
					fetchCommentReactionsIfNeeded(to: moc) {
						completeSync(in: moc, andCallback: callback)
					}
				} else {
					completeSync(in: moc, andCallback: callback)
				}
			}
		}

		apiQueue.maxConcurrentOperationCount = API.burstConcurrency

		if shouldSyncReactions {
			markItemsForPeriodicReactionsCheck(in: moc)
		} else {
			refreshesSinceLastReactionsCheck.removeAll()
			for s in DataItem.allItems(of: Reaction.self, in: moc) {
				s.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		fetchItems(from: repos, to: moc) {

			let reposWithSomeItems = repos.filter { $0.issues.count > 0 || $0.pullRequests.count > 0 }
			markExtraUpdatedItems(from: reposWithSomeItems, to: moc) {

				apiQueue.maxConcurrentOperationCount = API.sustainedConcurrency

				if willSyncItemReactions {
					fetchIssueReactionsIfNeeded(to: moc, callback: completionCallback)
					fetchPullRequestReactionsIfNeeded(to: moc, callback: completionCallback)
				}

				fetchCommentsForCurrentIssues(to: moc) {
					checkIssueClosures(in: moc)
					completionCallback()
				}
				updatePullRequests(in: moc) {
					completionCallback()
				}
			}
		}
	}

	private static func fetchItems(from repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

		var completionCount = 0
		let totalOperations = 2
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		fetchIssues(for: repos, to: moc, callback: completionCallback)
		fetchPullRequests(for: repos, to: moc, callback: completionCallback)
	}

	private static func markExtraUpdatedItems(from repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

		if repos.count == 0 {
			callback()
			return
		}

		var completionCount = 0
		let totalOperations = repos.count
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		for r in repos {
			let repoFullName = S(r.fullName)
			let lastLocalEvent = r.lastScannedIssueEventId
			let isFirstEventSync = lastLocalEvent == 0
			r.lastScannedIssueEventId = 0
			getPagedData(at: "/repos/\(repoFullName)/issues/events", from: r.apiServer, perPageCallback: { data, lastPage in
				guard let data = data, data.count > 0 else { return true }

				if isFirstEventSync {

					DLog("First event check for this repo. Let's ensure all items are marked as updated")
					for i in r.pullRequests { i.setToUpdatedIfIdle() }
					for i in r.issues { i.setToUpdatedIfIdle() }
					r.lastScannedIssueEventId = data.first!["id"] as? Int64 ?? 0
					return true

				} else {

					var numbers = Set<Int64>()
					var reasons = Set<String>()
					var foundLastEvent = false
					for event in data {
						if let eventId = event["id"] as? Int64, let issue = event["issue"] as? [AnyHashable:Any], let issueNumber = issue["number"] as? Int64 {
							if r.lastScannedIssueEventId == 0 {
								r.lastScannedIssueEventId = eventId
							}
							if eventId == lastLocalEvent {
								foundLastEvent = true
								DLog("Parsed all repo issue events up to the one we already have");
								break // we're done
							}
							if let reason = event["event"] as? String {
								numbers.insert(issueNumber)
								reasons.insert(reason)
							}
						}
					}
					if r.lastScannedIssueEventId == 0 {
						r.lastScannedIssueEventId = lastLocalEvent
					}
					if numbers.count > 0 {
						r.markItemsAsUpdated(with: numbers, reasons: reasons)
					}
					return foundLastEvent

				}

			}) { success, resultCode in
				if !success {
					r.apiServer.lastSyncSucceeded = false
				}
				completionCallback()
			}

		}
	}

	private static func completeSync(in moc: NSManagedObjectContext, andCallback: @escaping Completion) {

		DLog("Wrapping up sync")

        NotificationCenter.default.post(name: .RefreshProcessing, object: nil)

		// discard any changes related to any failed API server
		for apiServer in ApiServer.allApiServers(in: moc) {
			if !apiServer.lastSyncSucceeded {
				apiServer.rollBackAllUpdates(in: moc)
				apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
			}
		}

		let mainQueue = OperationQueue.main

		mainQueue.addOperation {
			DataItem.nukeDeletedItems(in: moc)
		}

		mainQueue.addOperation {
			DataManager.postProcessAllItems(in: moc)
		}

		mainQueue.addOperation {
			DLog("Caching \(URLCache.shared.currentMemoryUsage) bytes in memory")
			DLog("Caching \(URLCache.shared.currentDiskUsage) bytes on disk")
		}
		
		mainQueue.addOperation {
			do {
				DLog("Committing synced data")
				try moc.save()
				DLog("Synced data committed")
			} catch {
				DLog("Committing sync failed: %@", error.localizedDescription)
			}
			andCallback()
		}
	}

	private static func updatePullRequests(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let totalOperations = 3
			+ (Settings.showStatusItems ? 1 : 0)
			+ (Settings.showLabels ? 1 : 0)
			+ (shouldSyncReviewAssignments ? 1 : 0)

		var completionCount = 0
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		if Settings.showStatusItems {
			fetchStatusesForCurrentPullRequests(to: moc, callback: completionCallback)
		} else {
			refreshesSinceLastStatusCheck.removeAll()
			for s in DataItem.allItems(of: PRStatus.self, in: moc) {
				s.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		if Settings.showLabels {
			fetchLabelsForForCurrentPullRequests(to: moc, callback: completionCallback)
		} else {
			for l in DataItem.allItems(of: PRLabel.self, in: moc) {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		if shouldSyncReviews {
			fetchReviewsForForCurrentPullRequests(to: moc) {
				fetchCommentsForCurrentPullRequests(to: moc, callback: completionCallback)
			}
		} else {
			for r in DataItem.allItems(of: Review.self, in: moc) {
				r.postSyncAction = PostSyncAction.delete.rawValue
			}
			fetchCommentsForCurrentPullRequests(to: moc, callback: completionCallback)
		}

		checkPrClosures(in: moc, callback: completionCallback)

		detectAssignedPullRequests(in: moc, callback: completionCallback)

		if shouldSyncReviewAssignments {
			fetchReviewAssignmentsForCurrentPullRequests(to: moc, callback: completionCallback)
		}
	}

	private static func fetchUserTeams(from server: ApiServer, callback: @escaping Completion) {

		for t in server.teams {
			t.postSyncAction = PostSyncAction.delete.rawValue
		}

		getPagedData(at: "/user/teams", from: server, perPageCallback: { data, lastPage in
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
		clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

		syncUserDetails(in: moc) {
			for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
				r.postSyncAction = r.manuallyAdded ? PostSyncAction.doNothing.rawValue : PostSyncAction.delete.rawValue
			}

			let goodToGoServers = ApiServer.allApiServers(in: moc).filter { $0.goodToGo }
			let totalOperations = goodToGoServers.count * 3
			var completionCount = 0

			let completionCallback = {
				completionCount += 1
				if completionCount >= totalOperations {
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

			if totalOperations == 0 {
				completionCallback()
				return
			}

			for apiServer in goodToGoServers {
				syncWatchedRepos(from: apiServer, callback: completionCallback)
				syncManuallyAddedRepos(from: apiServer, callback: completionCallback)
				fetchUserTeams(from: apiServer, callback: completionCallback)
			}
		}
	}

	private static func fetchPullRequests(for repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

		for r in Repo.unsyncableRepos(in: moc) {
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		let totalOperations = repos.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0
		for r in repos {

			for p in r.pullRequests {
				if p.condition == ItemCondition.open.rawValue {
					p.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.lastSyncSucceeded && r.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue {
				let repoFullName = S(r.fullName)
				getPagedData(at: "/repos/\(repoFullName)/pulls", from: apiServer, perPageCallback: { data, lastPage in
					PullRequest.syncPullRequests(from: data, in: r)
					return false
				}) { success, resultCode in
					if !success {
						handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
					completionCount += 1
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
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

		let totalOperations = repos.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0
		for r in repos {

			for i in r.issues {
				if i.condition == ItemCondition.open.rawValue {
					i.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.lastSyncSucceeded && r.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue {
				let repoFullName = S(r.fullName)
				getPagedData(at: "/repos/\(repoFullName)/issues", from: apiServer, perPageCallback: { data, lastPage in
					Issue.syncIssues(from: data, in: r)
					return false
				}) { success, resultCode in
					if !success {
						handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
					completionCount += 1
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func fetchCommentReactionsIfNeeded(to moc: NSManagedObjectContext, callback: @escaping Completion) {
		let comments = PRComment.commentsThatNeedReactionsToBeRefreshed(in: moc).filter { $0.apiServer.lastSyncSucceeded }
		let totalOperations = comments.count
		guard totalOperations > 0 else { callback(); return }

		var completionCount = 0
		for c in comments {

			for r in c.reactions {
				r.postSyncAction = PostSyncAction.delete.rawValue
			}

			let apiServer = c.apiServer
			getPagedData(at: c.requiresReactionRefreshFromUrl!, from: apiServer, perPageCallback: { data, lastPage in
				Reaction.syncReactions(from: data, comment: c)
				return false
			}) { success, resultCode in
				if success {
					c.requiresReactionRefreshFromUrl = nil
				} else {
					apiServer.lastSyncSucceeded = false
				}
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func _fetchItemReactionsIfNeeded(to moc: NSManagedObjectContext, items: [ListableItem], callback: @escaping Completion) {
		let totalOperations = items.count
		guard totalOperations > 0 else { callback(); return }

		var completionCount = 0
		for i in items {

			for r in i.reactions {
				r.postSyncAction = PostSyncAction.delete.rawValue
			}

			let apiServer = i.apiServer
			getPagedData(at: i.requiresReactionRefreshFromUrl!, from: apiServer, perPageCallback: { data, lastPage in
				Reaction.syncReactions(from: data, parent: i)
				return false
			}) { success, resultCode in
				if success {
					i.requiresReactionRefreshFromUrl = nil
				} else {
					apiServer.lastSyncSucceeded = false
				}
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func fetchIssueReactionsIfNeeded(to moc: NSManagedObjectContext, callback: @escaping Completion) {
		let items = Issue.issuesThatNeedReactionsToBeRefreshed(in: moc).filter { $0.apiServer.lastSyncSucceeded }
		_fetchItemReactionsIfNeeded(to: moc, items: items, callback: callback)
	}

	private static func fetchPullRequestReactionsIfNeeded(to moc: NSManagedObjectContext, callback: @escaping Completion) {
		let items = PullRequest.pullRequestsThatNeedReactionsToBeRefreshed(in: moc).filter { $0.apiServer.lastSyncSucceeded }
		_fetchItemReactionsIfNeeded(to: moc, items: items, callback: callback)
	}

	private static func fetchCommentsForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }
		if prs.count == 0 {
			callback()
			return
		}

		for p in prs {
			for c in p.comments {
				c.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		let totalOperations = 2
		var completionCount = 0

		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations { callback() }
		}

		func _fetchComments(for pullRequests: [PullRequest], issues: Bool, in moc: NSManagedObjectContext, callback: @escaping Completion) {

			let totalOperations = pullRequests.count
			if totalOperations == 0 {
				callback()
				return
			}

			var completionCount = 0

			for p in pullRequests {
				if let link = (issues ? p.issueCommentLink : p.reviewCommentLink) {

					let apiServer = p.apiServer

					getPagedData(at: link, from: apiServer, perPageCallback: { data, lastPage in
						PRComment.syncComments(from: data, pullRequest: p)
						return false
					}) { success, resultCode in
						completionCount += 1
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == totalOperations {
							callback()
						}
					}
				} else {
					completionCount += 1
					if completionCount == totalOperations {
						callback()
					}
				}
			}
		}

		_fetchComments(for: prs, issues: true, in: moc, callback: completionCallback)
		_fetchComments(for: prs, issues: false, in: moc, callback: completionCallback)
	}

	private static func fetchCommentsForCurrentIssues(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let issues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = issues.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for i in issues {

			for c in i.comments {
				c.postSyncAction = PostSyncAction.delete.rawValue
			}

			if let link = i.commentsLink {

				let apiServer = i.apiServer

				getPagedData(at: link, from: apiServer, perPageCallback: { data, lastPage in
					PRComment.syncComments(from: data, issue: i)
					return false
				}) { success, resultCode in
					completionCount += 1
					if !success {
						apiServer.lastSyncSucceeded = false
					}
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func fetchReviewsForForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = prs.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			for l in p.reviews {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}

			let repoFullName = S(p.repo.fullName)
			getPagedData(at: "/repos/\(repoFullName)/pulls/\(p.number)/reviews", from: p.apiServer, perPageCallback: { data, lastPage in
				Review.syncReviews(from: data, withParent: p)
				return false
			}) { success, resultCode in
				completionCount += 1
				if !success {
					p.apiServer.lastSyncSucceeded = false
				}
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	class var shouldSyncReactions: Bool {
		return Settings.notifyOnItemReactions || Settings.notifyOnCommentReactions
	}
	class var shouldSyncReviews: Bool {
		return Settings.displayReviewsOnItems || Settings.notifyOnReviewDismissals || Settings.notifyOnReviewAcceptances || Settings.notifyOnReviewChangeRequests
	}
	class var shouldSyncReviewAssignments: Bool {
		return Settings.displayReviewsOnItems || Settings.notifyOnReviewAssignments || (Int64(Settings.assignedReviewHandlingPolicy) != Section.none.rawValue)
	}

	private static func fetchReviewAssignmentsForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = prs.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {

			var reviewUsers = Set<String>()
			var reviewTeams = Set<String>()
			let repoFullName = S(p.repo.fullName)
			getRawData(at: "/repos/\(repoFullName)/pulls/\(p.number)/requested_reviewers", from: p.apiServer) { data, resultCode in

				if let userList = data as? [[AnyHashable: Any]] {
					// Legacy API results
					for userName in userList.compactMap({ $0["login"] as? String }) {
						reviewUsers.insert(userName)
					}
					if p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams) && Settings.notifyOnReviewAssignments {
						NotificationQueue.add(type: .assignedForReview, for: p)
					}

				} else if let data = data as? [AnyHashable: Any], let userList = data["users"] as? [[AnyHashable: Any]], let teamList = data["teams"] as? [[AnyHashable: Any]] {
					// New API results
					for userName in userList.compactMap({ $0["login"] as? String }) {
						reviewUsers.insert(userName)
					}
					for teamName in teamList.compactMap({ $0["slug"] as? String }) {
						reviewTeams.insert(teamName)
					}
					if p.checkAndStoreReviewAssignments(reviewUsers, reviewTeams) && Settings.notifyOnReviewAssignments {
						NotificationQueue.add(type: .assignedForReview, for: p)
					}
				} else {
					p.apiServer.lastSyncSucceeded = false
				}

				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func fetchLabelsForForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = prs.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			for l in p.labels {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}

			if let link = p.labelsLink {

				getPagedData(at: link, from: p.apiServer, perPageCallback: { data, lastPage in
					PRLabel.syncLabels(from: data, withParent: p)
					return false
				}) { success, resultCode in
					completionCount += 1
					if !success {
						// 404/410 means the label has been deleted
						if !(resultCode==404 || resultCode==410) {
							p.apiServer.lastSyncSucceeded = false
						}
					}
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				// no labels link, so presumably no labels
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func fetchStatusesForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = PullRequest.active(of: PullRequest.self, in: moc, visibleOnly: !Settings.hidePrsThatArentPassing).filter { pr in
			guard pr.apiServer.lastSyncSucceeded, pr.shouldShowStatuses else { return false }

			let oid = pr.objectID
			let refreshes = refreshesSinceLastStatusCheck[oid]
			if refreshes == nil || refreshes! >= Settings.statusItemRefreshInterval {
				//DLog("Will check statuses for PR: '%@'", pr.title)
				return true
			} else {
				//DLog("No need to get statuses for PR: '%@' (%@ refreshes since last check)", pr.title, refreshes)
				refreshesSinceLastStatusCheck[oid] = (refreshes ?? 0)+1
				return false
			}
		}

		let totalOperations = prs.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			for s in p.statuses {
				s.postSyncAction = PostSyncAction.delete.rawValue
			}

			let apiServer = p.apiServer

			if let statusLink = p.statusesLink {
				getPagedData(at: statusLink, from: apiServer, perPageCallback: { data, lastPage in
					PRStatus.syncStatuses(from: data, pullRequest: p)
					return false
				}) { success, resultCode in
					completionCount += 1
					var allGood = success
					if !success {
						// 404/410 means the status has been deleted
						if !(resultCode==404 || resultCode==410) {
							apiServer.lastSyncSucceeded = false
						} else {
							allGood = true
						}
					}
					if allGood {
						refreshesSinceLastStatusCheck[p.objectID] = 1
					}
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				refreshesSinceLastStatusCheck[p.objectID] = 1
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private static func checkPrClosures(in moc: NSManagedObjectContext, callback: @escaping Completion) {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false

		let prsToCheck = try! moc.fetch(f).filter { $0.shouldCheckForClosing }

		let totalOperations = prsToCheck.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		for r in prsToCheck {
			investigatePrClosure(for: r, callback: completionCallback)
		}
	}

	private static func checkIssueClosures(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		
		for i in try! moc.fetch(f).filter { $0.shouldCheckForClosing } {
			handleClosing(of: i)
		}
	}

	private static func detectAssignedPullRequests(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = prs.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		for p in prs {
			let apiServer = p.apiServer
			if let issueLink = p.issueUrl {
				getData(in: issueLink, from: apiServer) { data, lastPage, resultCode in
					if resultCode == 200 || resultCode == 404 || resultCode == 410 {
						if let d = data as? [AnyHashable : Any] {
							p.processAssignmentStatus(from: d)
							p.processReactions(from: d)
						}
					} else {
						apiServer.lastSyncSucceeded = false
					}
					completionCallback()
				}
			} else {
				completionCallback()
			}
		}
	}

	private static func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext, callback: @escaping Completion) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServers(in: moc) {
			if apiServer.userId == 0 || (apiServer.userName?.isEmpty ?? true) {
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

	private static func investigatePrClosure(for pullRequest: PullRequest, callback: @escaping Completion) {
		DLog("Checking closed PR to see if it was merged: %@", pullRequest.title)

		let repoFullName = S(pullRequest.repo.fullName)
		let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

		getData(in: path, from: pullRequest.apiServer) { data, lastPage, resultCode in

			if let d = data as? [AnyHashable : Any] {
				if let mergeInfo = d["merged_by"] as? [AnyHashable : Any], let mergeUserId = mergeInfo["id"] as? Int64 {
					handleMerging(of: pullRequest, byUserId: mergeUserId)
				} else {
					handleClosing(of: pullRequest)
				}
			} else if resultCode == 404 || resultCode == 410 { // PR gone for good
				handleClosing(of: pullRequest)
			} else { // fetch/server problem
				pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // don't delete this, we couldn't check, play it safe
				pullRequest.apiServer.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private static func handleMerging(of pullRequest: PullRequest, byUserId: Int64) {

		let myUserId = pullRequest.apiServer.userId
		DLog("Detected merged PR: %@ by user %@, local user id is: %@, handling policy is %@, coming from section %@",
		     pullRequest.title,
		     byUserId,
		     myUserId,
		     Settings.mergeHandlingPolicy,
		     pullRequest.sectionIndex)

		if !pullRequest.isVisibleOnMenu {
			DLog("Merged PR was hidden, won't announce")
			return
		}

		let mergedByMe = byUserId == myUserId
		if !(mergedByMe && Settings.dontKeepPrsMergedByMe) {
			DLog("Checking if we want to keep this merged PR")
			if pullRequest.shouldKeep(accordingTo: Settings.mergeHandlingPolicy) {
				DLog("Will keep merged PR")
				pullRequest.keep(as: .merged, notification: .prMerged)
				return
			}
		}
		DLog("Will not keep merged PR")
	}

	private static func handleClosing(of item: ListableItem) {
		DLog("Detected closed item: %@, handling policy is %@, coming from section %@",
		     item.title,
		     Settings.closeHandlingPolicy,
		     item.sectionIndex)

		if !item.isVisibleOnMenu {
			DLog("Closed item was hidden, won't announce")
			return
		}

		if item.shouldKeep(accordingTo: Settings.closeHandlingPolicy) {
			DLog("Will keep closed item")
			item.keep(as: .closed, notification: item is Issue ? .issueClosed : .prClosed)
		} else {
			DLog("Will not keep closed item")
		}
	}

	private static func getRateLimit(from server: ApiServer, callback: @escaping (_ limits: ApiRateLimits?)->Void) {

		apiQueue.addOperation(ApiOperation(call: "/rate_limit", on: server, ignoreLastSync: true) { code, headers, data, error, shouldRetry in

			if error == nil, let h = headers {
				callback(ApiRateLimits.from(headers: h))
			} else if code == 404, let d = data as? [AnyHashable : Any], let m = d["message"] as? String, m != "Not Found" { // is GE account
				callback(ApiRateLimits.noLimits)
			} else {
				callback(nil)
			}
		})
	}

	static func updateLimitsFromServer() {
		let configuredServers = ApiServer.allApiServers(in: DataManager.main).filter { $0.goodToGo }
		for apiServer in configuredServers {
			getRateLimit(from: apiServer) { limits in
				if let l = limits {
					apiServer.updateApiLimits(l)
				}
			}
		}
	}

	private static func syncManuallyAddedRepos(from server: ApiServer, callback: @escaping Completion) {
		if !server.lastSyncSucceeded {
			callback()
			return
		}

		let repos = server.repos.filter { $0.manuallyAdded && $0.shouldSync }
		var count = 0
		let stepDone = { (error: Error?) in
			if error != nil {
				server.lastSyncSucceeded = false
			}
			count += 1
			if count == repos.count {
				callback()
			}
		}

		if repos.count == 0 {
			callback()
		}

		for repo in repos {
			fetchRepo(fullName: repo.fullName ?? "", from: server, completion: stepDone)
		}
	}

	private static func syncWatchedRepos(from server: ApiServer, callback: @escaping Completion) {

		if !server.lastSyncSucceeded {
			callback()
			return
		}

		let createNewRepos = Settings.automaticallyRemoveDeletedReposFromWatchlist
		getPagedData(at: "/user/subscriptions", from: server, perPageCallback: { data, lastPage in
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
		getData(in: path, from: server) { data, lastPage, resultCode in
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
		getPagedData(at: userPath, from: server, perPageCallback: { data, lastPage -> Bool in
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
		getPagedData(at: orgPath, from: server, perPageCallback: { data, lastPage -> Bool in
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

		group.notify(queue: DispatchQueue.main) {
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
		let totalOperations = configuredServers.count

		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for apiServer in configuredServers {
			getData(in: "/user", from: apiServer) { data, lastPage, resultCode in

				if let d = data as? [AnyHashable : Any] {
					apiServer.userName = d["login"] as? String
					apiServer.userId = d["id"] as? Int64 ?? 0
				} else {
					apiServer.lastSyncSucceeded = false
				}
				completionCount += 1
				if completionCount == totalOperations { callback() }
			}
		}
	}

	static func clearAllBadLinks() {
		badLinks.removeAll(keepingCapacity: false)
	}

	static func testApi(to apiServer: ApiServer, callback: @escaping (Error?) -> Void) {

		clearAllBadLinks()

		apiQueue.addOperation(ApiOperation(call: "/user", on: apiServer, ignoreLastSync: true) { code, headers, data, error, shouldRetry in

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
		})
	}

	private static func apiError(_ message: String) -> Error {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	//////////////////////////////////////////////////////////// low level

	private static func getPagedData(
		at path: String,
		from server: ApiServer,
		startingFrom page: Int = 1,
		perPageCallback: @escaping (_ data: [[AnyHashable : Any]]?, _ lastPage: Bool) -> Bool,
		finalCallback: @escaping (_ success: Bool, _ resultCode: Int64) -> Void) {

		if path.isEmpty {
			// handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
			finalCallback(true, -1)
			return
		}

		let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
		getData(in: p, from: server) { data, lastPage, resultCode in

			if let d = data as? [[AnyHashable : Any]] {
				if perPageCallback(d, lastPage) || lastPage {
					finalCallback(true, resultCode)
				} else {
					getPagedData(at: path, from: server, startingFrom: page+1, perPageCallback: perPageCallback, finalCallback: finalCallback)
				}
			} else {
				finalCallback(false, resultCode)
			}
		}
	}

	private static func getRawData(
		at path: String,
		from server: ApiServer,
		callback: @escaping (_ data: Any?, _ resultCode: Int64) -> Void) {

		if path.isEmpty {
			// handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
			callback(nil, -1)
			return
		}

		getData(in: "\(path)?per_page=100", from: server) { data, lastPage, resultCode in
			callback(data, resultCode)
		}
	}

	private static func getData(
		in path: String,
		from server: ApiServer,
		attemptCount: Int = 0,
		callback: @escaping (_ data: Any?, _ lastPage: Bool, _ resultCode: Int64) -> Void) {

		apiQueue.addOperation(ApiOperation(call: path, on: server, ignoreLastSync: false) { code, headers, data, error, shouldRetry in

			if error == nil {
				var lastPage = true
				if let allHeaders = headers {

					let latestLimits = ApiRateLimits.from(headers: allHeaders)
					server.updateApiLimits(latestLimits)

					if let linkHeader = allHeaders["Link"] as? String {
						lastPage = !linkHeader.contains("rel=\"next\"")
					}
				}
				callback(data, lastPage, code ?? 0)
			} else {
				if shouldRetry && attemptCount < 3 { // timeout, truncation, connection issue, etc
					let nextAttemptCount = attemptCount+1
					DLog("(%@) Will retry failed API call to %@ (attempt #%@)", S(server.label), path, nextAttemptCount)
					delay(3.0) {
						getData(in: path, from: server, attemptCount: nextAttemptCount, callback: callback)
					}
				} else {
					if shouldRetry {
						DLog("(%@) Giving up on failed API call to %@", S(server.label), path)
					}
					callback(nil, false, code ?? 0)
				}
			}
		})
	}

	private static func start(call path: String, on server: ApiServer, ignoreLastSync: Bool, completion: @escaping ApiCompletion) {

		let apiServerLabel: String
		if server.lastSyncSucceeded || ignoreLastSync {
			apiServerLabel = S(server.label)
		} else {
			atNextEvent {
				let e = apiError("Sync has failed, skipping this call")
				completion(nil, nil, nil, e, false)
			}
			return
		}

		let expandedPath = path.hasPrefix("/") ? S(server.apiPath).appending(pathComponent: path) : path
		let url = URL(string: expandedPath)!

		var request = URLRequest(url: url)
		var acceptTypes = [String]()
		if shouldSyncReactions {
			acceptTypes.append("application/vnd.github.squirrel-girl-preview")
		}
		if (shouldSyncReviews || shouldSyncReviewAssignments) && (!server.isGitHub) {
			acceptTypes.append("application/vnd.github.black-cat-preview+json")
		}
		acceptTypes.append("application/vnd.github.v3+json")
		request.setValue(acceptTypes.joined(separator: ", "), forHTTPHeaderField: "Accept")
		if let a = server.authToken {
			request.setValue("token \(a)", forHTTPHeaderField: "Authorization")
		}

		////////////////////////// preempt with error backoff algorithm
		let existingBackOff = badLinks[expandedPath]
		if let eb = existingBackOff {
			if eb.nextAttemptAt.timeIntervalSinceNow > 0 {
				// report failure and return
				DLog("(%@) Preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, expandedPath, eb.nextAttemptAt)
				atNextEvent {
					let e = apiError("Preempted fetch because of throttling")
					completion(nil, nil, nil, e, false)
				}
				return
			}
			else {
				badLinks.removeValue(forKey: expandedPath)
			}
		}

		proceedWithNetworkRequest(request, urlPath: expandedPath, apiServerLabel: apiServerLabel, existingBackOff: existingBackOff, completion: completion)
	}

	private static func proceedWithNetworkRequest(_ request: URLRequest,
	                                             urlPath: String,
	                                             apiServerLabel: String,
	                                             existingBackOff: UrlBackOffEntry?,
	                                             completion: @escaping ApiCompletion) {
		let task = urlSession.dataTask(with: request) { data, res, e in

			let response = res as? HTTPURLResponse
			let error: Error?
			let shouldRetry: Bool
			var parsedData: Any?
			let code = Int64(response?.statusCode ?? 0)
			let headers = response?.allHeaderFields

			if code > 299 {
				error = apiError("Server responded with error \(code)")
				shouldRetry = (code == 502 || code == 503) // retry in case GH is deploying
			} else if code == 0 {
				error = apiError("Server did not respond")
				shouldRetry = (e as NSError?)?.code == -1001 // retry if it was a timeout
			} else if Int64(data?.count ?? 0) < (response?.expectedContentLength ?? 0) {
				error = apiError("Server data was truncated")
				shouldRetry = true // transfer truncation, try again
			} else {
				DLog("(%@) GET %@ - RESULT: %@", apiServerLabel, urlPath, code)
				error = e as NSError?
				shouldRetry = false
				if let d = data {
					parsedData = try? JSONSerialization.jsonObject(with: d, options: [])
				}
			}

			handleResponse(with: data,
						   parsedData: parsedData,
						   serverLabel: apiServerLabel,
						   urlPath: urlPath,
						   code: code,
						   error: error,
						   shouldRetry: shouldRetry,
						   existingBackOff: existingBackOff,
						   headers: headers,
						   completion: completion)
		}
		task.resume()
	}

	private static func handleResponse(with data: Data?,
	                                  parsedData: Any?,
	                                  serverLabel: String,
	                                  urlPath: String,
	                                  code: Int64,
	                                  error: Error?,
	                                  shouldRetry: Bool,
	                                  existingBackOff: UrlBackOffEntry?,
	                                  headers: [AnyHashable : Any]?,
	                                  completion: @escaping ApiCompletion) {
		if let e = error {
			if code > 399 && !shouldRetry {
				if var backoff = existingBackOff {
					DLog("(%@) Extending backoff for already throttled URL %@ by %@ seconds", serverLabel, urlPath, backOffIncrement)
					if backoff.nextIncrement < 3600.0 {
						backoff.nextIncrement += backOffIncrement
					}
					backoff.nextAttemptAt = Date(timeIntervalSinceNow: backoff.nextIncrement)
					atNextEvent {
						badLinks[urlPath] = backoff
					}
				} else {
					DLog("(%@) Placing URL %@ on the throttled list", serverLabel, urlPath)
					let newEntry = UrlBackOffEntry(
						nextAttemptAt: Date(timeIntervalSinceNow: backOffIncrement),
						nextIncrement: backOffIncrement)
					atNextEvent {
						badLinks[urlPath] = newEntry
					}
				}
			}
			DLog("(%@) GET %@ - FAILED: (code %@) %@", serverLabel, urlPath, code, e.localizedDescription)
		}

		if Settings.dumpAPIResponsesInConsole, let d = data {
			DLog("API data from %@: %@", urlPath, String(bytes: d, encoding: .utf8))
		}

		atNextEvent {
			completion(code, headers, parsedData, error, shouldRetry)
		}
	}

	#if os(iOS)

	private static var networkIndicationCount = 0
	private static var networkBGTask = UIBackgroundTaskIdentifier.invalid
	private static let networkBGEndPopTimer = { ()->PopTimer in
		return PopTimer(timeInterval: 1.0) {
			endNetworkBGTask()
		}
	}()

	private static func networkIndicationStart() {
		networkIndicationCount += 1
		if networkIndicationCount == 1 {
			let a = UIApplication.shared
			a.isNetworkActivityIndicatorVisible = true
			networkBGTask = a.beginBackgroundTask(withName: "com.housetrip.Trailer.network") {
				endNetworkBGTask()
			}
		}
	}

	private static func networkIndicationEnd() {
		networkIndicationCount -= 1
		if networkIndicationCount == 0 {
			UIApplication.shared.isNetworkActivityIndicatorVisible = false
			networkBGEndPopTimer.push()
		}
	}
	
	private static func endNetworkBGTask() {
		if networkBGTask != UIBackgroundTaskIdentifier.invalid {
			UIApplication.shared.endBackgroundTask(networkBGTask)
			networkBGTask = UIBackgroundTaskIdentifier.invalid
		}
	}
	
	#endif
}
