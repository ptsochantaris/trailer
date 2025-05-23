import CoreData
import Lista
import TrailerQL

final class ApiServer: NSManagedObject {
    @NSManaged var apiPath: String?
    @NSManaged var graphQLPath: String?
    @NSManaged var label: String?
    @NSManaged var lastSyncSucceeded: Bool
    @NSManaged var reportRefreshFailures: Bool
    @NSManaged var requestsLimit: Int
    @NSManaged var requestsRemaining: Int
    @NSManaged var resetDate: Date?
    @NSManaged var userName: String?
    @NSManaged var webPath: String?
    @NSManaged var createdAt: Date?
    @NSManaged var userNodeId: String?

    @NSManaged var comments: Set<PRComment>
    @NSManaged var labels: Set<PRLabel>
    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var repos: Set<Repo>
    @NSManaged var statuses: Set<PRStatus>
    @NSManaged var teams: Set<Team>
    @NSManaged var issues: Set<Issue>
    @NSManaged var reviews: Set<Review>
    @NSManaged var reactions: Set<Reaction>

    @MainActor
    static var lastReportedOverLimit = Set<NSManagedObjectID>()

    @MainActor
    static var lastReportedNearLimit = Set<NSManagedObjectID>()

    override static func value(forUndefinedKey _: String) -> Any? {
        nil
    }

    static let lastSyncSucceededPredicate = NSPredicate(format: "apiServer.lastSyncSucceeded == YES")

    private var _cachedAuthToken: String??
    var authToken: String? {
        get {
            if let _cachedAuthToken {
                return _cachedAuthToken
            }

            if objectID.isTemporaryID {
                _cachedAuthToken = .some(nil)
                return nil
            }

            let serverKey = objectID.uriRepresentation().absoluteString

            if let result: String = keyVine[serverKey] {
                _cachedAuthToken = .some(result)
                return result
            }

            if let legacy = value(forKey: "authToken") as? String, let legacyData = legacy.data(using: .utf8) {
                Task { [label] in
                    await Logging.shared.log("Migrating server ID for \(label.orEmpty) to keychain...")
                }
                keyVine[serverKey] = legacyData
                setValue(nil, forKey: "authToken")
                _cachedAuthToken = .some(legacy)
                return legacy
            }

            _cachedAuthToken = .some(nil)
            return nil
        }
        set {
            assert(!objectID.isTemporaryID)
            _cachedAuthToken = .some(newValue)
            let oid = objectID
            Task.detached {
                let serverKey = oid.uriRepresentation().absoluteString
                keyVine[serverKey] = newValue
            }
        }
    }

    override func prepareForDeletion() {
        authToken = nil // clear from keychain
        super.prepareForDeletion()
    }

    @MainActor
    var shouldReportOverTheApiLimit: Bool {
        if requestsRemaining == 0 {
            if !ApiServer.lastReportedOverLimit.contains(objectID) {
                ApiServer.lastReportedOverLimit.insert(objectID)
                ApiServer.lastReportedNearLimit.insert(objectID) // so if we start over the limit, we don't also warn about being near the limit
                return true
            }
        } else {
            ApiServer.lastReportedOverLimit.remove(objectID)
        }
        return false
    }

    @MainActor
    var shouldReportCloseToApiLimit: Bool {
        if (100 * requestsRemaining / requestsLimit) < 20 {
            if !ApiServer.lastReportedNearLimit.contains(objectID) {
                ApiServer.lastReportedNearLimit.insert(objectID)
                return true
            }
        } else {
            ApiServer.lastReportedNearLimit.remove(objectID)
        }
        return false
    }

    var hasApiLimit: Bool {
        requestsLimit > 0
    }

    var goodToGo: Bool {
        !authToken.isEmpty
    }

    @MainActor
    static func resetSyncOfEverything() {
        Task {
            await Logging.shared.log("Resetting sync state of all items")
        }
        for r in Repo.allItems(in: DataManager.main, prefetchRelationships: ["pullRequests", "issues"]) {
            r.resetSyncState()
            for p in r.pullRequests {
                p.resetSyncState()
            }
            for i in r.issues {
                i.resetSyncState()
            }
        }
        preferencesDirty = true
    }

    func deleteEverything() {
        guard let managedObjectContext else { return }

        Task { [label] in
            await Logging.shared.log("Wiping all data for API server \(label ?? "<no API server name>")")
        }
        let categories: [Set<NSManagedObject>] = [pullRequests, issues, labels, teams, comments, statuses, reviews, reactions]
        for list in categories {
            list.forEach { managedObjectContext.delete($0) }
        }
    }

    @MainActor
    static func insertNewServer(in moc: NSManagedObjectContext) -> ApiServer {
        let githubServer: ApiServer = NSEntityDescription.insertNewObject(forEntityName: "ApiServer", into: moc) as! ApiServer
        githubServer.createdAt = Date()
        return githubServer
    }

    @MainActor
    static func resetSyncSuccess(in moc: NSManagedObjectContext) {
        for apiServer in allApiServers(in: moc) where apiServer.goodToGo {
            apiServer.lastSyncSucceeded = true
        }
    }

    @MainActor
    static func shouldReportRefreshFailure(in moc: NSManagedObjectContext) -> Bool {
        for apiServer in allApiServers(in: moc) where apiServer.goodToGo && !apiServer.lastSyncSucceeded && apiServer.reportRefreshFailures {
            return true
        }
        return false
    }

    @MainActor
    static func ensureAtLeastGithub(in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
        f.fetchLimit = 1
        let numberOfExistingApiServers = try! moc.count(for: f)
        if numberOfExistingApiServers == 0 {
            _ = addDefaultGithub(in: moc)
        }
    }

    @MainActor
    @discardableResult
    static func addDefaultGithub(in moc: NSManagedObjectContext) -> ApiServer {
        let githubServer = insertNewServer(in: moc)
        githubServer.resetToGithub()
        return githubServer
    }

    @MainActor
    static func allApiServers(in moc: NSManagedObjectContext) -> [ApiServer] {
        let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try! moc.fetch(f)
    }

    @MainActor
    static func someServersHaveAuthTokens(in moc: NSManagedObjectContext) -> Bool {
        for apiServer in allApiServers(in: moc) where !apiServer.authToken.isEmpty {
            return true
        }
        return false
    }

    static func countApiServers(in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<ApiServer>(entityName: "ApiServer")
        f.includesSubentities = false
        return try! moc.count(for: f)
    }

    func rollBackAllUpdates(in moc: NSManagedObjectContext) {
        Task { [label] in
            await Logging.shared.log("Rolling back changes for failed sync on API server '\(label.orEmpty)'")
        }
        for set in [repos, pullRequests, comments, statuses, labels, issues, teams, reviews, reactions] as [Set<DataItem>] {
            var i = set.makeIterator()
            while let dataItem = i.next() {
                switch dataItem.postSyncAction {
                case PostSyncAction.delete.rawValue:
                    dataItem.postSyncAction = PostSyncAction.doNothing.rawValue
                case PostSyncAction.isNew.rawValue:
                    moc.delete(dataItem)
                case PostSyncAction.isUpdated.rawValue:
                    moc.refresh(dataItem, mergeChanges: false)
                default: break
                }
            }
        }
        moc.refresh(self, mergeChanges: false)
    }

    func updateApiStats(_ stats: ApiStats) {
        requestsRemaining = stats.remaining
        requestsLimit = stats.limit
        resetDate = stats.resetAt
    }

    func test() async throws {
        try await withThrowingTaskGroup { group in
            if let graphQLPath {
                group.addTask {
                    await Logging.shared.log("Checking GraphQL interface on \(graphQLPath)")
                    try await GraphQL.testApi(to: self)
                }
            }

            if let apiPath {
                group.addTask {
                    await Logging.shared.log("Checking REST interface on \(apiPath)")
                    try await RestAccess.testApi(to: self)
                }
            }

            try await group.waitForAll()
        }
    }

    func resetToGithub() {
        webPath = "https://github.com"
        apiPath = "https://api.github.com"
        graphQLPath = "https://api.github.com/graphql"
        label = "GitHub"
        resetSyncState()
    }

    func resetSyncState() {
        Task { @MainActor in
            lastRepoCheck = .distantPast
        }
        lastSyncSucceeded = true
    }

    var isGitHub: Bool {
        apiPath?.hasPrefix("https://api.github.com") ?? true
    }

    @MainActor
    static func server(host: String, moc: NSManagedObjectContext) -> ApiServer? {
        for s in ApiServer.allApiServers(in: moc) {
            if let apiBase = s.apiPath,
               let c = URLComponents(string: apiBase),
               let serverHost = c.host {
                if serverHost == host {
                    return s
                }
            }
            if let webBase = s.webPath,
               let c = URLComponents(string: webBase),
               let serverHost = c.host {
                if serverHost == host {
                    return s
                }
            }
        }
        return nil
    }

    @MainActor
    static var archivedApiServers: [AnyHashable: [AnyHashable: Any]] {
        var archivedData = [AnyHashable: [AnyHashable: Any]]()
        for a in ApiServer.allApiServers(in: DataManager.main) {
            if let authToken = a.authToken, !authToken.isEmpty {
                var apiServerData = [AnyHashable: Any]()
                for (k, _) in a.entity.attributesByName {
                    if let v = a.value(forKey: k) as? NSObject {
                        apiServerData[k] = v
                    }
                }
                apiServerData["repos"] = a.archivedRepos
                archivedData[authToken] = apiServerData
            }
        }
        return archivedData
    }

    var archivedRepos: [AnyHashable: [AnyHashable: Any]] {
        var archivedData = [AnyHashable: [AnyHashable: Any]]()
        for r in repos {
            var repoData = [AnyHashable: Any]()
            for (k, _) in r.entity.attributesByName {
                if let v = r.value(forKey: k) as? NSObject {
                    repoData[k] = v
                }
            }
            let id = r.nodeId ?? UUID().uuidString
            archivedData[id] = repoData
        }
        return archivedData
    }

    @MainActor
    static func configure(from archive: [String: [String: NSObject]]) async -> Bool {
        for apiServer in allApiServers(in: DataManager.main) {
            DataManager.main.delete(apiServer)
        }

        var servers = [String: ApiServer]()

        for (authToken, apiServerData) in archive {
            let a = insertNewServer(in: DataManager.main)
            for (k, v) in apiServerData {
                if k == "repos" {
                    let archive = v as! [String: [String: NSObject]]
                    a.configureRepos(from: archive)
                } else {
                    if a.entity.attributesByName.keys.contains(k) {
                        a.setValue(v, forKey: k)
                    }
                }
            }
            a.resetSyncState()
            servers[authToken] = a
        }

        await DataManager.saveDB()

        for (k, a) in servers {
            a.authToken = k
        }

        return true
    }

    func configureRepos(from archive: [String: [String: NSObject]]) {
        guard let managedObjectContext else { return }
        for (_, repoData) in archive {
            let r = NSEntityDescription.insertNewObject(forEntityName: "Repo", into: managedObjectContext) as! Repo
            for (k, v) in repoData where r.entity.attributesByName.keys.contains(k) {
                r.setValue(v, forKey: k)
            }
            r.apiServer = self
            r.resetSyncState()
            r.postSyncAction = PostSyncAction.isUpdated.rawValue
        }
    }

    // MARK: GraphQL

    func run(queries: Lista<Query>) async throws {
        let path = graphQLPath.orEmpty
        let token = authToken.orEmpty

        try await GraphQL.runQueries(queries: queries, on: path, token: token) { [weak self] newStats in
            self?.managedObjectContext?.perform {
                self?.updateApiStats(newStats)
            }
        }
    }
}
