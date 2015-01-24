
import CoreData
#if os(iOS)
import UIKit
#endif

struct UrlBackOffEntry {
	var nextAttemptAt: NSDate
	var duration: NSTimeInterval
}

#if DEBUG
	#if os(iOS)
		let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Development"
	#else
		let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-OSX-Development"
	#endif
#else
	#if os(iOS)
		let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Release"
	#else
		let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-OSX-Release"
	#endif
#endif

class API {

	var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
	var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
	var currentNetworkStatus: NetworkStatus

	private let mediumFormatter: NSDateFormatter
	private let syncDateFormatter: NSDateFormatter
	private let cacheDirectory: String
	private let urlSession: NSURLSession
	private var badLinks = [String:UrlBackOffEntry]()
	#if os(iOS)
	private var networkIndicationCount: Int = 0
	#endif

	init() {

		#if os(iOS)
			let cache = NSURLCache(memoryCapacity: 1024*1024*2, diskCapacity: 1024*1024*32, diskPath: nil)
			#else
			let cache = NSURLCache(memoryCapacity: 1024*1024*4, diskCapacity: 1024*1024*128, diskPath: nil)
		#endif
		NSURLCache.setSharedURLCache(cache)

		mediumFormatter = NSDateFormatter()
		mediumFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
		mediumFormatter.timeStyle = NSDateFormatterStyle.MediumStyle

		syncDateFormatter = NSDateFormatter()
		syncDateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
		syncDateFormatter.timeZone = NSTimeZone(abbreviation: "UTC")
		syncDateFormatter.locale = NSLocale(localeIdentifier: "en_US")

		var reachability = Reachability.reachabilityForInternetConnection()
		reachability.startNotifier()
		currentNetworkStatus = reachability.currentReachabilityStatus()

		let fileManager = NSFileManager.defaultManager()
		let appSupportURL = fileManager.URLsForDirectory(NSSearchPathDirectory.CachesDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).first! as NSURL
		cacheDirectory = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer").path!

		let config = NSURLSessionConfiguration.defaultSessionConfiguration()
		config.HTTPMaximumConnectionsPerHost = 4
		config.HTTPShouldUsePipelining = true
		config.timeoutIntervalForResource = NETWORK_TIMEOUT
		config.timeoutIntervalForRequest = NETWORK_TIMEOUT
		config.HTTPAdditionalHeaders = ["User-Agent" : userAgent]
		urlSession = NSURLSession(configuration: config)

		if fileManager.fileExistsAtPath(cacheDirectory) {
			clearImageCache()
		} else {
			fileManager.createDirectoryAtPath(cacheDirectory, withIntermediateDirectories: true, attributes: nil, error: nil)
		}

		NSNotificationCenter.defaultCenter().addObserverForName(kReachabilityChangedNotification, object: nil, queue: NSOperationQueue.mainQueue()) { [weak self] n in
			let newStatus = (n.object as Reachability).currentReachabilityStatus()
			if  newStatus != self!.currentNetworkStatus {
				self!.currentNetworkStatus = newStatus
				if newStatus == NetworkStatus.NotReachable {
					DLog("Network went down: %d", newStatus.rawValue)
				} else {
					DLog("Network came up: %d", newStatus.rawValue)
					app.startRefreshIfItIsDue()
				}
			}
		}
	}

	/////////////////////////////////////////////////////// Utilities

	func lastUpdateDescription() -> String {
		if(app.isRefreshing) {
			return "Refreshing..."
		} else if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			return "Last update failed"
		} else {
			let lastSuccess = app.lastSuccessfulRefresh ?? NSDate()
			let ago = NSDate().timeIntervalSinceDate(lastSuccess)
			if ago<10 {
				return "Just updated"
			} else {
				return "Updated \(Int(ago)) seconds ago"
			}
		}
	}

	private func markLongCleanReposAsDirtyInMoc(moc: NSManagedObjectContext) {
		let f = NSFetchRequest(entityName: "Repo")
		f.predicate = NSPredicate(format: "dirty != YES and lastDirtied < %@", NSDate(timeInterval: -3600, sinceDate: NSDate()))
		f.includesPropertyValues = false
		f.returnsObjectsAsFaults = false
		let reposNotFetchedRecently = moc.executeFetchRequest(f, error: nil) as [Repo]
		for r in reposNotFetchedRecently {
			r.dirty = true
			r.lastDirtied = NSDate()
		}

		if reposNotFetchedRecently.count>0 {
			DLog("Marked dirty %d repos which haven't been refreshed in over an hour", reposNotFetchedRecently.count)
		}
	}

	///////////////////////////////////////////////////////// Images

	private func clearImageCache() {
		let fileManager = NSFileManager.defaultManager()
		let files = fileManager.contentsOfDirectoryAtPath(cacheDirectory, error:nil) as? [String]
		for f in files! {
			if startsWith(f, "imgcache-") {
				let path = cacheDirectory.stringByAppendingPathComponent(f)
				fileManager.removeItemAtPath(path, error:nil)
			}
		}
	}

	func expireOldImageCacheEntries() {
		let fileManager = NSFileManager.defaultManager()
		let files = fileManager.contentsOfDirectoryAtPath(cacheDirectory, error:nil) as? [String]
		let now = NSDate()
		for f in files! {
			if startsWith(f, "imgcache-") {
				let path = cacheDirectory.stringByAppendingPathComponent(f)
				let attributes = fileManager.attributesOfItemAtPath(path, error: nil)!
				let date = attributes[NSFileCreationDate] as NSDate
				if now.timeIntervalSinceDate(date) > (3600.0*24) {
					fileManager.removeItemAtPath(path, error:nil)
				}
			}
		}
	}

	// warning: now calls back on thread!!
	func getImage(url: NSURL,
		success:((response: NSHTTPURLResponse?, data: NSData?)->Void)?,
		failure:((response: NSHTTPURLResponse?, error: NSError?)->Void)?) {

			#if os(iOS)
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.1 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					self.networkIndicationStart()
				}
			#endif

			let task = urlSession.dataTaskWithURL(url) { [weak self] (data, res, e)  in

				let response = res as? NSHTTPURLResponse
				var error = e
				if error == nil && response?.statusCode>299 {
					error = NSError(domain: "Error response received", code: response!.statusCode, userInfo: nil)
				}
				if error != nil {
					//DLog("IMAGE %@ - FAILED: %@", url.absoluteString, error)
					failure?(response: response, error: error)
				} else {
					//DLog("IMAGE %@ - RESULT: %d", url.absoluteString, response.statusCode)
					if data != nil && data!.length > 0 {
						success?(response: response, data: data!)
					} else {
						failure?(response: response, error: error)
					}
				}
				#if os(iOS)
					self!.networkIndicationEnd()
				#endif
			}

			task.priority = NSURLSessionTaskPriorityHigh
			task.resume()
	}

	func haveCachedAvatar(path: String, tryLoadAndCallback: ((IMAGE_CLASS?)->Void)?) -> Bool
	{
		#if os(iOS)
			let absolutePath = path + (contains(path, "?") ? "&" : "?") + "s=\(40.0*GLOBAL_SCREEN_SCALE)"
			#else
			let absolutePath = path + (contains(path, "?") ? "&" : "?") + "s=88"
		#endif

		let imageKey = absolutePath + " " + currentAppVersion

		let cachePath = cacheDirectory.stringByAppendingPathComponent("imgcache-%@" + imageKey.md5hash())

		let fileManager = NSFileManager.defaultManager()
		if fileManager.fileExistsAtPath(cachePath) {
			#if os(iOS)
				let imgData = NSData(contentsOfFile: cachePath)
				let imgDataProvider = CGDataProviderCreateWithCFData(imgData)
				let cfImage = CGImageCreateWithJPEGDataProvider(imgDataProvider, nil, false, kCGRenderingIntentDefault)
				let ret = UIImage(CGImage: cfImage, scale: GLOBAL_SCREEN_SCALE, orientation:UIImageOrientation.Up)
				#else
				let ret = NSImage(contentsOfFile: cachePath)
			#endif
			if let r = ret {
				tryLoadAndCallback?(r)
				return true
			} else {
				fileManager.removeItemAtPath(cachePath, error: nil)
			}
		}

		if let c = tryLoadAndCallback {
			getImage(NSURL(string: absolutePath)!,
				success: { response, data in
					var image: IMAGE_CLASS?
					if data != nil {
						#if os(iOS)
							image = IMAGE_CLASS(data: data!, scale:GLOBAL_SCREEN_SCALE)
							UIImageJPEGRepresentation(image!, 1.0).writeToFile(cachePath, atomically: true)
							#else
							image = IMAGE_CLASS(data: data!)
							image!.TIFFRepresentation!.writeToFile(cachePath, atomically: true)
						#endif
					}
					dispatch_async(dispatch_get_main_queue(), { c(image) })
				}, failure: { response, error in
					dispatch_async(dispatch_get_main_queue(), { c(nil) })
			})
		}

		return false
	}

	////////////////////////////////////// API interface

	func fetchPullRequestsForActiveReposAndCallback(callback: (()->Void)?) {
		let syncContext = DataManager.tempContext()

		let shouldRefreshReposToo = (app.lastRepoCheck.isEqualToDate(NSDate.distantPast() as NSDate)
			|| (NSDate().timeIntervalSinceDate(app.lastRepoCheck) < NSTimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| (Repo.countVisibleReposInMoc(syncContext)==0))

		if shouldRefreshReposToo {
			fetchRepositoriesToMoc(syncContext, callback: { [weak self] in
				self!.syncToMoc(syncContext, callback: callback)
			})
		} else {
			ApiServer.resetSyncSuccessInMoc(syncContext)
			ensureApiServersHaveUserIdsInMoc(syncContext, callback: { [weak self] in
				self!.syncToMoc(syncContext, callback: callback)
			})
		}
	}

	private func syncToMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {
		markDirtyReposInMoc(moc, callback: { [weak self] in

			for r in Repo.unsyncableReposInMoc(moc) {
				for p in r.pullRequests.allObjects as [PullRequest] {
					p.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			self!.fetchPullRequestsForRepos(Repo.syncableReposInMoc(moc), toMoc: moc, callback: { [weak self] in
				self!.updatePullRequestsInMoc(moc, callback: { [weak self] in
					self!.completeSyncInMoc(moc)
					callback?()
					return
				})
				return
			})
		})
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

		for r in DataItem.itemsOfType("PullRequest", surviving: true, inMoc: moc) as [PullRequest] {
			r.postProcess()
		}

		var error: NSError?
		if !moc.save(&error) {
			DLog("Comitting sync failed: %@", error)
		}
	}

	func resetAllLabelChecks() {
		refreshesSinceLastLabelsCheck.removeAll()
	}

	func resetAllStatusChecks() {
		refreshesSinceLastStatusCheck.removeAll()
	}

	private func updatePullRequestsInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let willScanForStatuses = shouldScanForStatusesInMoc(moc)
		let willScanForLabels = shouldScanForLabelsInMoc(moc)

		var totalOperations = 3
		if willScanForStatuses { totalOperations++ }
		if willScanForLabels { totalOperations++ }

		var completionCount = 0
		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				callback?()
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

	private func markDirtyReposInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		let totalOperations = 2*allApiServers.count
		if totalOperations==0 {
			callback?()
			return
		}

		var completionCount = 0
		let repoIdsToMarkDirty = NSMutableSet()

		let completionCallback = { [weak self] () -> Void in
			completionCount++
			if completionCount==totalOperations {
				Repo.markDirtyReposWithIds(repoIdsToMarkDirty, inMoc:moc)
				if repoIdsToMarkDirty.count>0 {
					DLog("Marked %d dirty repos that have new events in their event stream", repoIdsToMarkDirty.count)
				}
				self!.markLongCleanReposAsDirtyInMoc(moc)
				callback?()
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

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingUserEventsFromServer: ApiServer, callback: (()->Void)?) {

		if !usingUserEventsFromServer.syncIsGood {
			callback?()
			return
		}

		let latestEtag = usingUserEventsFromServer.latestUserEventEtag
		let latestDate = usingUserEventsFromServer.latestUserEventDateProcessed ?? NSDate.distantPast() as NSDate

		var extraHeaders: Dictionary<String, String>?
		if let e = latestEtag {
			extraHeaders = ["If-None-Match": e]
		}

		let userName = usingUserEventsFromServer.userName ?? "NoApiUserName"
		getPagedDataInPath("/users/\(userName)/events",
			fromServer: usingUserEventsFromServer,
			startingFromPage: 1,
			parameters: nil,
			extraHeaders: extraHeaders,
			perPageCallback: { [weak self] data, lastPage in
				for d in data ?? [] {
					let eventDate = self!.syncDateFormatter.dateFromString(d.ofk("created_at") as String)!
					if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						DLog("New event at %@", eventDate)
						if let repoId = d["repo"]?["id"] as? NSNumber {
							repoIdsToMarkDirty.addObject(repoId)
						}
						if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending {
							usingUserEventsFromServer.latestUserEventDateProcessed = eventDate
							if latestDate.isEqualToDate(NSDate.distantPast() as NSDate) {
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
				callback?()
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingReceivedEventsFromServer: ApiServer, callback: (()->Void)?) {

		if !usingReceivedEventsFromServer.syncIsGood {
			callback?()
			return
		}

		let latestEtag = usingReceivedEventsFromServer.latestReceivedEventEtag
		let latestDate = usingReceivedEventsFromServer.latestReceivedEventDateProcessed ?? NSDate.distantPast() as NSDate

		var extraHeaders: Dictionary<String, String>?
		if let e = latestEtag {
			extraHeaders = ["If-None-Match": e]
		}

		usingReceivedEventsFromServer.latestReceivedEventDateProcessed = latestDate

		let userName = usingReceivedEventsFromServer.userName ?? "NoApiUserName"
		getPagedDataInPath("/users/\(userName)/received_events",
			fromServer: usingReceivedEventsFromServer,
			startingFromPage: 1,
			parameters: nil,
			extraHeaders: extraHeaders,
			perPageCallback: { [weak self] data, lastPage in
				for d in data ?? [] {
					let eventDate = self!.syncDateFormatter.dateFromString(d.ofk("created_at") as String)!
					if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						DLog("New event at %@", eventDate)
						if let repoId = d["repo"]?["id"] as? NSNumber {
							repoIdsToMarkDirty.addObject(repoId)
						}
						if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending {
							usingReceivedEventsFromServer.latestReceivedEventDateProcessed = eventDate
							if latestDate.isEqualToDate(NSDate.distantPast() as NSDate) {
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
				callback?()
		})
	}

	func fetchRepositoriesToMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		ApiServer.resetSyncSuccessInMoc(moc)

		syncUserDetailsInMoc(moc, callback: { [weak self] in
			for r in DataItem.itemsOfType("Repo", surviving: true, inMoc: moc) as [Repo] {
				r.postSyncAction = PostSyncAction.Delete.rawValue
				r.inaccessible = false
			}

			let allApiServers = ApiServer.allApiServersInMoc(moc)
			let totalOperations = allApiServers.count
			var completionCount = 0

			let completionCallback = { () -> Void in
				completionCount++
				if completionCount == totalOperations {
					let shouldHideByDefault = Settings.hideNewRepositories
					for r in DataItem.newItemsOfType("Repo", inMoc: moc) as [Repo] {
						r.hidden = shouldHideByDefault
						if !shouldHideByDefault {
							app.postNotificationOfType(PRNotificationType.NewRepoAnnouncement, forItem:r)
						}
					}
					app.lastRepoCheck = NSDate()
					callback?()
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo {
					self!.syncWatchedReposFromServer(apiServer, callback: completionCallback)
				} else {
					completionCallback()
				}
			}
		})
	}

	private func fetchPullRequestsForRepos(repos: [Repo], toMoc:NSManagedObjectContext, callback: (()->Void)?) {

		if repos.count==0 {
			callback?()
			return
		}
		let total = repos.count
		var completionCount = 0
		for r in repos {

			for pr in r.pullRequests.allObjects as [PullRequest] {
				if (pr.condition?.integerValue ?? 0) == PullRequestCondition.Open.rawValue {
					pr.postSyncAction = PostSyncAction.Delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood {
				let repoFullName = r.fullName ?? "NoRepoFullName"
				getPagedDataInPath("/repos/\(repoFullName)/pulls", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							let p = PullRequest.pullRequestWithInfo(info, fromServer:apiServer)
							p.repo = r
						}
						return false
					}, finalCallback: { success, resultCode, etag in
						if !success {
							if resultCode == 404 { // repo disabled
								r.inaccessible = true
								r.postSyncAction = PostSyncAction.DoNothing.rawValue
								for p in r.pullRequests.allObjects as [PullRequest] {
									p.postSyncAction = PostSyncAction.Delete.rawValue
								}
							} else if resultCode==410 { // repo gone for good
								r.postSyncAction = PostSyncAction.Delete.rawValue
							} else { // fetch problem
								apiServer.lastSyncSucceeded = false
							}
						}
						completionCount++
						r.dirty = false
						if completionCount==total {
							callback?()
						}
				})
			} else {
				completionCount++
				r.dirty = false
				if completionCount==total {
					callback?()
				}
			}
		}
	}

	private func fetchCommentsForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let prs = (DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as [PullRequest]).filter({ pr in
			return pr.apiServer.syncIsGood
		})
		if(prs.count==0) {
			callback?()
			return
		}

		for r in prs {
			for c in r.comments.allObjects as [PRComment] {
				c.postSyncAction = PostSyncAction.Delete.rawValue
			}
		}

		let totalOperations = 2
		var completionCount = 0

		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations { callback?() }
		}

		_fetchCommentsForPullRequests(prs, issues: true, inMoc: moc, callback: completionCallback)
		_fetchCommentsForPullRequests(prs, issues: false, inMoc: moc, callback: completionCallback)
	}

	private func _fetchCommentsForPullRequests(prs: [PullRequest], issues: Bool, inMoc: NSManagedObjectContext, callback: (()->Void)?) {

		let total = prs.count
		if total==0 {
			callback?()
			return
		}

		var completionCount = 0

		for p in prs {
			if let link = (issues ? p.issueCommentLink : p.reviewCommentLink) {

				let apiServer = p.apiServer

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { (data, lastPage) -> Bool in
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
							callback?()
						}
				})
			} else {
				completionCount++
				if completionCount == total {
					callback?()
				}
			}
		}
	}

	private func fetchLabelsForForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let prs = (DataItem.allItemsOfType("PullRequest", inMoc: moc) as [PullRequest]).filter { [weak self] pr in
			if !pr.apiServer.syncIsGood {
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
			callback?()
			return
		}

		var completionCount = 0

		for p in prs {
			for l in p.labels.allObjects as [PRLabel] {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let link = p.labelsLink() {

				getPagedDataInPath(link, fromServer: p.apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { data, lastPage in
						for info in data ?? [] {
							PRLabel.labelWithInfo(info, forPullRequest:p)
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
							callback?()
						}
				})
			} else {
				// no labels link, so presumably no labels
				refreshesSinceLastLabelsCheck[p.objectID] = 1
				completionCount++
				if completionCount == total {
					callback?()
				}
			}
		}
	}

	private func fetchStatusesForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let prs = (DataItem.allItemsOfType("PullRequest", inMoc: moc) as [PullRequest]).filter { [weak self] pr in
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

		let total = prs.count;
		if total==0 {
			callback?()
			return
		}

		var completionCount = 0

		for p in prs {
			for s in p.statuses.allObjects as [PRStatus] {
				s.postSyncAction = PostSyncAction.Delete.rawValue
			}

			let apiServer = p.apiServer

			if let statusLink = p.statusesLink {
				getPagedDataInPath(statusLink, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { (data, lastPage) -> Bool in
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
						if(completionCount==total) {
							callback?()
						}
				})
			} else {
				refreshesSinceLastStatusCheck[p.objectID] = 1
				completionCount++
				if completionCount==total {
					callback?()
				}
			}
		}
	}

	private func checkPrClosuresInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, PullRequestCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = moc.executeFetchRequest(f, error: nil) as [PullRequest]

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return (!parent.hidden.boolValue) && ((parent.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue) && r.apiServer.syncIsGood
		}

		let totalOperations = prsToCheck.count
		if totalOperations==0 {
			callback?()
			return
		}

		var completionCount = 0
		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				callback?()
				return
			}
		}

		for r in prsToCheck {
			investigatePrClosureForPr(r, callback: completionCallback)
		}
	}

	private func detectAssignedPullRequestsInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let prs = (DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as [PullRequest]).filter({ pr in
			return pr.apiServer.syncIsGood
		})
		if prs.count==0 {
			callback?()
			return
		}

		let totalOperations = prs.count
		var completionCount = 0

		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				callback?()
			}
		}

		for p in prs {
			let apiServer = p.apiServer
			if let issueLink = p.issueUrl {
				getDataInPath(issueLink, fromServer: apiServer, parameters: nil, extraHeaders: nil,
					callback: { data, lastPage, resultCode, etag in
						if data != nil {
							let assignee = ((data as NSDictionary).ofk("assignee") as NSDictionary?)?.ofk("login") as? String ?? "NoAssignedUserName"
							let assigned = (assignee == (apiServer.userName ?? "NoApiUser"))
							p.isNewAssignment = (assigned && !(p.assignedToMe?.boolValue ?? false))
							p.assignedToMe = assigned
						} else {
							if resultCode == 404 || resultCode == 410 {
								// 404/410 is fine, it means issue entry doesn't exist
								p.assignedToMe = false
								p.isNewAssignment = false
							} else {
								apiServer.lastSyncSucceeded = false
							}
						}
						completionCallback()
				})
			} else {
				completionCallback()
			}
		}
	}

	private func ensureApiServersHaveUserIdsInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {
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
			callback?()
		}
	}

	private func investigatePrClosureForPr(r: PullRequest, callback: (()->Void)?) {
		DLog("Checking closed PR to see if it was merged: %@", r.title)

		let repoFullName = r.repo.fullName ?? "NoRepoFullName"
		let repoNumber = r.number?.stringValue ?? "NoRepoNumber"
		get("/repos/\(repoFullName)/pulls/\(repoNumber)", fromServer: r.apiServer, ignoreLastSync: false, parameters: nil, extraHeaders: nil,
			success: { [weak self] response, data in

				if let mergeInfo = (data as? NSDictionary)?.ofk("merged_by") as? NSDictionary {
					DLog("detected merged PR: %@", r.title)

					let mergeUserId = mergeInfo.ofk("id") as? NSNumber ?? NSNumber(int: -2)
					DLog("merged by user id: %@, our id is: %@", mergeUserId, r.apiServer.userId)

					let mergedByMyself = mergeUserId.isEqualToNumber(r.apiServer.userId ?? NSNumber(int: -1))

					if !(mergedByMyself && Settings.dontKeepPrsMergedByMe) {
						self!.prWasMerged(r)
					} else {
						DLog("will not announce merged PR: %@", r.title)
					}
				} else {
					self!.prWasClosed(r)
				}
				callback?()

			}, failure: { [weak self] response, data, error in
				let resultCode = response?.statusCode ?? 0
				if resultCode == 404 || resultCode==410 { // PR gone for good
					self!.prWasClosed(r)
				} else { // fetch problem
					r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this, we couldn't check, play it safe
					r.apiServer.lastSyncSucceeded = false
				}
				callback?()
		})
	}

	private func prWasMerged(r: PullRequest) {
		DLog("detected merged PR: %@", r.title)
		switch Settings.mergeHandlingPolicy {

		case PRHandlingPolicy.KeepMine.rawValue:
			if (r.sectionIndex?.integerValue ?? 0)==PullRequestSection.All.rawValue { break }
			fallthrough

		case PRHandlingPolicy.KeepAll.rawValue:
			r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this
			r.condition = PullRequestCondition.Merged.rawValue
			app.postNotificationOfType(PRNotificationType.PrMerged, forItem: r)

		default:
			break
		}
	}

	private func prWasClosed(r: PullRequest) {
		DLog("detected closed PR: %@", r.title)
		switch(Settings.closeHandlingPolicy) {

		case PRHandlingPolicy.KeepMine.rawValue:
			if (r.sectionIndex?.integerValue ?? 0) == PullRequestSection.All.rawValue { break }
			fallthrough

		case PRHandlingPolicy.KeepAll.rawValue:
			r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this
			r.condition = PullRequestCondition.Closed.rawValue
			app.postNotificationOfType(PRNotificationType.PrClosed, forItem:r)

		default:
			break
		}
	}

	func getRateLimitFromServer(apiServer: ApiServer, callback: ((Int64, Int64, Int64)->Void)?)
	{
		get("/rate_limit", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil,
			success: { response, data in
				let allHeaders = response!.allHeaderFields
				let requestsRemaining = (allHeaders["X-RateLimit-Remaining"] as NSString).longLongValue
				let requestLimit = (allHeaders["X-RateLimit-Limit"] as NSString).longLongValue
				let epochSeconds = (allHeaders["X-RateLimit-Reset"] as NSString).longLongValue
				callback?(requestsRemaining, requestLimit, epochSeconds)
			},
			failure: { response, data, error in
				if response?.statusCode == 404 && data != nil && !((data as NSDictionary).ofk("message") as String == "Not Found") {
					callback?(10000, 10000, 0)
				} else {
					callback?(-1, -1, -1)
				}
		})
	}

	func updateLimitsFromServer() {
		let allApiServers = ApiServer.allApiServersInMoc(mainObjectContext)
		let total = allApiServers.count
		var count = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getRateLimitFromServer(apiServer, callback: { remaining, limit, reset in
					apiServer.requestsRemaining = NSNumber(longLong: remaining)
					apiServer.requestsLimit = NSNumber(longLong: limit)
					count++
					if count==total {
						NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: apiServer, userInfo: nil)
					}
				})
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

	func syncWatchedReposFromServer(apiServer: ApiServer, callback: (()->Void)?) {

		if !apiServer.syncIsGood {
			callback?
			return
		}

		getPagedDataInPath("/user/subscriptions", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
			perPageCallback: { (data, lastPage) -> Bool in

				if let d = data ?? [] {
					for info in d {
						if (info.ofk("private") as? NSNumber)?.boolValue ?? false {
							if let permissions = info.ofk("permissions") as? NSDictionary {
								if (permissions.ofk("pull") as NSNumber).boolValue ||
									(permissions.ofk("push") as NSNumber).boolValue ||
									(permissions.ofk("admin") as NSNumber).boolValue {
										let r = Repo.repoWithInfo(info, fromServer: apiServer)
										r.apiServer = apiServer
								} else {
									DLog("Watched private repository '%@' seems to be inaccessible, skipping", info.ofk("full_name") as String?)
									continue
								}
							}
						} else {
							let r = Repo.repoWithInfo(info, fromServer: apiServer)
							r.apiServer = apiServer
						}
					}
				}
				return false

			}, finalCallback: { success, resultCode, etag in
				if !success {
					apiServer.lastSyncSucceeded = false
				}
				callback?()
		})
	}

	func syncUserDetailsInMoc(moc: NSManagedObjectContext, callback: (()->Void)?) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		let operationCount = allApiServers.count
		if operationCount==0 {
			callback?()
			return
		}
		var completionCount = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getDataInPath("/user", fromServer:apiServer, parameters: nil, extraHeaders:nil, callback: {
					data, lastPage, resultCode, etag in

					if let d = data as? NSDictionary {
						apiServer.userName = d.ofk("login") as? String
						apiServer.userId = d.ofk("id") as? NSNumber
					} else {
						apiServer.lastSyncSucceeded = false
					}
					completionCount++
					if completionCount==operationCount { callback?() }
				})
			} else {
				completionCount++
				if(completionCount==operationCount) { callback?() }
			}
		}
	}

	func testApiToServer(apiServer: ApiServer, callback:((NSError?)->())?) {
		get("/rate_limit", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil,
			success: { response, data in
				callback?(nil)
				return // compiler seems to need this for some reason
			},
			failure: { response, data, error in
				let allOk = (response?.statusCode == 404 && data != nil && !((data as NSDictionary).ofk("message") as String == "Not Found"))
				callback?(allOk ? nil : error)
		})
	}



	//////////////////////////////////////////////////////////// low level

	private func lastPage(response: NSHTTPURLResponse) -> Bool {
		let linkHeader = (response.allHeaderFields as NSDictionary).ofk("Link") as? String
		if linkHeader == nil { return true }
		return linkHeader!.rangeOfString("rel=\"next\"") == nil
	}

	private func getPagedDataInPath(
		path: String,
		fromServer: ApiServer,
		startingFromPage: Int,
		parameters: Dictionary<String, String>?,
		extraHeaders: Dictionary<String, String>?,
		perPageCallback: ((data: [NSDictionary]?, lastPage: Bool)->Bool)?,
		finalCallback: ((success: Bool, resultCode: Int, etag: String?)->Void)?) {

			if path.isEmpty {
				// handling empty or null fields as success, since we don't want syncs to fail, we simply have nothing to process
				dispatch_async(dispatch_get_main_queue()) {
					finalCallback?(success: true, resultCode: -1, etag: nil)
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

				if let d = data as? [NSDictionary] {
					var isLastPage = lastPage
					if let p = perPageCallback {
						if p(data: d, lastPage: lastPage) { isLastPage = true }
						if isLastPage {
							finalCallback?(success: true, resultCode: resultCode, etag: etag)
						} else {
							self!.getPagedDataInPath(path, fromServer: fromServer, startingFromPage: startingFromPage+1, parameters: parameters, extraHeaders: extraHeaders, perPageCallback: perPageCallback, finalCallback: finalCallback)
						}
					}
				} else {
					finalCallback?(success: resultCode==304, resultCode: resultCode, etag: etag)
				}
			}
	}

	private func getDataInPath(
		path: String,
		fromServer: ApiServer,
		parameters: Dictionary<String, String>?,
		extraHeaders: Dictionary<String, String>?,
		callback:((data: AnyObject?, lastPage: Bool, resultCode: Int, etag: String?)->Void)?) {

			get(path, fromServer: fromServer, ignoreLastSync: false, parameters: parameters, extraHeaders: extraHeaders,
				success: { [weak self] response, data in

					let allHeaders = response!.allHeaderFields
					fromServer.requestsRemaining = NSNumber(longLong: (allHeaders["X-RateLimit-Remaining"] as NSString).longLongValue)
					fromServer.requestsLimit = NSNumber(longLong: (allHeaders["X-RateLimit-Limit"] as NSString).longLongValue)
					let epochSeconds = (allHeaders["X-RateLimit-Reset"] as NSString).doubleValue
					fromServer.resetDate = NSDate(timeIntervalSince1970: epochSeconds)
					NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: fromServer, userInfo: nil)

					let etag = allHeaders["Etag"] as? String
					let code = response!.statusCode ?? 0
					callback?(data: data, lastPage: self!.lastPage(response!), resultCode: code, etag: etag)

				}, failure: { response, data, error in
					let code = response?.statusCode ?? 0
					if code == 304 {
						DLog("(%@) no change reported (304)", fromServer.label)
					} else {
						DLog("(%@) failure for %@: %@", fromServer.label, path, error?.localizedDescription)
					}
					callback?(data: nil, lastPage: false, resultCode: code, etag: nil)
			})
	}

	private func get(
		path:String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		parameters: Dictionary<String, String>?,
		extraHeaders: Dictionary<String, String>?,
		success: ((response: NSHTTPURLResponse?, data: AnyObject?)->Void)?,
		failure: ((response: NSHTTPURLResponse?, data: AnyObject?, error: NSError?)->Void)?) {

			var apiServerLabel: String
			if fromServer.syncIsGood || ignoreLastSync {
				apiServerLabel = fromServer.label ?? "(untitled server)"
			} else {
				dispatch_async(dispatch_get_main_queue()) {
					let e = NSError(domain: "Sync has failed, skipping this call", code: -1, userInfo: nil)
					failure?(response: nil, data: nil, error: e)
				}
				return
			}

			#if os(iOS)
				networkIndicationStart()
			#endif

			let authToken = fromServer.authToken
			var expandedPath = startsWith(path, "/") ? (fromServer.apiPath ?? "").stringByAppendingPathComponent(path) : path

			if let params = parameters {
				var pairs = [String]()
				for (key, value) in params {
					pairs.append(key + "=" + value)
				}
				expandedPath = expandedPath + "?" + "&".join(pairs)
			}

			let r = NSMutableURLRequest(URL: NSURL(string: expandedPath)!, cachePolicy: NSURLRequestCachePolicy.UseProtocolCachePolicy, timeoutInterval: NETWORK_TIMEOUT)
			r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
			if authToken != nil { r.setValue("token " + authToken!, forHTTPHeaderField: "Authorization") }

			if let headers = extraHeaders {
				for (key,value) in headers {
					DLog("(%@) custom header: %@=%@", apiServerLabel, key, value)
					r.setValue(value, forHTTPHeaderField:key)
				}
			}

			////////////////////////// preempt with error backoff algorithm
			let fullUrlPath = r.URL!.absoluteString!
			var existingBackOff = badLinks[fullUrlPath]
			if existingBackOff != nil {
				if NSDate().compare(existingBackOff!.nextAttemptAt) == NSComparisonResult.OrderedAscending {
					// report failure and return
					DLog("(%@) preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, fullUrlPath, existingBackOff!.nextAttemptAt)
					dispatch_async(dispatch_get_main_queue()) {
						let e = NSError(domain: "Preempted fetch because of throttling", code: 400, userInfo: nil)
						failure?(response: nil, data: nil, error: e)
					}
					#if os(iOS)
						networkIndicationEnd()
					#endif
					return
				}
			}

			urlSession.dataTaskWithRequest(r) { [weak self] data, res, e in

				let response = res as? NSHTTPURLResponse
				var parsedData: AnyObject?
				if data?.length > 0 {
					parsedData = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.allZeros, error:nil)
				}
				var error = e
				if error == nil && response?.statusCode > 299 {
					error = NSError(domain: "Error response received", code:response!.statusCode, userInfo:nil)
					if(response?.statusCode >= 400) {
						if existingBackOff != nil {
							DLog("(%@) extending backoff for already throttled URL %@ by %f seconds", apiServerLabel, fullUrlPath, BACKOFF_STEP)
							if existingBackOff!.duration < 3600.0 {
								existingBackOff!.duration += BACKOFF_STEP
							}
							existingBackOff!.nextAttemptAt = NSDate(timeInterval: existingBackOff!.duration, sinceDate:NSDate())
						} else {
							DLog("(%@) placing URL %@ on the throttled list", apiServerLabel, fullUrlPath)
							self!.badLinks[fullUrlPath] = UrlBackOffEntry(
								nextAttemptAt: NSDate(timeInterval: BACKOFF_STEP, sinceDate: NSDate()),
								duration: BACKOFF_STEP)
						}
					}
				}

				if error != nil {
					DLog("(%@) GET %@ - FAILED: %@", apiServerLabel, fullUrlPath, error!.localizedDescription)
					dispatch_async(dispatch_get_main_queue()) {
						failure?(response: response, data: parsedData, error: error)
						return // compiler is acting weird, seems to need this
					}
				} else {
					DLog("(%@) GET %@ - RESULT: %d", apiServerLabel, fullUrlPath, response?.statusCode)
					self!.badLinks.removeValueForKey(fullUrlPath)
					dispatch_async(dispatch_get_main_queue()) {
						success?(response: response, data: parsedData)
						return // compiler is acting weird, seems to need this
					}
				}

				#if os(iOS)
					self!.networkIndicationEnd()
				#endif
			}.resume()
	}

	#if os(iOS)
	func networkIndicationStart() {
		dispatch_async(dispatch_get_main_queue(), { [weak self] in
			if ++self!.networkIndicationCount==1 {
				UIApplication.sharedApplication().networkActivityIndicatorVisible = true
			}
		})
	}
	
	func networkIndicationEnd() {
		dispatch_async(dispatch_get_main_queue(), { [weak self] in
			if --self!.networkIndicationCount==0 {
				UIApplication.sharedApplication().networkActivityIndicatorVisible = false
			}
		})
	}
	#endif
}
