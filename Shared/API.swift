
import CoreData
#if os(iOS)
import UIKit
#endif

final class API {

	private struct UrlBackOffEntry {
		var nextAttemptAt: Date
		var duration: TimeInterval
	}

	var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
	var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
	var currentNetworkStatus: NetworkStatus

	private let cacheDirectory: String
	private let urlSession: URLSession
	private var badLinks = [String:UrlBackOffEntry]()
	private let reachability = Reachability.forInternetConnection()!

	init() {

		reachability.startNotifier()
		let n = reachability.currentReachabilityStatus()
		DLog("Network is %@", n == NetworkStatus.NotReachable ? "down" : "up")
		currentNetworkStatus = n

		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: FileManager.SearchPathDirectory.cachesDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).first!
		cacheDirectory = appSupportURL.appendingPathComponent("com.housetrip.Trailer").path

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

		let config = URLSessionConfiguration.default
		config.httpShouldUsePipelining = true
		config.httpAdditionalHeaders = ["User-Agent" : userAgent]
		urlSession = URLSession(configuration: config)

		if fileManager.fileExists(atPath: cacheDirectory) {
			expireOldImageCacheEntries()
		} else {
			do { try fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true, attributes: nil) } catch _ {}
		}

		NotificationCenter.default.addObserver(forName: NSNotification.Name.reachabilityChanged, object: nil, queue: OperationQueue.main) { [weak self] n in
			self?.checkNetworkAvailability()
			if self?.currentNetworkStatus != NetworkStatus.NotReachable {
				app.startRefreshIfItIsDue()
			}
		}
	}

	private func checkNetworkAvailability() {
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
		if appIsRefreshing {
			let operations = apiRunningCount+apiCallQueue.count
			if operations < 2 {
				return "Refreshing..."
			} else {
				return "Refreshing... (\(operations) calls remaining)"
			}
		} else if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
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

	func expireOldImageCacheEntries() {

		do {
			let now = Date()
			let fileManager = FileManager.default
			for f in try fileManager.contentsOfDirectory(atPath: cacheDirectory) {
				if f.characters.starts(with: "imgcache-".characters) {
					do {
						let path = cacheDirectory.stringByAppendingPathComponent(f)
						let attributes = try fileManager.attributesOfItem(atPath: path)
						let date = attributes[FileAttributeKey.creationDate] as! Date
						if now.timeIntervalSince(date) > (3600.0*24.0) {
							try fileManager.removeItem(atPath: path)
						}
					} catch {
						DLog("File error when cleaning old cached image: %@", (error as NSError).localizedDescription)
					}
				}
			}
		} catch { /* No directory */ }
	}

	// Warning: Calls back on thread!!
	private func getImage(_ url: URL, completion:(data: Data?) -> Void) {

		let task = urlSession.dataTask(with: url) { [weak self] data, response, error in

			let r = response as? HTTPURLResponse
			if error != nil || response == nil || r?.statusCode > 299 || (r?.expectedContentLength ?? 0) < Int64(data?.count ?? 0) {
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
			task.priority = URLSessionTask.highPriority
			delay(0.1, self) { S in
				S.networkIndicationStart()
			}
		#endif

		task.resume()
	}

	func haveCachedAvatar(_ path: String, tryLoadAndCallback: (IMAGE_CLASS?, String) -> Void) -> Bool {

		#if os(iOS)
			let imgsize = 40.0*GLOBAL_SCREEN_SCALE
		#else
			let imgsize = 88
		#endif
		let connector = path.characters.contains("?") ? "&" : "?"
		let absolutePath = "\(path)\(connector)s=\(imgsize)"
		let imageKey = "\(absolutePath) \(currentAppVersion())"
		let cachePath = cacheDirectory.stringByAppendingPathComponent("imgcache-\(imageKey.md5hash)")
		
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: cachePath) {
			#if os(iOS)
				let imgData = NSData(contentsOfFile: cachePath)
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
					tryLoadAndCallback(r, cachePath)
				}
				return true
			} else {
				try! fileManager.removeItem(atPath: cachePath)
			}
		}

		getImage(URL(string: absolutePath)!) { data in

			var result: IMAGE_CLASS?
            #if os(iOS)
                if let d = data, let i = IMAGE_CLASS(data: d, scale:GLOBAL_SCREEN_SCALE) {
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
				tryLoadAndCallback(result, cachePath)
			}
        }
		return false
	}

	////////////////////////////////////// API interface

	func syncItemsForActiveReposAndCallback(_ processingCallback: Completion?, callback: Completion) {
		let syncContext = DataManager.childContext()

		let shouldRefreshReposToo = lastRepoCheck == Date.distantPast
			|| (Date().timeIntervalSince(lastRepoCheck) > TimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| !Repo.anyVisibleReposInMoc(syncContext)

		if shouldRefreshReposToo {
			fetchRepositoriesToMoc(syncContext) { [weak self] in
				self?.syncToMoc(syncContext, processingCallback: processingCallback, callback: callback)
			}
		} else {
			ApiServer.resetSyncSuccessInMoc(syncContext)
			ensureApiServersHaveUserIdsInMoc(syncContext) { [weak self] in
				self?.syncToMoc(syncContext, processingCallback: processingCallback, callback: callback)
			}
		}
	}

	private func syncToMoc(_ moc: NSManagedObjectContext, processingCallback: Completion?, callback: Completion) {

		markDirtyReposInMoc(moc) { [weak self] in
			guard let S = self else { return }

			let repos = Repo.syncableReposInMoc(moc)

			var completionCount = 0
			let totalOperations = 2
			let completionCallback: Completion = {
				completionCount += 1
				if completionCount == totalOperations {
					processingCallback?()
					for r in repos { r.dirty = false }
					S.completeSyncInMoc(moc, andCallback: callback)
				}
			}

			S.fetchIssuesForRepos(repos, toMoc: moc) {
				S.fetchCommentsForCurrentIssuesToMoc(moc) {
					S.checkIssueClosuresInMoc(moc)
					completionCallback()
				}
			}

			S.fetchPullRequestsForRepos(repos, toMoc: moc) {
				S.updatePullRequestsInMoc(moc) {
					completionCallback()
				}
			}
		}
	}

	private func completeSyncInMoc(_ moc: NSManagedObjectContext, andCallback: Completion) {

		DLog("Wrapping up sync")

		// discard any changes related to any failed API server
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if !apiServer.syncIsGood {
				apiServer.rollBackAllUpdatesInMoc(moc)
				apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
			}
		}

		let mainQueue = OperationQueue.main

		mainQueue.addOperation {
			DataItem.nukeDeletedItemsInMoc(moc)
			CacheEntry.cleanOldEntriesInMoc(moc)
		}

		for r in DataItem.itemsOfType("PullRequest", surviving: true, inMoc: moc) as! [PullRequest] {
			mainQueue.addOperation {
				r.postProcess()
			}
		}

		for i in DataItem.itemsOfType("Issue", surviving: true, inMoc: moc) as! [Issue] {
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

	private func updatePullRequestsInMoc(_ moc: NSManagedObjectContext, callback: Completion) {

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

	private func markDirtyReposInMoc(_ moc: NSManagedObjectContext, callback: Completion) {

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

	private func fetchUserTeamsFromApiServer(_ apiServer: ApiServer, callback: Completion) {

		for t in apiServer.teams {
			t.postSyncAction = PostSyncAction.delete.rawValue
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

	private func markDirtyRepoIds(_ repoIdsToMarkDirty: NSMutableSet, usingUserEventsFromServer s: ApiServer, callback: Completion) {

		if !s.syncIsGood {
			callback()
			return
		}

		var latestDate = s.latestUserEventDateProcessed
		if latestDate == nil {
			latestDate = Date.distantPast
			s.latestUserEventDateProcessed = latestDate
		}

		let userName = S(s.userName)
		let serverLabel = S(s.label)

		getPagedDataInPath("/users/\(userName)/events",
			fromServer: s,
			startingFromPage: 1,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = parseGH8601(d["created_at"] as? String) ?? Date.distantPast
					if latestDate!.compare(eventDate) == .orderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
							repoIdsToMarkDirty.add(repoId)
						}
						if s.latestUserEventDateProcessed!.compare(eventDate) == .orderedAscending {
							s.latestUserEventDateProcessed = eventDate
							if latestDate! == Date.distantPast {
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

	private func markDirtyRepoIds(_ repoIdsToMarkDirty: NSMutableSet, usingReceivedEventsFromServer s: ApiServer, callback: Completion) {

		if !s.syncIsGood {
			callback()
			return
		}

		var latestDate = s.latestReceivedEventDateProcessed
		if latestDate == nil {
			latestDate = Date.distantPast
			s.latestReceivedEventDateProcessed = latestDate
		}

		let userName = S(s.userName)
		let serverLabel = S(s.label)

		getPagedDataInPath("/users/\(userName)/received_events",
			fromServer: s,
			startingFromPage: 1,
			perPageCallback: { data, lastPage in
				for d in data ?? [] {
					let eventDate = parseGH8601(d["created_at"] as? String) ?? Date.distantPast
					if latestDate!.compare(eventDate) == .orderedAscending { // this is where we came in
						if let repoId = d["repo"]?["id"] as? NSNumber {
							DLog("(%@) New event at %@ from Repo ID %@", serverLabel, eventDate, repoId)
							repoIdsToMarkDirty.add(repoId)
						}
						if s.latestReceivedEventDateProcessed!.compare(eventDate) == .orderedAscending {
							s.latestReceivedEventDateProcessed = eventDate
							if latestDate! == Date.distantPast {
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

	func fetchRepositoriesToMoc(_ moc: NSManagedObjectContext, callback: Completion) {

		ApiServer.resetSyncSuccessInMoc(moc)
		clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

		syncUserDetailsInMoc(moc) { [weak self] in
			for r in DataItem.itemsOfType("Repo", surviving: true, inMoc: moc) as! [Repo] {
				r.postSyncAction = PostSyncAction.delete.rawValue
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
							app.postNotificationOfType(type: .newRepoAnnouncement, forItem:r)
						}
					}
					lastRepoCheck = Date()
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

	private func fetchPullRequestsForRepos(_ repos: [Repo], toMoc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableReposInMoc(toMoc) {
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.delete.rawValue
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
				if (p.condition?.intValue ?? 0) == ItemCondition.open.rawValue {
					p.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForPrs?.intValue != RepoDisplayPolicy.hide.rawValue {
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

	private func handleRepoSyncFailure(_ r: Repo, withResultCode: Int) {
		if withResultCode == 404 { // repo disabled
			r.inaccessible = true
			r.postSyncAction = PostSyncAction.doNothing.rawValue
			for p in r.pullRequests {
				p.postSyncAction = PostSyncAction.delete.rawValue
			}
			for i in r.issues {
				i.postSyncAction = PostSyncAction.delete.rawValue
			}
		} else if withResultCode==410 { // repo gone for good
			r.postSyncAction = PostSyncAction.delete.rawValue
		} else { // fetch problem
			r.apiServer.lastSyncSucceeded = false
		}
	}

	private func fetchIssuesForRepos(_ repos: [Repo], toMoc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableReposInMoc(toMoc) {
			for i in r.issues {
				i.postSyncAction = PostSyncAction.delete.rawValue
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
				if (i.condition?.intValue ?? 0) == ItemCondition.open.rawValue {
					i.postSyncAction = PostSyncAction.delete.rawValue
				}
			}

			let apiServer = r.apiServer

			if apiServer.syncIsGood && r.displayPolicyForIssues?.intValue != RepoDisplayPolicy.hide.rawValue {
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

	private func fetchCommentsForCurrentPullRequestsToMoc(_ moc: NSManagedObjectContext, callback: Completion) {

		let prs = (DataItem.newOrUpdatedItemsOfType("PullRequest", inMoc:moc) as! [PullRequest]).filter({ pr in
			return pr.apiServer.syncIsGood
		})
		if prs.count==0 {
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

		let completionCallback: Completion = {
			completionCount += 1
			if completionCount == totalOperations { callback() }
		}

		_fetchCommentsForPullRequests(prs, issues: true, inMoc: moc, callback: completionCallback)
		_fetchCommentsForPullRequests(prs, issues: false, inMoc: moc, callback: completionCallback)
	}

	private func _fetchCommentsForPullRequests(_ prs: [PullRequest], issues: Bool, inMoc: NSManagedObjectContext, callback: Completion) {

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

	private func fetchCommentsForCurrentIssuesToMoc(_ moc: NSManagedObjectContext, callback: Completion) {

		let allIssues = DataItem.newOrUpdatedItemsOfType("Issue", inMoc:moc) as! [Issue]

		for i in allIssues {
			for c in i.comments {
				c.postSyncAction = PostSyncAction.delete.rawValue
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

	private func fetchLabelsForForCurrentPullRequestsToMoc(_ moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.activeInMoc(moc, visibleOnly: true).filter { [weak self] pr in
			if !pr.apiServer.syncIsGood {
				return false
			}
			if pr.condition?.intValue != ItemCondition.open.rawValue {
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
				l.postSyncAction = PostSyncAction.delete.rawValue
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

	private func fetchStatusesForCurrentPullRequestsToMoc(_ moc: NSManagedObjectContext, callback: Completion) {

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
				s.postSyncAction = PostSyncAction.delete.rawValue
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

	private func checkPrClosuresInMoc(_ moc: NSManagedObjectContext, callback: Completion) {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.delete.rawValue, ItemCondition.open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = try! moc.fetch(f)

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return parent.shouldSync && ((parent.postSyncAction?.intValue ?? 0) != PostSyncAction.delete.rawValue) && r.apiServer.syncIsGood
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

	private func checkIssueClosuresInMoc(_ moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.predicate = NSPredicate(format: "postSyncAction == %d and condition == %d", PostSyncAction.delete.rawValue, ItemCondition.open.rawValue)
		f.returnsObjectsAsFaults = false

		for i in try! moc.fetch(f) {
			let r = i.repo
			if r.shouldSync && ((r.postSyncAction?.intValue ?? 0) != PostSyncAction.delete.rawValue) && r.apiServer.syncIsGood {
				itemWasClosed(i)
			}
		}
	}

	private func detectAssignedPullRequestsInMoc(_ moc: NSManagedObjectContext, callback: Completion) {

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
					if let d = data as? [NSObject : AnyObject], let assigneeInfo = d["assignee"] as? [NSObject : AnyObject], let assignee = assigneeInfo["login"] as? String {
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

	private func ensureApiServersHaveUserIdsInMoc(_ moc: NSManagedObjectContext, callback: Completion) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServersInMoc(moc) {
			if (apiServer.userId?.intValue ?? 0) == 0 {
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

	private func investigatePrClosureFor(_ r: PullRequest, callback: Completion) {
		DLog("Checking closed PR to see if it was merged: %@", r.title)

		let repoFullName = S(r.repo.fullName)
		let repoNumber = S(r.number?.stringValue)
		let path = "/repos/\(repoFullName)/pulls/\(repoNumber)"

		getDataInPath(path, fromServer: r.apiServer) { [weak self] data, lastPage, resultCode in

			if let d = data as? [NSObject : AnyObject] {
				if let mergeInfo = d["merged_by"] as? [NSObject : AnyObject], let mergeUserId = mergeInfo["id"] as? NSNumber {
					self?.prWasMerged(r, byUserId: mergeUserId)
				} else {
					self?.itemWasClosed(r)
				}
			} else if resultCode == 404 || resultCode == 410 { // PR gone for good
				self?.itemWasClosed(r)
			} else { // fetch/server problem
				r.postSyncAction = PostSyncAction.doNothing.rawValue // don't delete this, we couldn't check, play it safe
				r.apiServer.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private func prWasMerged(_ r: PullRequest, byUserId: NSNumber) {

		let myUserId = r.apiServer.userId ?? NSNumber(value: -1)
		DLog("Detected merged PR: %@ by user %@, local user id is: %@, handling policy is %@, coming from section %@",
			r.title,
			byUserId,
			myUserId,
			NSNumber(value: Settings.mergeHandlingPolicy),
			r.sectionIndex ?? NSNumber(value: 0))

        if !r.isVisibleOnMenu {
            DLog("Merged PR was hidden, won't announce")
            return
        }

		let mergedByMe = byUserId.isEqual(to: myUserId)
		if !(mergedByMe && Settings.dontKeepPrsMergedByMe) {
			DLog("Checking if we want to keep this merged PR")
			if r.shouldKeepForPolicy(Settings.mergeHandlingPolicy) {
				DLog("Will keep merged PR")
				r.keepWithCondition(.merged, notification: .prMerged)
				return
			}
		}
		DLog("Will not keep merged PR")
	}

	private func itemWasClosed(_ i: ListableItem) {
		DLog("Detected closed item: %@, handling policy is %@, coming from section %@",
			i.title,
			NSNumber(value: Settings.closeHandlingPolicy),
			i.sectionIndex ?? NSNumber(value: 0))

        if !i.isVisibleOnMenu {
            DLog("Closed item was hidden, won't announce")
            return
        }

		if i.shouldKeepForPolicy(Settings.closeHandlingPolicy) {
			DLog("Will keep closed item")
			i.keepWithCondition(.closed, notification: i is Issue ? .issueClosed : .prClosed)
		} else {
			DLog("Will not keep closed item")
		}
	}

	private func getRateLimitFromServer(_ apiServer: ApiServer, callback: (Int64, Int64, Int64)->Void)
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
					apiServer.requestsRemaining = NSNumber(value: remaining)
					apiServer.requestsLimit = NSNumber(value: limit)
					count += 1
					if count==total {
						NotificationCenter.default.post(name: Notification.Name(rawValue: API_USAGE_UPDATE), object: apiServer, userInfo: nil)
					}
				}
			}
		}
	}

	private func shouldScanForStatusesInMoc(_ moc: NSManagedObjectContext) -> Bool {
		if Settings.showStatusItems {
			return true
		} else {
			refreshesSinceLastStatusCheck.removeAll()
			for s in DataItem.allItemsOfType("PRStatus", inMoc: moc) {
				s.postSyncAction = PostSyncAction.delete.rawValue
			}
			return false
		}
	}

	private func shouldScanForLabelsInMoc(_ moc: NSManagedObjectContext) -> Bool {
		if Settings.showLabels {
			return true
		} else {
			refreshesSinceLastLabelsCheck.removeAll()
			for l in DataItem.allItemsOfType("PRLabel", inMoc: moc) {
				l.postSyncAction = PostSyncAction.delete.rawValue
			}
			return false
		}
	}

	private func syncWatchedReposFromServer(_ apiServer: ApiServer, callback: Completion) {

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

	private func syncUserDetailsInMoc(_ moc: NSManagedObjectContext, callback: Completion) {

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
		badLinks.removeAll(keepingCapacity: false)
	}

	func testApiToServer(_ apiServer: ApiServer, callback: (NSError?) -> ()) {
		clearAllBadLinks()
		api("/user", fromServer: apiServer, ignoreLastSync: true) { [weak self] code, headers, data, error, shouldRetry in

			if let d = data as? [NSObject : AnyObject], let userName = d["login"] as? String, let userId = d["id"] as? NSNumber, error == nil {
				if userName.isEmpty || userId.int64Value <= 0 {
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

	private func apiError(_ message: String) -> NSError {
		return NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	//////////////////////////////////////////////////////////// low level

	private func getPagedDataInPath(
		_ path: String,
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
		_ path: String,
		fromServer: ApiServer,
		callback:(data: AnyObject?, lastPage: Bool, resultCode: Int) -> Void) {

		attemptToGetDataInPath(path, fromServer: fromServer, callback: callback, attemptCount: 0)
	}

	private func attemptToGetDataInPath(
		_ path: String,
		fromServer: ApiServer,
		callback:(data: AnyObject?, lastPage: Bool, resultCode: Int) -> Void,
		attemptCount: Int) {

		api(path, fromServer: fromServer, ignoreLastSync: false) { [weak self] c, headers, data, error, shouldRetry in

			let code = c ?? 0

			if error == nil {
				var lastPage = true
				if let allHeaders = headers {

					if let v = allHeaders["X-RateLimit-Remaining"] as? String {
						fromServer.requestsRemaining = NSNumber(value: Int64(v) ?? 0)
					} else {
						fromServer.requestsRemaining = 10000
					}

					if let v = allHeaders["X-RateLimit-Limit"] as? String {
						fromServer.requestsLimit = NSNumber(value: Int64(v) ?? 0)
					} else {
						fromServer.requestsLimit = 10000
					}

					if let v = allHeaders["X-RateLimit-Reset"] as? String {
						fromServer.resetDate = Date(timeIntervalSince1970: Double(v) ?? 0)
					} else {
						fromServer.resetDate = nil
					}

					if let linkHeader = allHeaders["Link"] as? String {
						lastPage = !linkHeader.contains("rel=\"next\"")
					}

					NotificationCenter.default.post(name: Notification.Name(rawValue: API_USAGE_UPDATE), object: fromServer, userInfo: nil)
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

	private var apiRunningCount = 0
	private var apiCallQueue = [Completion]()
	private func api(
		_ path: String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		completion: ApiCompletion) {

		#if os(iOS)
			let maxOperations = 4
		#else
			let maxOperations = 8
		#endif

		if apiRunningCount < maxOperations {
			_api(path, fromServer: fromServer, ignoreLastSync: ignoreLastSync, completion: completion)
		} else {
			apiCallQueue.append { [weak self] in
				self?._api(path, fromServer: fromServer, ignoreLastSync: ignoreLastSync, completion: completion)
			}
		}
	}
	private func updateApiProgress() {
		NotificationCenter.default.post(Notification(name: Notification.Name(rawValue: kSyncProgressUpdate), object: nil, userInfo: nil))
	}
	private func dequeueApi() {
		apiRunningCount -= 1
		if apiCallQueue.count > 0 {
			apiCallQueue.removeFirst()()
		} else {
			updateApiProgress()
		}
	}

	private func _api(
		_ path: String,
		fromServer: ApiServer,
		ignoreLastSync: Bool,
		completion: ApiCompletion) {

		apiRunningCount += 1
		updateApiProgress()

		let apiServerLabel: String
		if fromServer.syncIsGood || ignoreLastSync {
			apiServerLabel = S(fromServer.label)
		} else {
			atNextEvent(self) { S in
				let e = S.apiError("Sync has failed, skipping this call")
				completion(code: nil, headers: nil, data: nil, error: e, shouldRetry: false)
				S.dequeueApi()
			}
			return
		}

		let expandedPath = path.characters.starts(with: "/".characters) ? S(fromServer.apiPath).stringByAppendingPathComponent(path) : path
		let url = URL(string: expandedPath)!

		var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)
		r.setValue("application/vnd.github.v3+json", forHTTPHeaderField:"Accept")
		if let a = fromServer.authToken {
			r.setValue("token \(a)", forHTTPHeaderField: "Authorization")
		}

		////////////////////////// preempt with error backoff algorithm
		let existingBackOff = badLinks[expandedPath]
		if let eb = existingBackOff {
			if Date().timeIntervalSince1970 < eb.nextAttemptAt.timeIntervalSince1970 {
				// report failure and return
				DLog("(%@) Preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, expandedPath, eb.nextAttemptAt)
				atNextEvent(self) { S in
					let e = S.apiError("Preempted fetch because of throttling")
					completion(code: nil, headers: nil, data: nil, error: e, shouldRetry: false)
					S.dequeueApi()
				}
				return
			}
			else {
				badLinks.removeValue(forKey: expandedPath)
			}
		}

		/////////////////////// 60 second dumb-caching
		let cacheKey = "\(fromServer.objectID.uriRepresentation().absoluteString) \(expandedPath)"
		let previousCacheEntry = CacheEntry.entryForKey(cacheKey)?.cacheUnit() // move data out of thread-specific context
		if let p = previousCacheEntry {
			if p.lastFetched.timeIntervalSince1970 > Date(timeIntervalSinceNow: -60).timeIntervalSince1970, let parsedData = p.parsedData() {
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

		let task = urlSession.dataTask(with: r) { [weak self] data, res, e in

			let response = res as? HTTPURLResponse
			var parsedData: AnyObject?
			var error = e as? NSError
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
			} else if (response?.expectedContentLength ?? 0) > Int64(data?.count ?? 0) {
				shouldRetry = true // truncation
				error = self?.apiError("Server data was truncated")
			} else {
				DLog("(%@) GET %@ - RESULT: %d", apiServerLabel, expandedPath, code)
				if let d = data {
					parsedData = try? JSONSerialization.jsonObject(with: d, options: JSONSerialization.ReadingOptions())
					if let h = headers, let e = h["Etag"] as? String {
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
		}
		task.resume()
	}

	private func handleResponse(_ data: Data?,
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
					backoff.nextAttemptAt = Date(timeInterval: existingBackOff!.duration, since:Date())
					badLinks[urlPath] = backoff
				} else {
					DLog("(%@) Placing URL %@ on the throttled list", serverLabel, urlPath)
					badLinks[urlPath] = UrlBackOffEntry(
						nextAttemptAt: Date().addingTimeInterval(BACKOFF_STEP),
						duration: BACKOFF_STEP)
				}
			}
			DLog("(%@) GET %@ - FAILED: (code %d) %@", serverLabel, urlPath, code, error!.localizedDescription)
		}

		if Settings.dumpAPIResponsesInConsole, let d = data {
			DLog("API data from %@: %@", urlPath, NSString(data: d, encoding: String.Encoding.utf8.rawValue))
		}

		completion(code: code, headers: headers, data: parsedData, error: error, shouldRetry: shouldRetry)

		dequeueApi()
	}

	#if os(iOS)

	private var networkBGTask = UIBackgroundTaskInvalid
	private var networkBGEndPopTimer: PopTimer?
	private var networkIndicationCount = 0

	func networkIndicationStart() {
		networkIndicationCount += 1
		if networkIndicationCount == 1 {
			let a = UIApplication.shared
			a.isNetworkActivityIndicatorVisible = true
			networkBGTask = a.beginBackgroundTask(withName: "com.housetrip.Trailer.imageload") { [weak self] in
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
			UIApplication.shared.isNetworkActivityIndicatorVisible = false
			networkBGEndPopTimer?.push()
		}
	}

	private func endNetworkBGTask() {
		if networkBGTask != UIBackgroundTaskInvalid {
			UIApplication.shared.endBackgroundTask(networkBGTask)
			networkBGTask = UIBackgroundTaskInvalid
		}
	}
	
	#endif
}
