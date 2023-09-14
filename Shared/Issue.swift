import CoreData
import Lista
import TrailerQL
#if os(iOS)
    import UIKit
#endif

final class Issue: ListableItem {
    @NSManaged var closedByPullRequests: Set<PullRequest>

    override class var typeName: String { "Issue" }

    static func mostRecentItemUpdate(in repo: Repo) -> Date {
        repo.issues.reduce(.distantPast) { max($0, $1.updatedAt ?? .distantPast) }
    }

    override var webUrl: String? {
        super.webUrl?.appending(pathComponent: "issues").appending(pathComponent: String(number))
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: Issue.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { issue, node in

            let parentId: String
            if let parent = node.parent {
                parentId = parent.id

                if parent.elementType == "PullRequest" {
                    if let pr = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) {
                        pr.closesIssuesList.insert(node.id)
                    }
                    return
                }

            } else if let repoJson = node.jsonPayload["repository"] as? JSON, let pid = repoJson["id"] as? String {
                parentId = pid
            } else {
                return
            }

            guard node.created || node.updated,
                  let parent = Repo.asParent(with: parentId, in: moc, parentCache: parentCache)
            else { return }

            issue.baseNodeSync(node: node, parent: parent)
        }
    }

    static func syncIssues(from data: [JSON]?, in repo: Repo, moc: NSManagedObjectContext) async {
        let apiServer = repo.apiServer
        let repoId = repo.objectID

        let filteredData = data?.filter { $0["pull_request"] == nil } // don't sync issues which are pull requests, they are already synced
        await v3items(with: filteredData, type: Issue.self, serverId: apiServer.objectID, prefetchRelationships: ["labels"], moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let repo = try? syncMoc.existingObject(with: repoId) as? Repo {
                item.baseSync(from: info, in: repo)

                for l in item.labels {
                    l.postSyncAction = PostSyncAction.delete.rawValue
                }
            }
            if item.condition == ItemCondition.closed.rawValue {
                item.stateChanged = StateChange.reopened.rawValue
            }
            item.condition = ItemCondition.open.rawValue
        }
    }

    override var asIssue: Issue? {
        self
    }

    override var searchKeywords: [String] {
        ["Issue", "Issues"] + super.searchKeywords
    }

    static func markEverythingRead(in section: Section, in moc: NSManagedObjectContext, settings: Settings.Cache) {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if section.visible {
            f.predicate = section.matchingPredicate
        }
        for pr in try! moc.fetch(f) {
            pr.catchUpWithComments(settings: settings)
        }
    }

    static func badgeCount(in moc: NSManagedObjectContext, settings: Settings.Cache) -> Int {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate(settings: settings)])
        return badgeCount(from: f, in: moc)
    }

    @MainActor
    static func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion?, settings: Settings.Cache) -> Int {
        let f = requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: criterion, settings: settings)
        return badgeCount(from: f, in: moc)
    }

    @MainActor
    override class func hasOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Bool {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.includesSubentities = false
        f.fetchLimit = 1
        add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.open.matchingPredicate, in: moc)
        return try! moc.count(for: f) > 0
    }

    var labelsLink: String? {
        issueUrl?.appending(pathComponent: "labels")
    }

    @objc var sectionName: String {
        Section(sectionIndex: sectionIndex).issuesMenuName
    }

    @MainActor
    static func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [Issue] {
        let f = NSFetchRequest<Issue>(entityName: "Issue")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let p = ItemCondition.closed.matchingPredicate
        add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
        return try! moc.fetch(f)
    }

    override var shouldHideBecauseOfRepoHidingPolicy: Section.HidingCause? {
        if createdByMe {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllMyAuthoredItems.rawValue:
                .hidingMyAuthoredIssues
            case RepoHidingPolicy.hideMyAuthoredIssues.rawValue:
                .hidingMyAuthoredIssues
            default:
                nil
            }
        } else {
            switch repo.itemHidingPolicy {
            case RepoHidingPolicy.hideAllOthersItems.rawValue:
                .hidingAllOthersItems
            case RepoHidingPolicy.hideOthersIssues.rawValue:
                .hidingOthersIssues
            default:
                nil
            }
        }
    }
}
