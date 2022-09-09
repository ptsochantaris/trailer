import CoreData

@MainActor
final class GroupingCriterion {
    let apiServerId: NSManagedObjectID?
    let repoGroup: String?

    init(apiServerId: NSManagedObjectID?) {
        self.apiServerId = apiServerId
        repoGroup = nil
    }

    init(repoGroup: String) {
        apiServerId = nil
        self.repoGroup = repoGroup
    }

    var label: String {
        if let r = repoGroup {
            return r
        } else if let aid = apiServerId, let a = existingObject(with: aid) as? ApiServer {
            return a.label ?? "<none>"
        } else {
            return "<none>"
        }
    }

    var relatedServerFailed: Bool {
        if let aid = apiServerId, let a = existingObject(with: aid) as? ApiServer, !a.lastSyncSucceeded {
            return true
        }
        if let group = repoGroup, Repo.repos(for: group, in: DataManager.main).contains(where: { !$0.apiServer.lastSyncSucceeded }) {
            return true
        }
        return false
    }

    func isRelated(to i: ListableItem) -> Bool {
        if let aid = apiServerId {
            if i.apiServer.objectID != aid {
                return false
            }
        } else if let r = repoGroup {
            if let l = i.repo.groupLabel {
                return r == l
            } else {
                return false
            }
        }
        return true
    }

    func addCriterion(to predicate: NSPredicate) -> NSPredicate {
        if let apiServerId {
            let np = NSPredicate(format: "apiServer == %@", apiServerId)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [np, predicate])
        } else if let r = repoGroup {
            let np = NSPredicate(format: "repo.groupLabel == %@", r)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [np, predicate])
        } else {
            return predicate
        }
    }
}
