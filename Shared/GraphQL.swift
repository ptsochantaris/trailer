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
    private static let nodeBlockMax = 400

    private static let idField = GQLField(name: "id")

    private static let nameWithOwnerField = GQLField(name: "nameWithOwner")

    private static let userFragment = GQLFragment(on: "User", elements: [
        idField,
        GQLField(name: "login"),
        GQLField(name: "avatarUrl")
    ])

    private static let userIdFragment = GQLFragment(on: "User", elements: [
        idField
    ])

    private static let mannequinFragment = GQLFragment(on: "Mannequin", elements: [
        idField,
        GQLField(name: "login"),
        GQLField(name: "avatarUrl")
    ])

    private static let teamFragment = GQLFragment(on: "Team", elements: [
        idField,
        GQLField(name: "slug")
    ])

    private static let commentFields: [GQLElement] = [
        idField,
        GQLField(name: "body"),
        GQLField(name: "url"),
        GQLField(name: "createdAt"),
        GQLField(name: "updatedAt"),
        GQLGroup(name: "author", fields: [userFragment])
    ]

    private static let statusFragment = GQLFragment(on: "StatusContext", elements: [
        idField,
        GQLField(name: "context"),
        GQLField(name: "description"),
        GQLField(name: "state"),
        GQLField(name: "targetUrl"),
        GQLField(name: "createdAt")
    ])

    private static let checkFragment = GQLFragment(on: "CheckRun", elements: [
        idField,
        GQLField(name: "name"),
        GQLField(name: "conclusion"),
        GQLField(name: "startedAt"),
        GQLField(name: "completedAt"),
        GQLField(name: "permalink")
    ])

    static func testApi(to apiServer: ApiServer) async throws {
        var gotUserNode = false
        let testQuery = GQLQuery(name: "Testing", rootElement: GQLGroup(name: "viewer", fields: [userFragment])) { node in
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

        let elements = LinkedList<GQLElement>(value: idField)

        if let prs = items as? [PullRequest] {
            if steps.contains(.reviewRequests) {
                let requestFragment = GQLFragment(on: "ReviewRequest", elements: [
                    idField,
                    GQLGroup(name: "requestedReviewer", fields: [userFragment, teamFragment, mannequinFragment])
                ])
                elements.append(GQLGroup(name: "reviewRequests", fields: [requestFragment], pageSize: 100))
            }

            if steps.contains(.reviews) {
                prs.forEach {
                    $0.reviews.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }

                let reviewFragment = GQLFragment(on: "PullRequestReview", elements: [
                    idField,
                    GQLField(name: "body"),
                    GQLField(name: "state"),
                    GQLField(name: "createdAt"),
                    GQLField(name: "updatedAt"),
                    GQLGroup(name: "author", fields: [userFragment])
                ])
                elements.append(GQLGroup(name: "reviews", fields: [reviewFragment], pageSize: 100))
            }

            if steps.contains(.statuses) {
                let now = Date()
                prs.forEach {
                    $0.lastStatusScan = now
                    $0.statuses.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }

                elements.append(GQLGroup(name: "commits", fields: [
                    GQLGroup(name: "commit", fields: [
                        GQLGroup(name: "checkSuites", fields: [
                            GQLGroup(name: "checkRuns", fields: [checkFragment], pageSize: 50, noPaging: true)
                        ], pageSize: 10, noPaging: true),
                        GQLGroup(name: "status", fields: [
                            GQLGroup(name: "contexts", fields: [statusFragment])
                        ])
                    ])
                ], pageSize: 1, onlyLast: true))
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

            let reactionFragment = GQLFragment(on: "Reaction", elements: [
                idField,
                GQLField(name: "content"),
                GQLField(name: "createdAt"),
                GQLGroup(name: "user", fields: [userFragment])
            ])
            elements.append(GQLGroup(name: "reactions", fields: [reactionFragment], pageSize: 100))
        }

        if steps.contains(.comments) {
            items.forEach {
                $0.comments.forEach {
                    $0.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
            let commentFragment = GQLFragment(on: "IssueComment", elements: commentFields)
            elements.append(GQLGroup(name: "comments", fields: [commentFragment], pageSize: 100))
        }

        let fields = [GQLFragment(on: typeName, elements: Array(elements))]
        try await process(name: steps.toString, items: items, parentType: T.self, fields: fields)
    }

    static func updateReactions(for comments: [PRComment]) async throws {
        let reactionFragment = GQLFragment(on: "Reaction", elements: [
            idField,
            GQLField(name: "content"),
            GQLField(name: "createdAt"),
            GQLGroup(name: "user", fields: [userFragment])
        ])

        let itemFragment = GQLFragment(on: "IssueComment", elements: [
            idField,
            GQLGroup(name: "reactions", fields: [reactionFragment], pageSize: 100)
        ])

        try await process(name: "Comment Reactions", items: comments, fields: [itemFragment])
    }

    static func updateComments(for reviews: [Review]) async throws {
        let commentFragment = GQLFragment(on: "PullRequestReviewComment", elements: commentFields)

        let itemFragment = GQLFragment(on: "PullRequestReview", elements: [
            idField,
            GQLGroup(name: "comments", fields: [commentFragment], pageSize: 100)
        ])

        try await process(name: "Review Comments", items: reviews, fields: [itemFragment])
    }

    private static func process(name: String, items: [DataItem], parentType: (some ListableItem).Type? = nil, fields: [GQLElement]) async throws {
        if items.isEmpty {
            return
        }

        let itemsByServer = Dictionary(grouping: items) { $0.apiServer }
        var count = 0
        for (server, items) in itemsByServer {
            let ids = items.compactMap(\.nodeId)
            var nodes = [String: LinkedList<GQLNode>]()
            let serverName = server.label ?? "<no label>"
            let queries = GQLQuery.batching("\(serverName): \(name)", fields: fields, idList: ids, batchSize: 100) { node in
                let type = node.elementType
                if let existingList = nodes[type] {
                    existingList.append(node)
                } else {
                    nodes[type] = LinkedList<GQLNode>(value: node)
                }

                count += 1
                if count > nodeBlockMax {
                    count = 0
                    await processItems(nodes, server, parentType: parentType, wait: false)
                    nodes.removeAll(keepingCapacity: true)
                }
            }

            do {
                try await server.run(queries: queries)
                await processItems(nodes, server, parentType: parentType, wait: true)
            } catch {
                server.lastSyncSucceeded = false
                throw error
            }
        }
    }

    private static var milestoneFragment: GQLFragment {
        GQLFragment(on: "Milestone", elements: [
            GQLField(name: "title")
        ])
    }

    private static var labelFragment: GQLFragment {
        GQLFragment(on: "Label", elements: [
            idField,
            GQLField(name: "name"),
            GQLField(name: "color"),
            GQLField(name: "createdAt"),
            GQLField(name: "updatedAt")
        ])
    }

    private static var repositoryFragment: GQLFragment {
        GQLFragment(on: "Repository", elements: [
            idField,
            GQLField(name: "createdAt"),
            GQLField(name: "updatedAt"),
            GQLField(name: "isFork"),
            GQLField(name: "isArchived"),
            GQLField(name: "nameWithOwner"),
            GQLField(name: "url"),
            GQLField(name: "isPrivate"),
            GQLGroup(name: "owner", fields: [idField])
        ])
    }

    private static func prFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> GQLFragment {
        var elements: [GQLElement] = [
            idField,
            GQLField(name: "bodyText"),
            GQLField(name: "state"),
            GQLField(name: "createdAt"),
            GQLField(name: "updatedAt"),
            GQLField(name: "number"),
            GQLField(name: "title"),
            GQLField(name: "url"),
            GQLGroup(name: "milestone", fields: [milestoneFragment]),
            GQLGroup(name: "author", fields: [userFragment]),
            GQLGroup(name: "assignees", fields: [userFragment], pageSize: assigneesAndLabelPageSize),
            GQLGroup(name: "labels", fields: [labelFragment], pageSize: assigneesAndLabelPageSize),
            GQLField(name: "headRefOid"),
            GQLField(name: "mergeable"),
            GQLField(name: "additions"),
            GQLField(name: "deletions"),
            GQLField(name: "headRefName"),
            GQLField(name: "baseRefName"),
            GQLField(name: "isDraft"),
            GQLGroup(name: "mergedBy", fields: [userIdFragment]),
            GQLGroup(name: "baseRepository", fields: [nameWithOwnerField]),
            GQLGroup(name: "headRepository", fields: [nameWithOwnerField])
        ]
        if includeRepo {
            elements.append(GQLGroup(name: "repository", fields: [repositoryFragment]))
        }
        return GQLFragment(on: "PullRequest", elements: elements)
    }

    private static func issueFragment(assigneesAndLabelPageSize: Int, includeRepo: Bool) -> GQLFragment {
        var elements: [GQLElement] = [
            idField,
            GQLField(name: "bodyText"),
            GQLField(name: "state"),
            GQLField(name: "createdAt"),
            GQLField(name: "updatedAt"),
            GQLField(name: "number"),
            GQLField(name: "title"),
            GQLField(name: "url"),
            GQLGroup(name: "milestone", fields: [milestoneFragment]),
            GQLGroup(name: "author", fields: [userFragment]),
            GQLGroup(name: "assignees", fields: [userFragment], pageSize: assigneesAndLabelPageSize),
            GQLGroup(name: "labels", fields: [labelFragment], pageSize: assigneesAndLabelPageSize)
        ]
        if includeRepo {
            elements.append(GQLGroup(name: "repository", fields: [repositoryFragment]))
        }
        return GQLFragment(on: "Issue", elements: elements)
    }

    static func fetchAllAuthoredPrs(from servers: [ApiServer]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                if Settings.queryAuthoredPRs {
                    let g = GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 20, includeRepo: true)], extraParams: ["states": "OPEN"], pageSize: 100)
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, fields: [g]) {
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
                    let g = GQLGroup(name: "issues", fields: [issueFragment(assigneesAndLabelPageSize: 20, includeRepo: true)], extraParams: ["states": "OPEN"], pageSize: 100)
                    group.addTask { @MainActor in
                        if let nodes = await fetchAllAuthoredItems(from: server, fields: [g]) {
                            checkAuthoredIssueClosures(nodes: nodes, in: server)
                        }
                    }
                } else {
                    server.repos.filter { $0.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue }.forEach { $0.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue }
                }
            }
        }
    }

    static func fetchAllAuthoredItems(from server: ApiServer, fields: [GQLGroup]) async -> [String: LinkedList<GQLNode>]? {
        var count = 0
        var nodes = [String: LinkedList<GQLNode>]()
        let group = GQLGroup(name: "viewer", fields: fields)
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
                await self.processItems(nodes, server, wait: false)
                nodes.removeAll(keepingCapacity: true)
            }
        }
        do {
            try await server.run(queries: LinkedList(value: authoredItemsQuery))
            await processItems(nodes, server, wait: true)
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
        
        let prGroup = GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 1, includeRepo: true)])
        let group = GQLBatchGroup(templateGroup: prGroup, idList: prsToCheck.compactMap(\.nodeId), batchSize: 100)
        let nodes = LinkedList<GQLNode>()
        let query = GQLQuery(name: "Closed Authored PRs", rootElement: group, allowsEmptyResponse: true) { node in
            node.forcedUpdate = true
            nodes.append(node)
        }
        do {
            try await server.run(queries: LinkedList(value: query))
            await processItems(["PullRequest": nodes], server, wait: true)
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

    private static let latestPrsFragment = GQLFragment(on: "Repository", elements: [
        idField,
        GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)], extraParams: ["orderBy": "{direction: DESC, field: UPDATED_AT}"], pageSize: 10)
    ])

    private static let latestIssuesFragment = GQLFragment(on: "Repository", elements: [
        idField,
        GQLGroup(name: "issues", fields: [issueFragment(assigneesAndLabelPageSize: 20, includeRepo: false)], extraParams: ["orderBy": "{direction: DESC, field: UPDATED_AT}"], pageSize: 20)
    ])

    private static let allOpenPrsFragment = GQLFragment(on: "Repository", elements: [
        idField,
        GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 20, includeRepo: false)], extraParams: ["states": "OPEN"], pageSize: 50)
    ])

    private static let allOpenIssuesFragment = GQLFragment(on: "Repository", elements: [
        idField,
        GQLGroup(name: "issues", fields: [issueFragment(assigneesAndLabelPageSize: 20, includeRepo: false)], extraParams: ["states": "OPEN"], pageSize: 50)
    ])

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
                    await processItems(nodes, server, wait: false)
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
                let q = GQLQuery.batching("\(serverLabel): Updated PRs", fields: [latestPrsFragment], idList: Array(idsForReposInThisServerWantingLatestPrs), batchSize: 10, perNode: perNodeBlock)
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenPrs.count > 0 {
                let q = GQLQuery.batching("\(serverLabel): Open PRs", fields: [allOpenPrsFragment], idList: Array(idsForReposInThisServerWantingAllOpenPrs), batchSize: 100, perNode: perNodeBlock)
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await processItems(nodes, server, wait: true)
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
                    await processItems(nodes, server, wait: false)
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
                let q = GQLQuery.batching("\(serverLabel): Updated Issues", fields: [latestIssuesFragment], idList: Array(idsForReposInThisServerWantingLatestIssues), batchSize: 10, perNode: perNodeBlock)
                queriesForServer.append(contentsOf: q)
            }

            if idsForReposInThisServerWantingAllOpenIssues.count > 0 {
                let q = GQLQuery.batching("\(serverLabel): Open Issues", fields: [allOpenIssuesFragment], idList: Array(idsForReposInThisServerWantingAllOpenIssues), batchSize: 100, perNode: perNodeBlock)
                queriesForServer.append(contentsOf: q)
            }

            do {
                try await server.run(queries: queriesForServer)
                await processItems(nodes, server, wait: true)
            } catch {
                server.lastSyncSucceeded = false
            }
        }
    }

    private static var processTask: Task<Void, Never>?
    private static let gateKeeper = GateKeeper(entries: 1)

    private static func processItems(_ nodes: [String: LinkedList<GQLNode>], _ server: ApiServer, parentType: (some ListableItem).Type? = nil, wait: Bool) async {
        await gateKeeper.waitForGate() // ensure this is a critical path
        defer {
            gateKeeper.signalGate()
        }

        if let p = processTask { // wait for any previous task
            await p.value
        }

        if nodes.count == 0 {
            return
        }

        processTask = Task {
            await processBlock(nodes, server, parentType)
        }

        if wait, let t = processTask {
            await t.value
            processTask = nil
        }
    }

    private static func processBlock(_ nodes: [String: LinkedList<GQLNode>], _ server: ApiServer, _ parentType: (some ListableItem).Type?) async {
        guard let moc = server.managedObjectContext else { return }
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
}
