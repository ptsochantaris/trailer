import CoreData
import Foundation
import Lista
import Semalot
import TrailerJson
import TrailerQL

extension ParseOutput {
    func asForcedUpdate() -> ParseOutput {
        switch self {
        case let .node(node):
            node.forcedUpdate = true
            return .node(node)
        case .queryComplete, .queryPageComplete:
            return self
        }
    }
}

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
        Task { @LogActor in
            TQL.debugLog = { message in
                Logging.log(message)
            }
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
                10
            case .moderate:
                0
            case .cautious:
                -10
            case .light:
                -20
            }
        }

        var itemInitialBatchCost: Int {
            switch self {
            case .high:
                40000
            case .moderate:
                10000
            case .cautious:
                2000
            case .light:
                1000
            }
        }

        var itemIncrementalBatchCost: Int {
            switch self {
            case .high:
                20000
            case .moderate:
                6000
            case .cautious:
                2000
            case .light:
                1000
            }
        }

        var itemAccompanyingBatchCount: Int {
            switch self {
            case .high:
                10000
            case .moderate:
                6000
            case .cautious:
                2000
            case .light:
                1000
            }
        }

        var largePageSize: Group.Paging {
            switch self {
            case .high:
                .first(count: 80, paging: true)
            case .moderate:
                .first(count: 50, paging: true)
            case .cautious:
                .first(count: 20, paging: true)
            case .light:
                .first(count: 10, paging: true)
            }
        }

        var mediumPageSize: Group.Paging {
            switch self {
            case .high:
                .first(count: 40, paging: true)
            case .moderate:
                .first(count: 20, paging: true)
            case .cautious:
                .first(count: 10, paging: true)
            case .light:
                .first(count: 8, paging: true)
            }
        }

        var smallPageSize: Group.Paging {
            switch self {
            case .light:
                .first(count: 5, paging: true)
            case .cautious:
                .first(count: 5, paging: true)
            case .moderate:
                .first(count: 10, paging: true)
            case .high:
                .first(count: 20, paging: true)
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

    private static func commentGroup(for typeName: String, profile: Profile) -> Group {
        Group("comments", paging: profile.largePageSize) {
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
        nonisolated(unsafe) var gotUserNode = false
        let testQuery = Query(name: "Testing", rootElement: Group("viewer") { userFragment }) {
            if case let .node(node) = $0 {
                Logging.log("Got a node, type: \(node.elementType), id: \(node.id)")
                if node.elementType == "User" {
                    gotUserNode = true
                }
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

    private static func fetchData(from urlString: String, for query: Query, authToken: String, attempts: Int) async throws -> TypedJson.Entry {
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

        guard let json = try await HTTP.getJsonData(for: request, attempts: attempts, logPrefix: query.logPrefix, retryOnInvalidJson: true).json else {
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
            if let extensions = json.potentialObject(named: "extensions"), let warnings = extensions.potentialArray(named: "warnings") {
                let deprecations = warnings.compactMap { $0.potentialObject(named: "data") }
                for deprecation in deprecations {
                    if let oldId = deprecation.potentialString(named: "legacy_global_id"), let newId = deprecation.potentialString(named: "next_global_id"), oldId != newId {
                        migratedIds[oldId] = newId
                    }
                }
            }

            let apiStats = ApiStats.fromV4(json: json.potentialObject(named: "data"), migratedIds: migratedIds.isEmpty ? nil : migratedIds)

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

            let hasData = (try? json.keys.contains("data")) == true
            let errorMessage: String? = if hasData {
                nil
            } else if let errors = json.potentialArray(named: "errors") {
                errors.first?.potentialString(named: "message")
            } else {
                json.potentialString(named: "message")
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

    static func update<T: ListableItem>(for items: [T], steps: API.SyncSteps, settings: Settings.Cache) async throws {
        let typeName = T.typeName

        if let prs = items as? [PullRequest] {
            if steps.contains(.reviews) {
                for pr in prs {
                    for review in pr.reviews {
                        review.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }

            if steps.contains(.statuses) {
                let now = Date()
                for pr in prs {
                    pr.lastStatusScan = now
                    for status in pr.statuses {
                        status.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
            }
        }

        if steps.contains(.reactions) {
            let now = Date()
            for item in items {
                item.lastReactionScan = now
                for reaction in item.reactions {
                    reaction.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
        }

        if steps.contains(.comments) {
            for item in items {
                for comment in item.comments {
                    comment.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
        }

        let profile = settings.syncProfile
        try await process(name: steps.toString, items: items, parentType: T.self, maxCost: profile.itemAccompanyingBatchCount) {
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
                    commentGroup(for: "IssueComment", profile: profile)
                }
            }
        }
    }

    static func updateReactions(for comments: [PRComment], profile: Profile) async throws {
        try await process(name: "Comment Reactions", items: comments, maxCost: profile.itemAccompanyingBatchCount) {
            Fragment(on: "IssueComment") {
                Field.id
                Group("reactions", paging: profile.largePageSize) {
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

    static func updateComments(for reviews: [Review], profile: Profile) async throws {
        try await process(name: "Review Comments", items: reviews, maxCost: profile.itemAccompanyingBatchCount) {
            Fragment(on: "PullRequestReview") {
                Field.id
                commentGroup(for: "PullRequestReviewComment", profile: profile)
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
            let scanner = NodeScanner(server: server, parentType: parentType)
            let serverName = server.label ?? "<no label>"
            let queries = Query.batching("\(serverName): \(name)", groupName: "nodes", idList: ids, maxCost: maxCost, perNode: { scanner.add(progress: $0) }, fields: fields)
            do {
                try await server.run(queries: queries)
                await scanner.done()
            } catch {
                await scanner.done()
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

    private static func prFragment(includeRepo: Bool, settings: Settings.Cache) -> Fragment {
        let syncProfile = settings.syncProfile
        return Fragment(on: "PullRequest") {
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
            Group("assignees", paging: syncProfile.smallPageSize) { userFragment }
            Group("labels", paging: syncProfile.smallPageSize) { labelFragment }
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
            if settings.showClosingInfo {
                Group("closingIssuesReferences", paging: syncProfile.smallPageSize) { Field.id }
            }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    private static func issueFragment(includeRepo: Bool, settings: Settings.Cache) -> Fragment {
        let syncProfile = settings.syncProfile
        return Fragment(on: "Issue") {
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
            Group("assignees", paging: syncProfile.smallPageSize) { userFragment }
            Group("labels", paging: syncProfile.smallPageSize) { labelFragment }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer], settings: Settings.Cache) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = Group("pullRequests", ("states", "[OPEN]"), paging: settings.syncProfile.mediumPageSize) {
                        prFragment(includeRepo: true, settings: settings)
                    }
                    group.addTask {
                        if let nodes = await fetchAllAuthoredItems(from: server, label: "PRs", fields: { g }) {
                            await checkAuthoredPrClosures(nodes: nodes, in: server, settings: settings)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredIssues(from servers: [ApiServer], settings: Settings.Cache) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if settings.queryAuthoredIssues {
                    let g = Group("issues", ("states", "[OPEN]"), paging: .max) {
                        issueFragment(includeRepo: true, settings: settings)
                    }
                    group.addTask {
                        if let nodes = await fetchAllAuthoredItems(from: server, label: "Issues", fields: { g }) {
                            await checkAuthoredIssueClosures(nodes: nodes, in: server)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredItems(from server: ApiServer, label: String, @ElementsBuilder fields: () -> [any Element]) async -> Lista<Node>? {
        let group = Group("viewer", fields: fields)
        let scanner = NodeScanner(server: server, parentType: nil)
        do {
            let nodesList = Lista<Node>()
            let authoredItemsQuery = Query(name: "Authored \(label)", rootElement: group) {
                scanner.add(progress: $0)
                if case let .node(node) = $0 {
                    nodesList.append(node)
                }
            }
            try await server.run(queries: Lista(value: authoredItemsQuery))
            await scanner.done()
            return nodesList

        } catch {
            await scanner.done()
            server.lastSyncSucceeded = false
            return nil
        }
    }

    private static func checkAuthoredPrClosures(nodes: Lista<Node>, in server: ApiServer, settings: Settings.Cache) async {
        let prIdsToCheck = Lista<String>()
        let fetchedPrIds = Set(nodes.map(\.id))
        for repo in server.repos.filter({ $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }) {
            let ids = repo.pullRequests.compactMap(\.nodeId).filter { !fetchedPrIds.contains($0) }
            prIdsToCheck.append(from: ids)
        }

        if prIdsToCheck.count == 0 {
            return
        }

        let prGroup = Group("pullRequests") { prFragment(includeRepo: true, settings: settings) }
        let group = BatchGroup(name: "nodes", templateGroup: prGroup, idList: prIdsToCheck)
        let scanner = NodeScanner(server: server, parentType: nil)
        let query = Query(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) {
            scanner.add(progress: $0.asForcedUpdate())
        }
        do {
            try await server.run(queries: Lista(value: query))
            await scanner.done()
        } catch {
            await scanner.done()
            server.lastSyncSucceeded = false
        }
    }

    private static func checkAuthoredIssueClosures(nodes: Lista<Node>, in server: ApiServer) {
        let fetchedIssueIds = Set(nodes.map(\.id)) // investigate missing issues
        for repo in server.repos.filter({ $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for issue in repo.issues where !fetchedIssueIds.contains(issue.nodeId.orEmpty) && issue.shouldCheckForClosing {
                issue.stateChanged = ListableItem.StateChange.closed.rawValue
                issue.condition = ItemCondition.closed.rawValue
            }
        }
    }

    private static func latestPrsFragment(settings: Settings.Cache) -> Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("pullRequests", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: settings.syncProfile.smallPageSize) {
                prFragment(includeRepo: false, settings: settings)
            }
        }
    }

    private static func latestIssuesFragment(settings: Settings.Cache) -> Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("issues", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: settings.syncProfile.smallPageSize) {
                issueFragment(includeRepo: false, settings: settings)
            }
        }
    }

    private static func allOpenPrsFragment(settings: Settings.Cache) -> Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("pullRequests", ("states", "[OPEN]"), paging: settings.syncProfile.mediumPageSize) {
                prFragment(includeRepo: false, settings: settings)
            }
        }
    }

    private static func allOpenIssuesFragment(settings: Settings.Cache) -> Fragment {
        Fragment(on: "Repository") {
            Field.id
            Group("issues", ("states", "[OPEN]"), paging: settings.syncProfile.largePageSize) {
                issueFragment(includeRepo: false, settings: settings)
            }
        }
    }

    static func fetchAllSubscribedPrs(from repos: [Repo], settings: Settings.Cache) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var _prRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        for repo in repos {
            if let n = repo.nodeId, repo.displayPolicyForPrs != hideValue {
                _prRepoIdToLatestExistingUpdate[n] = PullRequest.mostRecentItemUpdate(in: repo)
            }
        }

        let prRepoIdToLatestExistingUpdate = _prRepoIdToLatestExistingUpdate
        for (server, reposInThisServer) in reposByServer {
            let scanner = NodeScanner(server: server, parentType: nil)

            let perNodeBlock: Query.PerNodeBlock = { progress throws(TQL.Error) in
                scanner.add(progress: progress)

                if case let .node(node) = progress, node.elementType == "PullRequest",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload.potentialString(named: "updatedAt"),
                   let d = DataItem.parseGH8601(updatedAt),
                   let repoLatestUpdate = prRepoIdToLatestExistingUpdate[repo.id],
                   d < repoLatestUpdate {
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

            let profile = settings.syncProfile

            if idsForReposInThisServerWantingLatestPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Updated PRs", groupName: "nodes", idList: idsForReposInThisServerWantingLatestPrs, maxCost: profile.itemIncrementalBatchCost, perNode: perNodeBlock) { latestPrsFragment(settings: settings) }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Open PRs", groupName: "nodes", idList: idsForReposInThisServerWantingAllOpenPrs, maxCost: profile.itemInitialBatchCost, perNode: perNodeBlock) { allOpenPrsFragment(settings: settings) }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await scanner.done()
            } catch {
                await scanner.done()
                server.lastSyncSucceeded = false
            }
        }
    }

    static func fetchAllSubscribedIssues(from repos: [Repo], settings: Settings.Cache) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var _issueRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        for repo in repos {
            if let n = repo.nodeId, repo.displayPolicyForIssues != hideValue {
                _issueRepoIdToLatestExistingUpdate[n] = Issue.mostRecentItemUpdate(in: repo)
            }
        }

        let issueRepoIdToLatestExistingUpdate = _issueRepoIdToLatestExistingUpdate
        for (server, reposInThisServer) in reposByServer {
            let scanner = NodeScanner(server: server, parentType: nil)

            let perNodeBlock: Query.PerNodeBlock = { progress throws(TQL.Error) in
                scanner.add(progress: progress)

                if case let .node(node) = progress, node.elementType == "Issue",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload.potentialString(named: "updatedAt"),
                   let d = DataItem.parseGH8601(updatedAt),
                   let latestRepoUpdate = issueRepoIdToLatestExistingUpdate[repo.id],
                   d < latestRepoUpdate {
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

            let profile = settings.syncProfile

            if idsForReposInThisServerWantingLatestIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Updated Issues", groupName: "nodes", idList: idsForReposInThisServerWantingLatestIssues, maxCost: profile.itemIncrementalBatchCost, perNode: perNodeBlock) { latestIssuesFragment(settings: settings) }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Open Issues", groupName: "nodes", idList: idsForReposInThisServerWantingAllOpenIssues, maxCost: profile.itemInitialBatchCost, perNode: perNodeBlock) { allOpenIssuesFragment(settings: settings) }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await scanner.done()
            } catch {
                await scanner.done()
                server.lastSyncSucceeded = false
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

    private final class NodeScanner {
        private let scannerServer: ApiServer
        private let scannerMoc: NSManagedObjectContext
        private let parentType: DataItem.Type?
        private let parentCache = FetchCache()
        private var nodes = [String: Lista<Node>]()

        init(server: ApiServer, parentType: (some DataItem).Type?) {
            let child = server.managedObjectContext!.buildChildContext()
            scannerMoc = child
            scannerServer = try! child.existingObject(with: server.objectID) as! ApiServer
            self.parentType = parentType
        }

        func add(progress: ParseOutput) {
            scannerMoc.perform { [weak self] in
                guard let self else { return }
                switch progress {
                case .queryPageComplete:
                    flush()
                    nodes.removeAll()
                case .queryComplete:
                    break
                case let .node(node):
                    let type = node.elementType
                    if let existingList = nodes[type] {
                        existingList.append(node)
                    } else {
                        nodes[type] = Lista<Node>(value: node)
                    }
                }
            }
        }

        func done() async {
            await withCheckedContinuation { continuation in
                scannerMoc.perform { [weak self] in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    flush()
                    continuation.resume()
                }
            }
        }

        private func flush() {
            if nodes.isEmpty { return }

            // Order must be fixed, since labels may refer to PRs or Issues, ensure they are created first

            if let nodeList = nodes["Repository"] {
                Repo.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["Issue"] {
                Issue.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequest"] {
                PullRequest.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["Label"] {
                PRLabel.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["CommentReaction"] {
                Reaction.sync(from: nodeList, for: PRComment.self, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["IssueComment"] {
                PRComment.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequestReviewComment"] {
                PRComment.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["Reaction"], let parentType {
                Reaction.sync(from: nodeList, for: parentType, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["ReviewRequest"] {
                Review.syncRequests(from: nodeList, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["PullRequestReview"] {
                Review.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["StatusContext"] {
                PRStatus.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if let nodeList = nodes["CheckRun"] {
                PRStatus.sync(from: nodeList, on: scannerServer, moc: scannerMoc, parentCache: parentCache)
            }
            if scannerMoc.hasChanges {
                try? scannerMoc.save()
            }
        }
    }
}
