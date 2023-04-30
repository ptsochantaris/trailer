import CoreData
import Foundation

@globalActor
enum NodeActor {
    actor ActorType {}
    static let shared = ActorType()
}

typealias PerNodeBlock = @NodeActor (GQLNode) async throws -> Void

@MainActor
enum GraphQL {
    private static let nodeBlockMax = 2000

    static let idField = GQLField("id")

    private static let nameWithOwnerField = GQLField("nameWithOwner")

    private static let userFragment = GQLFragment(on: "User") {
        idField
        GQLField("login")
        GQLField("avatarUrl")
    }

    private static let userIdFragment = GQLFragment(on: "User") {
        idField
    }

    private static let mannequinFragment = GQLFragment(on: "Mannequin") {
        idField
        GQLField("login")
        GQLField("avatarUrl")
    }

    private static let teamFragment = GQLFragment(on: "Team") {
        idField
        GQLField("slug")
    }

    @GQLElementsBuilder
    private static func commentFields() -> [any GQLElement] {
        idField
        GQLField("body")
        GQLField("url")
        GQLField("createdAt")
        GQLField("updatedAt")
        GQLGroup("author") { userFragment }
    }

    private static let statusFragment = GQLFragment(on: "StatusContext") {
        idField
        GQLField("context")
        GQLField("description")
        GQLField("state")
        GQLField("targetUrl")
        GQLField("createdAt")
    }

    private static let checkFragment = GQLFragment(on: "CheckRun") {
        idField
        GQLField("name")
        GQLField("conclusion")
        GQLField("startedAt")
        GQLField("completedAt")
        GQLField("permalink")
    }

    static func testApi(to apiServer: ApiServer) async throws {
        var gotUserNode = false
        let testQuery = GQLQuery(name: "Testing", rootElement: GQLGroup("viewer") { userFragment }) { node in
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

        let elements = LinkedList<any GQLElement>(value: idField)

        if let prs = items as? [PullRequest] {
            if steps.contains(.reviewRequests) {
                let requestFragment = GQLFragment(on: "ReviewRequest") {
                    idField
                    GQLGroup("requestedReviewer") {
                        userFragment
                        teamFragment
                        mannequinFragment
                    }
                }
                elements.append(GQLGroup("reviewRequests", paging: .max) { requestFragment })
            }

            if steps.contains(.reviews) {
                prs.forEach {
                    $0.reviews.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }

                let reviewFragment = GQLFragment(on: "PullRequestReview") {
                    idField
                    GQLField("body")
                    GQLField("state")
                    GQLField("createdAt")
                    GQLField("updatedAt")
                    GQLGroup("author") { userFragment }
                }
                elements.append(GQLGroup("reviews", paging: .max) { reviewFragment })
            }

            if steps.contains(.statuses) {
                let now = Date()
                prs.forEach {
                    $0.lastStatusScan = now
                    $0.statuses.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }

                elements.append(
                    GQLGroup("commits", paging: .last(count: 1)) {
                        GQLGroup("commit") {
                            GQLGroup("checkSuites", paging: .first(count: 10, paging: false)) {
                                GQLGroup("checkRuns", paging: .first(count: 50, paging: false)) {
                                    checkFragment
                                }
                            }
                            GQLGroup("status") {
                                GQLGroup("contexts") {
                                    statusFragment
                                }
                            }
                        }
                    }
                )
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
            
            let reactionFragment = GQLFragment(on: "Reaction") {
                idField
                GQLField("content")
                GQLField("createdAt")
                GQLGroup("user") { userFragment }
            }
            elements.append(GQLGroup("reactions", paging: .max) { reactionFragment })
        }

        if steps.contains(.comments) {
            items.forEach {
                $0.comments.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
            let commentFragment = GQLFragment(on: "IssueComment", elements: commentFields)
            elements.append(GQLGroup("comments", paging: .max) { commentFragment })
        }

        try await process(name: steps.toString, items: items, parentType: T.self) {
            GQLFragment(on: typeName) {
                Array(elements)
            }
        }
    }

    static func updateReactions(for comments: [PRComment]) async throws {
        let reactionFragment = GQLFragment(on: "Reaction") {
            idField
            GQLField("content")
            GQLField("createdAt")
            GQLGroup("user") { userFragment }
        }

        let itemFragment = GQLFragment(on: "IssueComment") {
            idField
            GQLGroup("reactions", paging: .max) { reactionFragment }
        }

        try await process(name: "Comment Reactions", items: comments) { itemFragment }
    }

    static func updateComments(for reviews: [Review]) async throws {
        let commentFragment = GQLFragment(on: "PullRequestReviewComment", elements: commentFields)

        let itemFragment = GQLFragment(on: "PullRequestReview") {
            idField
            GQLGroup("comments", paging: .max) { commentFragment }
        }

        try await process(name: "Review Comments", items: reviews) { itemFragment }
    }

    private static func process(name: String, items: [DataItem], parentType: (some ListableItem).Type? = nil, @GQLElementsBuilder fields: () -> [any GQLElement]) async throws {
        if items.isEmpty {
            return
        }

        let processor = GQLProcessor()
        let itemsByServer = Dictionary(grouping: items) { $0.apiServer }
        var count = 0
        for (server, items) in itemsByServer {
            let ids = items.compactMap(\.nodeId)
            var nodes = [String: LinkedList<GQLNode>]()
            let serverName = server.label ?? "<no label>"
            let nodeBlock = { (node: GQLNode) in
                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<GQLNode>(value: node)
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: parentType, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }
            
            let queries = GQLQuery.batching("\(serverName): \(name)", idList: ids, perNode: nodeBlock, fields: fields)

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

    private static var milestoneFragment = GQLFragment(on: "Milestone") {
        GQLField("title")
    }

    private static var labelFragment = GQLFragment(on: "Label") {
        idField
        GQLField("name")
        GQLField("color")
        GQLField("createdAt")
        GQLField("updatedAt")
    }

    private static var repositoryFragment = GQLFragment(on: "Repository") {
        idField
        GQLField("createdAt")
        GQLField("updatedAt")
        GQLField("isFork")
        GQLField("isArchived")
        GQLField("nameWithOwner")
        GQLField("url")
        GQLField("isPrivate")
        GQLGroup("owner") { idField }
    }

    private static func prFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> GQLFragment {
        GQLFragment(on: "PullRequest") {
            idField
            GQLField("bodyText")
            GQLField("state")
            GQLField("createdAt")
            GQLField("updatedAt")
            GQLField("number")
            GQLField("title")
            GQLField("url")
            GQLGroup("milestone") { milestoneFragment }
            GQLGroup("author") { userFragment }
            GQLGroup("assignees", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { userFragment }
            GQLGroup("labels", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { labelFragment }
            GQLField("headRefOid")
            GQLField("mergeable")
            GQLField("additions")
            GQLField("deletions")
            GQLField("headRefName")
            GQLField("baseRefName")
            GQLField("isDraft")
            GQLGroup("mergedBy") { userIdFragment }
            GQLGroup("baseRepository") { nameWithOwnerField }
            GQLGroup("headRepository") { nameWithOwnerField }
            if includeRepo {
                GQLGroup("repository") { repositoryFragment }
            }
        }
    }

    private static func issueFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> GQLFragment {
        GQLFragment(on: "Issue") {
            idField
            GQLField("bodyText")
            GQLField("state")
            GQLField("createdAt")
            GQLField("updatedAt")
            GQLField("number")
            GQLField("title")
            GQLField("url")
            GQLGroup("milestone") { milestoneFragment }
            GQLGroup("author") { userFragment }
            GQLGroup("assignees", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { userFragment }
            GQLGroup("labels", paging: .first(count: assigneesAndLabelPageSize, paging: true)) { labelFragment }
            if includeRepo {
                GQLGroup("repository") { repositoryFragment }
            }
        }
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = GQLGroup("pullRequests", ("states", "[OPEN]"), paging: .max) {
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
                    let g = GQLGroup("issues", ("states", "[OPEN]"), paging: .max) {
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

    static func fetchAllAuthoredItems(from server: ApiServer, @GQLElementsBuilder fields: () -> [any GQLElement]) async -> [String: LinkedList<GQLNode>]? {
        var count = 0
        var nodes = [String: LinkedList<GQLNode>]()
        let group = GQLGroup("viewer", fields: fields)
        let processor = GQLProcessor()
        let authoredItemsQuery = GQLQuery(name: "Authored Items", rootElement: group) { node in
            let type = node.elementType
            if let existingList = nodes[type] {
                existingList.append(node)
            } else {
                nodes[type] = LinkedList<GQLNode>(value: node)
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

    private static func checkAuthoredPrClosures(nodes: [String: LinkedList<GQLNode>], in server: ApiServer) async {
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

        let prGroup = GQLGroup("pullRequests") { prFragment(assigneesAndLabelPageSize: 1, includeRepo: true) }
        let group = GQLBatchGroup(templateGroup: prGroup, idList: prsToCheck.compactMap(\.nodeId))
        let nodes = LinkedList<GQLNode>()
        let query = GQLQuery(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) { node in
            node.forcedUpdate = true
            nodes.append(node)
        }
        do {
            try await server.run(queries: LinkedList(value: query))
            let processor = GQLProcessor()
            processor.add(chunk: .init(nodes: ["PullRequest": nodes], server: server, parentType: nil, moreComing: false))
            await processor.waitForCompletion()
        } catch {
            server.lastSyncSucceeded = false
        }
    }

    private static func checkAuthoredIssueClosures(nodes: [String: LinkedList<GQLNode>], in server: ApiServer) {
        let fetchedIssueIds = Set(nodes["Issue"]?.map(\.id) ?? []) // investigate missing issues
        for repo in server.repos.filter({ $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }) {
            for issue in repo.issues where !fetchedIssueIds.contains(issue.nodeId ?? "") {
                issue.stateChanged = ListableItem.StateChange.closed.rawValue
                issue.condition = ItemCondition.closed.rawValue
            }
        }
    }

    private static let alreadyParsed = NSError(domain: "com.housetrip.Trailer.parsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Node already parsed in previous sync"])

    private static let latestPrsFragment = GQLFragment(on: "Repository") {
        idField
        GQLGroup("pullRequests", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: .first(count: 20, paging: true)) {
            prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let latestIssuesFragment = GQLFragment(on: "Repository") {
        idField
        GQLGroup("issues", ("orderBy", "{direction: DESC, field: UPDATED_AT}"), paging: .first(count: 40, paging: true)) {
            issueFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let allOpenPrsFragment = GQLFragment(on: "Repository") {
        idField
        GQLGroup("pullRequests", ("states", "[OPEN]"), paging: .first(count: 50, paging: true)) {
            prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)
        }
    }

    private static let allOpenIssuesFragment = GQLFragment(on: "Repository") {
        idField
        GQLGroup("issues", ("states", "[OPEN]"), paging: .first(count: 50, paging: true)) {
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
        
        let processor = GQLProcessor()

        for (server, reposInThisServer) in reposByServer {
            var count = 0
            var nodes = [String: LinkedList<GQLNode>]()

            let perNodeBlock: PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<GQLNode>(value: node)
                }

                if type == "PullRequest",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < prRepoIdToLatestExistingUpdate[repo.id]! {
                    throw GraphQL.alreadyParsed
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queriesForServer = LinkedList<GQLQuery>()
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
                let q = GQLQuery.batching("\(serverLabel): Updated PRs", idList: Array(idsForReposInThisServerWantingLatestPrs), perNode: perNodeBlock) { latestPrsFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = GQLQuery.batching("\(serverLabel): Open PRs", idList: Array(idsForReposInThisServerWantingAllOpenPrs), perNode: perNodeBlock) { allOpenPrsFragment }
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
        
        let processor = GQLProcessor()

        for (server, reposInThisServer) in reposByServer {
            var count = 0
            var nodes = [String: LinkedList<GQLNode>]()

            let perNodeBlock: PerNodeBlock = { node in

                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<GQLNode>(value: node)
                }

                if type == "Issue",
                   let repo = node.parent,
                   let updatedAt = node.jsonPayload["updatedAt"] as? String,
                   let d = DataItem.parseGH8601(updatedAt),
                   d < issueRepoIdToLatestExistingUpdate[repo.id]! {
                    throw GraphQL.alreadyParsed
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    processor.add(chunk: .init(nodes: nodes, server: server, parentType: nil, moreComing: true))
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            let queriesForServer = LinkedList<GQLQuery>()
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
                let q = GQLQuery.batching("\(serverLabel): Updated Issues", idList: Array(idsForReposInThisServerWantingLatestIssues), perNode: perNodeBlock) { latestIssuesFragment }
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = GQLQuery.batching("\(serverLabel): Open Issues", idList: Array(idsForReposInThisServerWantingAllOpenIssues), perNode: perNodeBlock) { allOpenIssuesFragment }
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
