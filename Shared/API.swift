
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

			API.start(call: path, on: server, ignoreLastSync: ignoreLastSync) { [weak self] code, headers, data, error, shouldRetry in
				guard let s = self else { return }

				s.completion(code, headers, data, error, shouldRetry)
				NotificationCenter.default.post(name: SyncProgressUpdateNotification, object: nil)

				#if os(iOS)
					API.networkIndicationEnd()
				#endif

				s.willChangeValue(forKey: "isFinished")
				s._isFinished = true
				s.didChangeValue(forKey: "isFinished")
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
	static var refreshesSinceLastLabelsCheck = [NSManagedObjectID : Int]()
	static var currentNetworkStatus = NetworkStatus.NotReachable

	private static let cacheDirectory = { ()->String in
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer").path
	}()

	private static let cacheMoc = DataManager.buildThreadParallelContext()

	private static let urlSession = { ()->URLSession in

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
		return URLSession(configuration: config)
	}()

	private static var badLinks = [String : UrlBackOffEntry]()
	private static let reachability = Reachability()
	private static let backOffIncrement: TimeInterval = 120

	class func setup() {

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

	private class func checkNetworkAvailability() {
		let newStatus = reachability.status
		if newStatus != currentNetworkStatus {
			currentNetworkStatus = newStatus
			DLog("Network changed to %@", newStatus.name)
			clearAllBadLinks()
		}
	}

	class var hasNetworkConnection: Bool {
		DLog("Actively verifying reported network availability state...")
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

	class var lastUpdateDescription: String {
		if appIsRefreshing {
			let operations = apiQueue.operationCount
			if operations < 2 {
				return "Refreshing..."
			} else {
				return "Refreshing... (\(operations) calls remaining)"
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

	private class func expireOldImageCacheEntries() {

		let now = Date()
		let fileManager = FileManager.default
		for f in try! fileManager.contentsOfDirectory(atPath: cacheDirectory) {
			if f.hasPrefix("imgcache-") {
				do {
					let path = cacheDirectory.appending(pathComponent: f)
					let attributes = try fileManager.attributesOfItem(atPath: path)
					let date = attributes[.creationDate] as! Date
					if now.timeIntervalSince(date) > (3600.0*24.0) {
						try! fileManager.removeItem(atPath: path)
					}
				} catch {
					DLog("File error when cleaning old cached image: %@", error.localizedDescription)
				}
			}
		}
	}

	@discardableResult
	class func haveCachedAvatar(from path: String, callback: @escaping (IMAGE_CLASS?, String) -> Void) -> Bool {

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
				#if os(iOS)
					atNextEvent {
						networkIndicationEnd()
					}
				#endif
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
		let imageKey = "\(absolutePath) \(currentAppVersion)"
		let cachePath = cacheDirectory.appending(pathComponent: "imgcache-\(imageKey.md5hashed)")

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

			var result: IMAGE_CLASS?
			#if os(iOS)
				if let d = data, let i = UIImage(data: d, scale: GLOBAL_SCREEN_SCALE) {
					result = i
					if let imageData = UIImageJPEGRepresentation(i, 1.0) {
						try! imageData.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
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
			}
		}
		return false
	}

	////////////////////////////////////// API interface

	class func syncItemsForActiveReposAndCallback(callback: @escaping Completion) {
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

	private class func sync(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		markDirtyRepos(in: moc) {

			let repos = Repo.syncableRepos(in: moc)

			var completionCount = 0
			let totalOperations = 2
			let completionCallback = {
				completionCount += 1
				if completionCount == totalOperations {
					NotificationCenter.default.post(name: RefreshProcessingNotification, object: nil)
					for r in repos { r.dirty = false }
					completeSync(in: moc, andCallback: callback)
				}
			}

			fetchIssues(for: repos, to: moc) {
				fetchCommentsForCurrentIssues(to: moc) {
					checkIssueClosures(in: moc)
					completionCallback()
				}
			}

			fetchPullRequests(for: repos, to: moc) {
				updatePullRequests(in: moc) {
					completionCallback()
				}
			}
		}
	}

	private class func completeSync(in moc: NSManagedObjectContext, andCallback: @escaping Completion) {

		DLog("Wrapping up sync")

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

		cacheMoc.performAndWait {
			CacheEntry.cleanOldEntries(in: cacheMoc)
			try! cacheMoc.save()
		}

		for r in DataItem.items(of: PullRequest.self, surviving: true, in: moc, prefetchRelationships: ["comments"]) {
			mainQueue.addOperation {
				r.postProcess()
			}
		}

		for i in DataItem.items(of: Issue.self, surviving: true, in: moc, prefetchRelationships: ["comments"]) {
			mainQueue.addOperation {
				i.postProcess()
			}
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

	class func resetAllLabelChecks() {
		refreshesSinceLastLabelsCheck.removeAll()
	}

	class func resetAllStatusChecks() {
		refreshesSinceLastStatusCheck.removeAll()
	}

	private class func updatePullRequests(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let willScanForStatuses = shouldScanForStatuses(in: moc)
		let willScanForLabels = shouldScanForLabels(in: moc)

		var totalOperations = 3
		if willScanForStatuses { totalOperations += 1 }
		if willScanForLabels { totalOperations += 1 }

		var completionCount = 0
		let completionCallback = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		if willScanForStatuses {
			fetchStatusesForCurrentPullRequests(to: moc, callback: completionCallback)
		}
		if willScanForLabels {
			fetchLabelsForForCurrentPullRequests(to: moc, callback: completionCallback)
		}
		fetchCommentsForCurrentPullRequests(to: moc, callback: completionCallback)
		checkPrClosures(in: moc, callback: completionCallback)
		detectAssignedPullRequests(in: moc, callback: completionCallback)
	}

	private class func markDirtyRepos(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let allApiServers = ApiServer.allApiServers(in: moc)
		let totalOperations = 2*allApiServers.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0
		let repoIdsToMarkDirty = NSMutableSet()

		let completionCallback = {
			completionCount += 1
			if completionCount==totalOperations {

				if repoIdsToMarkDirty.count>0 {
					Repo.markDirtyReposWithIds(repoIdsToMarkDirty, in: moc)
					DLog("Marked %@ dirty repos that have new events in their event stream", repoIdsToMarkDirty.count)
				}

				let reposNotRecentlyDirtied = Repo.reposNotRecentlyDirtied(in: moc)
				if reposNotRecentlyDirtied.count>0 {
					for r in reposNotRecentlyDirtied {
						r.resetSyncState()
					}
					DLog("Marked dirty %@ repos which haven't been refreshed in over an hour", reposNotRecentlyDirtied.count)
				}

				callback()
			}
		}

		for apiServer in allApiServers {
			if apiServer.goodToGo && apiServer.lastSyncSucceeded {
				markDirty(repoIds: repoIdsToMarkDirty, usingUserEventsFrom: apiServer, callback: completionCallback)
				markDirty(repoIds: repoIdsToMarkDirty, usingReceivedEventsFrom: apiServer, callback: completionCallback)
			} else {
				completionCallback()
				completionCallback()
			}
		}
	}

	private class func fetchUserTeams(from server: ApiServer, callback: @escaping Completion) {

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

	private class func markDirty(repoIds toMarkDirty: NSMutableSet, usingUserEventsFrom server: ApiServer, callback: @escaping Completion) {

		if !server.lastSyncSucceeded {
			callback()
			return
		}

		var latestDate = server.latestUserEventDateProcessed
		if latestDate == nil {
			latestDate = .distantPast
			server.latestUserEventDateProcessed = latestDate
		}

		let userName = S(server.userName)
		let serverLabel = S(server.label)

		getPagedData(at: "/users/\(userName)/events", from: server, perPageCallback: { data, lastPage in
			for d in data ?? [] {
				let eventDate = parseGH8601(d["created_at"] as? String) ?? .distantPast
				if latestDate! < eventDate {
					if let repoId = (d["repo"] as? [AnyHashable : Any])?["id"] as? NSNumber {
						DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
						toMarkDirty.add(repoId)
					}
					if server.latestUserEventDateProcessed! < eventDate {
						server.latestUserEventDateProcessed = eventDate
						if latestDate! == .distantPast {
							DLog("(%@) First sync, all repos are dirty so we don't need to read further, we have the latest received event date: %@", serverLabel, eventDate)
							return true
						}
					}
				} else {
					DLog("(%@) No further user events", serverLabel)
					return true
				}
			}
			return false
		}) { success, resultCode in
			if !success {
				server.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private class func markDirty(repoIds toMarkDirty: NSMutableSet, usingReceivedEventsFrom server: ApiServer, callback: @escaping Completion) {

		if !server.lastSyncSucceeded {
			callback()
			return
		}

		var latestDate = server.latestReceivedEventDateProcessed
		if latestDate == nil {
			latestDate = .distantPast
			server.latestReceivedEventDateProcessed = latestDate
		}

		let userName = S(server.userName)
		let serverLabel = S(server.label)

		getPagedData(at: "/users/\(userName)/received_events", from: server, perPageCallback: { data, lastPage in
			for d in data ?? [] {
				let eventDate = parseGH8601(d["created_at"] as? String) ?? .distantPast
				if latestDate! < eventDate {
					if let repoId = (d["repo"] as? [AnyHashable : Any])?["id"] as? NSNumber {
						DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
						toMarkDirty.add(repoId)
					}
					if server.latestReceivedEventDateProcessed! < eventDate {
						server.latestReceivedEventDateProcessed = eventDate
						if latestDate! == .distantPast {
							DLog("(%@) First sync, all repos are dirty so we don't need to read further, we have the latest received event date: %@", serverLabel, eventDate)
							return true
						}
					}
				} else {
					DLog("(%@) No further received events", serverLabel)
					return true
				}
			}
			return false
		}) { success, resultCode in
			if !success {
				server.lastSyncSucceeded = false
			}
			callback()
		}
	}

	class func fetchRepositories(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		ApiServer.resetSyncSuccess(in: moc)
		clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

		syncUserDetails(in: moc) {
			for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
				r.postSyncAction = r.manuallyAdded ? PostSyncAction.doNothing.rawValue : PostSyncAction.delete.rawValue
			}

			let allApiServers = ApiServer.allApiServers(in: moc)
			let totalOperations = allApiServers.count*2
			var completionCount = 0

			let completionCallback = {
				completionCount += 1
				if completionCount == totalOperations {
					for r in DataItem.newItems(of: Repo.self, in: moc) {
						if r.shouldSync {
							NotificationQueue.add(type: .newRepoAnnouncement, for: r)
						}
					}
					lastRepoCheck = Date()
					callback()
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo {
					syncWatchedRepos(from: apiServer, callback: completionCallback)
					fetchUserTeams(from: apiServer, callback: completionCallback)
				} else {
					completionCallback()
					completionCallback()
				}
			}
		}
	}

	private class func fetchPullRequests(for repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

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

	private class func handleRepoSyncFailure(repo: Repo, resultCode: Int64) {
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

	private class func fetchIssues(for repos: [Repo], to moc: NSManagedObjectContext, callback: @escaping Completion) {

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

	private class func fetchCommentsForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

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

	private class func fetchCommentsForCurrentIssues(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let allIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc)

		for i in allIssues {
			for c in i.comments {
				c.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		let issues = allIssues.filter { $0.apiServer.lastSyncSucceeded }

		let totalOperations = issues.count
		if totalOperations == 0 {
			callback()
			return
		}

		var completionCount = 0

		for i in issues {

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

	private class func fetchLabelsForForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = PullRequest.active(in: moc, visibleOnly: true).filter { pr in
			if !pr.apiServer.lastSyncSucceeded {
				return false
			}
			if pr.condition != ItemCondition.open.rawValue {
				//DLog("Won't check labels for closed/merged PR: %@", pr.title)
				return false
			}
			let oid = pr.objectID
			let refreshes = refreshesSinceLastLabelsCheck[oid]
			if refreshes == nil || refreshes! >= Settings.labelRefreshInterval {
				//DLog("Will check labels for PR: '%@'", pr.title)
				return true
			} else {
				//DLog("No need to get labels for PR: '%@' (%@ refreshes since last check)", pr.title, refreshes)
				refreshesSinceLastLabelsCheck[oid] = (refreshes ?? 0)+1
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
			for l in p.labels {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}

			if let link = p.labelsLink {

				getPagedData(at: link, from: p.apiServer, perPageCallback: { data, lastPage in
					PRLabel.syncLabels(from: data, withParent: p)
					return false
				}) { success, resultCode in
					completionCount += 1
					var allGood = success
					if !success {
						// 404/410 means the label has been deleted
						if !(resultCode==404 || resultCode==410) {
							p.apiServer.lastSyncSucceeded = false
						} else {
							allGood = true
						}
					}
					if allGood {
						refreshesSinceLastLabelsCheck[p.objectID] = 1
					}
					if completionCount == totalOperations {
						callback()
					}
				}
			} else {
				// no labels link, so presumably no labels
				refreshesSinceLastLabelsCheck[p.objectID] = 1
				completionCount += 1
				if completionCount == totalOperations {
					callback()
				}
			}
		}
	}

	private class func fetchStatusesForCurrentPullRequests(to moc: NSManagedObjectContext, callback: @escaping Completion) {

		let prs = PullRequest.active(in: moc, visibleOnly: !Settings.hidePrsThatArentPassing).filter { pr in
			if !pr.apiServer.lastSyncSucceeded {
				return false
			}
			let oid = pr.objectID
			let refreshes = self.refreshesSinceLastStatusCheck[oid]
			if refreshes == nil || refreshes! >= Settings.statusItemRefreshInterval {
				//DLog("Will check statuses for PR: '%@'", pr.title)
				return true
			} else {
				//DLog("No need to get statuses for PR: '%@' (%@ refreshes since last check)", pr.title, refreshes)
				self.refreshesSinceLastStatusCheck[oid] = (refreshes ?? 0)+1
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

	private class func checkPrClosures(in moc: NSManagedObjectContext, callback: @escaping Completion) {
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

	private class func checkIssueClosures(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [PostSyncAction.delete.matchingPredicate, ItemCondition.open.matchingPredicate])
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		
		for i in try! moc.fetch(f).filter { $0.shouldCheckForClosing } {
			handleClosing(of: i)
		}
	}

	private class func detectAssignedPullRequests(in moc: NSManagedObjectContext, callback: @escaping Completion) {

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
						p.processAssignmentStatus(from: data as? [AnyHashable : Any])
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

	private class func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext, callback: @escaping Completion) {
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

	private class func investigatePrClosure(for pullRequest: PullRequest, callback: @escaping Completion) {
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

	private class func handleMerging(of pullRequest: PullRequest, byUserId: Int64) {

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

	private class func handleClosing(of item: ListableItem) {
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

	private class func getRateLimit(from server: ApiServer, callback: @escaping (_ limits: ApiRateLimits?)->Void) {

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

	class func updateLimitsFromServer() {
		let allApiServers = ApiServer.allApiServers(in: DataManager.main)
		let totalOperations = allApiServers.count
		var completionCount = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getRateLimit(from: apiServer) { limits in
					if let l = limits {
						apiServer.updateApiLimits(l)
					}
					completionCount += 1
					if completionCount == totalOperations {
						NotificationCenter.default.post(name: ApiUsageUpdateNotification, object: apiServer, userInfo: nil)
					}
				}
			}
		}
	}

	private class func shouldScanForStatuses(in moc: NSManagedObjectContext) -> Bool {
		if Settings.showStatusItems {
			return true
		} else {
			refreshesSinceLastStatusCheck.removeAll()
			for s in DataItem.allItems(of: PRStatus.self, in: moc) {
				s.postSyncAction = PostSyncAction.delete.rawValue
			}
			return false
		}
	}

	private class func shouldScanForLabels(in moc: NSManagedObjectContext) -> Bool {
		if Settings.showLabels {
			return true
		} else {
			refreshesSinceLastLabelsCheck.removeAll()
			for l in DataItem.allItems(of: PRLabel.self, in: moc) {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}
			return false
		}
	}

	private class func syncWatchedRepos(from server: ApiServer, callback: @escaping Completion) {

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

	class func fetchRepo(named: String, owner: String, from server: ApiServer, completion: @escaping (Error?) -> Void) {
		let path = "\(server.apiPath ?? "")/repos/\(owner)/\(named)"
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

	private class func syncUserDetails(in moc: NSManagedObjectContext, callback: @escaping Completion) {

		let allApiServers = ApiServer.allApiServers(in: moc)
		let totalOperations = allApiServers.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0

		for apiServer in allApiServers {
			if apiServer.goodToGo {
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
			} else {
				completionCount += 1
				if completionCount == totalOperations { callback() }
			}
		}

	}

	class func clearAllBadLinks() {
		badLinks.removeAll(keepingCapacity: false)
	}

	class func testApi(to apiServer: ApiServer, callback: @escaping (Error?) -> Void) {

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

	private class func apiError(_ message: String) -> Error {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	//////////////////////////////////////////////////////////// low level

	private class func getPagedData(
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

		let p = page > 1 ? "\(path)?page=\(page)" : path
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

	private class func getData(
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

					NotificationCenter.default.post(name: ApiUsageUpdateNotification, object: server, userInfo: nil)
				}
				callback(data, lastPage, code ?? 0)
			} else {
				if shouldRetry && attemptCount < 2 { // timeout, truncation, connection issue, etc
					let nextAttemptCount = attemptCount+1
					DLog("(%@) Will retry failed API call to %@ (attempt #%@)", S(server.label), path, nextAttemptCount)
					delay(2.0) {
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

	private static let apiQueue = { () -> OperationQueue in
		let n = OperationQueue()
		n.underlyingQueue = DispatchQueue.main
		#if os(iOS)
			let archIs64Bit = (MemoryLayout<Int>.size == MemoryLayout<Int64>.size)
			n.maxConcurrentOperationCount = archIs64Bit ? 8 : 2
		#else
			n.maxConcurrentOperationCount = 8
		#endif
		return n
	}()

	private class func start(
		call path: String,
		on server: ApiServer,
		ignoreLastSync: Bool,
		completion: @escaping ApiCompletion) {

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

		var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)
		r.setValue("application/vnd.github.v3+json", forHTTPHeaderField:"Accept")
		if let a = server.authToken {
			r.setValue("token \(a)", forHTTPHeaderField: "Authorization")
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

		let cacheKey = "\(server.objectID.uriRepresentation().absoluteString) \(expandedPath)"
		var previousCacheEntry: CacheUnit?
		cacheMoc.performAndWait {
			previousCacheEntry = CacheEntry.entry(for: cacheKey, in: cacheMoc)?.cacheUnit // move data out of thread-specific context
		}
		if let p = previousCacheEntry {
			/////////////////////// 60 second dumb-caching
			if p.lastFetched > Date(timeIntervalSinceNow: -60), let parsedData = p.parsedData {
				DLog("(%@) GET %@ - CACHED", apiServerLabel, expandedPath)
				handleResponse(with: p.data,
				               parsedData: parsedData,
				               serverLabel: apiServerLabel,
				               urlPath: expandedPath,
				               code: p.code,
				               error: nil,
				               shouldRetry: false,
				               existingBackOff: nil,
				               headers: p.actualHeaders,
				               completion: completion)
				return
			}
			r.setValue(p.etag, forHTTPHeaderField: "If-None-Match")
		}

		let task = urlSession.dataTask(with: r) { data, res, e in

			let response = res as? HTTPURLResponse
			let parsedData: Any?
			let error: Error?
			let shouldRetry: Bool
			var code = Int64(response?.statusCode ?? 0)
			var headers = response?.allHeaderFields

			if code == 304, let p = previousCacheEntry {
				error = nil
				parsedData = p.parsedData
				shouldRetry = false
				code = p.code
				headers = p.actualHeaders
				cacheMoc.perform {
					CacheEntry.markFetched(for: cacheKey, in: cacheMoc)
				}
				DLog("(%@) GET %@ - NO CHANGE (304): %@", apiServerLabel, expandedPath, code)
			} else if code > 299 {
				error = apiError("Server responded with error \(code)")
				parsedData = nil
				shouldRetry = (code == 502 || code == 503) // retry in case GH is deploying
			} else if code == 0 {
				error = apiError("Server did not repond")
				parsedData = nil
				shouldRetry = (e as? NSError)?.code == -1001 // retry if it was a timeout
			} else if Int64(data?.count ?? 0) < (response?.expectedContentLength ?? 0) {
				error = apiError("Server data was truncated")
				parsedData = nil
				shouldRetry = true // transfer truncation, try again
			} else {
				DLog("(%@) GET %@ - RESULT: %@", apiServerLabel, expandedPath, code)
				error = e as? NSError
				shouldRetry = false
				if let d = data {
					parsedData = try? JSONSerialization.jsonObject(with: d, options: [])
					if let headers = headers, let etag = headers["Etag"] as? String {
						cacheMoc.perform {
							CacheEntry.setEntry(key: cacheKey, code: code, etag: etag, data: d, headers: headers, in: cacheMoc)
						}
					}
				} else {
					parsedData = nil
				}
			}

			DispatchQueue.main.sync {
				handleResponse(with: data,
				               parsedData: parsedData,
				               serverLabel: apiServerLabel,
				               urlPath: expandedPath,
				               code: code,
				               error: error,
				               shouldRetry: shouldRetry,
				               existingBackOff: existingBackOff,
				               headers: headers,
				               completion: completion)
			}
		}
		#if os(iOS)
			task.priority = URLSessionTask.lowPriority
		#endif
		task.resume()
	}

	private class func handleResponse(with data: Data?,
	                                  parsedData: Any?,
	                                  serverLabel: String,
	                                  urlPath: String,
	                                  code: Int64,
	                                  error: Error?,
	                                  shouldRetry: Bool,
	                                  existingBackOff: UrlBackOffEntry?,
	                                  headers: [AnyHashable : Any]?,
	                                  completion: ApiCompletion) {
		if let e = error {
			if code > 399 {
				if var backoff = existingBackOff {
					DLog("(%@) Extending backoff for already throttled URL %@ by %@ seconds", serverLabel, urlPath, backOffIncrement)
					if backoff.nextIncrement < 3600.0 {
						backoff.nextIncrement += backOffIncrement
					}
					backoff.nextAttemptAt = Date(timeIntervalSinceNow: backoff.nextIncrement)
					badLinks[urlPath] = backoff
				} else {
					DLog("(%@) Placing URL %@ on the throttled list", serverLabel, urlPath)
					badLinks[urlPath] = UrlBackOffEntry(
						nextAttemptAt: Date(timeIntervalSinceNow: backOffIncrement),
						nextIncrement: backOffIncrement)
				}
			}
			DLog("(%@) GET %@ - FAILED: (code %@) %@", serverLabel, urlPath, code, e.localizedDescription)
		}

		if Settings.dumpAPIResponsesInConsole, let d = data {
			DLog("API data from %@: %@", urlPath, String(bytes: d, encoding: .utf8))
		}

		completion(code, headers, parsedData, error, shouldRetry)
	}

	#if os(iOS)

	private static var networkIndicationCount = 0
	private static var networkBGTask = UIBackgroundTaskInvalid
	private static let networkBGEndPopTimer = { ()->PopTimer in
		return PopTimer(timeInterval: 1.0) {
			endNetworkBGTask()
		}
	}()

	private class func networkIndicationStart() {
		networkIndicationCount += 1
		if networkIndicationCount == 1 {
			let a = UIApplication.shared
			a.isNetworkActivityIndicatorVisible = true
			networkBGTask = a.beginBackgroundTask(withName: "com.housetrip.Trailer.network") {
				endNetworkBGTask()
			}
		}
	}

	private class func networkIndicationEnd() {
		networkIndicationCount -= 1
		if networkIndicationCount == 0 {
			UIApplication.shared.isNetworkActivityIndicatorVisible = false
			networkBGEndPopTimer.push()
		}
	}
	
	private class func endNetworkBGTask() {
		if networkBGTask != UIBackgroundTaskInvalid {
			UIApplication.shared.endBackgroundTask(networkBGTask)
			networkBGTask = UIBackgroundTaskInvalid
		}
	}
	
	#endif
}
