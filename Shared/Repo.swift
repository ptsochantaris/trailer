import CoreData
import Lista
import TrailerJson
import TrailerQL

final class Repo: DataItem {
    @NSManaged var fork: Bool
    @NSManaged var fullName: String?
    @NSManaged var groupLabel: String?
    @NSManaged var inaccessible: Bool
    @NSManaged var webUrl: String?
    @NSManaged var displayPolicyForPrs: Int
    @NSManaged var displayPolicyForIssues: Int
    @NSManaged var itemHidingPolicy: Int
    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var issues: Set<Issue>
    @NSManaged var ownerNodeId: String?
    @NSManaged var manuallyAdded: Bool
    @NSManaged var archived: Bool
    @NSManaged var lastScannedIssueEventId: Int

    override static var typeName: String { "Repo" }

    override func resetSyncState() {
        super.resetSyncState()
        lastScannedIssueEventId = 0
        updatedAt = updatedAt?.addingTimeInterval(-1)
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: Repo.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { repo, node in

            var neededByAuthoredPr = false
            var neededByAuthoredIssue = false
            if let parent = node.parent {
                if parent.elementType == "PullRequest" {
                    neededByAuthoredPr = true
                    PullRequest.asParent(with: parent.id, in: moc, parentCache: parentCache)?.repo = repo

                } else if parent.elementType == "Issue" {
                    neededByAuthoredIssue = true
                    Issue.asParent(with: parent.id, in: moc, parentCache: parentCache)?.repo = repo
                }
            }

            if node.created || node.updated {
                let json = node.jsonPayload
                repo.fullName = json.potentialString(named: "nameWithOwner")
                repo.fork = json.potentialBool(named: "fork") ?? false
                repo.webUrl = json.potentialString(named: "url")
                repo.inaccessible = false
                repo.archived = json.potentialBool(named: "isArchived") ?? false
                repo.ownerNodeId = json.potentialObject(named: "owner")?.potentialString(named: "id")
                if node.created {
                    repo.displayPolicyForPrs = Settings.displayPolicyForNewPrs.rawValue
                    repo.displayPolicyForIssues = Settings.displayPolicyForNewIssues.rawValue
                }
            }

            if neededByAuthoredPr, repo.displayPolicyForPrs == RepoDisplayPolicy.hide.rawValue, !(repo.archived && Settings.hideArchivedRepos) {
                repo.displayPolicyForPrs = RepoDisplayPolicy.authoredOnly.rawValue
            }
            if neededByAuthoredIssue, repo.displayPolicyForIssues == RepoDisplayPolicy.hide.rawValue, !(repo.archived && Settings.hideArchivedRepos) {
                repo.displayPolicyForIssues = RepoDisplayPolicy.authoredOnly.rawValue
            }
        }
    }

    static func syncRepos(from data: [TypedJson.Entry]?, server: ApiServer, addNewRepos: Bool, manuallyAdded: Bool, moc: NSManagedObjectContext) async {
        let filteredData = data?.filter { info -> Bool in
            if info.potentialBool(named: "private") ?? false {
                if let permissions = info.potentialObject(named: "permissions") {
                    let pull = permissions.potentialBool(named: "pull") ?? false
                    let push = permissions.potentialBool(named: "push") ?? false
                    let admin = permissions.potentialBool(named: "admin") ?? false

                    if pull || push || admin {
                        return true
                    } else if let fullName = info.potentialString(named: "full_name") {
                        Logging.log("Watched private repository '\(fullName)' seems to be inaccessible, skipping")
                    }
                }
                return false
            } else {
                return true
            }
        }

        await v3items(with: filteredData, type: Repo.self, serverId: server.objectID, createNewItems: addNewRepos, moc: moc) { item, info, newOrUpdated, _ in
            if newOrUpdated {
                item.fullName = info.potentialString(named: "full_name")
                item.fork = info.potentialBool(named: "fork") ?? false
                item.webUrl = info.potentialString(named: "html_url")
                item.inaccessible = false
                item.archived = info.potentialBool(named: "archived") ?? false
                item.ownerNodeId = info.potentialObject(named: "owner")?.potentialString(named: "node_id")
                item.manuallyAdded = manuallyAdded
                if item.postSyncAction == PostSyncAction.isNew.rawValue {
                    item.displayPolicyForPrs = Settings.displayPolicyForNewPrs.rawValue
                    item.displayPolicyForIssues = Settings.displayPolicyForNewIssues.rawValue
                }
            }
        }
    }

    var shouldBeWipedIfNotInWatchlist: Bool {
        if manuallyAdded {
            return false
        }
        if displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue {
            return issues.isEmpty
        }
        if displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue {
            return pullRequests.isEmpty
        }
        return true
    }

    @discardableResult
    static func hideArchivedRepos(in moc: NSManagedObjectContext) -> Bool {
        var madeChanges = false
        for repo in Repo.allItems(in: moc) where repo.archived && repo.shouldSync {
            Logging.log("Auto-hiding archived repo ID \(repo.nodeId ?? "<no ID>")")
            repo.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue
            repo.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue
            madeChanges = true
        }
        return madeChanges
    }

    var apiUrl: String? {
        apiServer.apiPath?.appending(pathComponent: "repos").appending(pathComponent: fullName.orEmpty)
    }

    var isMine: Bool {
        ownerNodeId == apiServer.userNodeId
    }

    override var asRepo: Repo? {
        self
    }

    var shouldSync: Bool {
        var go = false
        switch displayPolicyForPrs {
        case RepoDisplayPolicy.authoredOnly.rawValue, RepoDisplayPolicy.hide.rawValue:
            break
        default:
            go = true
        }
        switch displayPolicyForIssues {
        case RepoDisplayPolicy.authoredOnly.rawValue, RepoDisplayPolicy.hide.rawValue:
            break
        default:
            go = true
        }
        return go
    }

    static func repos(for group: String, in moc: NSManagedObjectContext) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "groupLabel == %@", group)
        return try! moc.fetch(f)
    }

    static let visibleRepoPredicate = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")

    @MainActor
    static func anyVisibleRepos(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, excludeGrouped: Bool = false) -> Bool {
        func excludeGroupedRepos(_ p: NSPredicate) -> NSPredicate {
            let nilCheck = NSPredicate(format: "groupLabel == nil")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [nilCheck, p])
        }

        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.includesSubentities = false
        f.fetchLimit = 1
        let p = visibleRepoPredicate
        if let criterion {
            switch criterion {
            case let .group(g):
                // special case will never need exclusion
                let rp = NSPredicate(format: "groupLabel == %@", g)
                f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [rp, p])
            case .server:
                let ep = criterion.addCriterion(to: p)
                if excludeGrouped {
                    f.predicate = excludeGroupedRepos(ep)
                } else {
                    f.predicate = ep
                }
            }
        } else if excludeGrouped {
            f.predicate = excludeGroupedRepos(p)
        } else {
            f.predicate = p
        }
        let c = try! moc.count(for: f)
        return c > 0
    }

    @MainActor
    static func mayProvideIssuesForDisplay(fromServerWithId id: NSManagedObjectID? = nil) -> Bool {
        let all: [Repo] = if let id {
            Repo.allItems(in: id, moc: DataManager.main)
        } else {
            Repo.allItems(in: DataManager.main)
        }
        return all.contains { $0.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue }
    }

    @MainActor
    static func mayProvidePrsForDisplay(fromServerWithId id: NSManagedObjectID? = nil) -> Bool {
        let all: [Repo] = if let id {
            Repo.allItems(in: id, moc: DataManager.main)
        } else {
            Repo.allItems(in: DataManager.main)
        }
        return all.contains { $0.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue }
    }

    @MainActor
    static func allGroupLabels(in moc: NSManagedObjectContext) -> [String] {
        let allRepos = allItems(in: moc)
        let labels = allRepos.compactMap { $0.displayPolicyForPrs > 0 || $0.displayPolicyForIssues > 0 ? $0.groupLabel : nil }
        return Set<String>(labels).sorted()
    }

    private static let syncableRepoPredicate = NSPredicate(format: "((displayPolicyForPrs > 0 and displayPolicyForPrs < 4) or (displayPolicyForIssues > 0 and displayPolicyForIssues < 4)) and inaccessible != YES")
    static func syncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = syncableRepoPredicate
        return try! moc.fetch(f)
    }

    private static let unsyncableRepoPredicate = NSPredicate(format: "(not ((displayPolicyForPrs > 0 and displayPolicyForPrs < 4) or (displayPolicyForIssues > 0 and displayPolicyForIssues < 4))) or inaccessible = YES")
    static func unsyncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = unsyncableRepoPredicate
        return try! moc.fetch(f)
    }

    @MainActor
    static func reposFiltered(by filter: String?) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if let filter, !filter.isEmpty {
            f.predicate = NSPredicate(format: "fullName contains [cd] %@", filter)
        }
        return try! DataManager.main.fetch(f)
    }

    func markItemsAsUpdated(with numbers: Set<Int>) {
        let predicate = NSPredicate(format: "(number IN %@) AND (repo == %@)", numbers, self)

        func mark<T>(type: T.Type) where T: ListableItem {
            let f = NSFetchRequest<T>(entityName: type.typeName)
            f.returnsObjectsAsFaults = false
            f.includesSubentities = false
            f.predicate = predicate
            for i in try! managedObjectContext!.fetch(f) {
                // Logging.log("Ensuring item '%@' in repo '%@' is marked as updated - reasons: %@", S(i.title), S(i.repo.fullName), reasons.joined(separator: ", "))
                i.setToUpdatedIfIdle()
            }
        }

        mark(type: PullRequest.self)
        mark(type: Issue.self)
    }
}
