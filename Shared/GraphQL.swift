import Foundation

@MainActor
enum GraphQL {
    @globalActor
    enum NodeActor {
        actor ActorType {}
        static let shared = ActorType()
    }

    typealias PerNodeBlock = @NodeActor (Node) async throws -> Void

    private static let nodeBlockMax = 2000

    static let idField = Field("id")

    private static let nameWithOwnerField = Field("nameWithOwner")

    private static let userFragment = Fragment(on: "User") {
        idField
        Field("login")
        Field("avatarUrl")
    }

    private static func commentGroup(for typeName: String) -> Group {
        Group("comments", paging: .max) {
            Fragment(on: typeName) {
                idField
                Field("body")
                Field("url")
                Field("createdAt")
                Field("updatedAt")
                Group("author") { userFragment }
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
        _ = try await testQuery.run(for: apiServer.graphQLPath ?? "", authToken: apiServer.authToken ?? "", attempts: 1)
        if !gotUserNode {
            throw API.apiError("Could not read a valid user record from this endpoint")
        }
    }

    static func update<T: ListableItem>(for items: [T], steps: API.SyncSteps) async throws {
        let typeName = String(describing: T.self)

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

        try await process(name: steps.toString, items: items, parentType: T.self) {
            Fragment(on: typeName) {
                idField

                if items is [PullRequest] {
                    if steps.contains(.reviewRequests) {
                        Group("reviewRequests", paging: .max) {
                            Fragment(on: "ReviewRequest") {
                                idField
                                Group("requestedReviewer") {
                                    userFragment
                                    Fragment(on: "Team") {
                                        idField
                                        Field("slug")
                                    }
                                    Fragment(on: "Mannequin") {
                                        idField
                                        Field("login")
                                        Field("avatarUrl")
                                    }
                                }
                            }
                        }
                    }

                    if steps.contains(.reviews) {
                        Group("reviews", paging: .max) {
                            Fragment(on: "PullRequestReview") {
                                idField
                                Field("body")
                                Field("state")
                                Field("createdAt")
                                Field("updatedAt")
                                Group("author") { userFragment }
                            }
                        }
                    }

                    if steps.contains(.statuses) {
                        Group("commits", paging: .last(count: 1)) {
                            Group("commit") {
                                Group("checkSuites", paging: .first(count: 10, paging: false)) {
                                    Group("checkRuns", paging: .first(count: 50, paging: false)) {
                                        Fragment(on: "CheckRun") {
                                            idField
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
                                            idField
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
                    Group("reactions", paging: .max) {
                        Fragment(on: "Reaction") {
                            idField
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
        try await process(name: "Comment Reactions", items: comments) {
            Fragment(on: "IssueComment") {
                idField
                Group("reactions", paging: .max) {
                    Fragment(on: "Reaction") {
                        idField
                        Field("content")
                        Field("createdAt")
                        Group("user") { userFragment }
                    }
                }
            }
        }
    }

    static func updateComments(for reviews: [Review]) async throws {
        try await process(name: "Review Comments", items: reviews) {
            Fragment(on: "PullRequestReview") {
                idField
                commentGroup(for: "PullRequestReviewComment")
            }
        }
    }

    private static func process(name: String, items: [DataItem], parentType: (some ListableItem).Type? = nil, @GQLElementsBuilder fields: () -> [any GQLElement]) async throws {
        if items.isEmpty {
            return
        }

        let processor = Processor()
        let itemsByServer = Dictionary(grouping: items) { $0.apiServer }
        var count = 0
        for (server, items) in itemsByServer {
            let ids = items.compactMap(\.nodeId)
            var nodes = [String: LinkedList<Node>]()
            let serverName = server.label ?? "<no label>"
            let nodeBlock = { (node: Node) in
                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<Node>(value: node)
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: parentType, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queries = Query.batching("\(serverName): \(name)", idList: ids, perNode: nodeBlock, fields: fields)

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

    private static var milestoneFragment = Fragment(on: "Milestone") {
        Field("title")
    }

    private static var labelFragment = Fragment(on: "Label") {
        idField
        Field("name")
        Field("color")
        Field("createdAt")
        Field("updatedAt")
    }

    private static var repositoryFragment = Fragment(on: "Repository") {
        idField
        Field("createdAt")
        Field("updatedAt")
        Field("isFork")
        Field("isArchived")
        Field("nameWithOwner")
        Field("url")
        Field("isPrivate")
        Group("owner") { idField }
    }

    private static func prFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> Fragment {
        Fragment(on: "PullRequest") {
            idField
            Field("bodyText")
            Field("state")
            Field("createdAt")
            Field("updatedAt")
            Field("number")
            Field("title")
            Field("url")
            Group("milestone") { milestoneFragment }
            Group("author") { userFragment }
            Group("assignees", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { userFragment }
            Group("labels", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { labelFragment }
            Field("headRefOid")
            Field("mergeable")
            Field("additions")
            Field("deletions")
            Field("headRefName")
            Field("baseRefName")
            Field("isDraft")
            Group("mergedBy") { Fragment(on: "User") { idField } }
            Group("baseRepository") { nameWithOwnerField }
            Group("headRepository") { nameWithOwnerField }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    private static func issueFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> Fragment {
        Fragment(on: "Issue") {
            idField
            Field("bodyText")
            Field("state")
            Field("createdAt")
            Field("updatedAt")
            Field("number")
            Field("title")
            Field("url")
            Group("milestone") { milestoneFragment }
            Group("author") { userFragment }
            Group("assignees", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { userFragment }
            Group("labels", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { labelFragment }
            if includeRepo {
                Group("repository") { repositoryFragment }
            }
        }
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = Group("pullRequests", ("states", "[OPEN]"), paging: .max) {
                        prFragment(assigneesAndLabelPageSize: 20, includeRepo: true)
                    }
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, fields: { g }) {
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
                        issueFragment(assigneesAndLabelPageSize: 20, includeRepo: true)
                    }
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, fields: { g }) {
                            checkAuthoredIssueClosures(nodes: nodes, in: server)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredItems(from server: ApiServer, @GQLElementsBuilder fields: () -> [any GQLElement]) async -> [String: LinkedList<Node>]? {
        var count = 0
        var nodes = [String: LinkedList<Node>]()
        let group = Group("viewer", fields: fields)
        let processor = Processor()
        let authoredItemsQuery = Query(name: "Authored Items", rootElement: group) { node in
            let type = node.elementType
            if let existingList = nodes[type] {
                existingList.append(node)
            } else {
                nodes[type] = LinkedList<Node>(value: node)
            }

            count += 1
            if count > nodeBlockMax {
                count = 0
                processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                nodes.removeAll(keepingCapacity: true)
            }
        }
        do {
            try await server.run(queries: LinkedList(value: authoredItemsQuery))
            processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: false))
            await processor.waitForCompletion()
            return nodes

        } catch {
            server.lastSyncSucceeded = false
            return nil
        }
    }

    private static func checkAuthoredPrClosures(nodes: [String: LinkedList<Node>], in server: ApiServer) async {
        let prsToCheck = LinkedList<PullRequest>()
        let fetchedPrIds = Set(nodes["PullRequest"]?.map(\.id) ?? [])
        for repo in server.repos.filter({ $0.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for pr in repo.pullRequests where !fetchedPrIds.contains(pr.nodeId ?? "") {
                prsToCheck.append(pr)
            }
        }

        if prsToCheck.count == 0 {
            return
        }

        let prGroup = Group("pullRequests") { prFragment(assigneesAndLabelPageSize: 1, includeRepo: true) }
        let group = BatchGroup(templateGroup: prGroup, idList: prsToCheck.compactMap(\.nodeId))
        let nodes = LinkedList<Node>()
        let query = Query(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) { node in
            node.forcedUpdate = true
            nodes.append(node)
        }
        do {
            try await server.run(queries: LinkedList(value: query))
            let processor = Processor()
            processor.add(chunk: .init(nodes: ["PullRequest": nodes], server: server, parentType: nil, moreComing: false))
            await processor.waitForCompletion()
        } catch {
            server.lastSyncSucceeded = false
        }
    }

    private static func checkAuthoredIssueClosures(nodes: [String: LinkedList<Node>], in server: ApiServer) {
        let fetchedIssueIds = Set(nodes["Issue"]?.map(\.id) ?? []) // investigate missing issues
        for repo in server.repos.filter({ $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for issue in repo.issues where !fetchedIssueIds.contains(issue.nodeId ?? "") {
                issue.stateChanged = ListableItem.StateChange.closed.rawValue
                issue.condition = ItemCondition.closed.rawValue
            }
        }
    }

    private static let alreadyParsed = NSError(domain: "com.housetrip.Trailer.parsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Node already parsed in previous sync"])

    private static let latestPrsFragment = Fragment(on: "Repository") {
        idField
        Group("pullRequests", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: .first(count: 20, paging: true)) {
            prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let latestIssuesFragment = Fragment(on: "Repository") {
        idField
        Group("issues", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: .first(count: 40, paging: true)) {
            issueFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let allOpenPrsFragment = Fragment(on: "Repository") {
        idField
        Group("pullRequests", ("states", "[OPEN]"), paging: .first(count: 50, paging: true)) {
            prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let allOpenIssuesFragment = Fragment(on: "Repository") {
        idField
        Group("issues", ("states", "[OPEN]"), paging: .first(count: 50, paging: true)) {
            issueFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
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
            var nodes = [String: LinkedList<Node>]()

            let perNodeBlock: PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<Node>(value: node)
                }

                if type == "PullRequest",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < prRepoIdToLatestExistingUpdate[repo.id]! {
                    throw alreadyParsed
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queriesForServer = LinkedList<Query>()
            let serverLabel = server.label ?? "<no label>"

            let idsForReposInThisServerWantingAllOpenPrs = LinkedList<String>()
            let idsForReposInThisServerWantingLatestPrs = LinkedList<String>()
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
                let q = Query.batching("\(serverLabel): Updated PRs", idList: Array(idsForReposInThisServerWantingLatestPrs), perNode: perNodeBlock) { latestPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = Query.batching("\(serverLabel): Open PRs", idList: Array(idsForReposInThisServerWantingAllOpenPrs), perNode: perNodeBlock) { allOpenPrsFragment }
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
            var nodes = [String: LinkedList<Node>]()

            let perNodeBlock: PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<Node>(value: node)
                }

                if type == "Issue",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < issueRepoIdToLatestExistingUpdate[repo.id]! {
                    throw alreadyParsed
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queriesForServer = LinkedList<Query>()
            let serverLabel = server.label ?? "<no label>"

            let idsForReposInThisServerWantingAllOpenIssues = LinkedList<String>()
            let idsForReposInThisServerWantingLatestIssues = LinkedList<String>()
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
                let q = Query.batching("\(serverLabel): Updated Issues", idList: Array(idsForReposInThisServerWantingLatestIssues), perNode: perNodeBlock) { latestIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = Query.batching("\(serverLabel): Open Issues", idList: Array(idsForReposInThisServerWantingAllOpenIssues), perNode: perNodeBlock) { allOpenIssuesFragment }
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
