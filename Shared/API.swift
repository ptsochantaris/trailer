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

enum ApiError: Error {
    case errorCode(Int)
    case nonHttpResponse
    case cancelled
    case invalidUrl(String)
    case imageFetchFailed
    case invalidImageData
    case noUserRecordFound
    case graphQLFailure(String)

    var description: String {
        switch self {
        case let .errorCode(code):
            return "HTTP Code \(code) received"
        case .nonHttpResponse:
            return "Network response was not a HTTP response"
        case .cancelled:
            return "Operation cancelled"
        case let .invalidUrl(url):
            return "Invalid URL: \(url)"
        case .imageFetchFailed:
            return "Image fetch failed"
        case .invalidImageData:
            return "Invalid image data"
        case .noUserRecordFound:
            return "Could not read a valid user record from this endpoint"
        case let .graphQLFailure(text):
            return "GraphQL issue: \(text)"
        }
    }
}

@MainActor
enum API {
    static var currentNetworkStatus = NetworkStatus.notReachable

    private static let reachability = Reachability()

    static func setup() {
        reachability.startNotifier()
        GraphQL.setup()

        let n = reachability.status
        Logging.log("Network is \(n.name)")
        currentNetworkStatus = n

        NotificationCenter.default.addObserver(forName: ReachabilityChangedNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                checkNetworkAvailability()
                if currentNetworkStatus != .notReachable {
                    await app.startRefreshIfItIsDue()
                }
            }
        }
    }

    private static func checkNetworkAvailability() {
        let newStatus = reachability.status
        if newStatus != currentNetworkStatus {
            currentNetworkStatus = newStatus
            Logging.log("Network changed to \(newStatus.name)")
        }
    }

    static var hasNetworkConnection: Bool {
        Logging.log("Actively verifying reported network availability state…")
        let previousNetworkStatus = currentNetworkStatus
        checkNetworkAvailability()
        if previousNetworkStatus != currentNetworkStatus {
            Logging.log("Network state seems to have changed without having been notified, noted")
        } else {
            Logging.log("No change to network state")
        }
        return currentNetworkStatus != .notReachable
    }

    /////////////////////////////////////////////////////// Utilities

    static var currentOperationName = lastSuccessfulSyncAt {
        didSet {
            Logging.log("Status update: \(currentOperationName)")
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
                Logging.log("Starting refresh")
                GraphQL.callCount = 0
                DataManager.postMigrationTasks()
                NotificationQueue.clear()
                NotificationCenter.default.post(name: .RefreshStarting, object: nil)
            } else {
                Logging.log("Refresh done")
                GraphQL.callCount = 0
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

    ////////////////////////////////////// API interface

    @MainActor
    static func attemptV4Migration() async {
        while isRefreshing {
            try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let childMoc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        childMoc.undoManager = nil
        childMoc.parent = DataManager.main

        currentOperationName = "Migrating IDs…"
        Logging.log("Staring v4 API ID migration")

        do {
            let types = [Team.self,
                         Reaction.self,
                         PRLabel.self,
                         PRComment.self,
                         Review.self,
                         PRStatus.self,
                         PullRequest.self,
                         Issue.self,
                         Repo.self]

            let goodToGoServers = ApiServer.allApiServers(in: childMoc).filter(\.goodToGo)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for server in goodToGoServers {
                    for type in types {
                        group.addTask {
                            try await GraphQL.migrateV4Ids(for: type, in: server)
                        }
                    }
                }
                try await group.waitForAll()
            }

            if childMoc.hasChanges {
                try childMoc.save()
                await DataManager.saveDB()
            }
            Logging.log("v4 sync ID migration complete")
            Settings.V4IdMigrationPhase = .done

        } catch {
            Settings.V4IdMigrationPhase = .failedPending
            Logging.log("ID Migration failed: \(error.localizedDescription)")
        }
    }

    static func performSync(settings: Settings.Cache) async {
        let syncMoc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        syncMoc.undoManager = nil
        syncMoc.parent = DataManager.main
        
        let useV4 = Settings.useV4API

        await HTTP.gateKeeper.setBonusTickets(8)

        if useV4 {
            if canUseV4API(for: syncMoc) != nil {
                return
            }
            if Settings.V4IdMigrationPhase == .pending {
                await attemptV4Migration()
            }

            if Settings.threadedSync {
                await GraphQL.multiGateKeeper.setBonusTickets(2)
            }
        }

        isRefreshing = true
        currentOperationCount += 1

        defer {
            isRefreshing = false
            currentOperationCount -= 1
        }

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

        Logging.log("Will sync items from: \(repos.compactMap(\.fullName).joined(separator: ", "))")

        if useV4 {
            do {
                try await v4Sync(repos, to: syncMoc, settings: settings)
            } catch {
                Logging.log("Sync aborted due to error: \(error.localizedDescription)")
            }

        } else {
            await v3Sync(repos, to: syncMoc, settings: settings)
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

        if syncMoc.hasChanges {
            do {
                Logging.log("Committing synced data")
                try syncMoc.save()
                Logging.log("Synced data committed")
                await DataManager.sendNotificationsIndexAndSave(settings: settings)
            } catch {
                Logging.log("Committing sync failed: \(error.localizedDescription)")
            }
        } else {
            Logging.log("No changes, skipping commit")
        }
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
        case .cancelled, .ignored, .success:
            break
        case .deleted, .failed, .notFound:
            server.lastSyncSucceeded = false
        }
    }

    @MainActor
    static func fetchRepositories(to moc: NSManagedObjectContext) async {
        ApiServer.resetSyncSuccess(in: moc)

        await syncUserDetails(in: moc)

        for r in Repo.items(surviving: true, in: moc) {
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
        for r in Repo.newItems(in: moc) where r.shouldSync {
            NotificationQueue.add(type: .newRepoAnnouncement, for: r)
        }
        lastRepoCheck = Date()
    }

    private static func ensureApiServersHaveUserIds(in moc: NSManagedObjectContext) async {
        let needToCheck = ApiServer.allApiServers(in: moc).contains {
            $0.userNodeId == nil || $0.userName.orEmpty.isEmpty
        }

        if needToCheck {
            Logging.log("Some API servers don't have user details yet, will bring user credentials down for them")
            await syncUserDetails(in: moc)
        }
    }

    private static func getRateLimit(from server: ApiServer) async -> ApiStats? {
        do {
            let (_, code) = try await RestAccess.start(call: "/rate_limit", on: server, triggeredByUser: true)
            switch code {
            case .notFound:
                // is GE account
                return ApiStats.noLimits
            case .cancelled, .deleted, .failed, .ignored:
                return nil
            case let .success(headers, _):
                return ApiStats.fromV3(headers: headers)
            }
        } catch {}
        return nil
    }

    static func updateLimitsFromServer() async {
        for apiServer in ApiServer.allApiServers(in: DataManager.main).filter(\.goodToGo) {
            if let l = await getRateLimit(from: apiServer) {
                apiServer.updateApiStats(l)
            }
        }
    }

    private static func syncManuallyAddedRepos(from server: ApiServer, moc: NSManagedObjectContext) async {
        if !server.lastSyncSucceeded {
            return
        }

        for repo in server.repos.filter(\.manuallyAdded) {
            do {
                try await fetchRepo(fullName: repo.fullName.orEmpty, from: server, moc: moc)
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
                let reposThatWouldBeDeleted = Repo.items(surviving: false, in: server.managedObjectContext!)
                for r in reposThatWouldBeDeleted {
                    r.postSyncAction = PostSyncAction.doNothing.rawValue
                }
            }
        case .cancelled, .ignored:
            break
        case .deleted, .failed, .notFound:
            server.lastSyncSucceeded = false
        }
    }

    static func fetchRepo(fullName: String, from server: ApiServer, moc: NSManagedObjectContext) async throws {
        let path = "\(server.apiPath.orEmpty)/repos/\(fullName)"
        let (data, _, _) = try await RestAccess.getData(in: path, from: server)
        if let repoData = data as? JSON {
            await Repo.syncRepos(from: [repoData], server: server, addNewRepos: true, manuallyAdded: true, moc: moc)
        }
    }

    static func fetchAllRepos(owner: String, from server: ApiServer, moc: NSManagedObjectContext) async throws {
        let userPath = "\(server.apiPath.orEmpty)/users/\(owner)/repos"
        let userTask = Task { () -> [JSON] in
            var userList = [JSON]()
            let result = await RestAccess.getPagedData(at: userPath, from: server) { data, _ -> Bool in
                if let data {
                    userList.append(contentsOf: data)
                }
                return false
            }
            switch result {
            case .success:
                return userList
            case .cancelled, .ignored:
                throw ApiError.cancelled
            case .notFound:
                throw ApiError.errorCode(404)
            case .deleted:
                throw ApiError.errorCode(410)
            case let .failed(code):
                throw ApiError.errorCode(code)
            }
        }

        let orgPath = "\(server.apiPath.orEmpty)/orgs/\(owner)/repos"
        let orgTask = Task { () -> [JSON] in
            var orgList = [JSON]()
            let result = await RestAccess.getPagedData(at: orgPath, from: server) { data, _ -> Bool in
                if let data {
                    orgList.append(contentsOf: data)
                }
                return false
            }
            switch result {
            case .success:
                return orgList
            case .cancelled, .ignored:
                throw ApiError.cancelled
            case .notFound:
                throw ApiError.errorCode(404)
            case .deleted:
                throw ApiError.errorCode(410)
            case let .failed(code):
                throw ApiError.errorCode(code)
            }
        }

        let userList = try await userTask.value
        let orgList = try await orgTask.value

        await Repo.syncRepos(from: userList + orgList, server: server, addNewRepos: true, manuallyAdded: true, moc: moc)
    }

    private static func syncUserDetails(in moc: NSManagedObjectContext) async {
        for apiServer in ApiServer.allApiServers(in: moc).filter(\.goodToGo) {
            do {
                let (data, _, _) = try await RestAccess.getData(in: "/user", from: apiServer)
                if let d = data as? JSON {
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
}
