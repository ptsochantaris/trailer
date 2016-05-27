
import CoreData
#if os(iOS)
import UIKit
#endif

final class API {

	private struct UrlBackOffEntry {
		var nextAttemptAt: NSDate
		var duration: NSTimeInterval
	}

	var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
	var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
	var currentNetworkStatus: NetworkStatus

	private let cacheDirectory: String
	private let urlSession: NSURLSession
	private var badLinks = [String:UrlBackOffEntry]()
	private let reachability = Reachability.reachabilityForInternetConnection()

	init() {

		reachability.startNotifier()
		let n = reachability.currentReachabilityStatus()
		DLog("Network is %@", n == .NotReachable ? "down" : "up")
		currentNetworkStatus = n

		let fileManager = NSFileManager.defaultManager()
		let appSupportURL = fileManager.URLsForDirectory(NSSearchPathDirectory.CachesDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).first! 
		cacheDirectory = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer").path!

        #if DEBUG
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion())-iOS-Development"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion())-OSX-Development"
            #endif
        #else
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion())-iOS-Release"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion())-OSX-Release"
            #endif
        #endif

		let config = NSURLSessionConfiguration.defaultSessionConfiguration()
		config.HTTPMaximumConnectionsPerHost = 4
		config.HTTPShouldUsePipelining = true
		config.HTTPAdditionalHeaders = ["User-Agent" : userAgent]
		urlSession = NSURLSession(configuration: config)

		if fileManager.fileExistsAtPath(cacheDirectory) {
			expireOldImageCacheEntries()
		} else {
			do { try fileManager.createDirectoryAtPath(cacheDirectory, withIntermediateDirectories: true, attributes: nil) } catch _ {}
		}

		NSNotificationCenter.defaultCenter().addObserverForName(kReachabilityChangedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { [weak self] n in
			self?.checkNetworkAvailability()
			if self?.currentNetworkStatus != .NotReachable {
				app.startRefreshIfItIsDue()
			}
		}
	}

	private func checkNetworkAvailability() {
		let newStatus = reachability.currentReachabilityStatus()
		if newStatus != currentNetworkStatus {
			currentNetworkStatus = newStatus
			if newStatus == .NotReachable {
				DLog("Network went down: %d", newStatus.rawValue)
			} else {
				DLog("Network came up: %d", newStatus.rawValue)
			}
			clearAllBadLinks()
		}
	}

	func noNetworkConnection() -> Bool {
		DLog("Actively verifying reported network availability state...")
		let previousNetworkStatus = currentNetworkStatus
		checkNetworkAvailability()
		if previousNetworkStatus != currentNetworkStatus {
			DLog("Network state seems to have changed without having been notified, noted")
		} else {
			DLog("No change to network state")
		}
		return currentNetworkStatus == .NotReachable
	}

	/////////////////////////////////////////////////////// Utilities

	func lastUpdateDescription() -> String {
		if appIsRefreshing {
			return "Refreshing..."
		} else if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			return "Last update failed"
		} else {
			let lastSuccess = Settings.lastSuccessfulRefresh ?? NSDate()
			let ago = NSDate().timeIntervalSinceDate(lastSuccess)
			if ago<10 {
				return "Just updated"
			} else {
				return "Updated \(Int(ago)) seconds ago"
			}
		}
	}

	///////////////////////////////////////////////////////// Images

	func expireOldImageCacheEntries() {

		do {
			let now = NSDate()
			let fileManager = NSFileManager.defaultManager()
			for f in try fileManager.contentsOfDirectoryAtPath(cacheDirectory) {
				if f.characters.startsWith("imgcache-".characters) {
					do {
						let path = cacheDirectory.stringByAppendingPathComponent(f)
						let attributes = try fileManager.attributesOfItemAtPath(path)
						let date = attributes[NSFileCreationDate] as! NSDate
						if now.timeIntervalSinceDate(date) > (3600.0*24.0) {
							try fileManager.removeItemAtPath(path)
						}
					} catch {
						DLog("File error when cleaning old cached image: %@", (error as NSError).localizedDescription)
					}
				}
			}
		} catch { /* No directory */ }
	}

	// Warning: Calls back on thread!!
	private func getImage(url: NSURL, completion:(data: NSData?) -> Void) {

		let task = urlSession.dataTaskWithURL(url) { [weak self] data, response, error in

			let r = response as? NSHTTPURLResponse
			if error != nil || response == nil || r?.statusCode > 299 || (r?.expectedContentLength ?? 0) < Int64(data?.length ?? 0) {
				completion(data: nil)
			} else {
				completion(data: data)
			}
			#if os(iOS)
				atNextEvent(self) { S in
					S.networkIndicationEnd()
				}
			#endif
		}

		#if os(iOS)
			task.priority = NSURLSessionTaskPriorityHigh
			delay(0.1, self) { S in
				S.networkIndicationStart()
			}
		#endif

		task.resume()
	}

	func haveCachedAvatar(path: String, tryLoadAndCallback: (IMAGE_CLASS?, String) -> Void) -> Bool {

		#if os(iOS)
			let imgsize = 40.0*GLOBAL_SCREEN_SCALE
		#else
			let imgsize = 88
		#endif
		let connector = path.characters.contains("?") ? "&" : "?"
		let absolutePath = "\(path)\(connector)s=\(imgsize)"
		let imageKey = "\(absolutePath) \(currentAppVersion())"
		let cachePath = cacheDirectory.stringByAppendingPathComponent("imgcache-\(imageKey.md5hash)")
		
		let fileManager = NSFileManager.defaultManager()
		if fileManager.fileExistsAtPath(cachePath) {
			#if os(iOS)
				let imgData = NSData(contentsOfFile: cachePath)
				let imgDataProvider = CGDataProviderCreateWithCFData(imgData)
				var ret: UIImage?
				if let cfImage = CGImageCreateWithJPEGDataProvider(imgDataProvider, nil, false, CGColorRenderingIntent.RenderingIntentDefault) {
					ret = UIImage(CGImage: cfImage, scale: GLOBAL_SCREEN_SCALE, orientation:UIImageOrientation.Up)
				}
            #else
				let ret = NSImage(contentsOfFile: cachePath)
			#endif
			if let r = ret {
				atNextEvent {
					tryLoadAndCallback(r, cachePath)
				}
				return true
			} else {
				try! fileManager.removeItemAtPath(cachePath)
			}
		}

		getImage(NSURL(string: absolutePath)!) { data in

			var result: IMAGE_CLASS?
            #if os(iOS)
                if let d = data, i = IMAGE_CLASS(data: d, scale:GLOBAL_SCREEN_SCALE) {
					result = i
                    UIImageJPEGRepresentation(i, 1.0)?.writeToFile(cachePath, atomically: true)
				}
            #else
                if let d = data, i = IMAGE_CLASS(data: d) {
					result = i
                    i.TIFFRepresentation?.writeToFile(cachePath, atomically: true)
				}
            #endif
			atNextEvent {
				tryLoadAndCallback(result, cachePath)
			}
        }
		return false
	}

	////////////////////////////////////// API interface

	func syncItemsForActiveReposAndCallback(callback: Completion) {
		let syncContext = DataManager.tempContext()

		let shouldRefreshReposToo = lastRepoCheck.isEqualToDate(never())
			|| (NSDate().timeIntervalSinceDate(lastRepoCheck) > NSTimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| !Repo.anyVisibleReposInMoc(syncContext)

		if shouldRefreshReposToo {
			fetchRepositoriesToMoc(syncContext) { [weak self] in
				self?.syncToMoc(syncContext, callback: callback)
			}
		} else {
			ApiServer.resetSyncSuccessInMoc(syncContext)
			ensureApiServersHaveUserIdsInMoc(syncContext) { [weak self] in
				self?.syncToMoc(syncContext, callback: callback)
			}
		}
	}

	private func syncToMoc(moc: NSManagedObjectContext, callback: Completion) {

		markDirtyReposInMoc(moc) { [weak self] in

			let repos = Repo.syncableReposInMoc(moc)

			var completionCount = 0
			let totalOperations = 2
			let completionCallback: Completion = {
				completionCount += 1
				if completionCount == totalOperations {
					for r in repos { r.dirty = false }
					self?.completeSyncInMoc(moc, andCallback: callback)
				}
			}

			self?.fetchIssuesForRepos(repos, toMoc: moc) {
				self?.fetchCommentsForCurrentIssuesToMoc(moc) {
					self?.checkIssueClosuresInMoc(moc)
					completionCallback()
				}
			}

			self?.fetchPullRequestsForRepos(repos, toMoc: moc) {
				self?.updatePullRequestsInMoc(moc) {
					completionCallback()
				}
			}
		}
	}

	private func completeSyncInMoc(moc: NSManagedObjectContext, andCallback: Completion) {

		DLog("Wrapping up sync")

		// discard any changes related to any failed API server
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if !apiServer.syncIsGood {
				apiServer.rollBackAllUpdatesInMoc(moc)
				apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
			}
		}

		let mainQueue = NSOperationQueue.mainQueue()

		mainQueue.addOperationWithBlock {
			DataItem.nukeDeletedItemsInMoc(moc)
			CacheEntry.cleanOldEntries()
		}

		for r in DataItem.itemsOfType("PullRequest", surviving: true, inMoc: moc) as! [PullRequest] {
			mainQueue.addOperationWithBlock {
				r.postProcess()
			}
		}

		for i in DataItem.itemsOfType("Issue", surviving: true, inMoc: moc) as! [Issue] {
			mainQueue.addOperationWithBlock {
				i.postProcess()
			}
		}

		mainQueue.addOperationWithBlock {
			do {
				DLog("Committing synced data")
				try moc.save()
				DLog("Synced data committed")
			} catch {
				DLog("Committing sync failed: %@", (error as NSError).localizedDescription)
			}
			andCallback()
		}
	}

	func resetAllLabelChecks() {
		refreshesSinceLastLabelsCheck.removeAll()
	}

	func resetAllStatusChecks() {
		refreshesSinceLastStatusCheck.removeAll()
	}

	private func updatePullRequestsInMoc(moc: NSManagedObjectContext, callback: Completion) {

		let willScanForStatuses = shouldScanForStatusesInMoc(moc)
		let willScanForLabels = shouldScanForLabelsInMoc(moc)

		var totalOperations = 3
		if willScanForStatuses { totalOperations += 1 }
		if willScanForLabels { totalOperations += 1 }

		var completionCount = 0
		let completionCallback: Completion = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		if willScanForStatuses {
			fetchStatusesForCurrentPullRequestsToMoc(moc, callback: completionCallback)
		}
		if willScanForLabels {
			fetchLabelsForForCurrentPullRequestsToMoc(moc, callback: completionCallback)
		}
		fetchCommentsForCurrentPullRequestsToMoc(moc, callback: completionCallback)
		checkPrClosuresInMoc(moc, callback: completionCallback)
		detectAssignedPullRequestsInMoc(moc, callback: completionCallback)
	}

	private func markDirtyReposInMoc(moc: NSManagedObjectContext, callback: Completion) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		let totalOperations = 2*allApiServers.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0
		let repoIdsToMarkDirty = NSMutableSet()

		let completionCallback: Completion = {
			completionCount += 1
			if completionCount==totalOperations {

				if repoIdsToMarkDirty.count>0 {
					Repo.markDirtyReposWithIds(repoIdsToMarkDirty, inMoc:moc)
					DLog("Marked %d dirty repos that have new events in their event stream", repoIdsToMarkDirty.count)
				}

				let reposNotRecentlyDirtied = Repo.reposNotRecentlyDirtied(moc)
				if reposNotRecentlyDirtied.count>0 {
					for r in reposNotRecentlyDirtied {
						r.resetSyncState()
					}
					DLog("Marked dirty %d repos which haven't been refreshed in over an hour", reposNotRecentlyDirtied.count)
				}

				callback()
			}
		}

		for apiServer in allApiServers {
			if apiServer.goodToGo && apiServer.syncIsGood {
				markDirtyRepoIds(repoIdsToMarkDirty, usingUserEventsFromServer: apiServer, callback: completionCallback)
				markDirtyRepoIds(repoIdsToMarkDirty, usingReceivedEventsFromServer: apiServer, callback: completionCallback)
			} else {
				completionCallback()
				completionCallback()
			}
		}
	}

	private func fetchUserTeamsFromApiServer(apiServer: ApiServer, callback: Completion) {

		for t in apiServer.teams {
			t.postSyncAction = PostSyncAction.Delete.rawValue
		}

		getPagedDataInPath("/user/teams",
			fromServer: apiServer,
			startingFromPage: 1,
			perPageCallback: { data, lastPage in
				Team.syncTeamsWithInfo(data, apiServer: apiServer)
				return false
			}, finalCallback: { success, resultCode in
				if !success {
					apiServer.lastSyncSucceeded = false
				}
				callback()
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingUserEventsFromServer s: ApiServer, callback: Completion) {

		if !s.syncIsGood {
			callback()
			return
		}

		var latestDate = s.latestUserEventDateProcessed
		if latestDate == nil {
			latestDate = never()
			s.latestUserEventDateProcessed = latestDate
		}

		let userName = S(s.userName)
		let serverLabel = S(s.label)

		getPagedDataInPath("/users/\(userName)/events",
			fromServer: s,
			startingFromPage: 1,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = parseGH8601(d["created_at"] as? String) ?? never()
					if latestDate!.compare(eventDate) == .OrderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
							repoIdsToMarkDirty.addObject(repoId)
						}
						if s.latestUserEventDateProcessed!.compare(eventDate) == .OrderedAscending {
							s.latestUserEventDateProcessed = eventDate
							if latestDate!.isEqualToDate(never()) {
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
			}, finalCallback: { success, resultCode in
				if !success {
					s.lastSyncSucceeded = false
				}
				callback()
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingReceivedEventsFromServer s: ApiServer, callback: Completion) {

		if !s.syncIsGood {
			callback()
			return
		}

		var latestDate = s.latestReceivedEventDateProcessed
		if latestDate == nil {
			latestDate = never()
			s.latestReceivedEventDateProcessed = latestDate
		}

		let userName = S(s.userName)
		let serverLabel = S(s.label)

		getPagedDataInPath("/users/\(userName)/received_events",
			fromServer: s,
			startingFromPage: 1,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = parseGH8601(d["created_at"] as? String) ?? never()
					if latestDate!.compare(eventDate) == .OrderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
							repoIdsToMarkDirty.addObject(repoId)
						}
						if s.latestReceivedEventDateProcessed!.compare(eventDate) == .OrderedAscending {
							s.latestReceivedEventDateProcessed = eventDate
							if latestDate!.isEqualToDate(never()) {
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
			}, finalCallback: { success, resultCode in
				if !success {
					s.lastSyncSucceeded = false
				}
				callback()
		})
	}

	func fetchRepositoriesToMoc(moc: NSManagedObjectContext, callback: Completion) {

		ApiServer.resetSyncSuccessInMoc(moc)
		clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

		syncUserDetailsInMoc(moc) { [weak self] in
			for r in DataItem.itemsOfType("Repo", surviving: true, inMoc: moc) as! [Repo] {
				r.postSyncAction = PostSyncAction.Delete.rawValue
			}

			let allApiServers = ApiServer.allApiServersInMoc(moc)
			let totalOperations = allApiServers.count*2
			var completionCount = 0

			let completionCallback: Completion = {
				completionCount += 1
				if completionCount == totalOperations {
					for r in DataItem.newItemsOfType("Repo", inMoc: moc) as! [Repo] {
						r.displayPolicyForPrs = Settings.displayPolicyForNewPrs
						r.displayPolicyForIssues = Settings.displayPolicyForNewIssues
						if r.shouldSync {
							app.postNotificationOfType(.NewRepoAnnouncement, forItem:r)
						}
					}
					lastRepoCheck = NSDate()
					callback()
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo {
					self?.syncWatchedReposFromServer(apiServer, callback: completionCallback)
					self?.fetchUserTeamsFromApiServer(apiServer, callback: completionCallback)
				} else {
					completionCallback()
					completionCallback()
				}
			}
		}
	}

	private func fetchPullRequestsForRepos(repos: [Repo], toMoc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableReposInMoc(toMoc) {
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.Delete.rawValue
			}
		}

		if repos.count==0 {
			callback()
			return
		}
		let total = repos.count
		var completionCount = 0
		for r in repos {

			for p in r.pullRequests {
				if (p.condition?.integerValue ?? 0) == ItemCondition.Open.rawValue {
					p.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForPrs?.integerValue != RepoDisplayPolicy.Hide.rawValue {
				let repoFullName = S(r.fullName)
				getPagedDataInPath("/repos/\(repoFullName)/pulls", fromServer: apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						PullRequest.syncPullRequestsFromInfoArray(data, inRepo: r)
						return false
					}, finalCallback: { [weak self] success, resultCode in
						if !success {
							self?.handleRepoSyncFailure(r, withResultCode: resultCode)
						}
						completionCount += 1
						if completionCount==total {
							callback()
						}
				})
			} else {
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func handleRepoSyncFailure(r: Repo, withResultCode: Int) {
		if withResultCode == 404 { // repo disabled
			r.inaccessible = true
			r.postSyncAction = PostSyncAction.DoNothing.rawValue
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.Delete.rawValue
			}
			for i in r.issues {
				i.postSyncAction = PostSyncAction.Delete.rawValue
			}
		} else if withResultCode==410 { // repo gone for good
			r.postSyncAction = PostSyncAction.Delete.rawValue
		} else { // fetch problem
			r.apiServer.lastSyncSucceeded = false
		}
	}

	private func fetchIssuesForRepos(repos: [Repo], toMoc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableReposInMoc(toMoc) {
			for i in r.issues {
				i.postSyncAction = PostSyncAction.Delete.rawValue
			}
		}

		if repos.count==0 {
			callback()
			return
		}
		let total = repos.count
		var completionCount = 0
		for r in repos {

			for i in r.issues {
				if (i.condition?.integerValue ?? 0) == ItemCondition.Open.rawValue {
					i.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForIssues?.integerValue != RepoDisplayPolicy.Hide.rawValue {
				let repoFullName = S(r.fullName)
				getPagedDataInPath("/repos/\(repoFullName)/issues", fromServer: apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						Issue.syncIssuesFromInfoArray(data, inRepo: r)
						return false
					}, finalCallback: { [weak self] success, resultCode in
						if !success {
							self?.handleRepoSyncFailure(r, withResultCode: resultCode)
						}
						completionCount += 1
						if completionCount==total {
							callback()
						}
				})
			} else {
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func fetchCommentsForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = (DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as! [PullRequest]).filter({ pr in
			return pr.apiServer.syncIsGood
		})
		if prs.count==0 {
			callback()
			return
		}

		for p in prs {
			for c in p.comments {
				c.postSyncAction = PostSyncAction.Delete.rawValue
			}
		}

		let totalOperations = 2
		var completionCount = 0

		let completionCallback: Completion = {
			completionCount += 1
			if completionCount == totalOperations { callback() }
		}

		_fetchCommentsForPullRequests(prs, issues: true, inMoc: moc, callback: completionCallback)
		_fetchCommentsForPullRequests(prs, issues: false, inMoc: moc, callback: completionCallback)
	}

	private func _fetchCommentsForPullRequests(prs: [PullRequest], issues: Bool, inMoc: NSManagedObjectContext, callback: Completion) {

		let total = prs.count
		if total==0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			if let link = (issues ? p.issueCommentLink : p.reviewCommentLink) {

				let apiServer = p.apiServer

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						PRComment.syncCommentsFromInfo(data, pullRequest: p)
						return false
					}, finalCallback: { success, resultCode in
						completionCount += 1
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				completionCount += 1
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchCommentsForCurrentIssuesToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let allIssues = DataItem.newOrUpdatedItemsOfType("Issue", inMoc:moc) as! [Issue]

		for i in allIssues {
			for c in i.comments {
				c.postSyncAction = PostSyncAction.Delete.rawValue
			}
		}

		let issues = allIssues.filter({ i in
			return i.apiServer.syncIsGood
		})

		let total = issues.count
		if total==0 {
			callback()
			return
		}

		var completionCount = 0

		for i in issues {

			if let link = i.commentsLink {

				let apiServer = i.apiServer

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						PRComment.syncCommentsFromInfo(data, issue: i)
						return false
					}, finalCallback: { success, resultCode in
						completionCount += 1
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				completionCount += 1
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchLabelsForForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.activeInMoc(moc, visibleOnly: true).filter { [weak self] pr in
			if !pr.apiServer.syncIsGood {
				return false
			}
			if pr.condition?.integerValue != ItemCondition.Open.rawValue {
				//DLog("Won't check labels for closed/merged PR: %@", pr.title)
				return false
			}
			let oid = pr.objectID
			let refreshes = self?.refreshesSinceLastLabelsCheck[oid]
			if refreshes == nil || refreshes! >= Settings.labelRefreshInterval {
				//DLog("Will check labels for PR: '%@'", pr.title)
				return true
			} else {
				//DLog("No need to get labels for PR: '%@' (%d refreshes since last check)", pr.title, refreshes)
				self?.refreshesSinceLastLabelsCheck[oid] = (refreshes ?? 0)+1
				return false
			}
		}

		let total = prs.count
		if total==0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			for l in p.labels {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let link = p.labelsLink {

				getPagedDataInPath(link, fromServer: p.apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						PRLabel.syncLabelsWithInfo(data, withParent: p)
						return false
					}, finalCallback: { [weak self] success, resultCode in
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
							self?.refreshesSinceLastLabelsCheck[p.objectID] = 1
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				// no labels link, so presumably no labels
				refreshesSinceLastLabelsCheck[p.objectID] = 1
				completionCount += 1
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchStatusesForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.activeInMoc(moc, visibleOnly: !Settings.hidePrsThatArentPassing).filter { [unowned self] pr in
			if !pr.apiServer.syncIsGood {
				return false
			}
			let oid = pr.objectID
			let refreshes = self.refreshesSinceLastStatusCheck[oid]
			if refreshes == nil || refreshes! >= Settings.statusItemRefreshInterval {
				//DLog("Will check statuses for PR: '%@'", pr.title)
				return true
			} else {
				//DLog("No need to get statuses for PR: '%@' (%d refreshes since last check)", pr.title, refreshes)
				self.refreshesSinceLastStatusCheck[oid] = (refreshes ?? 0)+1
				return false
			}
		}

		let total = prs.count
		if total==0 {
			callback()
			return
		}

		var completionCount = 0

		for p in prs {
			for s in p.statuses {
				s.postSyncAction = PostSyncAction.Delete.rawValue
			}

			let apiServer = p.apiServer

			if let statusLink = p.statusesLink {
				getPagedDataInPath(statusLink, fromServer: apiServer, startingFromPage: 1,
					perPageCallback: { data, lastPage in
						PRStatus.syncStatusesFromInfo(data, pullRequest: p)
						return false
					}, finalCallback: { [weak self] success, resultCode in
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
							self?.refreshesSinceLastStatusCheck[p.objectID] = 1
						}
						if completionCount==total {
							callback()
						}
				})
			} else {
				refreshesSinceLastStatusCheck[p.objectID] = 1
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func checkPrClosuresInMoc(moc: NSManagedObjectContext, callback: Completion) {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, ItemCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = try! moc.executeFetchRequest(f) as! [PullRequest]

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return parent.shouldSync && ((parent.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue) && r.apiServer.syncIsGood
		}

		let totalOperations = prsToCheck.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0
		let completionCallback: Completion = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		for r in prsToCheck {
			investigatePrClosureFor(r, callback: completionCallback)
		}
	}

	private func checkIssueClosuresInMoc(moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, ItemCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false

		for i in try! moc.executeFetchRequest(f) as! [Issue] {
			let r = i.repo
			if r.shouldSync && ((r.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue) && r.apiServer.syncIsGood {
				itemWasClosed(i)
			}
		}
	}

	private func detectAssignedPullRequestsInMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = (DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as! [PullRequest]).filter({ pr in
			return pr.apiServer.syncIsGood
		})
		if prs.count==0 {
			callback()
			return
		}

		let totalOperations = prs.count
		var completionCount = 0

		let completionCallback: Completion = {
			completionCount += 1
			if completionCount == totalOperations {
				callback()
			}
		}

		for p in prs {
			let apiServer = p.apiServer
			if let issueLink = p.issueUrl {
				getDataInPath(issueLink, fromServer: apiServer) { data, lastPage, resultCode in
					if let d = data as? [NSObject : AnyObject], assigneeInfo = d["assignee"] as? [NSObject : AnyObject], assignee = assigneeInfo["login"] as? String {
						let assigned = (assignee == S(apiServer.userName))
						p.isNewAssignment = (assigned && !p.createdByMe && !(p.assignedToMe?.boolValue ?? false))
						p.assignedToMe = assigned
					} else if resultCode == 200 || resultCode == 404 || resultCode == 410 {
						// 200 means PR is not assigned to anyone, there was no asgineee info
						// 404/410 is fine, it means issue entry doesn't exist
						p.assignedToMe = false
						p.isNewAssignment = false
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

	private func ensureApiServersHaveUserIdsInMoc(moc: NSManagedObjectContext, callback: Completion) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if (apiServer.userId?.integerValue ?? 0) == 0 {
				needToCheck = true
				break
			}
		}

		if needToCheck {
			DLog("Some API servers don't have user details yet, will bring user credentials down for them")
			syncUserDetailsInMoc(moc, callback: callback)
		} else {
			callback()
		}
	}

	private func investigatePrClosureFor(r: PullRequest, callback: Completion) {
		DLog("Checking closed PR to see if it was merged: %@", r.title)

		let repoFullName = S(r.repo.fullName)
		let repoNumber = S(r.number?.stringValue)
		let path = "/repos/\(repoFullName)/pulls/\(repoNumber)"

		getDataInPath(path, fromServer: r.apiServer) { [weak self] data, lastPage, resultCode in

			if let d = data as? [NSObject : AnyObject] {
				if let mergeInfo = d["merged_by"] as? [NSObject : AnyObject], mergeUserId = mergeInfo["id"] as? NSNumber {
					self?.prWasMerged(r, byUserId: mergeUserId)
				} else {
					self?.itemWasClosed(r)
				}
			} else if resultCode == 404 || resultCode == 410 { // PR gone for good
				self?.itemWasClosed(r)
			} else { // fetch/server problem
				r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this, we couldn't check, play it safe
				r.apiServer.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private func prWasMerged(r: PullRequest, byUserId: NSNumber) {

		let myUserId = r.apiServer.userId ?? NSNumber(integer: -1)
		DLog("Detected merged PR: %@ by user %@, local user id is: %@, handling policy is %@, coming from section %@",
			r.title,
			byUserId,
			myUserId,
			NSNumber(integer: Settings.mergeHandlingPolicy),
			r.sectionIndex ?? NSNumber(integer: 0))

        if !r.isVisibleOnMenu {
            DLog("Merged PR was hidden, won't announce")
            return
        }

		let mergedByMe = byUserId.isEqualToNumber(myUserId)
		if !(mergedByMe && Settings.dontKeepPrsMergedByMe) {
			DLog("Checking if we want to keep this merged PR")
			if r.shouldKeepForPolicy(Settings.mergeHandlingPolicy) {
				DLog("Will keep merged PR")
				r.keepWithCondition(.Merged, notification: .PrMerged)
				return
			}
		}
		DLog("Will not keep merged PR")
	}

	private func itemWasClosed(i: ListableItem) {
		DLog("Detected closed item: %@, handling policy is %@, coming from section %@",
			i.title,
			NSNumber(integer: Settings.closeHandlingPolicy),
			i.sectionIndex ?? NSNumber(integer: 0))

        if !i.isVisibleOnMenu {
            DLog("Closed item was hidden, won't announce")
            return
        }

		if i.shouldKeepForPolicy(Settings.closeHandlingPolicy) {
			DLog("Will keep closed item")
			i.keepWithCondition(.Closed, notification: i is Issue ? .IssueClosed : .PrClosed)
		} else {
			DLog("Will not keep closed item")
		}
	}

	private func getRateLimitFromServer(apiServer: ApiServer, callback: (Int64, Int64, Int64)->Void)
	{
		api("/rate_limit", fromServer: apiServer, ignoreLastSync: true) { code, headers, data, error, shouldRetry in

			if error == nil {
				let allHeaders = headers!
				let requestsRemaining = (allHeaders["X-RateLimit-Remaining"] as! NSString).longLongValue
				let requestLimit = (allHeaders["X-RateLimit-Limit"] as! NSString).longLongValue
				let epochSeconds = (allHeaders["X-RateLimit-Reset"] as! NSString).longLongValue
				callback(requestsRemaining, requestLimit, epochSeconds)
			} else {
				if code == 404 && data != nil && !((data as? [NSObject : AnyObject])?["message"] as? String == "Not Found") {
					callback(10000, 10000, 0)
				} else {
					callback(-1, -1, -1)
				}
			}
		}
	}

	func updateLimitsFromServer() {
		let allApiServers = ApiServer.allApiServersInMoc(mainObjectContext)
		let total = allApiServers.count
		var count = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getRateLimitFromServer(apiServer) { remaining, limit, reset in
					apiServer.requestsRemaining = NSNumber(longLong: remaining)
					apiServer.requestsLimit = NSNumber(longLong: limit)
					count += 1
					if count==total {
						NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: apiServer, userInfo: nil)
					}
				}
			}
		}
	}

	private func shouldScanForStatusesInMoc(moc: NSManagedObjectContext) -> Bool {
		if Settings.showStatusItems {
			return true
		} else {
			refreshesSinceLastStatusCheck.removeAll()
			for s in DataItem.allItemsOfType("PRStatus", inMoc: moc) {
				s.postSyncAction = PostSyncAction.Delete.rawValue
			}
			return false
		}
	}

	private func shouldScanForLabelsInMoc(moc: NSManagedObjectContext) -> Bool {
		if Settings.showLabels {
			return true
		} else {
			refreshesSinceLastLabelsCheck.removeAll()
			for l in DataItem.allItemsOfType("PRLabel", inMoc: moc) {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}
			return false
		}
	}

	private func syncWatchedReposFromServer(apiServer: ApiServer, callback: Completion) {

		if !apiServer.syncIsGood {
			callback()
			return
		}

		getPagedDataInPath("/user/subscriptions", fromServer: apiServer, startingFromPage: 1,
			perPageCallback: { data, lastPage in
				Repo.syncReposFromInfo(data, apiServer: apiServer)
				return false

			}, finalCallback: { success, resultCode in
				if !success {
					apiServer.lastSyncSucceeded = false
				}
				callback()
		})
	}

	private func syncUserDetailsInMoc(moc: NSManagedObjectContext, callback: Completion) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		let operationCount = allApiServers.count
		if operationCount==0 {
			callback()
			return
		}

		var completionCount = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getDataInPath("/user", fromServer:apiServer) { data, lastPage, resultCode in

					if let d = data as? [NSObject : AnyObject] {
						apiServer.userName = d["login"] as? String
						apiServer.userId = d["id"] as? NSNumber
					} else {
						apiServer.lastSyncSucceeded = false
					}
					completionCount += 1
					if completionCount==operationCount { callback() }
				}
			} else {
				completionCount += 1
				if completionCount==operationCount { callback() }
			}
		}

	}

	func clearAllBadLinks() {
		badLinks.removeAll(keepCapacity: false)
	}

	func testApiToServer(apiServer: ApiServer, callback: (NSError?) -> ()) {
		clearAllBadLinks()
		api("/user", fromServer: apiServer, ignoreLastSync: true) { [weak self] code, headers, data, error, shouldRetry in

			if let d = data as? [NSObject : AnyObject], userName = d["login"] as? String, userId = d["id"] as? NSNumber where error == nil {
				if userName.isEmpty || userId.longLongValue <= 0 {
					let localError = self?.apiError("Could not read a valid user record from this endpoint")
					callback(localError)
				} else {
					callback(error)
				}
			} else {
				callback(error)
			}
		}
	}

	private func apiError(message: String) -> NSError {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	//////////////////////////////////////////////////////////// low level

	private func getPagedDataInPath(
		path: String,
		fromServer: ApiServer,
		startingFromPage: Int,
		perPageCallback: (data: [[NSObject: AnyObject]]?, lastPage: Bool) -> Bool,
		finalCallback: (success: Bool, resultCode: Int) -> Void) {

		if path.isEmpty {
			// handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
			atNextEvent {
				finalCallback(success: true, resultCode: -1)
				return
			}
			return
		}

		let p = startingFromPage > 1 ? "\(path)?page=\(startingFromPage)" : path
		getDataInPath(p, fromServer: fromServer) {
			[weak self] data, lastPage, resultCode in

			if let d = data as? [[NSObject: AnyObject]] {
				var isLastPage = lastPage
				if perPageCallback(data: d, lastPage: lastPage) { isLastPage = true }
				if isLastPage {
					finalCallback(success: true, resultCode: resultCode)
				} else {
					self?.getPagedDataInPath(path, fromServer: fromServer, startingFromPage: startingFromPage+1, perPageCallback: perPageCallback, finalCallback: finalCallback)
				}
			} else {
				finalCallback(success: false, resultCode: resultCode)
			}
		}
	}

	private func getDataInPath(
		path: String,
		fromServer: ApiServer,
		callback:(data: AnyObject?, lastPage: Bool, resultCode: Int) -> Void) {

		attemptToGetDataInPath(path, fromServer: fromServer, callback: callback, attemptCount: 0)
	}

	private func attemptToGetDataInPath(
		path: String,
		fromServer: ApiServer,
		callback:(data: AnyObject?, lastPage: Bool, resultCode: Int) -> Void,
		attemptCount: Int) {

		api(path, fromServer: fromServer, ignoreLastSync: false) { [weak self] c, headers, data, error, shouldRetry in

			let code = c ?? 0

			if error == nil {
				var lastPage = true
				if let allHeaders = headers {

					if let v = allHeaders["X-RateLimit-Remaining"] as? String {
						fromServer.requestsRemaining = NSNumber(longLong: Int64(v) ?? 0)
					} else {
						fromServer.requestsRemaining = 10000
					}

					if let v = allHeaders["X-RateLimit-Limit"] as? String {
						fromServer.requestsLimit = NSNumber(longLong: Int64(v) ?? 0)
					} else {
						fromServer.requestsLimit = 10000
					}

					if let v = allHeaders["X-RateLimit-Reset"] as? String {
						fromServer.resetDate = NSDate(timeIntervalSince1970: Double(v) ?? 0)
					} else {
						fromServer.resetDate = nil
					}

					if let linkHeader = allHeaders["Link"] as? String {
						lastPage = linkHeader.rangeOfString("rel=\"next\"") == nil
					}

					NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: fromServer, userInfo: nil)
				}
				callback(data: data, lastPage: lastPage, resultCode: code)
			} else {
				if shouldRetry && attemptCount < 2 { // timeout, truncation, connection issue, etc
					let nextAttemptCount = attemptCount+1
					DLog("(%@) Will retry failed API call to %@ (attempt #%d)", S(fromServer.label), path, nextAttemptCount)
					delay(2.0) {
						self?.attemptToGetDataInPath(path, fromServer: fromServer, callback: callback, attemptCount: nextAttemptCount)
					}
				} else {
					if shouldRetry {
						DLog("(%@) Giving up on failed API call to %@", S(fromServer.label), path)
					}
					callback(data: nil, lastPage: false, resultCode: code)
				}
			}
		}
	}

	typealias ApiCompletion = (code: Int?, headers: [NSObject : AnyObject]?, data: AnyObject?, error: NSError?, shouldRetry: Bool) -> Void

	private func api(
		path:String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		completion: ApiCompletion) {

		let apiServerLabel: String
		if fromServer.syncIsGood || ignoreLastSync {
			apiServerLabel = S(fromServer.label)
		} else {
			atNextEvent(self) { S in
				let e = S.apiError("Sync has failed, skipping this call")
				completion(code: nil, headers: nil, data: nil, error: e, shouldRetry: false)
			}
			return
		}

		let expandedPath = path.characters.startsWith("/".characters) ? S(fromServer.apiPath).stringByAppendingPathComponent(path) : path
		let url = NSURL(string: expandedPath)!

		let r = NSMutableURLRequest(URL: url, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: 60.0)
		r.setValue("application/vnd.github.v3+json", forHTTPHeaderField:"Accept")
		if let a = fromServer.authToken {
			r.setValue("token \(a)", forHTTPHeaderField: "Authorization")
		}

		////////////////////////// preempt with error backoff algorithm
		let existingBackOff = badLinks[expandedPath]
		if let eb = existingBackOff {
			if NSDate().timeIntervalSince1970 < eb.nextAttemptAt.timeIntervalSince1970 {
				// report failure and return
				DLog("(%@) Preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, expandedPath, eb.nextAttemptAt)
				atNextEvent(self) { S in
					let e = S.apiError("Preempted fetch because of throttling")
					completion(code: nil, headers: nil, data: nil, error: e, shouldRetry: false)
				}
				return
			}
			else {
				badLinks.removeValueForKey(expandedPath)
			}
		}

		/////////////////////// 60 second dumb-caching
		let cacheKey = "\(fromServer.objectID.URIRepresentation().absoluteString) \(expandedPath)"
		let previousCacheEntry = CacheEntry.entryForKey(cacheKey)?.cacheUnit() // move data out of thread-specific context
		if let p = previousCacheEntry {
			if p.lastFetched.timeIntervalSince1970 > NSDate(timeIntervalSinceNow: -60).timeIntervalSince1970, let parsedData = p.parsedData() {
				DLog("(%@) GET %@ - CACHED", apiServerLabel, expandedPath)
				handleResponse(p.data,
				               parsedData: parsedData,
				               serverLabel: apiServerLabel,
				               urlPath: expandedPath,
				               code: p.code,
				               error: nil,
				               shouldRetry: false,
				               badServerResponse: false,
				               existingBackOff: nil,
				               headers: p.actualHeaders(),
				               completion: completion)
				return
			}
			r.setValue(p.etag, forHTTPHeaderField: "If-None-Match")
		}

		#if os(iOS)
			networkIndicationStart()
		#endif

		urlSession.dataTaskWithRequest(r) { [weak self] data, res, e in

			let response = res as? NSHTTPURLResponse
			var parsedData: AnyObject?
			var error = e
			var badServerResponse = false
			var code = response?.statusCode ?? 0
			var shouldRetry = false
			var headers = response?.allHeaderFields

			if code == 304, let p = previousCacheEntry {
				parsedData = p.parsedData()
				code = p.code
				headers = p.actualHeaders()
				atNextEvent {
					CacheEntry.markKeyAsFetched(cacheKey)
				}
				DLog("(%@) GET %@ - NO CHANGE (304): %d", apiServerLabel, expandedPath, code)
			} else if code > 299 {
				error = self?.apiError("Server responded with \(code)")
				badServerResponse = true
			} else if code == 0 {
				shouldRetry = error?.code == -1001 // timeout
				error = self?.apiError("Server did not repond")
			} else if (response?.expectedContentLength ?? 0) > Int64(data?.length ?? 0) {
				shouldRetry = true // truncation
				error = self?.apiError("Server data was truncated")
			} else {
				DLog("(%@) GET %@ - RESULT: %d", apiServerLabel, expandedPath, code)
				if let d = data {
					parsedData = try? NSJSONSerialization.JSONObjectWithData(d, options: NSJSONReadingOptions())
					if let h = headers, e = h["Etag"] as? String {
						atNextEvent {
							CacheEntry.setEntry(cacheKey, code: code, etag: e, data: d, headers: h)
						}
					}
				}
			}

			atNextEvent(self) { S in
				S.handleResponse(data,
				                 parsedData: parsedData,
				                 serverLabel: apiServerLabel,
				                 urlPath: expandedPath,
				                 code: code,
				                 error: error,
				                 shouldRetry: shouldRetry,
				                 badServerResponse: badServerResponse,
				                 existingBackOff: existingBackOff,
				                 headers: headers,
				                 completion: completion)

				#if os(iOS)
					S.networkIndicationEnd()
				#endif
			}
		}.resume()
	}

	private func handleResponse(data: NSData?,
	                            parsedData: AnyObject?,
	                            serverLabel: String,
	                            urlPath: String,
	                            code: Int,
	                            error: NSError?,
	                            shouldRetry: Bool,
	                            badServerResponse: Bool,
	                            existingBackOff: UrlBackOffEntry?,
	                            headers: [NSObject : AnyObject]?,
	                            completion: ApiCompletion) {
		if error != nil {
			if badServerResponse {
				if var backoff = existingBackOff {
					DLog("(%@) Extending backoff for already throttled URL %@ by %f seconds", serverLabel, urlPath, BACKOFF_STEP)
					if backoff.duration < 3600.0 {
						backoff.duration += BACKOFF_STEP
					}
					backoff.nextAttemptAt = NSDate(timeInterval: existingBackOff!.duration, sinceDate:NSDate())
					badLinks[urlPath] = backoff
				} else {
					DLog("(%@) Placing URL %@ on the throttled list", serverLabel, urlPath)
					badLinks[urlPath] = UrlBackOffEntry(
						nextAttemptAt: NSDate().dateByAddingTimeInterval(BACKOFF_STEP),
						duration: BACKOFF_STEP)
				}
			}
			DLog("(%@) GET %@ - FAILED: (code %d) %@", serverLabel, urlPath, code, error!.localizedDescription)
		}

		if Settings.dumpAPIResponsesInConsole, let d = data {
			DLog("API data from %@: %@", urlPath, NSString(data: d, encoding: NSUTF8StringEncoding))
		}

		completion(code: code, headers: headers, data: parsedData, error: error, shouldRetry: shouldRetry)
	}

	#if os(iOS)

	private var networkBGTask = UIBackgroundTaskInvalid
	private var networkBGEndPopTimer: PopTimer?
	private var networkIndicationCount: Int = 0

	func networkIndicationStart() {
		networkIndicationCount += 1
		if networkIndicationCount == 1 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = true
			networkBGTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.imageload") { [weak self] in
				self?.endNetworkBGTask()
			}
			if networkBGEndPopTimer == nil {
				networkBGEndPopTimer = PopTimer(timeInterval: 1.0) { [weak self] in
					self?.endNetworkBGTask()
				}
			}
		}
	}
	
	func networkIndicationEnd() {
		networkIndicationCount -= 1
		if networkIndicationCount == 0 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = false
			networkBGEndPopTimer?.push()
		}
	}

	private func endNetworkBGTask() {
		if networkBGTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(networkBGTask)
			networkBGTask = UIBackgroundTaskInvalid
		}
	}
	
	#endif
}
