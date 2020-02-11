import Foundation
import CoreData

final class GraphQL {
        
    private static let userFragment = GQLFragment(on: "User", elements: [
        GQLField(name: "id"),
        GQLField(name: "login"),
        GQLField(name: "avatarUrl")
    ])

    private static let mannequinFragment = GQLFragment(on: "Mannequin", elements: [
        GQLField(name: "id"),
        GQLField(name: "login"),
        GQLField(name: "avatarUrl")
    ])
    
    private static let teamFragment = GQLFragment(on: "Team", elements: [
        GQLField(name: "id"),
        GQLField(name: "slug")
    ])
    
    private static let commentFields: [GQLElement] = [
        GQLField(name: "id"),
        GQLField(name: "body"),
        GQLField(name: "url"),
        GQLField(name: "createdAt"),
        GQLField(name: "updatedAt"),
        GQLGroup(name: "author", fields: [userFragment])
    ]
    
    static func testApi(to apiServer: ApiServer, completion: @escaping (Bool, Error?) -> Void) {
        var gotUserNode = false
        let testQuery = GQLQuery(name: "Testing", rootElement: GQLGroup(name: "viewer", fields: [userFragment])) { node in
            DLog("Got a node, type: \(node.elementType), id: \(node.id)")
            if node.elementType == "User" {
                gotUserNode = true
            }
            return true
        }
        testQuery.run(for: apiServer.graphQLPath ?? "", authToken: apiServer.authToken ?? "", attempt: 0) { error, updatedStats in
            DispatchQueue.main.async {
                completion(gotUserNode, error)
            }
        }
    }

    static func update<T: ListableItem>(for items: [T], of type: T.Type, in moc: NSManagedObjectContext, steps: API.SyncSteps, callback: @escaping (Error?) -> Void) {
        let typeName = String(describing: T.self)
        
        var elements: [GQLElement] = [GQLField(name: "id")]
        var elementTypes = [String]()
        
        if let prs = items as? [PullRequest] {
            if steps.contains(.reviewRequests) {
                elementTypes.append("ReviewRequest")
                let requestFragment = GQLFragment(on: "ReviewRequest", elements: [
                    GQLField(name: "id"),
                    GQLGroup(name: "requestedReviewer", fields: [userFragment, teamFragment, mannequinFragment]),
                ])
                elements.append(GQLGroup(name: "reviewRequests", fields: [requestFragment], pageSize: 100))
            }
            
            if steps.contains(.reviews) {
                prs.forEach {
                    $0.reviews.forEach {
                        $0.postSyncAction = PostSyncAction.delete.rawValue
                    }
                }
                
                elementTypes.append("PullRequestReview")
                let reviewFragment = GQLFragment(on: "PullRequestReview", elements: [
                    GQLField(name: "id"),
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
                
                elementTypes.append("StatusContext")
                let statusFragment = GQLFragment(on: "StatusContext", elements: [
                    GQLField(name: "id"),
                    GQLField(name: "context"),
                    GQLField(name: "description"),
                    GQLField(name: "state"),
                    GQLField(name: "targetUrl"),
                    GQLField(name: "createdAt"),
                ])
                elements.append(GQLGroup(name: "commits", fields: [
                    GQLGroup(name: "commit", fields: [
                        GQLGroup(name: "status", fields: [
                            GQLGroup(name: "contexts", fields: [statusFragment])
                        ])
                    ])
                ], pageSize: 100, onlyLast: true))
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
            
            elementTypes.append("Reaction")
            let reactionFragment = GQLFragment(on: "Reaction", elements: [
                GQLField(name: "id"),
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
            elementTypes.append("IssueComment")
            let commentFragment = GQLFragment(on: "IssueComment", elements: commentFields)
            elements.append(GQLGroup(name: "comments", fields: [commentFragment], pageSize: 100))
        }

        
        let fields = [GQLFragment(on: typeName, elements: elements)]

        process(name: steps.toString, elementTypes: elementTypes, items: items, fields: fields, blockCallback: { server, nodeLookup, error in
            for (type, list) in nodeLookup {
                switch type {
                case "IssueComment":
                    PRComment.sync(from: list, on: server)
                case "Reaction":
                    Reaction.sync(from: list, for: T.self, on: server)
                case "ReviewRequest":
                    Review.syncRequests(from: list, on: server)
                case "PullRequestReview":
                    Review.sync(from: list, on: server)
                case "StatusContext":
                    PRStatus.sync(from: list, on: server)
                default:
                    break
                }
            }
        }, callback: callback)
    }
    
    static func updateReactions(for comments: [PRComment], moc: NSManagedObjectContext, callback: @escaping (Error?) -> Void) {
        let reactionFragment = GQLFragment(on: "Reaction", elements: [
            GQLField(name: "id"),
            GQLField(name: "content"),
            GQLField(name: "createdAt"),
            GQLGroup(name: "user", fields: [userFragment])
        ])

        let itemFragment = GQLFragment(on: "IssueComment", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "reactions", fields: [reactionFragment], pageSize: 100)
            ])
        
        process(name: "Reactions", elementType: "Reaction", items: comments, fields: [itemFragment], blockCallback: { server, nodes, error in
            Reaction.sync(from: nodes, for: PRComment.self, on: server)
        }, callback: callback)
    }

    static func updateComments(for reviews: [Review], moc: NSManagedObjectContext, callback: @escaping (Error?) -> Void) {
        let commentFragment = GQLFragment(on: "PullRequestReviewComment", elements: commentFields)
        
        let itemFragment = GQLFragment(on: "PullRequestReview", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "comments", fields: [commentFragment], pageSize: 100)
        ])

        process(name: "Review Comments", elementType: "PullRequestReviewComment", items: reviews, fields: [itemFragment], blockCallback: { server, nodes, error in
            PRComment.sync(from: nodes, on: server)
        }, callback: callback)
    }

    private static func process(name: String, elementType: String, items: [DataItem], fields: [GQLElement], blockCallback: @escaping (ApiServer, ContiguousArray<GQLNode>, Error?) -> Void, callback: @escaping (Error?)->Void) {
        process(name: name, elementTypes: [elementType], items: items, fields: fields, blockCallback: { server, nodeLookup, error in
            blockCallback(server, nodeLookup[elementType] ?? [], error)
        }, callback: callback)
    }
    
    private static func process(name: String, elementTypes: [String], items: [DataItem], fields: [GQLElement], blockCallback: @escaping (ApiServer, [String: ContiguousArray<GQLNode>], Error?) -> Void, callback: @escaping (Error?)->Void) {
        if items.isEmpty {
            callback(nil)
            return
        }
        
        let group = DispatchGroup()
        var finalError: Error?
        
        let itemsByServer = Dictionary(grouping: items) { $0.apiServer }
        var count = 0
        for (server, items) in itemsByServer {
            let ids = ContiguousArray(items.compactMap { $0.nodeId })
            var nodes = [String: ContiguousArray<GQLNode>]()
            let serverName = server.label ?? "<no label>"
            let queries = GQLQuery.batching("\(serverName): \(name)", fields: fields, idList: ids, batchSize: 100) { node in
                let type = node.elementType
                if var existingList = nodes[type] {
                    existingList.append(node)
                    nodes[type] = existingList
                } else {
                    var array = ContiguousArray<GQLNode>()
                    array.reserveCapacity(200)
                    array.append(node)
                    nodes[type] = array
                }
                
                count += 1
                if count > 199 {
                    count = 0
                    let nodesCopy = nodes
                    DispatchQueue.main.async {
                        blockCallback(server, nodesCopy, nil)
                    }
                    nodes.removeAll()
                }
                return true
            }
            group.enter()
            server.run(queries: queries) { error in
                if count > 0 || error != nil {
                    DispatchQueue.main.async { // needed in order to be sure this is queued after the node callback
                        if let error = error {
                            finalError = error
                            server.lastSyncSucceeded = false
                        }
                        blockCallback(server, nodes, error)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            DispatchQueue.main.async { // needed in order to be sure this is queued after the node callback
                callback(finalError)
            }
        }
    }
        
    static func fetchAllPrsAndIssues(from repos: [Repo], group: DispatchGroup) {
        if repos.isEmpty {
            return
        }
        
        let milestoneFragment = GQLFragment(on: "Milestone", elements: [
            GQLField(name: "title")
        ])
        
        let labelFragment = GQLFragment(on: "Label", elements: [
            GQLField(name: "id"),
            GQLField(name: "name"),
            GQLField(name: "color"),
            GQLField(name: "createdAt"),
            GQLField(name: "updatedAt")
        ])

        func prFragment(assigneesAndLabelPageSize: Int) -> GQLFragment {
            return GQLFragment(on: "PullRequest", elements: [
                GQLField(name: "id"),
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
                GQLGroup(name: "mergedBy", fields: [userFragment])
            ])
        }
        
        func issueFragment(assigneesAndLabelPageSize: Int) -> GQLFragment {
            return GQLFragment(on: "Issue", elements: [
                GQLField(name: "id"),
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
            ])
        }

        var prRepoIdToLatestExistingUpdate = [String: Date]()
        var issueRepoIdToLatestExistingUpdate = [String: Date]()

        let hideValue = RepoDisplayPolicy.hide.rawValue
        repos.forEach {
            if let n = $0.nodeId {
                if $0.displayPolicyForPrs != hideValue {
                    prRepoIdToLatestExistingUpdate[n] = PullRequest.mostRecentItemUpdate(in: $0)
                }
                if $0.displayPolicyForIssues != hideValue {
                    issueRepoIdToLatestExistingUpdate[n] = Issue.mostRecentItemUpdate(in: $0)
                }
            }
        }
        
        let allOpenPrsFragment = GQLFragment(on: "Repository", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 24)], extraParams: ["states": "OPEN"], pageSize: 100),
            ])
        let allOpenIssuesFragment = GQLFragment(on: "Repository", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "issues", fields: [issueFragment(assigneesAndLabelPageSize: 24)], extraParams: ["states": "OPEN"], pageSize: 100)
            ])

        
        let latestPrsFragment = GQLFragment(on: "Repository", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "pullRequests", fields: [prFragment(assigneesAndLabelPageSize: 100)], extraParams: ["orderBy": "{direction: DESC, field: UPDATED_AT}"], pageSize: 20),
            ])
        let latestIssuesFragment = GQLFragment(on: "Repository", elements: [
            GQLField(name: "id"),
            GQLGroup(name: "issues", fields: [issueFragment(assigneesAndLabelPageSize: 100)], extraParams: ["orderBy": "{direction: DESC, field: UPDATED_AT}"], pageSize: 20)
            ])

        let reposByServer = Dictionary(grouping: repos) { $0.apiServer }
        var count = 0
        
        for (server, reposInThisServer) in reposByServer {

            var nodes = [String: ContiguousArray<GQLNode>]()

            let perNodeCallback = { (node: GQLNode) -> Bool in

                let type = node.elementType
                if var existingList = nodes[type] {
                    existingList.append(node)
                    nodes[type] = existingList
                } else {
                    var array = ContiguousArray<GQLNode>()
                    array.reserveCapacity(200)
                    array.append(node)
                    nodes[type] = array
                }
                
                if type == "PullRequest",
                    let repo = node.parent,
                    let updatedAt = node.jsonPayload["updatedAt"] as? String,
                    let d = DataItem.parseGH8601(updatedAt),
                    d < prRepoIdToLatestExistingUpdate[repo.id]! {
                    return false
                }

                if type == "Issue",
                    let repo = node.parent,
                    let updatedAt = node.jsonPayload["updatedAt"] as? String,
                    let d = DataItem.parseGH8601(updatedAt),
                    d < issueRepoIdToLatestExistingUpdate[repo.id]! {
                    return false
                }

                count += 1
                if count > 399 {
                    count = 0
                    let nodesCopy = nodes
                    DispatchQueue.main.async {
                        self.processItem(nodesCopy, server)
                    }
                    nodes.removeAll()
                }
                
                return true
            }
            
            var queriesForServer = [GQLQuery]()
            let serverLabel = server.label ?? "<no label>"
            
            var idsForReposInThisServerWantingAllOpenPrs = ContiguousArray<String>()
            var idsForReposInThisServerWantingLatestPrs = ContiguousArray<String>()
            var idsForReposInThisServerWantingAllOpenIssues = ContiguousArray<String>()
            var idsForReposInThisServerWantingLatestIssues = ContiguousArray<String>()
            for repo in reposInThisServer {
                if let n = repo.nodeId {
                    if let last = prRepoIdToLatestExistingUpdate[n], last != .distantPast {
                        idsForReposInThisServerWantingLatestPrs.append(n)
                    } else if repo.displayPolicyForPrs != hideValue {
                        idsForReposInThisServerWantingAllOpenPrs.append(n)
                    }
                    if let last = issueRepoIdToLatestExistingUpdate[n], last != .distantPast {
                        idsForReposInThisServerWantingLatestIssues.append(n)
                    } else if repo.displayPolicyForIssues != hideValue {
                        idsForReposInThisServerWantingAllOpenIssues.append(n)
                    }
                }
            }
            
            if !idsForReposInThisServerWantingAllOpenPrs.isEmpty {
                let q = GQLQuery.batching("\(serverLabel): Open PRs", fields: [allOpenPrsFragment], idList: idsForReposInThisServerWantingAllOpenPrs, batchSize: 100, perNodeCallback: perNodeCallback)
                queriesForServer.append(contentsOf: q)
            }
            
            if !idsForReposInThisServerWantingAllOpenIssues.isEmpty {
                let q = GQLQuery.batching("\(serverLabel): Open Issues", fields: [allOpenIssuesFragment], idList: idsForReposInThisServerWantingAllOpenIssues, batchSize: 100, perNodeCallback: perNodeCallback)
                queriesForServer.append(contentsOf: q)
            }

            if !idsForReposInThisServerWantingLatestPrs.isEmpty {
                let q = GQLQuery.batching("\(serverLabel): Updated PRs", fields: [latestPrsFragment], idList: idsForReposInThisServerWantingLatestPrs, batchSize: 100, perNodeCallback: perNodeCallback)
                queriesForServer.append(contentsOf: q)
            }
            
            if !idsForReposInThisServerWantingLatestIssues.isEmpty {
                let q = GQLQuery.batching("\(serverLabel): Updated Issues", fields: [latestIssuesFragment], idList: idsForReposInThisServerWantingLatestIssues, batchSize: 100, perNodeCallback: perNodeCallback)
                queriesForServer.append(contentsOf: q)
            }

            group.enter()
            server.run(queries: queriesForServer) { error in
                if error != nil {
                    server.lastSyncSucceeded = false
                } else {
                    self.processItem(nodes, server)
                }
                group.leave()
            }
        }
    }
    
    private static func processItem(_ nodes: [String: ContiguousArray<GQLNode>], _ server: ApiServer) {
        // Order must be fixed, since labels may refer to PRs or Issues, ensure they are created first
        if let nodeList = nodes["PullRequest"] {
            PullRequest.sync(from: nodeList, on: server)
        }
        if let nodeList = nodes["Issue"] {
            Issue.sync(from: nodeList, on: server)
        }
        if let nodeList = nodes["Label"] {
            PRLabel.sync(from: nodeList, on: server)
        }
    }
}
