import AsyncHTTPClient
import Foundation
import Lista
import NIOCore
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
            DLog(message)
        }
    }

    private static let nodeBlockMax = 2000

    enum Profile: Int {
        case light = -20
        case cautious = -10
        case moderate = 0
        case high = 10

        static var current: Profile {
            Profile(settingsValue: Settings.syncProfile)
        }

        init(settingsValue: Int) {
            switch settingsValue {
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
        Group("comments", paging: Profile.current.largePageSize) {
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
            DLog("Got a node, type: \(node.elementType), id: \(node.id)")
            if node.elementType == "User" {
                gotUserNode = true
            }
        }
        _ = try await run(testQuery, for: apiServer.graphQLPath ?? "", authToken: apiServer.authToken ?? "", expectedNodeCost: nil, attempts: 1) { _ in }
        if !gotUserNode {
            throw API.apiError("Could not read a valid user record from this endpoint")
        }
    }

    private static let multiGateKeeper = Gate(tickets: 2)

    private static func fetchData(from urlString: String, for query: Query, authToken: String, attempts: Int) async throws -> JSON {
        let Q = query.queryText

        guard let requestData = try? JSONSerialization.data(withJSONObject: ["query": Q]) else {
            throw API.apiError("\(query.logPrefix)Could not serialise query")
        }

        var request = HTTPClientRequest(url: urlString)
        request.method = .POST
        request.body = .bytes(ByteBuffer(bytes: requestData))
        request.headers.add(name: "Authorization", value: "bearer \(authToken)")

        await multiGateKeeper.takeTicket()
        let start = Date()
        defer {
            multiGateKeeper.relaxedReturnTicket()
            if Settings.dumpAPIResponsesInConsole {
                DLog("\(query.logPrefix)Response time: \(-start.timeIntervalSinceNow) sec")
            }
        }

        Task { @MainActor in
            API.currentOperationName = query.name
        }

        if Settings.dumpAPIResponsesInConsole {
            DLog("\(query.logPrefix)Fetching: \(Q)")
        }

        guard let json = try await HTTP.getJsonData(for: request, attempts: attempts, checkCache: false, logPrefix: query.logPrefix, retryOnInvalidJson: true).json as? JSON else {
            throw API.apiError("\(query.logPrefix)Retuned data is not JSON")
        }

        return json
    }

    private static func run(_ query: Query, for urlString: String, authToken: String, expectedNodeCost: Int?, attempts: Int = 5, newStats: @escaping (ApiStats) -> Void) async throws {
        if let expectedNodeCost, Settings.dumpAPIResponsesInConsole {
            DLog("\(query.logPrefix)Queued - Expected Count: \(expectedNodeCost)")
        }

        let json = try await fetchData(from: urlString, for: query, authToken: authToken, attempts: attempts)

        let apiStats = ApiStats.fromV4(json: json["data"] as? JSON)
        if let expectedNodeCost {
            if let apiStats {
                DLog("\(query.logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Expected Count: \(expectedNodeCost) - Returned Count: \(apiStats.nodeCount))")
                if expectedNodeCost != apiStats.nodeCount {
                    DLog("Warning: Mismatched expected and received node count!")
                }
                newStats(apiStats)
            } else {
                DLog("\(query.logPrefix)Received page (No stats) - Expected Count: \(expectedNodeCost)")
            }
        } else {
            if let apiStats {
                DLog("\(query.logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Returned Count: \(apiStats.nodeCount))")
                newStats(apiStats)
            } else {
                DLog("\(query.logPrefix)Received page (No stats)")
            }
        }
        
        do {
            let extraQueries = try await query.processResponse(from: json)
            if extraQueries.count > 0 {
                try await runQueries(queries: extraQueries, on: urlString, token: authToken, newStats: newStats)
            }

        } catch {
            let msg: String?
            if let errors = json["errors"] as? [JSON] {
                msg = errors.first?["message"] as? String
            } else {
                msg = json["message"] as? String
            }
            throw API.apiError("\(query.logPrefix)" + (msg ?? "Unspecified server error: \(json)"))
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

        try await process(name: steps.toString, items: items, parentType: T.self, maxCost: Profile.current.itemAccompanyingBatchCount) {
            Fragment(on: typeName) {
                Field.id

                if items is [PullRequest] {
                    if steps.contains(.reviewRequests) {
                        Group("reviewRequests", paging: Profile.current.smallPageSize) {
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
                        Group("reviews", paging: Profile.current.smallPageSize) {
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
                                Group("checkSuites", paging: Profile.current.smallPageSize) {
                                    Group("checkRuns", paging: Profile.current.smallPageSize) {
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
                    Group("reactions", paging: Profile.current.smallPageSize) {
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
        try await process(name: "Comment Reactions", items: comments, maxCost: Profile.current.itemAccompanyingBatchCount) {
            Fragment(on: "IssueComment") {
                Field.id
                Group("reactions", paging: Profile.current.largePageSize) {
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
        try await process(name: "Review Comments", items: reviews, maxCost: Profile.current.itemAccompanyingBatchCount) {
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

        let processor = Processor()
        let itemsByServer = Dictionary(grouping: items) { $0.apiServer }
        var count = 0
        for (server, items) in itemsByServer {
            let ids = items.compactMap(\.nodeId)
            var nodes = [String: Lista<Node>]()
            let serverName = server.label ?? "<no label>"
            let nodeBlock = { (node: Node) in
                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = Lista<Node>(value: node)
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: parentType, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queries = Query.batching("\(serverName): \(name)", groupName: "nodes", idList: ids, maxCost: maxCost, perNode: nodeBlock, fields: fields)

            do {
                try await server.run(queries: queries)
                processor.add(chunk: .init(nodes: nodes, server: server, parentType: parentType, moreComing: false))
                await processor.waitForCompletion()
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
            Group("assignees", paging: Profile.current.smallPageSize) { userFragment }
            Group("labels", paging: Profile.current.smallPageSize) { labelFragment }
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
            Group("assignees", paging: Profile.current.smallPageSize) { userFragment }
            Group("labels", paging: Profile.current.smallPageSize) { labelFragment }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = Group("pullRequests", ("states", "[OPEN]"), paging: Profile.current.mediumPageSize) {
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
        var count = 0
        var nodes = [String: Lista<Node>]()
        let group = Group("viewer", fields: fields)
        let processor = Processor()
        let authoredItemsQuery = Query(name: "Authored \(label)", rootElement: group) { node in
            let type = node.elementType
            if let existingList = nodes[type] {
                existingList.append(node)
            } else {
                nodes[type] = Lista<Node>(value: node)
            }

            count += 1
            if count > nodeBlockMax {
                count = 0
                processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                nodes.removeAll(keepingCapacity: true)
            }
        }
        do {
            try await server.run(queries: Lista(value: authoredItemsQuery))
            processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: false))
            await processor.waitForCompletion()
            return nodes

        } catch {
            server.lastSyncSucceeded = false
            return nil
        }
    }

    private static func checkAuthoredPrClosures(nodes: [String: Lista<Node>], in server: ApiServer) async {
        let prsToCheck = Lista<PullRequest>()
        let fetchedPrIds = Set(nodes["PullRequest"]?.map(\.id) ?? [])
        for repo in server.repos.filter({ $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for pr in repo.pullRequests where !fetchedPrIds.contains(pr.nodeId ?? "") {
                prsToCheck.append(pr)
            }
        }

        if prsToCheck.count == 0 {
            return
        }

        let prGroup = Group("pullRequests") { prFragment(includeRepo: true) }
        let group = BatchGroup(name: "nodes", templateGroup: prGroup, idList: prsToCheck.compactMap(\.nodeId))
        let nodes = Lista<Node>()
        let query = Query(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) { node in
            node.forcedUpdate = true
            nodes.append(node)
        }
        do {
            try await server.run(queries: Lista(value: query))
            let processor = Processor()
            processor.add(chunk: .init(nodes: ["PullRequest": nodes], server: server, parentType: nil, moreComing: false))
            await processor.waitForCompletion()
        } catch {
            server.lastSyncSucceeded = false
        }
    }

    private static func checkAuthoredIssueClosures(nodes: [String: Lista<Node>], in server: ApiServer) {
        let fetchedIssueIds = Set(nodes["Issue"]?.map(\.id) ?? []) // investigate missing issues
        for repo in server.repos.filter({ $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for issue in repo.issues where !fetchedIssueIds.contains(issue.nodeId ?? "") {
                issue.stateChanged = ListableItem.StateChange.closed.rawValue
                issue.condition = ItemCondition.closed.rawValue
            }
        }
    }

    private static var latestPrsFragment = Fragment(on: "Repository") {
        Field.id
        Group("pullRequests", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: Profile.current.smallPageSize) {
            prFragment(includeRepo: false)
        }
    }

    private static var latestIssuesFragment = Fragment(on: "Repository") {
        Field.id
        Group("issues", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: Profile.current.smallPageSize) {
            issueFragment(includeRepo: false)
        }
    }

    private static var allOpenPrsFragment = Fragment(on: "Repository") {
        Field.id
        Group("pullRequests", ("states", "[OPEN]"), paging: Profile.current.mediumPageSize) {
            prFragment(includeRepo: false)
        }
    }

    private static var allOpenIssuesFragment = Fragment(on: "Repository") {
        Field.id
        Group("issues", ("states", "[OPEN]"), paging: Profile.current.largePageSize) {
            issueFragment(includeRepo: false)
        }
    }

    static func fetchAllSubscribedPrs(from repos: [Repo]) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var prRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        repos.forEach {
            if let n = $0.nodeId {
                if $0.displayPolicyForPrs != hideValue {
                    prRepoIdToLatestExistingUpdate[n] = PullRequest.mostRecentItemUpdate(in: $0)
                }
            }
        }

        let processor = Processor()

        for (server, reposInThisServer) in reposByServer {
            var count = 0
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

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
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
                let q = Query.batching("\(serverLabel): Updated PRs", groupName: "nodes", idList: Array(idsForReposInThisServerWantingLatestPrs), maxCost: Profile.current.itemIncrementalBatchCost, perNode: perNodeBlock) { latestPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Open PRs", groupName: "nodes", idList: Array(idsForReposInThisServerWantingAllOpenPrs), maxCost: Profile.current.itemInitialBatchCost, perNode: perNodeBlock) { allOpenPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: false))
                await processor.waitForCompletion()
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }

    static func fetchAllSubscribedIssues(from repos: [Repo]) async {
        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }

        var issueRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        repos.forEach {
            if let n = $0.nodeId {
                if $0.displayPolicyForIssues != hideValue {
                    issueRepoIdToLatestExistingUpdate[n] = Issue.mostRecentItemUpdate(in: $0)
                }
            }
        }

        let processor = Processor()

        for (server, reposInThisServer) in reposByServer {
            var count = 0
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

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
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
                let q = Query.batching("\(serverLabel): Updated Issues", groupName: "nodes", idList: Array(idsForReposInThisServerWantingLatestIssues), maxCost: Profile.current.itemIncrementalBatchCost, perNode: perNodeBlock) { latestIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Open Issues", groupName: "nodes", idList: Array(idsForReposInThisServerWantingAllOpenIssues), maxCost: Profile.current.itemInitialBatchCost, perNode: perNodeBlock) { allOpenIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: false))
                await processor.waitForCompletion()
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }
}
