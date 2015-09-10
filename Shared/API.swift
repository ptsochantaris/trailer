
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

	private let mediumFormatter: NSDateFormatter
	private let cacheDirectory: String
	private let urlSession: NSURLSession
	private var badLinks = [String:UrlBackOffEntry]()
	private let reachability = Reachability.reachabilityForInternetConnection()

	init() {

		mediumFormatter = NSDateFormatter()
		mediumFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
		mediumFormatter.timeStyle = NSDateFormatterStyle.MediumStyle

		reachability.startNotifier()
		let n = reachability.currentReachabilityStatus()
		DLog("Network is %@", n == NetworkStatus.NotReachable ? "down" : "up")
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
		config.timeoutIntervalForResource = NETWORK_TIMEOUT
		config.timeoutIntervalForRequest = NETWORK_TIMEOUT
		config.HTTPAdditionalHeaders = ["User-Agent" : userAgent]
		urlSession = NSURLSession(configuration: config)

		if fileManager.fileExistsAtPath(cacheDirectory) {
			expireOldImageCacheEntries()
		} else {
			do { try fileManager.createDirectoryAtPath(cacheDirectory, withIntermediateDirectories: true, attributes: nil) } catch _ {}
		}

		NSNotificationCenter.defaultCenter().addObserverForName(kReachabilityChangedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { [weak self] n in
			self?.checkNetworkAvailability()
			if self?.currentNetworkStatus != NetworkStatus.NotReachable {
				app.startRefreshIfItIsDue()
			}
		}
	}

	func checkNetworkAvailability() {
		let newStatus = reachability.currentReachabilityStatus()
		if newStatus != currentNetworkStatus {
			currentNetworkStatus = newStatus
			if newStatus == NetworkStatus.NotReachable {
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
		return currentNetworkStatus == NetworkStatus.NotReachable
	}

	/////////////////////////////////////////////////////// Utilities

	func lastUpdateDescription() -> String {
		if app.isRefreshing {
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
	private func getImage(url: NSURL, completion:(response: NSHTTPURLResponse?, data: NSData?, error: NSError?) -> Void) {

		let task = urlSession.dataTaskWithURL(url) { [weak self] data, res, e in

			let response = res as? NSHTTPURLResponse
			var error = e
			if error == nil && (response == nil || response?.statusCode > 399) {
				let code = response?.statusCode ?? -1
				error = self!.apiError("Server responded with \(code)")
			}
			completion(response: response, data: data, error: error)
			#if os(iOS)
				dispatch_sync(dispatch_get_main_queue()) { [weak self] in
					self!.networkIndicationEnd()
				}
			#endif
		}

		#if os(iOS)
			task.priority = NSURLSessionTaskPriorityHigh
			atNextEvent { [weak self] in
				self!.networkIndicationStart()
			}
		#endif

		task.resume()
	}

	func cachePathForAvatar(path: String) -> (String, String) {
		#if os(iOS)
			let absolutePath = path + (path.characters.contains("?") ? "&" : "?") + "s=\(40.0*GLOBAL_SCREEN_SCALE)"
			#else
			let absolutePath = path + (path.characters.contains("?") ? "&" : "?") + "s=88"
		#endif

		let imageKey = absolutePath + " " + currentAppVersion()
		let cachePath = cacheDirectory.stringByAppendingPathComponent("imgcache-" + md5hash(imageKey))
		return (absolutePath, cachePath)
	}

	func haveCachedAvatar(path: String, tryLoadAndCallback: (IMAGE_CLASS?, String) -> Void) -> Bool {

		let (absolutePath, cachePath) = cachePathForAvatar(path)

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
				tryLoadAndCallback(r, cachePath)
				return true
			} else {
				try! fileManager.removeItemAtPath(cachePath)
			}
		}

		getImage(NSURL(string: absolutePath)!) { response, data, error in

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
			dispatch_sync(dispatch_get_main_queue()) { tryLoadAndCallback(result, cachePath) }
        }
		return false
	}

	////////////////////////////////////// API interface

	func syncItemsForActiveReposAndCallback(callback: Completion) {
		let syncContext = DataManager.tempContext()

		let shouldRefreshReposToo = app.lastRepoCheck.isEqualToDate(never())
			|| (NSDate().timeIntervalSinceDate(app.lastRepoCheck) > NSTimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| (Repo.countVisibleReposInMoc(syncContext)==0)

		if shouldRefreshReposToo {
			fetchRepositoriesToMoc(syncContext) { [weak self] in
				self!.syncToMoc(syncContext, callback: callback)
			}
		} else {
			ApiServer.resetSyncSuccessInMoc(syncContext)
			ensureApiServersHaveUserIdsInMoc(syncContext) { [weak self] in
				self!.syncToMoc(syncContext, callback: callback)
			}
		}
	}

	private func syncToMoc(moc: NSManagedObjectContext, callback: Completion) {
		markDirtyReposInMoc(moc) { [weak self] in

			let repos = Repo.syncableReposInMoc(moc)

			var completionCount = 0
			let totalOperations = 2
			let completionCallback: Completion = { [weak self] in
				completionCount++
				if completionCount == totalOperations {
					for r in repos { r.dirty = false }
					self!.completeSyncInMoc(moc)
					callback()
				}
			}

			self!.fetchIssuesForRepos(repos, toMoc: moc) { [weak self] in
				self!.fetchCommentsForCurrentIssuesToMoc(moc) { [weak self] in
					self!.checkIssueClosuresInMoc(moc)
					completionCallback()
				}
			}

			self!.fetchPullRequestsForRepos(repos, toMoc: moc) {
				self!.updatePullRequestsInMoc(moc) {
					completionCallback()
				}
			}
		}
	}

	private func completeSyncInMoc(moc: NSManagedObjectContext) {

		// discard any changes related to any failed API server
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if !apiServer.syncIsGood {
				apiServer.rollBackAllUpdatesInMoc(moc)
				apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
			}
		}

		DataItem.nukeDeletedItemsInMoc(moc)

		for r in DataItem.itemsOfType("PullRequest", surviving: true, inMoc: moc) as! [PullRequest] {
			r.postProcess()
		}

		for i in DataItem.itemsOfType("Issue", surviving: true, inMoc: moc) as! [Issue] {
			i.postProcess()
		}

		do {
			try moc.save()
		} catch {
			DLog("Comitting sync failed: %@", (error as NSError).localizedDescription)
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
		if willScanForStatuses { totalOperations++ }
		if willScanForLabels { totalOperations++ }

		var completionCount = 0
		let completionCallback: Completion = {
			completionCount++
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
			completionCount++
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
				markDirtyRepoIds(repoIdsToMarkDirty, usingReceivedEventsFromServer: apiServer, callback:completionCallback)
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
			parameters: nil,
			extraHeaders: nil,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					Team.teamWithInfo(d, fromApiServer: apiServer)
				}
				return false
			}, finalCallback: { success, resultCode, etag in
				if !success {
					apiServer.lastSyncSucceeded = false
				}
				callback()
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingUserEventsFromServer: ApiServer, callback: Completion) {

		if !usingUserEventsFromServer.syncIsGood {
			callback()
			return
		}

		var extraHeaders: [String : String]?
		if let e = usingUserEventsFromServer.latestUserEventEtag {
			extraHeaders = ["If-None-Match": e]
		}

		var latestDate = usingUserEventsFromServer.latestUserEventDateProcessed
		if latestDate == nil {
			latestDate = never()
			usingUserEventsFromServer.latestUserEventDateProcessed = latestDate
		}

		let userName = usingUserEventsFromServer.userName ?? "NoApiUserName"
		getPagedDataInPath("/users/\(userName)/events",
			fromServer: usingUserEventsFromServer,
			startingFromPage: 1,
			parameters: nil,
			extraHeaders: extraHeaders,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = syncDateFormatter.dateFromString(N(d, "created_at") as! String)!
					if latestDate!.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("New event at %@ from Repo ID %@", eventDate, repoId)
							repoIdsToMarkDirty.addObject(repoId)
						}
						if latestDate!.compare(eventDate) == NSComparisonResult.OrderedAscending {
							usingUserEventsFromServer.latestUserEventDateProcessed = eventDate
							if latestDate!.isEqualToDate(never()) {
								DLog("First sync, all repos are dirty so we don't need to read further, we have the latest user event date: %@", eventDate)
								return true
							}
						}
					} else {
						DLog("The rest of these user events are processed, stopping event parsing")
						return true
					}
				}
				return false
			}, finalCallback: { success, resultCode, etag in
				usingUserEventsFromServer.latestUserEventEtag = etag
				if !success {
					usingUserEventsFromServer.lastSyncSucceeded = false
				}
				callback()
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingReceivedEventsFromServer: ApiServer, callback: Completion) {

		if !usingReceivedEventsFromServer.syncIsGood {
			callback()
			return
		}

		var extraHeaders: [String : String]?
		if let e = usingReceivedEventsFromServer.latestReceivedEventEtag {
			extraHeaders = ["If-None-Match": e]
		}

		var latestDate = usingReceivedEventsFromServer.latestReceivedEventDateProcessed
		if latestDate == nil {
			latestDate = never()
			usingReceivedEventsFromServer.latestReceivedEventDateProcessed = latestDate
		}

		let userName = usingReceivedEventsFromServer.userName ?? "NoApiUserName"
		getPagedDataInPath("/users/\(userName)/received_events",
			fromServer: usingReceivedEventsFromServer,
			startingFromPage: 1,
			parameters: nil,
			extraHeaders: extraHeaders,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = syncDateFormatter.dateFromString(N(d, "created_at") as! String)!
					if latestDate!.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("New event at %@ from Repo ID %@", eventDate, repoId)
							repoIdsToMarkDirty.addObject(repoId)
						}
						if latestDate!.compare(eventDate) == NSComparisonResult.OrderedAscending {
							usingReceivedEventsFromServer.latestReceivedEventDateProcessed = eventDate
							if latestDate!.isEqualToDate(never()) {
								DLog("First sync, all repos are dirty so we don't need to read further, we have the latest received event date: %@", latestDate)
								return true
							}
						}
					} else {
						DLog("The rest of these received events are processed, stopping event parsing")
						return true
					}
				}
				return false
			}, finalCallback: { success, resultCode, etag in
				usingReceivedEventsFromServer.latestReceivedEventEtag = etag
				if !success {
					usingReceivedEventsFromServer.lastSyncSucceeded = false
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
				completionCount++
				if completionCount == totalOperations {
					for r in DataItem.newItemsOfType("Repo", inMoc: moc) as! [Repo] {
						r.displayPolicyForPrs = Settings.displayPolicyForNewPrs
						r.displayPolicyForIssues = Settings.displayPolicyForNewIssues
						if r.shouldSync() {
							app.postNotificationOfType(PRNotificationType.NewRepoAnnouncement, forItem:r)
						}
					}
					app.lastRepoCheck = NSDate()
					callback()
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo {
					self!.syncWatchedReposFromServer(apiServer, callback: completionCallback)
					self!.fetchUserTeamsFromApiServer(apiServer, callback: completionCallback)
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
				if (p.condition?.integerValue ?? 0) == PullRequestCondition.Open.rawValue {
					p.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForPrs?.integerValue != RepoDisplayPolicy.Hide.rawValue {
				let repoFullName = r.fullName ?? "NoRepoFullName"
				getPagedDataInPath("/repos/\(repoFullName)/pulls", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							PullRequest.pullRequestWithInfo(info, inRepo:r)
						}
						return false
					}, finalCallback: { [weak self] success, resultCode, etag in
						if !success {
							self!.handleRepoSyncFailure(r, withResultCode: resultCode)
						}
						completionCount++
						if completionCount==total {
							callback()
						}
				})
			} else {
				completionCount++
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
				if (i.condition?.integerValue ?? 0) == PullRequestCondition.Open.rawValue {
					i.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForIssues?.integerValue != RepoDisplayPolicy.Hide.rawValue {
				let repoFullName = r.fullName ?? "NoRepoFullName"
				getPagedDataInPath("/repos/\(repoFullName)/issues", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							if N(info, "pull_request") == nil { // don't sync issues which are pull requests, they are already synced
								Issue.issueWithInfo(info, inRepo:r)
							}
						}
						return false
					}, finalCallback: { [weak self] success, resultCode, etag in
						if !success {
							self!.handleRepoSyncFailure(r, withResultCode: resultCode)
						}
						completionCount++
						if completionCount==total {
							callback()
						}
				})
			} else {
				completionCount++
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
			completionCount++
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

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							let c = PRComment.commentWithInfo(info, fromServer: apiServer)
							c.pullRequest = p

							// check if we're assigned to a just created pull request, in which case we want to "fast forward" its latest comment dates to our own if we're newer
							if (p.postSyncAction?.integerValue ?? 0) == PostSyncAction.NoteNew.rawValue {
								let commentCreation = c.createdAt!
								if p.latestReadCommentDate == nil || p.latestReadCommentDate!.compare(commentCreation) == NSComparisonResult.OrderedAscending {
									p.latestReadCommentDate = commentCreation
								}
							}
						}
						return false
					}, finalCallback: { success, resultCode, etag in
						completionCount++
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				completionCount++
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

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							let c = PRComment.commentWithInfo(info, fromServer: apiServer)
							c.issue = i

							// check if we're assigned to a just created pull request, in which case we want to "fast forward" its latest comment dates to our own if we're newer
							if (i.postSyncAction?.integerValue ?? 0) == PostSyncAction.NoteNew.rawValue {
								let commentCreation = c.createdAt!
								if i.latestReadCommentDate == nil || i.latestReadCommentDate!.compare(commentCreation) == NSComparisonResult.OrderedAscending {
									i.latestReadCommentDate = commentCreation
								}
							}
						}
						return false
					}, finalCallback: { success, resultCode, etag in
						completionCount++
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				completionCount++
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchLabelsForForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.visibleAndActivePullRequestsInMoc(moc).filter { [weak self] pr in
			if !pr.apiServer.syncIsGood {
				return false
			}
			if pr.condition?.integerValue != PullRequestCondition.Open.rawValue {
				DLog("Won't check labels for closed/merged PR: %@", pr.title)
				return false
			}
			let oid = pr.objectID
			let refreshes = self!.refreshesSinceLastLabelsCheck[oid]
			if refreshes == nil || refreshes! >= Settings.labelRefreshInterval {
				DLog("Will check labels for PR: '%@'", pr.title)
				return true
			} else {
				DLog("No need to get labels for PR: '%@' (%d refreshes since last check)", pr.title, refreshes)
				self!.refreshesSinceLastLabelsCheck[oid] = (refreshes ?? 0)+1
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

			if let link = p.labelsLink() {

				getPagedDataInPath(link, fromServer: p.apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							PRLabel.labelWithInfo(info, withParent: p)
						}
						return false
					}, finalCallback: { [weak self] success, resultCode, etag in
						completionCount++
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
							self!.refreshesSinceLastLabelsCheck[p.objectID] = 1
						}
						if completionCount == total {
							callback()
						}
				})
			} else {
				// no labels link, so presumably no labels
				refreshesSinceLastLabelsCheck[p.objectID] = 1
				completionCount++
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchStatusesForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.visibleAndActivePullRequestsInMoc(moc).filter { [weak self] pr in
			if !pr.apiServer.syncIsGood {
				return false
			}
			let oid = pr.objectID
			let refreshes = self!.refreshesSinceLastStatusCheck[oid]
			if refreshes == nil || refreshes! >= Settings.statusItemRefreshInterval {
				DLog("Will check statuses for PR: '%@'", pr.title)
				return true
			} else {
				DLog("No need to get statuses for PR: '%@' (%d refreshes since last check)", pr.title, refreshes)
				self!.refreshesSinceLastStatusCheck[oid] = (refreshes ?? 0)+1
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
				getPagedDataInPath(statusLink, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							let s = PRStatus.statusWithInfo(info, fromServer: apiServer)
							s.pullRequest = p
						}
						return false
					}, finalCallback: { [weak self] success, resultCode, etag in
						completionCount++
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
							self!.refreshesSinceLastStatusCheck[p.objectID] = 1
						}
						if completionCount==total {
							callback()
						}
				})
			} else {
				refreshesSinceLastStatusCheck[p.objectID] = 1
				completionCount++
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func checkPrClosuresInMoc(moc: NSManagedObjectContext, callback: Completion) {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, PullRequestCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = try! moc.executeFetchRequest(f) as! [PullRequest]

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return parent.shouldSync() && ((parent.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue) && r.apiServer.syncIsGood
		}

		let totalOperations = prsToCheck.count
		if totalOperations==0 {
			callback()
			return
		}

		var completionCount = 0
		let completionCallback: Completion = {
			completionCount++
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
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, PullRequestCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false

		for i in try! moc.executeFetchRequest(f) as! [Issue] {
			let r = i.repo
			if r.shouldSync() && ((r.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue) && r.apiServer.syncIsGood {
				issueWasClosed(i)
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
			completionCount++
			if completionCount == totalOperations {
				callback()
			}
		}

		for p in prs {
			let apiServer = p.apiServer
			if let issueLink = p.issueUrl {
				getDataInPath(issueLink, fromServer: apiServer, parameters: nil, extraHeaders: nil) { data, lastPage, resultCode, etag in
						if let assigneeInfo = N(data, "assignee") as? [NSObject : AnyObject] {
							let assignee = N(assigneeInfo, "login") as? String ?? "NoAssignedUserName"
							let assigned = (assignee == (apiServer.userName ?? "NoApiUser"))
							p.isNewAssignment = (assigned && !p.createdByMe() && !(p.assignedToMe?.boolValue ?? false))
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

		let repoFullName = r.repo.fullName ?? "NoRepoFullName"
		let repoNumber = r.number?.stringValue ?? "NoRepoNumber"
		get("/repos/\(repoFullName)/pulls/\(repoNumber)", fromServer: r.apiServer, ignoreLastSync: false, parameters: nil, extraHeaders: nil) { [weak self] response, data, error in

			if error == nil {
				if let mergeInfo = N(data, "merged_by") as? [NSObject: AnyObject], mergeUserId = N(mergeInfo, "id") as? NSNumber {
					self!.prWasMerged(r, byUserId: mergeUserId)
				} else {
					self!.prWasClosed(r)
				}
			} else {
				if let resultCode = response?.statusCode where resultCode == 404 || resultCode==410 { // PR gone for good
					self!.prWasClosed(r)
				} else { // fetch problem
					r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this, we couldn't check, play it safe
					r.apiServer.lastSyncSucceeded = false
				}
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

        if !r.isVisibleOnMenu() {
            DLog("Merged PR was hidden, won't announce")
            return
        }

		let mergedByMe = byUserId.isEqualToNumber(myUserId)
		if !(mergedByMe && Settings.dontKeepPrsMergedByMe) {
			DLog("Checking if we want to keep this merged PR")
			if r.shouldKeepForPolicy(Settings.mergeHandlingPolicy) {
				DLog("Will keep merged PR")
				r.postSyncAction = PostSyncAction.DoNothing.rawValue
				r.condition = PullRequestCondition.Merged.rawValue
				app.postNotificationOfType(PRNotificationType.PrMerged, forItem: r)
				return
			}
		}
		DLog("Will not keep merged PR")
	}

	private func prWasClosed(r: PullRequest) {
		DLog("Detected closed PR: %@, handling policy is %@, coming from section %@",
			r.title,
			NSNumber(integer: Settings.closeHandlingPolicy),
			r.sectionIndex ?? NSNumber(integer: 0))

        if !r.isVisibleOnMenu() {
            DLog("Closed PR was hidden, won't announce")
            return
        }

		if r.shouldKeepForPolicy(Settings.closeHandlingPolicy) {
			DLog("Will keep closed PR")
			r.postSyncAction = PostSyncAction.DoNothing.rawValue
			r.condition = PullRequestCondition.Closed.rawValue
			app.postNotificationOfType(PRNotificationType.PrClosed, forItem:r)
		} else {
			DLog("Will not keep closed PR")
		}
	}

	private func issueWasClosed(i: Issue) {
		DLog("Detected closed issue: %@, handling policy is %@, coming from section %@",
			i.title,
			NSNumber(integer: Settings.closeHandlingPolicy),
			i.sectionIndex ?? NSNumber(integer: 0))

        if !i.isVisibleOnMenu() {
            DLog("Closed issue was hidden, won't announce")
            return
        }

		if i.shouldKeepForPolicy(Settings.closeHandlingPolicy) {
			DLog("Will keep closed issue")
			i.postSyncAction = PostSyncAction.DoNothing.rawValue
			i.condition = PullRequestCondition.Closed.rawValue
			app.postNotificationOfType(PRNotificationType.IssueClosed, forItem:i)
		} else {
			DLog("Will not keep closed issue")
		}
	}

	private func getRateLimitFromServer(apiServer: ApiServer, callback: (Int64, Int64, Int64)->Void)
	{
		get("/rate_limit", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil) { response, data, error in

			if error == nil {
				let allHeaders = response!.allHeaderFields
				let requestsRemaining = (allHeaders["X-RateLimit-Remaining"] as! NSString).longLongValue
				let requestLimit = (allHeaders["X-RateLimit-Limit"] as! NSString).longLongValue
				let epochSeconds = (allHeaders["X-RateLimit-Reset"] as! NSString).longLongValue
				callback(requestsRemaining, requestLimit, epochSeconds)
			} else {
				if response?.statusCode == 404 && data != nil && !(N(data, "message") as? String == "Not Found") {
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
					count++
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

		getPagedDataInPath("/user/subscriptions", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
			perPageCallback: { data, lastPage in

				if let d = data {
					for info in d {
						if (N(info, "private") as? NSNumber)?.boolValue ?? false {
							if let permissions = N(info, "permissions") as? [NSObject: AnyObject] {

								let pull = (N(permissions, "pull") as? NSNumber)?.boolValue ?? false
								let push = (N(permissions, "push") as? NSNumber)?.boolValue ?? false
								let admin = (N(permissions, "admin") as? NSNumber)?.boolValue ?? false

								if	pull || push || admin {
									Repo.repoWithInfo(info, fromServer: apiServer)
								} else {
									DLog("Watched private repository '%@' seems to be inaccessible, skipping", N(info, "full_name") as? String)
								}
							}
						} else {
							Repo.repoWithInfo(info, fromServer: apiServer)
						}
					}
				}
				return false

			}, finalCallback: { success, resultCode, etag in
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
				getDataInPath("/user", fromServer:apiServer, parameters: nil, extraHeaders:nil) { data, lastPage, resultCode, etag in

					if let d = data as? [NSObject : AnyObject] {
						apiServer.userName = N(d, "login") as? String
						apiServer.userId = N(d, "id") as? NSNumber
					} else {
						apiServer.lastSyncSucceeded = false
					}
					completionCount++
					if completionCount==operationCount { callback() }
				}
			} else {
				completionCount++
				if completionCount==operationCount { callback() }
			}
		}

	}

	func clearAllBadLinks() {
		badLinks.removeAll(keepCapacity: false)
	}

	func testApiToServer(apiServer: ApiServer, callback: (NSError?) -> ()) {
		clearAllBadLinks()
		get("/user", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil) { [weak self] response, data, error in

			if let d = data as? [NSObject : AnyObject], userName = N(d, "login") as? String, userId = N(d, "id") as? NSNumber where error == nil {
				if userName.isEmpty || userId.longLongValue <= 0 {
					let localError = self!.apiError("Could not read a valid user record from this endpoint")
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
		parameters: [String : String]?,
		extraHeaders: [String : String]?,
		perPageCallback: (data: [[NSObject: AnyObject]]?, lastPage: Bool) -> Bool,
		finalCallback: (success: Bool, resultCode: Int, etag: String?) -> Void) {

			if path.isEmpty {
				// handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
				dispatch_async(dispatch_get_main_queue()) {
					finalCallback(success: true, resultCode: -1, etag: nil)
					return
				}
				return
			}

			var mutableParams: [String:String]
			if let p = parameters {
				mutableParams = p
			} else {
				mutableParams = [String:String]()
			}
			mutableParams["page"] = String(startingFromPage)
			mutableParams["per_page"] = "100"

			getDataInPath(path, fromServer: fromServer, parameters: mutableParams, extraHeaders: extraHeaders) {
				[weak self] data, lastPage, resultCode, etag in

				if let d = data as? [[NSObject: AnyObject]] {
					var isLastPage = lastPage
					if perPageCallback(data: d, lastPage: lastPage) { isLastPage = true }
					if isLastPage {
						finalCallback(success: true, resultCode: resultCode, etag: etag)
					} else {
						self!.getPagedDataInPath(path, fromServer: fromServer, startingFromPage: startingFromPage+1, parameters: parameters, extraHeaders: extraHeaders, perPageCallback: perPageCallback, finalCallback: finalCallback)
					}
				} else {
					finalCallback(success: resultCode==304, resultCode: resultCode, etag: etag)
				}
			}
	}

	private func getDataInPath(
		path: String,
		fromServer: ApiServer,
		parameters: [String : String]?,
		extraHeaders: [String : String]?,
		callback:(data: AnyObject?, lastPage: Bool, resultCode: Int, etag: String?) -> Void) {

			get(path, fromServer: fromServer, ignoreLastSync: false, parameters: parameters, extraHeaders: extraHeaders) { response, data, error in

				let code = response?.statusCode ?? 0

				if error == nil {
					var etag: String? = nil
					if let allHeaders = response?.allHeaderFields {

                        etag = allHeaders["Etag"] as? String

						if let hv = allHeaders["X-RateLimit-Remaining"] as? NSString {
							fromServer.requestsRemaining = NSNumber(longLong: hv.longLongValue)
						} else {
							fromServer.requestsRemaining = 10000
						}

						if let hv = allHeaders["X-RateLimit-Limit"] as? NSString {
							fromServer.requestsLimit = NSNumber(longLong: hv.longLongValue)
						} else {
							fromServer.requestsLimit = 10000
						}

						if let hv = allHeaders["X-RateLimit-Reset"] as? NSString {
							fromServer.resetDate = NSDate(timeIntervalSince1970: hv.doubleValue)
						} else {
							fromServer.resetDate = nil
						}

						NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: fromServer, userInfo: nil)
					}
                    var lastPage = true
                    let allHeaders = response?.allHeaderFields as [NSObject : AnyObject]?
                    if let linkHeader = N(allHeaders, "Link") as? String {
                        lastPage = linkHeader.rangeOfString("rel=\"next\"") == nil
                    }
					callback(data: data, lastPage: lastPage, resultCode: code, etag: etag)
				} else {
					callback(data: nil, lastPage: false, resultCode: code, etag: nil)
				}
			}
	}

	private func get(
		path:String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		parameters: [String : String]?,
		extraHeaders: [String : String]?,
		completion: (response: NSHTTPURLResponse?, data: AnyObject?, error: NSError?) -> Void) {

			let apiServerLabel: String
			if fromServer.syncIsGood || ignoreLastSync {
				apiServerLabel = fromServer.label ?? "(untitled server)"
			} else {
				dispatch_async(dispatch_get_main_queue()) { [weak self] in
					let e = self!.apiError("Sync has failed, skipping this call")
					completion(response: nil, data: nil, error: e)
				}
				return
			}

			#if os(iOS)
				networkIndicationStart()
			#endif

			var expandedPath = path.characters.startsWith("/".characters) ? (fromServer.apiPath ?? "").stringByAppendingPathComponent(path) : path

			if let params = parameters {
				var pairs = [String]()
				for (key, value) in params {
					pairs.append(key + "=" + value)
				}
				expandedPath = expandedPath + "?" + pairs.joinWithSeparator("&")
			}

			let r = NSMutableURLRequest(URL: NSURL(string: expandedPath)!, cachePolicy: NSURLRequestCachePolicy.UseProtocolCachePolicy, timeoutInterval: NETWORK_TIMEOUT)
			if let a = fromServer.authToken {
				r.setValue("token " + a, forHTTPHeaderField: "Authorization")
			}

			if let headers = extraHeaders {
				for (key,value) in headers {
					//DLog("(%@) custom header: %@=%@", apiServerLabel, key, value)
					r.setValue(value, forHTTPHeaderField:key)
				}
			}

			////////////////////////// preempt with error backoff algorithm
			let fullUrlPath = r.URL!.absoluteString
			var existingBackOff = badLinks[fullUrlPath]
			if existingBackOff != nil {
				if NSDate().compare(existingBackOff!.nextAttemptAt) == NSComparisonResult.OrderedAscending {
					// report failure and return
					DLog("(%@) Preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, fullUrlPath, existingBackOff!.nextAttemptAt)
					dispatch_async(dispatch_get_main_queue()) { [weak self] in
						let e = self!.apiError("Preempted fetch because of throttling")
						completion(response: nil, data: nil, error: e)
						#if os(iOS)
							self!.networkIndicationEnd()
						#endif
					}
					return
				}
				else {
					badLinks.removeValueForKey(fullUrlPath)
				}
			}

			urlSession.dataTaskWithRequest(r) { [weak self] data, res, e in

				let response = res as? NSHTTPURLResponse
				var parsedData: AnyObject?
				var error = e
				var badServerResponse = false

				if let code = response?.statusCode {
					if code > 399 {
						error = self!.apiError("Server responded with \(code)")
						badServerResponse = true
					} else {
						DLog("(%@) GET %@ - RESULT: %d", apiServerLabel, fullUrlPath, code)
						if let d = data {
							parsedData = try? NSJSONSerialization.JSONObjectWithData(d, options: NSJSONReadingOptions())
						}
					}
				} else {
					error = self!.apiError("Server did not repond")
				}

				if error != nil {
					if badServerResponse {
						if existingBackOff != nil {
							DLog("(%@) Extending backoff for already throttled URL %@ by %f seconds", apiServerLabel, fullUrlPath, BACKOFF_STEP)
							if existingBackOff!.duration < 3600.0 {
								existingBackOff!.duration += BACKOFF_STEP
							}
							existingBackOff!.nextAttemptAt = NSDate(timeInterval: existingBackOff!.duration, sinceDate:NSDate())
						} else {
							DLog("(%@) Placing URL %@ on the throttled list", apiServerLabel, fullUrlPath)
							existingBackOff = UrlBackOffEntry(
								nextAttemptAt: NSDate(timeInterval: BACKOFF_STEP, sinceDate: NSDate()),
								duration: BACKOFF_STEP)
						}
						self!.badLinks[fullUrlPath] = existingBackOff
					}
					DLog("(%@) GET %@ - FAILED: %@", apiServerLabel, fullUrlPath, error!.localizedDescription)
				}

				dispatch_sync(dispatch_get_main_queue()) { [weak self] in
					if Settings.dumpAPIResponsesInConsole, let d = data {
						DLog("API data from %@: %@", fullUrlPath, NSString(data: d, encoding: NSUTF8StringEncoding))
					}
					completion(response: response, data: parsedData, error: error)
					#if os(iOS)
						self!.networkIndicationEnd()
					#endif
				}
			}.resume()
	}

	#if os(iOS)

	private var networkIndicationCount: Int = 0

	func networkIndicationStart() {
		if ++networkIndicationCount == 1 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = true
		}
	}
	
	func networkIndicationEnd() {
		if --networkIndicationCount == 0 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = false
		}
	}
	
	#endif
}
