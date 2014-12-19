
struct UrlBackOffEntry {
	var nextAttemptAt: NSDate
	var duration: NSTimeInterval
}

class API: NSOperationQueue {

	var reachability = Reachability.reachabilityForInternetConnection()
	var successfulRefreshesSinceLastStatusCheck: Int = 0
	var successfulRefreshesSinceLastLabelCheck: Int = 0

	private let mediumFormatter: NSDateFormatter
	private let syncDateFormatter: NSDateFormatter
	private let cacheDirectory: String
	private var badLinks = [String:UrlBackOffEntry]()
	#if os(iOS)
	private var networkIndicationCount: Int = 0
	private let GLOBAL_SCREEN_SCALE = UIScreen.mainScreen().scale
	#endif

	override init() {

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

		reachability.startNotifier()

		let fileManager = NSFileManager.defaultManager()
		let appSupportURL = fileManager.URLsForDirectory(NSSearchPathDirectory.CachesDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).first! as NSURL
		cacheDirectory = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer").path!

		super.init()

		if fileManager.fileExistsAtPath(cacheDirectory) {
			clearImageCache()
		} else {
			fileManager.createDirectoryAtPath(cacheDirectory, withIntermediateDirectories: true, attributes: nil, error: nil)
		}

		maxConcurrentOperationCount = 4

		api = self
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
		failure:((response: NSHTTPURLResponse?, error: NSError?)->Void)?) -> NSBlockOperation {

			networkIndicationStart()

			let o = NSBlockOperation {

				let r = NSMutableURLRequest(URL: url, cachePolicy: NSURLRequestCachePolicy.UseProtocolCachePolicy, timeoutInterval: NETWORK_TIMEOUT)
				r.setValue(self.userAgent(), forHTTPHeaderField: "User-Agent")

				var error: NSError?
				var res: NSURLResponse?
				let data = NSURLConnection.sendSynchronousRequest(r, returningResponse: &res, error: &error)
				let response = res as? NSHTTPURLResponse
				if error == nil && response?.statusCode>299 {
					error = NSError(domain: "Error response received", code: response!.statusCode, userInfo: nil)
				}
				if error != nil {
					//DLog("IMAGE %@ - FAILED: %@", url.absoluteString, error)
					if let fail = failure {
						fail(response: response, error: error)
					}
				} else {
					//DLog("IMAGE %@ - RESULT: %d", url.absoluteString, response.statusCode)
					if data != nil && data!.length > 0 {
						if let c = success { c(response: response, data: data!) }
					} else {
						if let c = failure { c(response: response, error: error) }
					}
				}
				self.networkIndicationEnd()
			}
			o.queuePriority = NSOperationQueuePriority.VeryLow
			addOperation(o)
			return o
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
				if let c = tryLoadAndCallback { c(r) }
				return true
			} else {
				fileManager.removeItemAtPath(cachePath, error: nil)
			}
		}

		if let c = tryLoadAndCallback {
			getImage(NSURL(string: absolutePath)!,
				success: { (response, data) in
					var image: IMAGE_CLASS?
					if data != nil {
						#if os(iOS)
							image = IMAGE_CLASS(data: data!, scale: self.GLOBAL_SCREEN_SCALE)
							UIImageJPEGRepresentation(image!, 1.0).writeToFile(cachePath, atomically: true)
							#else
							image = IMAGE_CLASS(data: data!)
							image!.TIFFRepresentation!.writeToFile(cachePath, atomically: true)
						#endif
					}
					dispatch_async(dispatch_get_main_queue(), { c(image) })
				}, failure: { (response, error) in
					dispatch_async(dispatch_get_main_queue(), { c(nil) })
			})
		}

		return false
	}

	////////////////////////////////////// API interface

	func fetchPullRequestsForActiveReposAndCallback(callback: completionBlockType) {
		let syncContext = DataManager.tempContext()

		let shouldRefreshReposToo = (app.lastRepoCheck.isEqualToDate(NSDate.distantPast() as NSDate)
			|| (NSDate().timeIntervalSinceDate(app.lastRepoCheck) < NSTimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| (Repo.countVisibleReposInMoc(syncContext)==0))

		if shouldRefreshReposToo {
			self.fetchRepositoriesToMoc(syncContext, andCallback: {
				self.syncToMoc(syncContext, andCallback: callback)
			})
		} else {
			ApiServer.resetSyncSuccessInMoc(syncContext)
			ensureApiServersHaveUserIdsInMoc(syncContext, andCallback: {
				self.syncToMoc(syncContext, andCallback: callback)
			})
		}
	}

	private func syncToMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {
		markDirtyReposInMoc(moc, andCallback: {

			for r in Repo.unsyncableReposInMoc(moc) {
				for p in r.pullRequests.allObjects as [PullRequest] {
					moc.deleteObject(p)
				}
			}

			self.fetchPullRequestsForRepos(Repo.syncableReposInMoc(moc), toMoc: moc, andCallback: {
				self.updatePullRequestsInMoc(moc, andCallback: {
					self.completeSyncInMoc(moc)
					self.CALLBACK(andCallback)
				})
			})
		})
	}

	private func completeSyncInMoc(moc: NSManagedObjectContext) {

		// discard any changes related to any failed API server
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if !(apiServer.lastSyncSucceeded?.boolValue ?? false) {
				apiServer.rollBackAllUpdatesInMoc(moc)
				apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
			}
		}

		DataItem.nukeDeletedItemsInMoc(moc)

		for r in DataItem.itemsOfType("PullRequest", surviving: true, inMoc: moc) as [PullRequest] {
			r.postProcess()
		}

		var error: NSError?
		moc.save(&error)
		if error != nil {
			DLog("Comitting sync failed: %@", error)
		}

		if(Settings.showStatusItems) {
			self.successfulRefreshesSinceLastStatusCheck++
		}
		if(Settings.showLabels) {
			self.successfulRefreshesSinceLastLabelCheck++
		}
	}

	private func updatePullRequestsInMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let willScanForStatuses = shouldScanForStatusesInMoc(moc)
		let willScanForLabels = shouldScanForLabelsInMoc(moc)

		var totalOperations = 3
		if willScanForStatuses { totalOperations++ }
		if willScanForLabels { totalOperations++ }

		var completionCount = 0
		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				self.CALLBACK(andCallback)
			}
		}

		if willScanForStatuses {
			fetchStatusesForCurrentPullRequestsToMoc(moc, andCallback: completionCallback)
		}

		if willScanForLabels {
			fetchLabelsForForCurrentPullRequestsToMoc(moc, andCallback: completionCallback)
		}

		fetchCommentsForCurrentPullRequestsToMoc(moc, andCallback: completionCallback)
		checkPrClosuresInMoc(moc, andCallback: completionCallback)
		detectAssignedPullRequestsInMoc(moc, andCallback: completionCallback)
	}

	private func markDirtyReposInMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		let totalOperations = 2*allApiServers.count
		if totalOperations==0 {
			CALLBACK(andCallback)
			return
		}

		var completionCount = 0
		let repoIdsToMarkDirty = NSMutableSet()

		let completionCallback = { () -> Void in
			completionCount++
			if completionCount==totalOperations {
				Repo.markDirtyReposWithIds(repoIdsToMarkDirty, inMoc:moc)
				if repoIdsToMarkDirty.count>0 {
					DLog("Marked dirty %d repos which have events in their event stream", repoIdsToMarkDirty.count)
				}
				self.markLongCleanReposAsDirtyInMoc(moc)
				self.CALLBACK(andCallback)
			}
		}

		for apiServer in allApiServers {
			if apiServer.goodToGo() {
				markDirtyRepoIds(repoIdsToMarkDirty, usingUserEventsFromServer: apiServer, andCallback: completionCallback)
				markDirtyRepoIds(repoIdsToMarkDirty, usingReceivedEventsFromServer: apiServer, andCallback:completionCallback)
			} else {
				completionCallback()
				completionCallback()
			}
		}
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingUserEventsFromServer: ApiServer, andCallback: completionBlockType) {
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
			parameters:nil,
			extraHeaders: extraHeaders,
			perPageCallback: { (data, lastPage) in
				for d in data as [NSDictionary] {
					let eventDate = self.syncDateFormatter.dateFromString(d.ofk("created_at") as String!)!
					if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						DLog("New event at %@", eventDate)
						let repoId = d["repo"]?["id"] as NSNumber?
						if let r = repoId {
							repoIdsToMarkDirty.addObject(r)
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
			}, finalCallback: { (success, resultCode, etag) in
				usingUserEventsFromServer.latestUserEventEtag = etag
				if !success {
					usingUserEventsFromServer.lastSyncSucceeded = false
				}
				self.CALLBACK(andCallback)
		})
	}

	private func markDirtyRepoIds(repoIdsToMarkDirty: NSMutableSet, usingReceivedEventsFromServer: ApiServer, andCallback: completionBlockType) {
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
			perPageCallback: { (data, lastPage) in
				for d in data as [NSDictionary] {
					let eventDate = self.syncDateFormatter.dateFromString(d.ofk("created_at") as String!)!
					if latestDate.compare(eventDate) == NSComparisonResult.OrderedAscending { // this is where we came in
						DLog("New event at %@", eventDate)
						let repoId = d["repo"]?["id"] as NSNumber?
						if let r = repoId {
							repoIdsToMarkDirty.addObject(r)
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
			}, finalCallback: { (success, resultCode, etag) in
				usingReceivedEventsFromServer.latestReceivedEventEtag = etag
				if !success {
					usingReceivedEventsFromServer.lastSyncSucceeded = false
				}
				self.CALLBACK(andCallback)
		})
	}

	func fetchRepositoriesToMoc(moc: NSManagedObjectContext, andCallback:completionBlockType) {

		ApiServer.resetSyncSuccessInMoc(moc)

		syncUserDetailsInMoc(moc, andCallback: {
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
					self.CALLBACK(andCallback)
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo() {
					self.syncWatchedReposFromServer(apiServer, andCallback: completionCallback)
				} else {
					completionCallback()
				}
			}
		})
	}

	private func fetchPullRequestsForRepos(repos: [Repo], toMoc:NSManagedObjectContext, andCallback: completionBlockType) {

		if repos.count==0 {
			CALLBACK(andCallback)
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

			let repoFullName = r.fullName ?? "NoRepoFullName"
			getPagedDataInPath("/repos/\(repoFullName)/pulls", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
				perPageCallback: { (data, lastPage) in
					for info in data as [NSDictionary] {
						let p = PullRequest.pullRequestWithInfo(info, fromServer:apiServer)
						p.repo = r
					}
					return false
				}, finalCallback: { (success, resultCode, etag) in
					completionCount++
					r.dirty = false
					if !success {
						if resultCode == 404 { // repo disabled
							r.inaccessible = true
							r.postSyncAction = PostSyncAction.DoNothing.rawValue
							for p in r.pullRequests.allObjects as [PullRequest] {
								toMoc.deleteObject(p)
							}
						} else if resultCode==410 { // repo gone for good
							r.postSyncAction = PostSyncAction.Delete.rawValue
						} else { // fetch problem
							apiServer.lastSyncSucceeded = false
						}
					}
					if completionCount==total {
						self.CALLBACK(andCallback)
					}
			})
		}
	}

	private func fetchCommentsForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let prs = DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as [PullRequest]
		if(prs.count==0) {
			CALLBACK(andCallback)
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
			if completionCount == totalOperations { self.CALLBACK(andCallback) }
		}

		_fetchCommentsForPullRequests(prs, issues: true, inMoc: moc, andCallback: completionCallback)
		_fetchCommentsForPullRequests(prs, issues: false, inMoc: moc, andCallback: completionCallback)
	}

	private func _fetchCommentsForPullRequests(prs: [PullRequest], issues: Bool, inMoc: NSManagedObjectContext, andCallback: completionBlockType) {

		let total = prs.count
		if total==0 {
			CALLBACK(andCallback)
			return
		}

		var completionCount = 0

		for p in prs {
			if let link = (issues ? p.issueCommentLink : p.reviewCommentLink) {

				let apiServer = p.apiServer

				getPagedDataInPath(link, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { (data, lastPage) -> Bool in
						for info in data as [NSDictionary] {
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
					}, finalCallback: { (success, resultCode, etag) in
						completionCount++
						if !success {
							apiServer.lastSyncSucceeded = false
						}
						if completionCount == total {
							self.CALLBACK(andCallback)
						}
				})
			} else {
				completionCount++
				if completionCount == total {
					CALLBACK(andCallback)
				}
			}
		}
	}

	private func fetchLabelsForForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let prs = DataItem.allItemsOfType("PullRequest", inMoc: moc) as [PullRequest]

		let total = prs.count
		if total==0 {
			CALLBACK(andCallback)
			return
		}

		var completionCount = 0

		for p in prs {
			for l in p.labels.allObjects as [PRLabel] {
				l.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let link = p.labelsLink() {

				getPagedDataInPath(link, fromServer: p.apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
					perPageCallback: { (data, lastPage) in
						for info in data as [NSDictionary] {
							PRLabel.labelWithInfo(info, forPullRequest:p)
						}
						return false
					}, finalCallback: { (success, resultCode, etag) in
						completionCount++
						if success {
							self.successfulRefreshesSinceLastLabelCheck = 0
						} else {
							// 404/410 means the PR has been deleted
							if !(resultCode==404 || resultCode==410) {
								p.apiServer.lastSyncSucceeded = false
							}
						}
						if completionCount == total {
							self.CALLBACK(andCallback)
						}
				})
			} else {
				// no issues link, so presumably no labels
				completionCount++
				if completionCount == total {
					CALLBACK(andCallback)
				}
			}
		}
	}

	private func fetchStatusesForCurrentPullRequestsToMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let prs = DataItem.allItemsOfType("PullRequest", inMoc:moc) as [PullRequest]

		let total = prs.count;
		if total==0 {
			CALLBACK(andCallback)
			return
		}

		var completionCount = 0

		for p in prs {
			for s in p.statuses.allObjects as [PullRequest] {
				s.postSyncAction = PostSyncAction.Delete.rawValue
			}

			let apiServer = p.apiServer

			getPagedDataInPath(p.statusesLink!, fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
				perPageCallback: { (data, lastPage) -> Bool in
					for info in data as [NSDictionary]
					{
						let s = PRStatus.statusWithInfo(info, fromServer: apiServer)
						s.pullRequest = p
					}
					return false
				}, finalCallback: { (success, resultCode, etag) in
					completionCount++
					if success {
						self.successfulRefreshesSinceLastStatusCheck = 0
					} else {
						// 404/410 means the PR has been deleted
						if !(resultCode==404 || resultCode==410) {
							apiServer.lastSyncSucceeded = false
						}
					}
					if(completionCount==total) {
						self.CALLBACK(andCallback)
					}
			})
		}
	}

	private func checkPrClosuresInMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.Delete.rawValue, PullRequestCondition.Open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = moc.executeFetchRequest(f, error: nil) as [PullRequest]

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return (!parent.hidden.boolValue) && ((parent.postSyncAction?.integerValue ?? 0) != PostSyncAction.Delete.rawValue)
		}

		let totalOperations = prsToCheck.count
		if totalOperations==0 {
			CALLBACK(andCallback)
			return
		}

		var completionCount = 0
		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				self.CALLBACK(andCallback)
			}
		}

		for r in prsToCheck {
			investigatePrClosureForPr(r, andCallback: completionCallback)
		}
	}

	private func detectAssignedPullRequestsInMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {

		let prs = DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as [PullRequest]
		if prs.count==0 {
			CALLBACK(andCallback)
			return
		}

		let totalOperations = prs.count
		var completionCount = 0

		let completionCallback = { () -> Void in
			completionCount++
			if completionCount == totalOperations {
				self.CALLBACK(andCallback)
			}
		}

		for p in prs {
			let apiServer = p.apiServer
			if let issueLink = p.issueUrl {
				getDataInPath(issueLink, fromServer: apiServer, parameters: nil, extraHeaders: nil,
					andCallback: { (data, lastPage, resultCode, etag) in
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

	private func ensureApiServersHaveUserIdsInMoc(moc: NSManagedObjectContext, andCallback: completionBlockType) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if (apiServer.userId?.integerValue ?? 0) == 0 {
				needToCheck = true
				break
			}
		}

		if needToCheck {
			DLog("Some API servers don't have user details yet, will bring user credentials down for them")
			syncUserDetailsInMoc(moc, andCallback: andCallback)
		} else {
			CALLBACK(andCallback)
		}
	}

	private func investigatePrClosureForPr(r: PullRequest, andCallback: completionBlockType) {
		DLog("Checking closed PR to see if it was merged: %@", r.title)

		let repoFullName = r.repo.fullName ?? "NoRepoFullName"
		let repoNumber = r.number ?? "NoRepoNumber"
		get("/repos/\(repoFullName)/pulls/\(repoNumber)", fromServer: r.apiServer, ignoreLastSync: false, parameters:nil, extraHeaders: nil,
			success: { (response, data) in

				if let mergeInfo = (data as? NSDictionary)?.ofk("merged_by") as NSDictionary? {
					DLog("detected merged PR: %@", r.title)

					let mergeUserId = mergeInfo.ofk("id") as NSNumber? ?? NSNumber(int: -2)
					DLog("merged by user id: %@, our id is: %@", mergeUserId, r.apiServer.userId)

					let mergedByMyself = mergeUserId.isEqualToNumber(r.apiServer.userId ?? NSNumber(int: -1))

					if !(mergedByMyself && Settings.dontKeepPrsMergedByMe) {
						DLog("detected merged PR: %@", r.title)
						switch Settings.mergeHandlingPolicy {

						case PRHandlingPolicy.PullRequestHandlingKeepMine.rawValue:
							if (r.sectionIndex?.integerValue ?? 0)==PullRequestSection.All.rawValue { break }
							fallthrough

						case PRHandlingPolicy.PullRequestHandlingKeepAll.rawValue:
							r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this
							r.condition = PullRequestCondition.Merged.rawValue
							app.postNotificationOfType(PRNotificationType.PrMerged, forItem: r)

						default:
							break
						}
					} else {
						DLog("will not announce merged PR: %@", r.title)
					}
				} else {
					DLog("detected closed PR: %@", r.title)
					switch(Settings.closeHandlingPolicy) {

					case PRHandlingPolicy.PullRequestHandlingKeepMine.rawValue:
						if (r.sectionIndex?.integerValue ?? 0) == PullRequestSection.All.rawValue { break }
						fallthrough

					case PRHandlingPolicy.PullRequestHandlingKeepAll.rawValue:
						r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this
						r.condition = PullRequestCondition.Closed.rawValue
						app.postNotificationOfType(PRNotificationType.PrClosed, forItem:r)

					default:
						break
					}
				}
				self.CALLBACK(andCallback)

			}, failure: { (response, data, error) in
				r.postSyncAction = PostSyncAction.DoNothing.rawValue // don't delete this, we couldn't check, play it safe
				r.apiServer.lastSyncSucceeded = false
				self.CALLBACK(andCallback)
		})
	}

	func getRateLimitFromServer(apiServer:ApiServer, andCallback: ((Int64, Int64, Int64)->Void)?)
	{
		get("/rate_limit", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil,
			success: { (response, data) in
				if let c = andCallback {
					let allHeaders = response!.allHeaderFields
					let requestsRemaining = (allHeaders["X-RateLimit-Remaining"] as NSString).longLongValue
					let requestLimit = (allHeaders["X-RateLimit-Limit"] as NSString).longLongValue
					let epochSeconds = (allHeaders["X-RateLimit-Reset"] as NSString).longLongValue
					c(requestsRemaining, requestLimit, epochSeconds)
				}
			},
			failure: { (response, data, error) in
				if let c = andCallback {
					if response?.statusCode == 404 && data != nil && !((data as NSDictionary).ofk("message") as String == "Not Found") {
						c(10000, 10000, 0)
					} else {
						c(-1, -1, -1)
					}
				}
		})
	}

	func updateLimitsFromServer() {
		let allApiServers = ApiServer.allApiServersInMoc(mainObjectContext)
		let total = allApiServers.count
		var count = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo() {
				getRateLimitFromServer(apiServer, andCallback: { (remaining, limit, reset) in
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

	typealias completionBlockType = (()->Void)?
	private func CALLBACK(c: completionBlockType) {
		if let cExists = c { cExists() }
	}

	private func shouldScanForStatusesInMoc(moc: NSManagedObjectContext) -> Bool {
		if successfulRefreshesSinceLastStatusCheck % Settings.statusItemRefreshInterval == 0 {
			if Settings.showStatusItems { return true }
			for s in DataItem.allItemsOfType("PRStatus", inMoc:moc) as [PRStatus] { moc.deleteObject(s) }
		}
		return false
	}

	private func shouldScanForLabelsInMoc(moc: NSManagedObjectContext) -> Bool {
		if successfulRefreshesSinceLastLabelCheck % Settings.labelRefreshInterval == 0 {
			if Settings.showLabels { return true }
			for l in DataItem.allItemsOfType("PRLabel", inMoc:moc) as [PRLabel] { moc.deleteObject(l) }
		}
		return false
	}

	func syncWatchedReposFromServer(apiServer: ApiServer, andCallback:completionBlockType) {

		getPagedDataInPath("/user/subscriptions", fromServer: apiServer, startingFromPage: 1, parameters: nil, extraHeaders: nil,
			perPageCallback: { (data, lastPage) -> Bool in

				if let d = data as? [NSDictionary] {
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

			}, finalCallback: { (success, resultCode, etag) in
				if !success {
					DLog("Error while fetching data from %@", apiServer.label)
					apiServer.lastSyncSucceeded = false
				}
				self.CALLBACK(andCallback)
		})
	}

	func syncUserDetailsInMoc(moc: NSManagedObjectContext, andCallback:completionBlockType) {

		let allApiServers = ApiServer.allApiServersInMoc(moc)
		if allApiServers.count==0 {
			CALLBACK(andCallback)
			return
		}
		var completionCount = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo() {
				getDataInPath("/user", fromServer:apiServer, parameters:nil, extraHeaders:nil, andCallback: {
					(data, lastPage, resultCode, etag) in

					if let d = data as NSDictionary? {
						apiServer.userName = d.ofk("login") as? String
						apiServer.userId = d.ofk("id") as? NSNumber
					} else {
						DLog("Could not read user credentials from %@", apiServer.label)
						apiServer.lastSyncSucceeded = false
					}
					completionCount++
					if completionCount==allApiServers.count { self.CALLBACK(andCallback) }
				})
			} else {
				completionCount++
				if(completionCount==allApiServers.count) { CALLBACK(andCallback) }
			}
		}
	}

	func testApiToServer(apiServer: ApiServer, andCallback:((NSError?)->())?) {
		get("/rate_limit", fromServer: apiServer, ignoreLastSync: true, parameters: nil, extraHeaders: nil,
			success: { (_, _) -> Void in
				if let c = andCallback { c(nil) }
			},
			failure: { (response, data, error) in
				if response?.statusCode == 404 && data != nil && !((data as NSDictionary).ofk("message") as String == "Not Found") {
					if let c = andCallback { c(nil) }
				} else {
					if let c = andCallback { c(error) }
				}
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
		parameters: Dictionary<String,AnyObject>?,
		extraHeaders: Dictionary<String, String>?,
		perPageCallback: ((data: AnyObject?, lastPage: Bool)->Bool)?,
		finalCallback: ((success: Bool, resultCode: Int, etag: String?)->Void)?) {

			if path.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
				// handling empty or null fields as success, since we don't want syncs to fail, we simply have nothing to process
				dispatch_async(dispatch_get_main_queue(), {
					if let c = finalCallback {
						c(success: true, resultCode: -1, etag: nil)
					}
				})
				return
			}

			var mutableParams = parameters ?? [String:AnyObject]()
			mutableParams["page"] = startingFromPage
			mutableParams["per_page"] = 100

			getDataInPath(path, fromServer: fromServer, parameters: mutableParams, extraHeaders: extraHeaders) {
				(data, lastPage, resultCode, etag) in
				if let d: AnyObject = data {
					var isLastPage = lastPage
					if let p = perPageCallback {
						if p(data: d, lastPage: lastPage) { isLastPage = true }
						if isLastPage {
							if let c = finalCallback {
								c(success: true, resultCode: resultCode, etag: etag)
							}
						} else {
							self.getPagedDataInPath(path, fromServer: fromServer, startingFromPage: startingFromPage+1, parameters: parameters, extraHeaders: extraHeaders, perPageCallback: perPageCallback, finalCallback: finalCallback)
						}
					}
				} else {
					if let c = finalCallback {
						c(success: resultCode==304, resultCode: resultCode, etag: etag)
					}
				}
			}
	}


	private func getDataInPath(
		path: String,
		fromServer: ApiServer,
		parameters: Dictionary<String,AnyObject>?,
		extraHeaders: Dictionary<String, String>?,
		andCallback:((data: AnyObject?, lastPage: Bool, resultCode: Int, etag: String?)->Void)?) {

			get(path, fromServer: fromServer, ignoreLastSync: false, parameters: parameters, extraHeaders: extraHeaders,
				success: { (response, data) in

					let allHeaders = response!.allHeaderFields
					fromServer.requestsRemaining = NSNumber(longLong: (allHeaders["X-RateLimit-Remaining"] as NSString).longLongValue)
					fromServer.requestsLimit = NSNumber(longLong: (allHeaders["X-RateLimit-Limit"] as NSString).longLongValue)
					let epochSeconds = (allHeaders["X-RateLimit-Reset"] as NSString).doubleValue
					fromServer.resetDate = NSDate(timeIntervalSince1970: epochSeconds)
					NSNotificationCenter.defaultCenter().postNotificationName(API_USAGE_UPDATE, object: fromServer, userInfo: nil)

					if let c = andCallback {
						let etag = allHeaders["Etag"] as String?
						let code = response!.statusCode ?? 0
						c(data: data, lastPage: self.lastPage(response!), resultCode: code, etag: etag)
					}
				}, failure: { (response, data, error) in
					let code = response?.statusCode ?? 0
					if code == 304 {
						DLog("(%@) no change reported (304)", fromServer.label)
					} else {
						DLog("(%@) failure for %@: %@", fromServer.label, path,error)
					}
					if let c = andCallback {
						c(data: nil, lastPage: false, resultCode: code, etag: nil)
					}
			})
	}

	private func get(
		path:String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		parameters: Dictionary<String,AnyObject>?,
		extraHeaders: Dictionary<String, String>?,
		success: ((response: NSHTTPURLResponse?, data: AnyObject?)->Void)?,
		failure: ((response: NSHTTPURLResponse?, data: AnyObject?, error: NSError?)->Void)?) {

			var apiServerLabel: String
			if fromServer.lastSyncSucceeded?.boolValue ?? ignoreLastSync {
				apiServerLabel = fromServer.label ?? "(untitled server)"
			} else {
				if let fail = failure {
					let error = NSError(domain: "Server already inaccessible, saving the network call", code: -1, userInfo: nil)
					fail(response: nil, data: nil, error: error)
				}
				return
			}

			networkIndicationStart()
			let authToken = fromServer.authToken
			let apiPath = fromServer.apiPath ?? ""

			let o = NSBlockOperation {

				var expandedPath = startsWith(path, "/") ? apiPath.stringByAppendingPathComponent(path) : path

				if let params = parameters {
					var pairs = [String]()
					for (key,value) in params {
						pairs.append("\(key)=\(value)")
					}
					expandedPath = expandedPath + "?" + "&".join(pairs)
				}

				let r = NSMutableURLRequest(URL: NSURL(string: expandedPath)!, cachePolicy: NSURLRequestCachePolicy.UseProtocolCachePolicy, timeoutInterval: NETWORK_TIMEOUT)
				r.setValue(self.userAgent(), forHTTPHeaderField: "User-Agent")
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
				var existingBackOff = self.badLinks[fullUrlPath]
				if existingBackOff != nil {
					if NSDate().compare(existingBackOff!.nextAttemptAt) == NSComparisonResult.OrderedAscending {
						// report failure and return
						DLog("(%@) preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, fullUrlPath, existingBackOff!.nextAttemptAt)
						if let fail = failure {
							let error = NSError(domain: "Preempted fetch because of throttling", code: 400, userInfo: nil)
							dispatch_async(dispatch_get_main_queue(), {
								fail(response: nil, data: nil, error: error)
							});
						}
						self.networkIndicationEnd()
						return
					}
				}

				#if DEBUG
					let startTime = NSDate()
				#endif

				var error: NSError?
				var res: NSURLResponse?
				let data = NSURLConnection.sendSynchronousRequest(r, returningResponse: &res, error: &error)
				let response = res as? NSHTTPURLResponse

				#if DEBUG
					let networkTime = NSDate().timeIntervalSinceDate(startTime)
				#endif

				var parsedData: AnyObject?
				if data?.length > 0 {
					parsedData = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.allZeros, error:nil)
				}

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
							let newDuration = existingBackOff!.duration + BACKOFF_STEP
							self.badLinks[fullUrlPath] = UrlBackOffEntry(
								nextAttemptAt: NSDate(timeInterval: newDuration, sinceDate: NSDate()),
								duration: newDuration)
						}
					}
				}

				if error != nil {
					DLog("(%@) GET %@ - FAILED: %@", apiServerLabel, fullUrlPath, error!.localizedDescription)
					if let failed = failure {
						dispatch_async(dispatch_get_main_queue(), {
							failed(response: response, data: parsedData, error: error)
						})
					}
				} else {
					#if DEBUG
						DLog("(%@) GET %@ - RESULT: %d, %f sec.", apiServerLabel, fullUrlPath, response?.statusCode, networkTime)
						#else
						DLog("(%@) GET %@ - RESULT: %d", apiServerLabel, fullUrlPath, response?.statusCode)
					#endif
					self.badLinks.removeValueForKey(fullUrlPath)
					if let succeeded = success {
						dispatch_async(dispatch_get_main_queue(), {
							succeeded(response: response, data: parsedData)
						})
					}
				}

				self.networkIndicationEnd()
			}
			o.queuePriority = NSOperationQueuePriority.High
			addOperation(o)
	}

	private func userAgent() -> String {
		#if DEBUG
			#if os(iOS)
				return "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Development"
				#else
				return "HouseTrip-Trailer-v\(currentAppVersion)-OSX-Development"
			#endif
			#else
			#if os(iOS)
			return "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Release"
			#else
			return "HouseTrip-Trailer-v\(currentAppVersion)-OSX-Release"
			#endif
		#endif
	}

	private func networkIndicationStart() {
		#if os(iOS)
			dispatch_async(dispatch_get_main_queue(), {
			if ++self.networkIndicationCount==1 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = true
			}
			})
		#endif
	}
	
	private func networkIndicationEnd() {
		#if os(iOS)
			dispatch_async(dispatch_get_main_queue(), {
			if --self.networkIndicationCount==0 {
			UIApplication.sharedApplication().networkActivityIndicatorVisible = false
			}
			})
		#endif
	}
}
