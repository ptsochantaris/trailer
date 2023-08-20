import Foundation
import Lista
import Semalot
import TrailerQL

extension Node {
    var creationSkipped: Bool {
        get {
            flags & 0b0000_0001 != 0
        }
        set {
            if newValue {
                flags |= 0b0000_0001
            } else {
                flags &= 0b1111_1110
            }
        }
    }

    var created: Bool {
        get {
            flags & 0b0000_0010 != 0
        }
        set {
            if newValue {
                flags |= 0b0000_0010
            } else {
                flags &= 0b1111_1101
            }
        }
    }

    var updated: Bool {
        get {
            flags & 0b0000_0100 != 0
        }
        set {
            if newValue {
                flags |= 0b0000_0100
            } else {
                flags &= 0b1111_1011
            }
        }
    }

    var forcedUpdate: Bool {
        get {
            flags & 0b0000_1000 != 0
        }
        set {
            if newValue {
                flags |= 0b0000_1000
            } else {
                flags &= 0b1111_0111
            }
        }
    }
}

@MainActor
enum GraphQL {
    static func setup() {
        TQL.debugLog = { message in
            Logging.log(message)
        }
    }

    enum Profile: RawRepresentable {
        case light, cautious, moderate, high

        init(rawValue: Int) {
            switch rawValue {
            case 10:
                self = .high
            case 0:
                self = .moderate
            case -10:
                self = .cautious
            default:
                self = .light
            }
        }

        var rawValue: Int {
            switch self {
            case .high:
                return 10
            case .moderate:
                return 0
            case .cautious:
                return -10
            case .light:
                return -20
            }
        }

        var itemInitialBatchCost: Int {
            switch self {
            case .high:
                return 40000
            case .moderate:
                return 10000
            case .cautious:
                return 2000
            case .light:
                return 1000
            }
        }

        var itemIncrementalBatchCost: Int {
            switch self {
            case .high:
                return 20000
            case .moderate:
                return 6000
            case .cautious:
                return 2000
            case .light:
                return 1000
            }
        }

        var itemAccompanyingBatchCount: Int {
            switch self {
            case .high:
                return 10000
            case .moderate:
                return 6000
            case .cautious:
                return 2000
            case .light:
                return 1000
            }
        }

        var largePageSize: Group.Paging {
            switch self {
            case .high:
                return .first(count: 80, paging: true)
            case .moderate:
                return .first(count: 50, paging: true)
            case .cautious:
                return .first(count: 20, paging: true)
            case .light:
                return .first(count: 10, paging: true)
            }
        }

        var mediumPageSize: Group.Paging {
            switch self {
            case .high:
                return .first(count: 40, paging: true)
            case .moderate:
                return .first(count: 20, paging: true)
            case .cautious:
                return .first(count: 10, paging: true)
            case .light:
                return .first(count: 8, paging: true)
            }
        }

        var smallPageSize: Group.Paging {
            switch self {
            case .light:
                return .first(count: 5, paging: true)
            case .cautious:
                return .first(count: 5, paging: true)
            case .moderate:
                return .first(count: 10, paging: true)
            case .high:
                return .first(count: 20, paging: true)
            }
        }
    }

    private static let nameWithOwnerField = Field("nameWithOwner")

    private static let userFragment = Fragment(on: "User") {
        Field.id
        Field("login")
        Field("avatarUrl")
    }

    private static let mannequinFragment = Fragment(on: "Mannequin") {
        Field.id
        Field("login")
        Field("avatarUrl")
    }

    private static let authorGroup = Group("author") {
        userFragment
        Fragment(on: "Bot") {
            Field.id
            Field("login")
            Field("avatarUrl")
        }
    }

    private static func commentGroup(for typeName: String) -> Group {
        Group("comments", paging: Settings.cache.syncProfile.largePageSize) {
            Fragment(on: typeName) {
                Field.id
                Field("body")
                Field("url")
                Field("createdAt")
                Field("updatedAt")
                authorGroup
            }
        }
    }

    static func testApi(to apiServer: ApiServer) async throws {
        var gotUserNode = false
        let testQuery = Query(name: "Testing", rootElement: Group("viewer") { userFragment }) { node in
            Logging.log("Got a node, type: \(node.elementType), id: \(node.id)")
            if node.elementType == "User" {
                gotUserNode = true
            }
        }
        _ = try await run(testQuery, for: apiServer.graphQLPath.orEmpty, authToken: apiServer.authToken.orEmpty, expectedNodeCost: nil, attempts: 1) { _ in }
        if !gotUserNode {
            throw ApiError.noUserRecordFound
        }
    }

    private static let singleGateKeeper = Semalot(tickets: 1)
    static let multiGateKeeper = Semalot(tickets: 2)

    static var callCount = 0

    private static func fetchData(from urlString: String, for query: Query, authToken: String, attempts: Int) async throws -> JSON {
        let Q = query.queryText

        guard let url = URL(string: urlString) else {
            throw ApiError.invalidUrl(urlString)
        }

        guard let requestData = try? JSONSerialization.data(withJSONObject: ["query": Q]) else {
            throw ApiError.graphQLFailure("\(query.logPrefix)Could not serialise query")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")
        if Settings.V4IdMigrationPhase.wantsNewIds {
            request.setValue("1", forHTTPHeaderField: "X-Github-Next-Global-ID")
        }

        let gate = Settings.threadedSync ? multiGateKeeper : singleGateKeeper

        await gate.takeTicket()

        let start = Date()

        defer {
            gate.returnTicket()
            Logging.log("\(query.logPrefix)Response time: \(-start.timeIntervalSinceNow) sec")
        }

        Task { @MainActor in
            callCount += 1
            API.currentOperationName = query.name + " (call \(callCount))"
        }

        Logging.log("\(query.logPrefix)Fetching: \(Q)")

        guard let json = try await HTTP.getJsonData(for: request, attempts: attempts, logPrefix: query.logPrefix, retryOnInvalidJson: true).json as? JSON else {
            throw ApiError.graphQLFailure("\(query.logPrefix)Retuned data is not JSON")
        }

        return json
    }

    private static func run(_ query: Query, for urlString: String, authToken: String, expectedNodeCost: Int?, attempts: Int = 5, newStats: @escaping (ApiStats) -> Void) async throws {
        if let expectedNodeCost {
            Logging.log("\(query.logPrefix)Queued - Expected Count: \(expectedNodeCost)")
        }

        var currentAttempt = attempts

        while true {
            let json = try await fetchData(from: urlString, for: query, authToken: authToken, attempts: attempts)

            var migratedIds = [String: String]()
            if let extensions = json["extensions"] as? JSON, let warnings = extensions["warnings"] as? [JSON] {
                let deprecations = warnings.compactMap { $0["data"] as? JSON }
                for deprecation in deprecations {
                    if let oldId = deprecation["legacy_global_id"] as? String, let newId = deprecation["next_global_id"] as? String, oldId != newId {
                        migratedIds[oldId] = newId
                    }
                }
            }

            let apiStats = ApiStats.fromV4(json: json["data"] as? JSON, migratedIds: migratedIds.isEmpty ? nil : migratedIds)

            if let expectedNodeCost {
                if let apiStats {
                    Logging.log("\(query.logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Expected Count: \(expectedNodeCost) - Returned Count: \(apiStats.nodeCount))")
                    if expectedNodeCost != apiStats.nodeCount {
                        Logging.log("Warning: Mismatched expected and received node count!")
                    }
                    newStats(apiStats)
                } else {
                    Logging.log("\(query.logPrefix)Received page (No stats) - Expected Count: \(expectedNodeCost)")
                }
            } else {
                if let apiStats {
                    Logging.log("\(query.logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Returned Count: \(apiStats.nodeCount))")
                    newStats(apiStats)
                } else {
                    Logging.log("\(query.logPrefix)Received page (No stats)")
                }
            }

            let errorMessage: String?
            if json.keys.contains("data") {
                errorMessage = nil
            } else if let errors = json["errors"] as? [JSON] {
                errorMessage = errors.first?["message"] as? String
            } else {
                errorMessage = json["message"] as? String
            }

            if let errorMessage {
                if currentAttempt > 0 {
                    Logging.log("Retrying on GitHub error (attempts left: \(currentAttempt)): \(errorMessage)")
                    try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                    currentAttempt -= 1
                    continue
                }
                throw ApiError.graphQLFailure("\(query.logPrefix)Server error: \(errorMessage)")
            }

            do {
                let extraQueries = try await query.processResponse(from: json)
                if extraQueries.count > 0 {
                    try await runQueries(queries: extraQueries, on: urlString, token: authToken, newStats: newStats)
                }
                break

            } catch {
                throw ApiError.graphQLFailure("\(query.logPrefix)Error while parsing GraphQL response: \(error.localizedDescription) - in: \(json)")
            }
        }
    }

    static func runQueries(queries: Lista<Query>, on path: String, token: String, newStats: @escaping (ApiStats) -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for query in queries {
                group.addTask {
                    do {
                        try await run(query, for: path, authToken: token, expectedNodeCost: query.nodeCost, newStats: newStats)
                    } catch _ as CancellationError {
                        // nothing to do here
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    static func update<T: ListableItem>(for items: [T], steps: API.SyncSteps) async throws {
        let typeName = T.typeName

        if let prs = items as? [PullRequest] {
            if steps.contains(.reviews) {
                prs.forEach {
                    $0.reviews.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }

            if steps.contains(.statuses) {
                let now = Date()
                prs.forEach {
                    $0.lastStatusScan = now
                    $0.statuses.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }
        }

        if steps.contains(.reactions) {
            let now = Date()
            items.forEach {
                $0.lastReactionScan = now
                $0.reactions.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
        }

        if steps.contains(.comments) {
            items.forEach {
                $0.comments.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
        }

        try await process(name: steps.toString, items: items, parentType: T.self, maxCost: Settings.cache.syncProfile.itemAccompanyingBatchCount) {
            let profile = Settings.cache.syncProfile
            Fragment(on: typeName) {
                Field.id

                if items is [PullRequest] {
                    if steps.contains(.reviewRequests) {
                        Group("reviewRequests", paging: profile.smallPageSize) {
                            Fragment(on: "ReviewRequest") {
                                Field.id
                                Group("requestedReviewer") {
                                    userFragment
                                    mannequinFragment
                                    Fragment(on: "Team") {
                                        Field.id
                                        Field("slug")
                                    }
                                }
                            }
                        }
                    }

                    if steps.contains(.reviews) {
                        Group("reviews", paging: profile.smallPageSize) {
                            Fragment(on: "PullRequestReview") {
                                Field.id
                                Field("body")
                                Field("state")
                                Field("createdAt")
                                Field("updatedAt")
                                authorGroup
                            }
                        }
                    }

                    if steps.contains(.statuses) {
                        Group("commits", paging: .last(count: 1)) {
                            Group("commit") {
                                Group("checkSuites", paging: profile.smallPageSize) {
                                    Group("checkRuns", paging: profile.smallPageSize) {
                                        Fragment(on: "CheckRun") {
                                            Field.id
                                            Field("name")
                                            Field("conclusion")
                                            Field("startedAt")
                                            Field("completedAt")
                                            Field("permalink")
                                        }
                                    }
                                }
                                Group("status") {
                                    Group("contexts") {
                                        Fragment(on: "StatusContext") {
                                            Field.id
                                            Field("context")
                                            Field("description")
                                            Field("state")
                                            Field("targetUrl")
                                            Field("createdAt")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if steps.contains(.reactions) {
                    Group("reactions", paging: profile.smallPageSize) {
                        Fragment(on: "Reaction") {
                            Field.id
                            Field("content")
                            Field("createdAt")
                            Group("user") { userFragment }
                        }
                    }
                }

                if steps.contains(.comments) {
                    commentGroup(for: "IssueComment")
                }
            }
        }
    }

    static func updateReactions(for comments: [PRComment]) async throws {
        try await process(name: "Comment Reactions", items: comments, maxCost: Settings.cache.syncProfile.itemAccompanyingBatchCount) {
            Fragment(on: "IssueComment") {
                Field.id
                Group("reactions", paging: Settings.cache.syncProfile.largePageSize) {
                    Fragment(on: "Reaction") {
                        Field.id
                        Field("content")
                        Field("createdAt")
                        Group("user") { userFragment }
                    }
                }
            }
        }
    }

    static func updateComments(for reviews: [Review]) async throws {
        try await process(name: "Review Comments", items: reviews, maxCost: Settings.cache.syncProfile.itemAccompanyingBatchCount) {
            Fragment(on: "PullRequestReview") {
                Field.id
                commentGroup(for: "PullRequestReviewComment")
            }
        }
    }

    private static func process(name: String, items: [DataItem], parentType: (some ListableItem).Type? = nil, maxCost: Int, @ElementsBuilder fields: () -> [any Element]) async throws {
        if items.isEmpty {
            return
        }

        var itemIdsByServer = [ApiServer: Lista<String>]()
        for item in items {
            guard let nodeId = item.nodeId else {
                continue
            }
            let server = item.apiServer
            if let existing = itemIdsByServer[server] {
                existing.append(nodeId)
            } else {
                itemIdsByServer[server] = Lista(value: nodeId)
            }
        }
        for (server, ids) in itemIdsByServer {
            var nodes = [String: Lista<Node>]()
            let serverName = server.label ?? "<no label>"
            let nodeBlock: Query.PerNodeBlock = { node in
                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = Lista<Node>(value: node)
                }
            }

            do {
                let queries = Query.batching("\(serverName): \(name)", groupName: "nodes", idList: ids, maxCost: maxCost, perNode: nodeBlock, fields: fields)
                try await server.run(queries: queries)
                await scanNodes(nodes, from: server, parentType: parentType)
            } catch {
                server.lastSyncSucceeded = false
                throw error
            }
        }
    }

    private static let milestoneFragment = Fragment(on: "Milestone") {
        Field("title")
    }

    private static let labelFragment = Fragment(on: "Label") {
        Field.id
        Field("name")
        Field("color")
        Field("createdAt")
        Field("updatedAt")
    }

    private static let repositoryFragment = Fragment(on: "Repository") {
        Field.id
        Field("createdAt")
        Field("updatedAt")
        Field("isFork")
        Field("isArchived")
        Field("nameWithOwner")
        Field("url")
        Field("isPrivate")
        Group("owner") { Field.id }
    }

    private static func prFragment(includeRepo: Bool) -> Fragment {
        Fragment(on: "PullRequest") {
            Field.id
            Field("bodyText")
            Field("state")
            Field("createdAt")
            Field("updatedAt")
            Field("number")
            Field("title")
            Field("url")
            Group("milestone") { milestoneFragment }
            authorGroup
            let profile = Settings.cache.syncProfile
            Group("assignees", paging: profile.smallPageSize) { userFragment }
            Group("labels", paging: profile.smallPageSize) { labelFragment }
            Field("headRefOid")
            Field("mergeable")
            Field("additions")
            Field("deletions")
            Field("headRefName")
            Field("baseRefName")
            Field("isDraft")
            Group("mergedBy") { Fragment(on: "User") { Field.id } }
            Group("baseRepository") { nameWithOwnerField }
            Group("headRepository") { nameWithOwnerField }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    private static func issueFragment(includeRepo: Bool) -> Fragment {
        Fragment(on: "Issue") {
            Field.id
            Field("bodyText")
            Field("state")
            Field("createdAt")
            Field("updatedAt")
            Field("number")
            Field("title")
            Field("url")
            Group("milestone") { milestoneFragment }
            authorGroup
            Group("assignees", paging: Settings.cache.syncProfile.smallPageSize) { userFragment }
            Group("labels", paging: Settings.cache.syncProfile.smallPageSize) { labelFragment }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = Group("pullRequests", ("states", "[OPEN]"), paging: Settings.cache.syncProfile.mediumPageSize) {
                        prFragment(includeRepo: true)
                    }
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, label: "PRs", fields: { g }) {
                            await checkAuthoredPrClosures(nodes: nodes, in: server)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredIssues(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredIssues {
                    let g = Group("issues", ("states", "[OPEN]"), paging: .max) {
                        issueFragment(includeRepo: true)
                    }
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, label: "Issues", fields: { g }) {
                            checkAuthoredIssueClosures(nodes: nodes, in: server)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredItems(from server: ApiServer, label: String, @ElementsBuilder fields: () -> [any Element]) async -> [String: Lista<Node>]? {
        var nodes = [String: Lista<Node>]()
        let group = Group("viewer", fields: fields)
        let authoredItemsQuery = Query(name: "Authored \(label)", rootElement: group) { node in
            let type = node.elementType
            if let existingList = nodes[type] {
                existingList.append(node)
            } else {
                nodes[type] = Lista<Node>(value: node)
            }
        }
        do {
            try await server.run(queries: Lista(value: authoredItemsQuery))
            await scanNodes(nodes, from: server, parentType: nil)
            return nodes

        } catch {
            server.lastSyncSucceeded = false
            return nil
        }
    }

    private static func checkAuthoredPrClosures(nodes: [String: Lista<Node>], in server: ApiServer) async {
        let prIdsToCheck = Lista<String>()
        let fetchedPrIds = Set(nodes["PullRequest"]?.map(\.id) ?? [])
        for repo in server.repos.filter({ $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }) {
            let ids = repo.pullRequests.compactMap(\.nodeId).filter { !fetchedPrIds.contains($0) }
            prIdsToCheck.append(from: ids)
        }

        if prIdsToCheck.count == 0 {
            return
        }

        let prGroup = Group("pullRequests") { prFragment(includeRepo: true) }
        let group = BatchGroup(name: "nodes", templateGroup: prGroup, idList: prIdsToCheck)
        let nodes = Lista<Node>()
        let query = Query(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) { node in
            node.forcedUpdate = true
            nodes.append(node)
        }
        do {
            try await server.run(queries: Lista(value: query))
            await scanNodes(["PullRequest": nodes], from: server, parentType: nil)
        } catch {
            server.lastSyncSucceeded = false
        }
    }

    private static func checkAuthoredIssueClosures(nodes: [String: Lista<Node>], in server: ApiServer) {
        let fetchedIssueIds = Set(nodes["Issue"]?.map(\.id) ?? []) // investigate missing issues
        for repo in server.repos.filter({ $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for issue in repo.issues where !fetchedIssueIds.contains(issue.nodeId.orEmpty) {
                issue.stateChanged = ListableItem.StateChange.closed.rawValue
                issue.condition = ItemCondition.closed.rawValue
            }
        }
    }

    private static var latestPrsFragment = Fragment(on: "Repository") {
        Field.id
        Group("pullRequests", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: Settings.cache.syncProfile.smallPageSize) {
            prFragment(includeRepo: false)
        }
    }

    private static var latestIssuesFragment = Fragment(on: "Repository") {
        Field.id
        Group("issues", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: Settings.cache.syncProfile.smallPageSize) {
            issueFragment(includeRepo: false)
        }
    }

    private static var allOpenPrsFragment = Fragment(on: "Repository") {
        Field.id
        Group("pullRequests", ("states", "[OPEN]"), paging: Settings.cache.syncProfile.mediumPageSize) {
            prFragment(includeRepo: false)
        }
    }

    private static var allOpenIssuesFragment = Fragment(on: "Repository") {
        Field.id
        Group("issues", ("states", "[OPEN]"), paging: Settings.cache.syncProfile.largePageSize) {
            issueFragment(includeRepo: false)
        }
    }

    static func fetchAllSubscribedPrs(from repos: [Repo]) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var prRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        for repo in repos {
            if let n = repo.nodeId, repo.displayPolicyForPrs != hideValue {
                prRepoIdToLatestExistingUpdate[n] = PullRequest.mostRecentItemUpdate(in: repo)
            }
        }

        for (server, reposInThisServer) in reposByServer {
            var nodes = [String: Lista<Node>]()

            let perNodeBlock: Query.PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = Lista<Node>(value: node)
                }

                if type == "PullRequest",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < prRepoIdToLatestExistingUpdate[repo.id]! {
                    throw TQL.Error.alreadyParsed
                }
            }

            let queriesForServer = Lista<Query>()
            let serverLabel = server.label ?? "<no label>"

            let idsForReposInThisServerWantingAllOpenPrs = Lista<String>()
            let idsForReposInThisServerWantingLatestPrs = Lista<String>()
            for repo in reposInThisServer {
                if let n = repo.nodeId {
                    if let last = prRepoIdToLatestExistingUpdate[n], last != .distantPast {
                        idsForReposInThisServerWantingLatestPrs.append(n)
                    } else if repo.displayPolicyForPrs != hideValue {
                        idsForReposInThisServerWantingAllOpenPrs.append(n)
                    }
                }
            }

            if idsForReposInThisServerWantingLatestPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Updated PRs", groupName: "nodes", idList: idsForReposInThisServerWantingLatestPrs, maxCost: Settings.cache.syncProfile.itemIncrementalBatchCost, perNode: perNodeBlock) { latestPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Open PRs", groupName: "nodes", idList: idsForReposInThisServerWantingAllOpenPrs, maxCost: Settings.cache.syncProfile.itemInitialBatchCost, perNode: perNodeBlock) { allOpenPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await scanNodes(nodes, from: server, parentType: nil)
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }

    static func fetchAllSubscribedIssues(from repos: [Repo]) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var issueRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        for repo in repos {
            if let n = repo.nodeId, repo.displayPolicyForIssues != hideValue {
                issueRepoIdToLatestExistingUpdate[n] = Issue.mostRecentItemUpdate(in: repo)
            }
        }

        for (server, reposInThisServer) in reposByServer {
            var nodes = [String: Lista<Node>]()

            let perNodeBlock: Query.PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = Lista<Node>(value: node)
                }

                if type == "Issue",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < issueRepoIdToLatestExistingUpdate[repo.id]! {
                    throw TQL.Error.alreadyParsed
                }
            }

            let queriesForServer = Lista<Query>()
            let serverLabel = server.label ?? "<no label>"

            let idsForReposInThisServerWantingAllOpenIssues = Lista<String>()
            let idsForReposInThisServerWantingLatestIssues = Lista<String>()
            for repo in reposInThisServer {
                if let n = repo.nodeId {
                    if let last = issueRepoIdToLatestExistingUpdate[n], last != .distantPast {
                        idsForReposInThisServerWantingLatestIssues.append(n)
                    } else if repo.displayPolicyForIssues != hideValue {
                        idsForReposInThisServerWantingAllOpenIssues.append(n)
                    }
                }
            }

            if idsForReposInThisServerWantingLatestIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Updated Issues", groupName: "nodes", idList: idsForReposInThisServerWantingLatestIssues, maxCost: Settings.cache.syncProfile.itemIncrementalBatchCost, perNode: perNodeBlock) { latestIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Open Issues", groupName: "nodes", idList: idsForReposInThisServerWantingAllOpenIssues, maxCost: Settings.cache.syncProfile.itemInitialBatchCost, perNode: perNodeBlock) { allOpenIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await scanNodes(nodes, from: server, parentType: nil)
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }

    private static func scanNodes(_ nodes: [String: Lista<Node>], from server: ApiServer, parentType: (some DataItem).Type?) async {
        guard nodes.count > 0, let moc = server.managedObjectContext else { return }
        await DataManager.runInChild(of: moc) { child in
            guard let server = try? child.existingObject(with: server.objectID) as? ApiServer else {
                return
            }

            let parentCache = FetchCache()
            // Order must be fixed, since labels may refer to PRs or Issues, ensure they are created first

            if let nodeList = nodes["Repository"] {
                Repo.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["Issue"] {
                Issue.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequest"] {
                PullRequest.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["Label"] {
                PRLabel.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["CommentReaction"] {
                Reaction.sync(from: nodeList, for: PRComment.self, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["IssueComment"] {
                PRComment.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequestReviewComment"] {
                PRComment.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["Reaction"], let parentType {
                Reaction.sync(from: nodeList, for: parentType, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["ReviewRequest"] {
                Review.syncRequests(from: nodeList, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequestReview"] {
                Review.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["StatusContext"] {
                PRStatus.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
            if let nodeList = nodes["CheckRun"] {
                PRStatus.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
            }
        }
    }

    @MainActor
    static func migrateV4Ids(for type: DataItem.Type, in server: ApiServer) async throws {
        guard let graphQLPath = server.graphQLPath, let authToken = server.authToken, let moc = server.managedObjectContext else {
            return
        }

        let serverName = server.label.orEmpty

        let typeName = type.typeName
        Logging.log("Migrating V4 \(typeName) DSs in `\(serverName)`")

        let ids = type.allIds(in: server, moc: moc)
        Logging.log("\(ids.count) IDs to process")
        if ids.isEmpty {
            return
        }

        do {
            let queries = Query.batching("\(serverName): \(typeName) ID Migration", groupName: "nodes", idList: ids, maxCost: 1000, perNode: nil) {
                Field.id
            }

            try await GraphQL.runQueries(queries: queries, on: graphQLPath, token: authToken) { newStats in
                moc.perform {
                    server.updateApiStats(newStats)
                    if let idMigrations = newStats.migratedIds {
                        for (k, v) in idMigrations where k != v {
                            // Logging.log("Migrating \(typeName) ID \(k) to \(v)")
                            if let item = type.item(id: k, in: moc) {
                                item.nodeId = v
                            }
                        }
                    }
                }
            }

        } catch {
            server.lastSyncSucceeded = false
            throw error
        }
    }
}
