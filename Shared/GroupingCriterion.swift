import CoreData

enum GroupingCriterion {
    case server(NSManagedObjectID), group(String)

    @MainActor
    var label: String {
        switch self {
        case let .group(name):
            return name
        case let .server(aid):
            let a = existingObject(with: aid) as? ApiServer
            return a?.label ?? "<none>"
        }
    }

    @MainActor
    var relatedServerFailed: Bool {
        switch self {
        case let .group(name):
            return Repo.repos(for: name, in: DataManager.main).contains { !$0.apiServer.lastSyncSucceeded }
        case let .server(aid):
            let a = existingObject(with: aid) as? ApiServer
            return !(a?.lastSyncSucceeded ?? true)
        }
    }

    func isRelated(to i: ListableItem) -> Bool {
        switch self {
        case let .group(name):
            return i.repo.groupLabel == name
        case let .server(aid):
            return i.apiServer.objectID == aid
        }
    }

    func addCriterion(to predicate: NSPredicate) -> NSPredicate {
        switch self {
        case let .group(name):
            let np = NSPredicate(format: "repo.groupLabel == %@", name)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [np, predicate])
        case let .server(aid):
            let np = NSPredicate(format: "apiServer == %@", aid)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [np, predicate])
        }
    }

    var repoGroup: String? {
        switch self {
        case let .group(name):
            return name
        case .server:
            return nil
        }
    }

    var apiServerId: NSManagedObjectID? {
        switch self {
        case .group:
            return nil
        case let .server(aid):
            return aid
        }
    }
}
