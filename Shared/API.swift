import AsyncHTTPClient
import CommonCrypto
import CoreData

extension String {
    private func sha1() -> Data {
        utf8CString.withUnsafeBytes { bytes -> Data in
            let len = Int(CC_SHA1_DIGEST_LENGTH)
            var digest = [UInt8](repeating: 0, count: len)
            CC_SHA1(bytes.baseAddress, CC_LONG(bytes.count), &digest)
            return Data(bytes: digest, count: len)
        }
    }

    var fileHash: String {
        sha1().base64EncodedString().replacingOccurrences(of: "/", with: "-")
    }
}

@MainActor
enum API {
    static var currentNetworkStatus = NetworkStatus.NotReachable

    private static let reachability = Reachability()

    static func setup() {
        reachability.startNotifier()

        let n = reachability.status
        DLog("Network is %@", n.name)
        currentNetworkStatus = n

        NotificationCenter.default.addObserver(forName: ReachabilityChangedNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                checkNetworkAvailability()
                if currentNetworkStatus != .NotReachable {
                    await app.startRefreshIfItIsDue()
                }
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
            DLog("Status update: \(currentOperationName)")
            NotificationCenter.default.post(name: .SyncProgressUpdate, object: nil)
        }
    }

    static var currentOperationCount = 0 {
        didSet {
            if isRefreshing, currentOperationName.hasPrefix("Fetching…") {
                let newValue = currentOperationCount
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

    nonisolated static var shouldSyncReactions: Bool {
        Settings.notifyOnItemReactions || Settings.notifyOnCommentReactions
    }

    nonisolated static var shouldSyncReviews: Bool {
        Settings.displayReviewsOnItems || Settings.notifyOnReviewDismissals || Settings.notifyOnReviewAcceptances || Settings.notifyOnReviewChangeRequests
    }

    nonisolated static var shouldSyncReviewAssignments: Bool {
        Settings.displayReviewsOnItems || Settings.showRequestedTeamReviews || Settings.notifyOnReviewAssignments || (Int64(Settings.assignedReviewHandlingPolicy) != Section.none.rawValue)
    }

    ////////////////////////////////////// API interface

    static func performSync() async {
        let syncMoc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        syncMoc.undoManager = nil
        syncMoc.parent = DataManager.main

        if Settings.useV4API && canUseV4API(for: syncMoc) != nil {
            return
        }

        isRefreshing = true
        currentOperationCount += 1
        currentOperationName = "Fetching…"

        let lastCheck = lastRepoCheck
        let shouldRefreshReposToo = lastCheck == .distantPast
            || (Date().timeIntervalSince(lastCheck) > TimeInterval(Settings.newRepoCheckPeriod * 3600))
            || !Repo.anyVisibleRepos(in: syncMoc)

        if shouldRefreshReposToo {
            await fetchRepositories(to: syncMoc)
        } else {
            ApiServer.resetSyncSuccess(in: syncMoc)
            await ensureApiServersHaveUserIds(in: syncMoc)
        }

        let disabledRepos = Repo.unsyncableRepos(in: syncMoc)
        disabledRepos.forEach {
            $0.pullRequests.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
            $0.issues.forEach {
                $0.postSyncAction = PostSyncAction.delete.rawValue
            }
        }

        let repos = Repo.syncableRepos(in: syncMoc)

        DLog("Will sync items from: %@", repos.compactMap(\.fullName).joined(separator: ", "))

        if Settings.useV4API {
            do {
                try await v4Sync(repos, to: syncMoc)
            } catch {
                DLog("Sync aborted due to error")
            }

        } else {
            await v3Sync(repos, to: syncMoc)
        }

        // Transfer done, process
        let total = syncMoc.updatedObjects.count + syncMoc.insertedObjects.count + syncMoc.deletedObjects.count
        if total > 1, let totalText = numberFormatter.string(for: total) {
            currentOperationName = "Processing \(totalText) items…"
        } else {
            currentOperationName = "Processing update…"
        }

        // discard any changes related to any failed API server
        for apiServer in ApiServer.allApiServers(in: syncMoc) where !apiServer.lastSyncSucceeded {
            apiServer.rollBackAllUpdates(in: syncMoc)
            apiServer.lastSyncSucceeded = false // we just wiped all changes, but want to keep this one
        }
        DataItem.nukeDeletedItems(in: syncMoc)
        DataItem.nukeOrphanedItems(in: syncMoc)
        await DataManager.postProcessAllItems(in: syncMoc)

        do {
            if syncMoc.hasChanges {
                DLog("Committing synced data")
                try syncMoc.save()
                DLog("Synced data committed")
                DataManager.saveDB()
            } else {
                DLog("No changes, skipping commit")
            }
        } catch {
            DLog("Committing sync failed: %@", error.localizedDescription)
        }

        isRefreshing = false
        currentOperationCount -= 1

        await DataManager.sendNotificationsIndexAndSave()
    }

    static var lastSuccessfulSyncAt: String {
        let last = Settings.lastSuccessfulRefresh ?? Date()
        return agoFormat(prefix: "updated", since: last).capitalFirstLetter
    }

    private static func fetchUserTeams(from server: ApiServer, moc: NSManagedObjectContext) async {
        for t in server.teams {
            t.postSyncAction = PostSyncAction.delete.rawValue
        }

        let serverId = server.objectID
        let result = await RestAccess.getPagedData(at: "/user/teams", from: server) { data, _ in
            await Team.syncTeams(from: data, serverId: serverId, moc: moc)
            return false
        }
        switch result {
        case .success:
            break
        case .deleted, .failed, .notFound:
            server.lastSyncSucceeded = false
        }
    }

    // moc must have been created in an @APIActor task
    static func fetchRepositories(to moc: NSManagedObjectContext) async {
        ApiServer.resetSyncSuccess(in: moc)

        await syncUserDetails(in: moc)

        for r in DataItem.items(of: Repo.self, surviving: true, in: moc) {
            r.postSyncAction = r.shouldBeWipedIfNotInWatchlist ? PostSyncAction.delete.rawValue : PostSyncAction.doNothing.rawValue
        }

        let goodToGoServers = ApiServer.allApiServers(in: moc).filter(\.goodToGo)
        await withTaskGroup(of: Void.self) { group in
            for apiServer in goodToGoServers {
                group.addTask { @MainActor in
                    await syncWatchedRepos(from: apiServer, moc: moc)
                }
                group.addTask { @MainActor in
                    await syncManuallyAddedRepos(from: apiServer, moc: moc)
                }
                group.addTask { @MainActor in
                    await fetchUserTeams(from: apiServer, moc: moc)
                }
            }
        }

        if Settings.hideArchivedRepos { Repo.hideArchivedRepos(in: moc) }
        for r in DataItem.newItems(of: Repo.self, in: moc) where r.shouldSync {
            NotificationQueue.add(type: .newRepoAnnouncement, for: r)
        }
        lastRepoCheck = Date()
    }

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

    private static func getRateLimit(from server: ApiServer) async -> ApiStats? {
        do {
            let (code, _) = try await RestAccess.start(call: "/rate_limit", on: server, triggeredByUser: true)
            switch code {
            case .notFound: // is GE account
                return ApiStats.noLimits
            case .deleted, .failed:
                break
            case let .success(headers, _):
                return ApiStats.fromV3(headers: headers)
            }
        } catch {}
        return nil
    }

    static func updateLimitsFromServer() async {
        let configuredServers = ApiServer.allApiServers(in: DataManager.main).filter(\.goodToGo)
        for apiServer in configuredServers {
            if let l = await getRateLimit(from: apiServer) {
                apiServer.updateApiStats(l)
            }
        }
    }

    private static func syncManuallyAddedRepos(from server: ApiServer, moc: NSManagedObjectContext) async {
        if !server.lastSyncSucceeded {
            return
        }

        let repos = server.repos.filter(\.manuallyAdded)
        for repo in repos {
            do {
                try await fetchRepo(fullName: repo.fullName ?? "", from: server, moc: moc)
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }

    private static func syncWatchedRepos(from server: ApiServer, moc: NSManagedObjectContext) async {
        if !server.lastSyncSucceeded {
            return
        }

        let createNewRepos = Settings.automaticallyRemoveDeletedReposFromWatchlist
        let result = await RestAccess.getPagedData(at: "/user/subscriptions", from: server) { data, _ in
            await Repo.syncRepos(from: data, server: server, addNewRepos: createNewRepos, manuallyAdded: false, moc: moc)
            return false
        }
        switch result {
        case .success:
            if !Settings.automaticallyRemoveDeletedReposFromWatchlist { // Ignore any missing repos in all cases if deleteGoneRepos is false
                let reposThatWouldBeDeleted = Repo.items(of: Repo.self, surviving: false, in: server.managedObjectContext!)
                for r in reposThatWouldBeDeleted {
                    r.postSyncAction = PostSyncAction.doNothing.rawValue
                }
            }
        case .deleted, .failed, .notFound:
            server.lastSyncSucceeded = false
        }
    }

    static func fetchRepo(fullName: String, from server: ApiServer, moc: NSManagedObjectContext) async throws {
        let path = "\(server.apiPath ?? "")/repos/\(fullName)"
        do {
            let (data, _, _) = try await RestAccess.getData(in: path, from: server)
            if let repoData = data as? [AnyHashable: Any] {
                await Repo.syncRepos(from: [repoData], server: server, addNewRepos: true, manuallyAdded: true, moc: moc)
            }
        } catch {
            let resultCode = (error as NSError).code
            throw apiError("Operation failed with code \(resultCode)")
        }
    }

    static func fetchAllRepos(owner: String, from server: ApiServer, moc: NSManagedObjectContext) async throws {
        let userPath = "\(server.apiPath ?? "")/users/\(owner)/repos"
        let userTask = Task { () -> [[AnyHashable: Any]] in
            var userList = [[AnyHashable: Any]]()
            let result = await RestAccess.getPagedData(at: userPath, from: server) { data, _ -> Bool in
                if let data {
                    userList.append(contentsOf: data)
                }
                return false
            }
            switch result {
            case .success:
                return userList
            case .notFound:
                throw apiError("Operation failed with code 404")
            case .deleted:
                throw apiError("Operation failed with code 410")
            case let .failed(code):
                throw apiError("Operation failed with code \(code)")
            }
        }

        let orgPath = "\(server.apiPath ?? "")/orgs/\(owner)/repos"
        let orgTask = Task { () -> [[AnyHashable: Any]] in
            var orgList = [[AnyHashable: Any]]()
            let result = await RestAccess.getPagedData(at: orgPath, from: server) { data, _ -> Bool in
                if let data {
                    orgList.append(contentsOf: data)
                }
                return false
            }
            switch result {
            case .success:
                return orgList
            case .notFound:
                throw apiError("Operation failed with code 404")
            case .deleted:
                throw apiError("Operation failed with code 410")
            case let .failed(code):
                throw apiError("Operation failed with code \(code)")
            }
        }

        let userList = try await userTask.value
        let orgList = try await orgTask.value

        await Repo.syncRepos(from: userList + orgList, server: server, addNewRepos: true, manuallyAdded: true, moc: moc)
    }

    static func fetchRepo(named: String, owner: String, from server: ApiServer, moc: NSManagedObjectContext) async throws {
        try await fetchRepo(fullName: "\(owner)/\(named)", from: server, moc: moc)
    }

    private static func syncUserDetails(in moc: NSManagedObjectContext) async {
        let configuredServers = ApiServer.allApiServers(in: moc).filter(\.goodToGo)
        for apiServer in configuredServers {
            do {
                let (data, _, _) = try await RestAccess.getData(in: "/user", from: apiServer)
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

    nonisolated static func apiError(_ message: String) -> Error {
        NSError(domain: "API Error", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
