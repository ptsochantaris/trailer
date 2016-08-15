
import CoreData
#if os(iOS)
import UIKit
#endif

final class API {

	private struct UrlBackOffEntry {
		var nextAttemptAt: Date
		var nextIncrement: TimeInterval
	}

	var refreshesSinceLastStatusCheck = [NSManagedObjectID : Int]()
	var refreshesSinceLastLabelsCheck = [NSManagedObjectID : Int]()
	var currentNetworkStatus: NetworkStatus

	private let cacheDirectory: String
	private let urlSession: URLSession
	private var badLinks = [String : UrlBackOffEntry]()
	private let reachability = Reachability()
	private let backOffIncrement: TimeInterval = 120

	init() {

		reachability.startNotifier()

		let n = reachability.status
		DLog("Network is %@", n.name)
		currentNetworkStatus = n

		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
		cacheDirectory = appSupportURL.appendingPathComponent("com.housetrip.Trailer").path

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

		let config = URLSessionConfiguration.default
		config.httpShouldUsePipelining = true
		config.httpAdditionalHeaders = ["User-Agent" : userAgent]
		urlSession = URLSession(configuration: config)

		if fileManager.fileExists(atPath: cacheDirectory) {
			expireOldImageCacheEntries()
		} else {
			try! fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
		}

		NotificationCenter.default.addObserver(forName: ReachabilityChangedNotification, object: nil, queue: .main) { [weak self] n in
			guard let s = self else { return }
			s.checkNetworkAvailability()
			if s.currentNetworkStatus != .NotReachable {
				app.startRefreshIfItIsDue()
			}
		}
	}

	private func checkNetworkAvailability() {
		let newStatus = reachability.status
		if newStatus != currentNetworkStatus {
			currentNetworkStatus = newStatus
			DLog("Network changed to %@", newStatus.name)
			clearAllBadLinks()
		}
	}

	var hasNetworkConnection: Bool {
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

	var lastUpdateDescription: String {
		if appIsRefreshing {
			let operations = apiRunningCount+apiCallQueue.count
			if operations < 2 {
				return "Refreshing..."
			} else {
				return "Refreshing... (\(operations) calls remaining)"
			}
		} else if ApiServer.shouldReportRefreshFailure(in: mainObjectContext) {
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

	private func expireOldImageCacheEntries() {

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
					DLog("File error when cleaning old cached image: %@", (error as NSError).localizedDescription)
				}
			}
		}
	}

	func haveCachedAvatar(from path: String, tryLoadAndCallback: (IMAGE_CLASS?, String) -> Void) -> Bool {

		func getImage(at path: String, completion:(data: Data?) -> Void) {

			let url = URL(string: path)!
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

		let connector = path.contains("?") ? "&" : "?"
		let absolutePath = "\(path)\(connector)s=\(THUMBNAIL_SIDE)"
		let imageKey = "\(absolutePath) \(currentAppVersion)"
		let cachePath = cacheDirectory.appending(pathComponent: "imgcache-\(imageKey.md5hashed).jpg")
		
		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: cachePath) {
			#if os(iOS)
				let imgData = try? Data(contentsOf: URL(fileURLWithPath: cachePath))
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

		getImage(at: absolutePath) { data in

			var result: IMAGE_CLASS?
            #if os(iOS)
                if let d = data, let i = IMAGE_CLASS(data: d, scale: GLOBAL_SCREEN_SCALE) {
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
		let syncContext = DataManager.buildChildContext()

		let shouldRefreshReposToo = lastRepoCheck == .distantPast
			|| (Date().timeIntervalSince(lastRepoCheck) > TimeInterval(Settings.newRepoCheckPeriod*3600.0))
			|| !Repo.anyVisibleRepos(in: syncContext)

		if shouldRefreshReposToo {
			fetchRepositories(to: syncContext) { [weak self] in
				self?.sync(to: syncContext, processingCallback: processingCallback, callback: callback)
			}
		} else {
			ApiServer.resetSyncSuccess(in: syncContext)
			ensureApiServersHaveUserIds(in: syncContext) { [weak self] in
				self?.sync(to: syncContext, processingCallback: processingCallback, callback: callback)
			}
		}
	}

	private func sync(to moc: NSManagedObjectContext, processingCallback: Completion?, callback: Completion) {

		markDirtyRepos(in: moc) { [weak self] in
			guard let S = self else { return }

			let repos = Repo.syncableRepos(in: moc)

			var completionCount = 0
			let totalOperations = 2
			let completionCallback: Completion = {
				completionCount += 1
				if completionCount == totalOperations {
					processingCallback?()
					for r in repos { r.dirty = false }
					S.completeSync(in: moc, andCallback: callback)
				}
			}

			S.fetchIssues(for: repos, to: moc) {
				S.fetchCommentsForCurrentIssues(to: moc) {
					S.checkIssueClosures(in: moc)
					completionCallback()
				}
			}

			S.fetchPullRequests(for: repos, to: moc) {
				S.updatePullRequests(in: moc) {
					completionCallback()
				}
			}
		}
	}

	private func completeSync(in moc: NSManagedObjectContext, andCallback: Completion) {

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
			CacheEntry.cleanOldEntries(in: moc)
		}

		for r in DataItem.items(of: PullRequest.self, surviving: true, in: moc) {
			mainQueue.addOperation {
				r.postProcess()
			}
		}

		for i in DataItem.items(of: Issue.self, surviving: true, in: moc) {
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

	private func updatePullRequests(in moc: NSManagedObjectContext, callback: Completion) {

		let willScanForStatuses = shouldScanForStatuses(in: moc)
		let willScanForLabels = shouldScanForLabels(in: moc)

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
			fetchStatusesForCurrentPullRequests(to: moc, callback: completionCallback)
		}
		if willScanForLabels {
			fetchLabelsForForCurrentPullRequests(to: moc, callback: completionCallback)
		}
		fetchCommentsForCurrentPullRequests(to: moc, callback: completionCallback)
		checkPrClosures(in: moc, callback: completionCallback)
		detectAssignedPullRequests(in: moc, callback: completionCallback)
	}

	private func markDirtyRepos(in moc: NSManagedObjectContext, callback: Completion) {

		let allApiServers = ApiServer.allApiServers(in: moc)
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
					Repo.markDirtyReposWithIds(repoIdsToMarkDirty, in: moc)
					DLog("Marked %d dirty repos that have new events in their event stream", repoIdsToMarkDirty.count)
				}

				let reposNotRecentlyDirtied = Repo.reposNotRecentlyDirtied(in: moc)
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
			if apiServer.goodToGo && apiServer.lastSyncSucceeded {
				markDirty(repoIds: repoIdsToMarkDirty, usingUserEventsFrom: apiServer, callback: completionCallback)
				markDirty(repoIds: repoIdsToMarkDirty, usingReceivedEventsFrom: apiServer, callback: completionCallback)
			} else {
				completionCallback()
				completionCallback()
			}
		}
	}

	private func fetchUserTeams(from server: ApiServer, callback: Completion) {

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

	private func markDirty(repoIds toMarkDirty: NSMutableSet, usingUserEventsFrom server: ApiServer, callback: Completion) {

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
					if let repoId = d["repo"]?["id"] as? NSNumber {
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

	private func markDirty(repoIds toMarkDirty: NSMutableSet, usingReceivedEventsFrom server: ApiServer, callback: Completion) {

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
					if let repoId = d["repo"]?["id"] as? NSNumber {
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

	func fetchRepositories(to moc: NSManagedObjectContext, callback: Completion) {

		ApiServer.resetSyncSuccess(in: moc)
		clearAllBadLinks() // otherwise inaccessible repos may get a cached error response, even if they have become available

		syncUserDetails(in: moc) { [weak self] in
			for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
				r.postSyncAction = PostSyncAction.delete.rawValue
			}

			let allApiServers = ApiServer.allApiServers(in: moc)
			let totalOperations = allApiServers.count*2
			var completionCount = 0

			let completionCallback: Completion = {
				completionCount += 1
				if completionCount == totalOperations {
					for r in DataItem.newItems(of: Repo.self, in: moc) {
						r.displayPolicyForPrs = Int64(Settings.displayPolicyForNewPrs)
						r.displayPolicyForIssues = Int64(Settings.displayPolicyForNewIssues)
						if r.shouldSync {
							app.postNotification(type: .newRepoAnnouncement, for: r)
						}
					}
					lastRepoCheck = Date()
					callback()
				}
			}

			for apiServer in allApiServers {
				if apiServer.goodToGo {
					self?.syncWatchedRepos(from: apiServer, callback: completionCallback)
					self?.fetchUserTeams(from: apiServer, callback: completionCallback)
				} else {
					completionCallback()
					completionCallback()
				}
			}
		}
	}

	private func fetchPullRequests(for repos: [Repo], to moc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableRepos(in: moc) {
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
				}) { [weak self] success, resultCode in
					if !success {
						self?.handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
					completionCount += 1
					if completionCount==total {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func handleRepoSyncFailure(repo: Repo, resultCode: Int64) {
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

	private func fetchIssues(for repos: [Repo], to moc: NSManagedObjectContext, callback: Completion) {

		for r in Repo.unsyncableRepos(in: moc) {
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
				}) { [weak self] success, resultCode in
					if !success {
						self?.handleRepoSyncFailure(repo: r, resultCode: resultCode)
					}
					completionCount += 1
					if completionCount==total {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func fetchCommentsForCurrentPullRequests(to moc: NSManagedObjectContext, callback: Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }
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

		func _fetchComments(for pullRequests: [PullRequest], issues: Bool, in moc: NSManagedObjectContext, callback: Completion) {

			let total = pullRequests.count
			if total==0 {
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
						if completionCount == total {
							callback()
						}
					}
				} else {
					completionCount += 1
					if completionCount == total {
						callback()
					}
				}
			}
		}

		_fetchComments(for: prs, issues: true, in: moc, callback: completionCallback)
		_fetchComments(for: prs, issues: false, in: moc, callback: completionCallback)
	}

	private func fetchCommentsForCurrentIssues(to moc: NSManagedObjectContext, callback: Completion) {

		let allIssues = DataItem.newOrUpdatedItems(of: Issue.self, in: moc)

		for i in allIssues {
			for c in i.comments {
				c.postSyncAction = PostSyncAction.delete.rawValue
			}
		}

		let issues = allIssues.filter { $0.apiServer.lastSyncSucceeded }

		let total = issues.count
		if total==0 {
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
					if completionCount == total {
						callback()
					}
				}
			} else {
				completionCount += 1
				if completionCount == total {
					callback()
				}
			}
		}
	}

	private func fetchLabelsForForCurrentPullRequests(to moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.active(in: moc, visibleOnly: true).filter { [weak self] pr in
			if !pr.apiServer.lastSyncSucceeded {
				return false
			}
			if pr.condition != ItemCondition.open.rawValue {
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

				getPagedData(at: link, from: p.apiServer, perPageCallback: { data, lastPage in
					PRLabel.syncLabels(from: data, withParent: p)
					return false
				}) { [weak self] success, resultCode in
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
				}
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

	private func fetchStatusesForCurrentPullRequests(to moc: NSManagedObjectContext, callback: Completion) {

		let prs = PullRequest.active(in: moc, visibleOnly: !Settings.hidePrsThatArentPassing).filter { [unowned self] pr in
			if !pr.apiServer.lastSyncSucceeded {
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
				getPagedData(at: statusLink, from: apiServer, perPageCallback: { data, lastPage in
					PRStatus.syncStatuses(from: data, pullRequest: p)
					return false
				}) { [weak self] success, resultCode in
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
				}
			} else {
				refreshesSinceLastStatusCheck[p.objectID] = 1
				completionCount += 1
				if completionCount==total {
					callback()
				}
			}
		}
	}

	private func checkPrClosures(in moc: NSManagedObjectContext, callback: Completion) {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "postSyncAction == %lld and condition == %lld", PostSyncAction.delete.rawValue, ItemCondition.open.rawValue)
		f.returnsObjectsAsFaults = false
		let pullRequests = try! moc.fetch(f)

		let prsToCheck = pullRequests.filter { r -> Bool in
			let parent = r.repo
			return parent.shouldSync && parent.postSyncAction != PostSyncAction.delete.rawValue && r.apiServer.lastSyncSucceeded
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
			investigatePrClosure(for: r, callback: completionCallback)
		}
	}

	private func checkIssueClosures(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.predicate = NSPredicate(format: "postSyncAction == %lld and condition == %lld", PostSyncAction.delete.rawValue, ItemCondition.open.rawValue)
		f.returnsObjectsAsFaults = false

		for i in try! moc.fetch(f) {
			let r = i.repo
			if r.shouldSync && r.postSyncAction != PostSyncAction.delete.rawValue && r.apiServer.lastSyncSucceeded {
				handleClosing(of: i)
			}
		}
	}

	private func detectAssignedPullRequests(in moc: NSManagedObjectContext, callback: Completion) {

		let prs = DataItem.newOrUpdatedItems(of: PullRequest.self, in: moc).filter { $0.apiServer.lastSyncSucceeded }
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
				getData(in: issueLink, from: apiServer) { data, lastPage, resultCode in
					if resultCode == 200 || resultCode == 404 || resultCode == 410 {
						p.processAssignmentStatus(from: data as? [String : AnyObject])
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

	private func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext, callback: Completion) {
		var needToCheck = false
		for apiServer in ApiServer.allApiServers(in: moc) {
			if apiServer.userId == 0 {
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

	private func investigatePrClosure(for pullRequest: PullRequest, callback: Completion) {
		DLog("Checking closed PR to see if it was merged: %@", pullRequest.title)

		let repoFullName = S(pullRequest.repo.fullName)
		let path = "/repos/\(repoFullName)/pulls/\(pullRequest.number)"

		getData(in: path, from: pullRequest.apiServer) { [weak self] data, lastPage, resultCode in

			if let d = data as? [String : AnyObject] {
				if let mergeInfo = d["merged_by"] as? [String : AnyObject], let mergeUserId = mergeInfo["id"] as? NSNumber {
					self?.handleMerging(of: pullRequest, byUserId: mergeUserId.int64Value)
				} else {
					self?.handleClosing(of: pullRequest)
				}
			} else if resultCode == 404 || resultCode == 410 { // PR gone for good
				self?.handleClosing(of: pullRequest)
			} else { // fetch/server problem
				pullRequest.postSyncAction = PostSyncAction.doNothing.rawValue // don't delete this, we couldn't check, play it safe
				pullRequest.apiServer.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private func handleMerging(of pullRequest: PullRequest, byUserId: Int64) {

		let myUserId = pullRequest.apiServer.userId
		DLog("Detected merged PR: %@ by user %lld, local user id is: %lld, handling policy is %d, coming from section %lld",
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

	private func handleClosing(of item: ListableItem) {
		DLog("Detected closed item: %@, handling policy is %d, coming from section %lld",
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

	private func getRateLimit(from server: ApiServer, callback: (Int64, Int64, Int64)->Void)
	{
		api(call: "/rate_limit", on: server, ignoreLastSync: true) { code, headers, data, error, shouldRetry in

			if error == nil {
				let allHeaders = headers!
				let requestsRemaining = Int64(S(allHeaders["X-RateLimit-Remaining"] as? String)) ?? 0
				let requestLimit = Int64(S(allHeaders["X-RateLimit-Limit"] as? String)) ?? 0
				let epochSeconds = Int64(S(allHeaders["X-RateLimit-Reset"] as? String)) ?? 0
				callback(requestsRemaining, requestLimit, epochSeconds)
			} else {
				if code == 404 && data != nil && !((data as? [String : AnyObject])?["message"] as? String == "Not Found") {
					callback(10000, 10000, 0)
				} else {
					callback(-1, -1, -1)
				}
			}
		}
	}

	func updateLimitsFromServer() {
		let allApiServers = ApiServer.allApiServers(in: mainObjectContext)
		let total = allApiServers.count
		var count = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getRateLimit(from: apiServer) { remaining, limit, reset in
					apiServer.requestsRemaining = remaining
					apiServer.requestsLimit = limit
					count += 1
					if count==total {
						NotificationCenter.default.post(name: ApiUsageUpdateNotification, object: apiServer, userInfo: nil)
					}
				}
			}
		}
	}

	private func shouldScanForStatuses(in moc: NSManagedObjectContext) -> Bool {
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

	private func shouldScanForLabels(in moc: NSManagedObjectContext) -> Bool {
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

	private func syncWatchedRepos(from server: ApiServer, callback: Completion) {

		if !server.lastSyncSucceeded {
			callback()
			return
		}

		getPagedData(at: "/user/subscriptions", from: server, perPageCallback: { data, lastPage in
			Repo.syncRepos(from: data, server: server)
			return false
		}) { success, resultCode in
			if !success {
				server.lastSyncSucceeded = false
			}
			callback()
		}
	}

	private func syncUserDetails(in moc: NSManagedObjectContext, callback: Completion) {

		let allApiServers = ApiServer.allApiServers(in: moc)
		let operationCount = allApiServers.count
		if operationCount==0 {
			callback()
			return
		}

		var completionCount = 0
		for apiServer in allApiServers {
			if apiServer.goodToGo {
				getData(in: "/user", from: apiServer) { data, lastPage, resultCode in

					if let d = data as? [String : AnyObject] {
						apiServer.userName = d["login"] as? String
						apiServer.userId = (d["id"] as? NSNumber)?.int64Value ?? 0
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

	func testApi(to apiServer: ApiServer, callback: (NSError?) -> ()) {
		clearAllBadLinks()
		api(call: "/user", on: apiServer, ignoreLastSync: true) { [weak self] code, headers, data, error, shouldRetry in

			if let d = data as? [String : AnyObject], let userName = d["login"] as? String, let userId = d["id"] as? NSNumber, error == nil {
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

	private func getPagedData(
		at path: String,
		from server: ApiServer,
		startingFrom page: Int = 1,
		perPageCallback: (data: [[String : AnyObject]]?, lastPage: Bool) -> Bool,
		finalCallback: (success: Bool, resultCode: Int64) -> Void) {

		if path.isEmpty {
			// handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
			atNextEvent {
				finalCallback(success: true, resultCode: -1)
				return
			}
			return
		}

		let p = page > 1 ? "\(path)?page=\(page)" : path
		getData(in: p, from: server) {
			[weak self] data, lastPage, resultCode in

			if let d = data as? [[String : AnyObject]] {
				var isLastPage = lastPage
				if perPageCallback(data: d, lastPage: lastPage) { isLastPage = true }
				if isLastPage {
					finalCallback(success: true, resultCode: resultCode)
				} else {
					self?.getPagedData(at: path, from: server, startingFrom: page+1, perPageCallback: perPageCallback, finalCallback: finalCallback)
				}
			} else {
				finalCallback(success: false, resultCode: resultCode)
			}
		}
	}

	private func getData(
		in path: String,
		from server: ApiServer,
		attemptCount: Int = 0,
		callback: (data: AnyObject?, lastPage: Bool, resultCode: Int64) -> Void) {

		api(call: path, on: server, ignoreLastSync: false) { [weak self] c, headers, data, error, shouldRetry in

			let code = c ?? 0

			if error == nil {
				var lastPage = true
				if let allHeaders = headers {

					if let v = allHeaders["X-RateLimit-Remaining"] as? String {
						server.requestsRemaining = Int64(v) ?? 0
					} else {
						server.requestsRemaining = 10000
					}

					if let v = allHeaders["X-RateLimit-Limit"] as? String {
						server.requestsLimit = Int64(v) ?? 0
					} else {
						server.requestsLimit = 10000
					}

					if let v = allHeaders["X-RateLimit-Reset"] as? String {
						server.resetDate = Date(timeIntervalSince1970: Double(v) ?? 0)
					} else {
						server.resetDate = nil
					}

					if let linkHeader = allHeaders["Link"] as? String {
						lastPage = !linkHeader.contains("rel=\"next\"")
					}

					NotificationCenter.default.post(name: ApiUsageUpdateNotification, object: server, userInfo: nil)
				}
				callback(data: data, lastPage: lastPage, resultCode: code)
			} else {
				if shouldRetry && attemptCount < 2 { // timeout, truncation, connection issue, etc
					let nextAttemptCount = attemptCount+1
					DLog("(%@) Will retry failed API call to %@ (attempt #%d)", S(server.label), path, nextAttemptCount)
					delay(2.0) {
						self?.getData(in: path, from: server, attemptCount: nextAttemptCount, callback: callback)
					}
				} else {
					if shouldRetry {
						DLog("(%@) Giving up on failed API call to %@", S(server.label), path)
					}
					callback(data: nil, lastPage: false, resultCode: code)
				}
			}
		}
	}

	typealias ApiCompletion = (code: Int64?, headers: [NSObject : AnyObject]?, data: AnyObject?, error: NSError?, shouldRetry: Bool) -> Void

	private var apiRunningCount = 0
	private var apiCallQueue = [Completion]()
	#if os(iOS)
	private let maxApiOperations = (sizeof(Int.self) == sizeof(Int64.self)) ? 8 : 2
	#else
	private let maxApiOperations = 8
	#endif

	private func api(
		call path: String,
		on server: ApiServer,
		ignoreLastSync: Bool,
		completion: ApiCompletion) {

		if apiRunningCount < maxApiOperations {
			_api(call: path, on: server, ignoreLastSync: ignoreLastSync, completion: completion)
		} else {
			apiCallQueue.append { [weak self] in
				self?._api(call: path, on: server, ignoreLastSync: ignoreLastSync, completion: completion)
			}
		}
	}
	private func updateApiProgress() {
		NotificationCenter.default.post(Notification(name: SyncProgressUpdateNotification, object: nil, userInfo: nil))
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
		call path: String,
		on server: ApiServer,
		ignoreLastSync: Bool,
		completion: ApiCompletion) {

		apiRunningCount += 1
		updateApiProgress()

		let apiServerLabel: String
		if server.lastSyncSucceeded || ignoreLastSync {
			apiServerLabel = S(server.label)
		} else {
			atNextEvent(self) { S in
				let e = S.apiError("Sync has failed, skipping this call")
				completion(code: nil, headers: nil, data: nil, error: e, shouldRetry: false)
				S.dequeueApi()
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

		let cacheKey = "\(server.objectID.uriRepresentation().absoluteString) \(expandedPath)"
		let previousCacheEntry = CacheEntry.entry(for: cacheKey)?.cacheUnit // move data out of thread-specific context
		if let p = previousCacheEntry {
			/////////////////////// 60 second dumb-caching
			if p.lastFetched.timeIntervalSince1970 > Date(timeIntervalSinceNow: -60).timeIntervalSince1970, let parsedData = p.parsedData {
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

		#if os(iOS)
			networkIndicationStart()
		#endif

		let task = urlSession.dataTask(with: r) { [weak self] data, res, e in

			guard let S = self else { return }

			let response = res as? HTTPURLResponse
			let parsedData: AnyObject?
			let error: NSError?
			let shouldRetry: Bool
			var code = Int64(response?.statusCode ?? 0)
			var headers = response?.allHeaderFields

			if code == 304, let p = previousCacheEntry {
				error = nil
				parsedData = p.parsedData
				shouldRetry = false
				code = p.code
				headers = p.actualHeaders
				atNextEvent {
					CacheEntry.markFetched(for: cacheKey)
				}
				DLog("(%@) GET %@ - NO CHANGE (304): %lld", apiServerLabel, expandedPath, code)
			} else if code > 299 {
				error = S.apiError("Server responded with error \(code)")
				parsedData = nil
				shouldRetry = false
			} else if code == 0 {
				error = S.apiError("Server did not repond")
				parsedData = nil
				shouldRetry = (e as? NSError)?.code == -1001 // retry if it was a timeout
			} else if (response?.expectedContentLength ?? 0) > Int64(data?.count ?? 0) {
				error = S.apiError("Server data was truncated")
				parsedData = nil
				shouldRetry = true // truncation
			} else {
				DLog("(%@) GET %@ - RESULT: %lld", apiServerLabel, expandedPath, code)
				error = e as? NSError
				shouldRetry = false
				if let data = data {
					parsedData = try? JSONSerialization.jsonObject(with: data, options: [])
					if let headers = headers, let etag = headers["Etag"] as? String {
						atNextEvent {
							CacheEntry.setEntry(key: cacheKey, code: code, etag: etag, data: data, headers: headers)
						}
					}
				} else {
					parsedData = nil
				}
			}

			atNextEvent {
				S.handleResponse(with: data,
				                 parsedData: parsedData,
				                 serverLabel: apiServerLabel,
				                 urlPath: expandedPath,
				                 code: code,
				                 error: error,
				                 shouldRetry: shouldRetry,
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

	private func handleResponse(with data: Data?,
	                            parsedData: AnyObject?,
	                            serverLabel: String,
	                            urlPath: String,
	                            code: Int64,
	                            error: NSError?,
	                            shouldRetry: Bool,
	                            existingBackOff: UrlBackOffEntry?,
	                            headers: [NSObject : AnyObject]?,
	                            completion: ApiCompletion) {
		if error != nil {
			if code > 399 {
				if var backoff = existingBackOff {
					DLog("(%@) Extending backoff for already throttled URL %@ by %f seconds", serverLabel, urlPath, backOffIncrement)
					if backoff.nextIncrement < 3600.0 {
						backoff.nextIncrement += backOffIncrement
					}
					backoff.nextAttemptAt = Date().addingTimeInterval(backoff.nextIncrement)
					badLinks[urlPath] = backoff
				} else {
					DLog("(%@) Placing URL %@ on the throttled list", serverLabel, urlPath)
					badLinks[urlPath] = UrlBackOffEntry(
						nextAttemptAt: Date().addingTimeInterval(backOffIncrement),
						nextIncrement: backOffIncrement)
				}
			}
			DLog("(%@) GET %@ - FAILED: (code %lld) %@", serverLabel, urlPath, code, error!.localizedDescription)
		}

		if Settings.dumpAPIResponsesInConsole, let d = data {
			DLog("API data from %@: %@", urlPath, String(bytes: d, encoding: .utf8))
		}

		completion(code: code, headers: headers, data: parsedData, error: error, shouldRetry: shouldRetry)

		dequeueApi()
	}

	#if os(iOS)

	private var networkBGTask = UIBackgroundTaskInvalid
	private var networkBGEndPopTimer: PopTimer?
	private var networkIndicationCount = 0

	private func networkIndicationStart() {
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
	
	private func networkIndicationEnd() {
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
