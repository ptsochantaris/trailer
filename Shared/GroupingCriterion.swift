import CoreData

// A value enum, so nonisolated. Only `label` and `relatedServerFailed` reach for `DataManager.main`,
// and they stay explicitly main-actor; everything else is pure and is used from model code and from
// child-context queues.
nonisolated enum GroupingCriterion {
    case server(NSManagedObjectID), group(String)

    var id: String {
        switch self {
        case let .server(id):
            id.uriRepresentation().absoluteString
        case let .group(label):
            label
        }
    }

    @MainActor
    var label: String {
        switch self {
        case let .group(name):
            return name
        case let .server(aid):
            let a = try? DataManager.main.existingObject(with: aid) as? ApiServer
            return a?.label ?? "<none>"
        }
    }

    @MainActor
    var relatedServerFailed: Bool {
        switch self {
        case let .group(name):
            return Repo.repos(for: name, in: DataManager.main).contains { !$0.apiServer.lastSyncSucceeded }
        case let .server(aid):
            let a = try? DataManager.main.existingObject(with: aid) as? ApiServer
            return !(a?.lastSyncSucceeded ?? true)
        }
    }

    func isRelated(to i: ListableItem) -> Bool {
        switch self {
        case let .group(name):
            i.repo.groupLabel == name
        case let .server(aid):
            i.apiServer.objectID == aid
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
            name
        case .server:
            nil
        }
    }

    var apiServerId: NSManagedObjectID? {
        switch self {
        case .group:
            nil
        case let .server(aid):
            aid
        }
    }
}
