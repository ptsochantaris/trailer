import CoreData

final class Repo: DataItem {
    @NSManaged var fork: Bool
    @NSManaged var fullName: String?
    @NSManaged var groupLabel: String?
    @NSManaged var inaccessible: Bool
    @NSManaged var webUrl: String?
    @NSManaged var displayPolicyForPrs: Int64
    @NSManaged var displayPolicyForIssues: Int64
    @NSManaged var itemHidingPolicy: Int64
    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var issues: Set<Issue>
    @NSManaged var ownerNodeId: String?
    @NSManaged var manuallyAdded: Bool
    @NSManaged var archived: Bool
    @NSManaged var lastScannedIssueEventId: Int64

    override class var isParentType: Bool { true }

    override func resetSyncState() {
        super.resetSyncState()
        lastScannedIssueEventId = 0
        updatedAt = updatedAt?.addingTimeInterval(-1)
    }

    static func sync(from nodes: ContiguousArray<GQLNode>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: Repo.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { repo, node in

            var neededByAuthoredPr = false
            var neededByAuthoredIssue = false
            if let parent = node.parent {
                if parent.elementType == "PullRequest" {
                    neededByAuthoredPr = true
                    DataItem.parent(of: PullRequest.self, with: parent.id, in: moc, parentCache: parentCache)?.repo = repo

                } else if parent.elementType == "Issue" {
                    neededByAuthoredIssue = true
                    DataItem.parent(of: Issue.self, with: parent.id, in: moc, parentCache: parentCache)?.repo = repo
                }
            }

            if node.created || node.updated {
                let json = node.jsonPayload
                repo.fullName = json["nameWithOwner"] as? String
                repo.fork = json["fork"] as? Bool ?? false
                repo.webUrl = json["url"] as? String
                repo.inaccessible = false
                repo.archived = json["isArchived"] as? Bool ?? false
                repo.ownerNodeId = (json["owner"] as? [AnyHashable: Any])?["id"] as? String
                if node.created {
                    repo.displayPolicyForPrs = Int64(Settings.displayPolicyForNewPrs)
                    repo.displayPolicyForIssues = Int64(Settings.displayPolicyForNewIssues)
                }
            }

            if neededByAuthoredPr, repo.displayPolicyForPrs == RepoDisplayPolicy.hide.rawValue {
                repo.displayPolicyForPrs = RepoDisplayPolicy.authoredOnly.rawValue
            }
            if neededByAuthoredIssue, repo.displayPolicyForIssues == RepoDisplayPolicy.hide.rawValue {
                repo.displayPolicyForIssues = RepoDisplayPolicy.authoredOnly.rawValue
            }
        }
    }

    static func syncRepos(from data: [[AnyHashable: Any]]?, server: ApiServer, addNewRepos: Bool, manuallyAdded: Bool, moc: NSManagedObjectContext) async {
        let filteredData = data?.filter { info -> Bool in
            if info["private"] as? Bool ?? false {
                if let permissions = info["permissions"] as? [AnyHashable: Any] {
                    let pull = permissions["pull"] as? Bool ?? false
                    let push = permissions["push"] as? Bool ?? false
                    let admin = permissions["admin"] as? Bool ?? false

                    if pull || push || admin {
                        return true
                    } else if let fullName = info["full_name"] as? String {
                        DLog("Watched private repository '%@' seems to be inaccessible, skipping", fullName)
                    }
                }
                return false
            } else {
                return true
            }
        }

        await v3items(with: filteredData, type: Repo.self, serverId: server.objectID, createNewItems: addNewRepos, moc: moc) { item, info, newOrUpdated, _ in
            if newOrUpdated {
                item.fullName = info["full_name"] as? String
                item.fork = info["fork"] as? Bool ?? false
                item.webUrl = info["html_url"] as? String
                item.inaccessible = false
                item.archived = info["archived"] as? Bool ?? false
                item.ownerNodeId = (info["owner"] as? [AnyHashable: Any])?["node_id"] as? String
                item.manuallyAdded = manuallyAdded
                if item.postSyncAction == PostSyncAction.isNew.rawValue {
                    item.displayPolicyForPrs = Int64(Settings.displayPolicyForNewPrs)
                    item.displayPolicyForIssues = Int64(Settings.displayPolicyForNewIssues)
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
        for repo in Repo.allItems(of: Repo.self, in: moc) where repo.archived && repo.shouldSync {
            DLog("Auto-hiding archived repo ID \(repo.nodeId ?? "<no ID>")")
            repo.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue
            repo.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue
            madeChanges = true
        }
        return madeChanges
    }

    var apiUrl: String? {
        apiServer.apiPath?.appending(pathComponent: "repos").appending(pathComponent: fullName ?? "")
    }

    var isMine: Bool {
        ownerNodeId == apiServer.userNodeId
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

    @MainActor
    static func anyVisibleRepos(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, excludeGrouped: Bool = false) -> Bool {
        func excludeGroupedRepos(_ p: NSPredicate) -> NSPredicate {
            let nilCheck = NSPredicate(format: "groupLabel == nil")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [nilCheck, p])
        }

        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.includesSubentities = false
        f.fetchLimit = 1
        let p = NSPredicate(format: "displayPolicyForPrs > 0 or displayPolicyForIssues > 0")
        if let c = criterion {
            if let g = c.repoGroup { // special case will never need exclusion
                let rp = NSPredicate(format: "groupLabel == %@", g)
                f.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [rp, p])
            } else {
                let ep = c.addCriterion(to: p)
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
        let all: [Repo]
        if let serverId = id {
            all = Repo.allItems(of: Repo.self, in: serverId, moc: DataManager.main)
        } else {
            all = Repo.allItems(of: Repo.self, in: DataManager.main)
        }
        return all.contains { $0.displayPolicyForIssues != RepoDisplayPolicy.hide.rawValue }
    }

    @MainActor
    static func mayProvidePrsForDisplay(fromServerWithId id: NSManagedObjectID? = nil) -> Bool {
        let all: [Repo]
        if let serverId = id {
            all = Repo.allItems(of: Repo.self, in: serverId, moc: DataManager.main)
        } else {
            all = Repo.allItems(of: Repo.self, in: DataManager.main)
        }
        return all.contains { $0.displayPolicyForPrs != RepoDisplayPolicy.hide.rawValue }
    }

    @MainActor
    static func allGroupLabels(in moc: NSManagedObjectContext) -> [String] {
        let allRepos = allItems(of: Repo.self, in: moc)
        let labels = allRepos.compactMap { $0.displayPolicyForPrs > 0 || $0.displayPolicyForIssues > 0 ? $0.groupLabel : nil }
        return Set<String>(labels).sorted()
    }

    static func syncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "((displayPolicyForPrs > 0 and displayPolicyForPrs < 4) or (displayPolicyForIssues > 0 and displayPolicyForIssues < 4)) and inaccessible != YES")
        return try! moc.fetch(f)
    }

    static func unsyncableRepos(in moc: NSManagedObjectContext) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.relationshipKeyPathsForPrefetching = ["issues", "pullRequests"]
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "(not ((displayPolicyForPrs > 0 and displayPolicyForPrs < 4) or (displayPolicyForIssues > 0 and displayPolicyForIssues < 4))) or inaccessible = YES")
        return try! moc.fetch(f)
    }

    @MainActor
    static func reposFiltered(by filter: String?) -> [Repo] {
        let f = NSFetchRequest<Repo>(entityName: "Repo")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if let filterText = filter, !filterText.isEmpty {
            f.predicate = NSPredicate(format: "fullName contains [cd] %@", filterText)
        }
        return try! DataManager.main.fetch(f)
    }

    func markItemsAsUpdated(with numbers: Set<Int64>) {
        let predicate = NSPredicate(format: "(number IN %@) AND (repo == %@)", numbers, self)

        func mark<T>(type: T.Type) where T: ListableItem {
            let f = NSFetchRequest<T>(entityName: String(describing: type))
            f.returnsObjectsAsFaults = false
            f.includesSubentities = false
            f.predicate = predicate
            for i in try! managedObjectContext!.fetch(f) {
                // DLog("Ensuring item '%@' in repo '%@' is marked as updated - reasons: %@", S(i.title), S(i.repo.fullName), reasons.joined(separator: ", "))
                i.setToUpdatedIfIdle()
            }
        }

        mark(type: PullRequest.self)
        mark(type: Issue.self)
    }
}
