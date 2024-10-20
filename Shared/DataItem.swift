import CoreData
import Lista
import TrailerQL
import TrailerJson

final class FetchCache {
    private var store = [String: NSManagedObject]()

    subscript(key: String) -> NSManagedObject? {
        get { store[key] }
        set { store[key] = newValue }
    }
}

protocol Querying: NSManagedObject {
    static var typeName: String { get }
    var nodeId: String? { get set }
}

extension Querying {
    static func allItems(offset: Int? = nil, count: Int? = nil, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.relationshipKeyPathsForPrefetching = prefetchRelationships
        if let offset {
            f.fetchOffset = offset
        }
        if let count {
            f.fetchLimit = count
        }
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        return try! moc.fetch(f)
    }

    static func allItems(in serverId: NSManagedObjectID, moc: NSManagedObjectContext) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.predicate = NSPredicate(format: "apiServer == %@", serverId)
        return try! moc.fetch(f)
    }

    static func items(surviving: Bool, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.relationshipKeyPathsForPrefetching = prefetchRelationships
        f.includesSubentities = false
        if surviving {
            f.returnsObjectsAsFaults = false
            f.predicate = PostSyncAction.delete.excludingPredicate
        } else {
            f.returnsObjectsAsFaults = true
            f.predicate = PostSyncAction.delete.matchingPredicate
        }
        return try! moc.fetch(f)
    }

    static func untouchedMergedItems(in moc: NSManagedObjectContext) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [
            ItemCondition.merged.matchingPredicate,
            ApiServer.lastSyncSucceededPredicate,
            PostSyncAction.doNothing.matchingPredicate
        ])
        return try! moc.fetch(f)
    }

    static func untouchedClosedItems(in moc: NSManagedObjectContext) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSCompoundPredicate(type: .and, subpredicates: [
            ItemCondition.closed.matchingPredicate,
            ApiServer.lastSyncSucceededPredicate,
            PostSyncAction.doNothing.matchingPredicate
        ])
        return try! moc.fetch(f)
    }

    static func newOrUpdatedItems(in moc: NSManagedObjectContext, fromSuccessfulSyncOnly: Bool = false) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let typePredicate = NSCompoundPredicate(type: .or, subpredicates: [PostSyncAction.isNew.matchingPredicate, PostSyncAction.isUpdated.matchingPredicate])
        if fromSuccessfulSyncOnly {
            f.predicate = NSCompoundPredicate(type: .and, subpredicates: [
                ApiServer.lastSyncSucceededPredicate,
                typePredicate
            ])
        } else {
            f.predicate = typePredicate
        }
        return try! moc.fetch(f)
    }

    static func updatedItems(in moc: NSManagedObjectContext) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = PostSyncAction.isUpdated.matchingPredicate
        return try! moc.fetch(f)
    }

    static func newItems(in moc: NSManagedObjectContext) -> [Self] {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = PostSyncAction.isNew.matchingPredicate
        return try! moc.fetch(f)
    }

    static func asParent(with nodeId: String, in moc: NSManagedObjectContext, parentCache: FetchCache) -> Self? {
        if let existingObject = parentCache[nodeId] as? Self {
            return existingObject
        }
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.returnsObjectsAsFaults = true
        f.includesSubentities = false
        f.fetchLimit = 1
        f.predicate = NSPredicate(format: "nodeId == %@", nodeId)
        let object = try! moc.fetch(f).first
        if let object {
            parentCache[nodeId] = object
        }
        return object
    }

    static func nuke(query: String, in moc: NSManagedObjectContext) {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.includesSubentities = false
        f.predicate = NSPredicate(format: query)
        let orphaned = try! moc.fetch(f)
        if !orphaned.isEmpty {
            Logging.log("Nuking \(orphaned.count) \(typeName) items that no longer have a parent")
            for i in orphaned {
                moc.delete(i)
            }
        }
    }

    static func nukeDeletedItems(in moc: NSManagedObjectContext) -> Int {
        let discarded = items(surviving: false, in: moc)
        if !discarded.isEmpty {
            Logging.log("Nuking \(discarded.count) \(typeName) items marked for deletion")
            for i in discarded {
                moc.delete(i)
            }
        }
        return discarded.count
    }

    static func countItems(in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.includesSubentities = false
        return try! moc.count(for: f)
    }

    static func nullNodeIdItems(in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.fetchLimit = 1
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "nodeId == nil")
        return try! moc.count(for: f)
    }

    static func item(id: String, in moc: NSManagedObjectContext) -> Self? {
        let f = NSFetchRequest<Self>(entityName: typeName)
        f.fetchLimit = 1
        f.includesSubentities = false
        f.propertiesToFetch = ["nodeId"]
        f.predicate = NSPredicate(format: "nodeId == %@", id)
        do {
            return try moc.fetch(f).first
        } catch {
            Logging.log("Fetch error: \(error.localizedDescription)")
            return nil
        }
    }
}

class DataItem: NSManagedObject, Querying {
    @NSManaged var nodeId: String?
    @NSManaged var postSyncAction: Int
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var apiServer: ApiServer

    var alternateCreationDate: Bool { false }

    class var typeName: String { abort() }

    override func value(forUndefinedKey _: String) -> Any? {
        nil
    }

    func resetSyncState() {
        updatedAt = updatedAt?.addingTimeInterval(-1) ?? .distantPast
        apiServer.resetSyncState()
    }

    final func createdBefore(_ item: DataItem) -> Bool {
        let a = createdAt ?? .distantPast
        let b = item.createdAt ?? .distantPast
        if a < b {
            return true
        } else if a == b {
            return objectID.uriRepresentation().absoluteString < item.objectID.uriRepresentation().absoluteString
        } else {
            return false
        }
    }

    static func v3items<T: DataItem>(with data: [TypedJson.Entry]?,
                                     type _: T.Type,
                                     serverId: NSManagedObjectID,
                                     prefetchRelationships: [String]? = nil,
                                     createNewItems: Bool = true,
                                     moc: NSManagedObjectContext,
                                     postProcessCallback: @escaping (T, TypedJson.Entry, Bool, NSManagedObjectContext) -> Void) async {
        guard let data, !data.isEmpty else { return }

        var nodeIdsToInfo = [String: TypedJson.Entry]()
        nodeIdsToInfo.reserveCapacity(data.count)
        for info in data {
            let nodeId = info.potentialString(named: "node_id")!
            nodeIdsToInfo[nodeId] = info
        }

        if nodeIdsToInfo.isEmpty { return }

        await DataManager.runInChild(of: moc) { child in
            let entityName = typeName
            let f = NSFetchRequest<T>(entityName: entityName)
            f.relationshipKeyPathsForPrefetching = prefetchRelationships
            f.returnsObjectsAsFaults = false
            f.includesSubentities = false

            var nodeIdsOfItems = Set(nodeIdsToInfo.map { k, _ in k })
            f.predicate = NSPredicate(format: "nodeId in %@ and apiServer == %@", nodeIdsOfItems, serverId)
            let existingItems = try! child.fetch(f)

            let now = Date()

            for i in existingItems {
                if let nodeId = i.nodeId, let info = nodeIdsToInfo[nodeId] {
                    let updatedDate = DataItem.parseGH8601(info.potentialString(named: "updated_at")) ?? i.createdAt ?? now
                    if updatedDate != i.updatedAt {
                        Logging.log("Updating \(entityName): \(nodeId) (v3)")
                        i.postSyncAction = PostSyncAction.isUpdated.rawValue
                        i.updatedAt = updatedDate
                        postProcessCallback(i, info, true, child)
                    } else {
                        // Logging.log("Skipping %@: %@",type,serverId)
                        i.postSyncAction = PostSyncAction.doNothing.rawValue
                        postProcessCallback(i, info, false, child)
                    }
                    nodeIdsOfItems.remove(nodeId)
                }
            }

            guard createNewItems else { return }

            for nodeId in nodeIdsOfItems {
                if let info = nodeIdsToInfo[nodeId], let apiServer = try? child.existingObject(with: serverId) as? ApiServer {
                    Logging.log("Creating \(entityName): \(nodeId) (v3)")
                    let i = NSEntityDescription.insertNewObject(forEntityName: entityName, into: child) as! T
                    i.postSyncAction = PostSyncAction.isNew.rawValue
                    i.apiServer = apiServer
                    i.nodeId = nodeId

                    i.createdAt = DataItem.parseGH8601(info.potentialString(named: "created_at")) ?? now
                    i.updatedAt = DataItem.parseGH8601(info.potentialString(named: "updated_at")) ?? i.createdAt

                    postProcessCallback(i, info, true, child)
                }
            }
        }
    }

    static func nukeOrphanedItems(in moc: NSManagedObjectContext) {
        PRLabel.nuke(query: "pullRequests.@count == 0 and issues.@count == 0", in: moc)
        Review.nuke(query: "pullRequest == nil", in: moc)
        PRComment.nuke(query: "pullRequest == nil and issue == nil and review == nil", in: moc)
        PRStatus.nuke(query: "pullRequest == nil", in: moc)
        Reaction.nuke(query: "pullRequest == nil and issue == nil and comment == nil", in: moc)
    }

    static func nukeDeletedItems(in moc: NSManagedObjectContext) {
        var count = 0
        count += Repo.nukeDeletedItems(in: moc)
        count += PullRequest.nukeDeletedItems(in: moc)
        count += PRStatus.nukeDeletedItems(in: moc)
        count += PRComment.nukeDeletedItems(in: moc)
        count += PRLabel.nukeDeletedItems(in: moc)
        count += Issue.nukeDeletedItems(in: moc)
        count += Team.nukeDeletedItems(in: moc)
        count += Review.nukeDeletedItems(in: moc)
        count += Reaction.nukeDeletedItems(in: moc)
        Logging.log("Nuked total \(count) items marked for deletion")
    }

    @MainActor
    static func add(criterion: GroupingCriterion?, toFetchRequest: NSFetchRequest<some ListableItem>, originalPredicate: NSPredicate, in moc: NSManagedObjectContext, includeAllGroups: Bool = false) {
        var andPredicates = [NSPredicate]()
        if let criterion {
            andPredicates.append(criterion.addCriterion(to: originalPredicate))
        } else {
            andPredicates.append(originalPredicate)
        }
        if !includeAllGroups, criterion?.repoGroup == nil {
            for otherGroup in Repo.allGroupLabels(in: moc) {
                let p = NSPredicate(format: "repo.groupLabel == nil or repo.groupLabel != %@", otherGroup)
                andPredicates.append(p)
            }
        }
        if andPredicates.count == 1 {
            toFetchRequest.predicate = andPredicates.first
        } else {
            toFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        }
    }

    private nonisolated(unsafe) static var _lock = os_unfair_lock_s()
    private nonisolated(unsafe) static var dateParserTemplate = "                   +0000".cString(using: .ascii)!
    static func parseGH8601(_ i: String?) -> Date? {
        guard let i, i.count > 18 else { return nil }

        var timeData = tm()
        os_unfair_lock_lock(&_lock)
        memcpy(&dateParserTemplate, i, 19)
        strptime(dateParserTemplate, "%FT%T%z", &timeData)
        os_unfair_lock_unlock(&_lock)

        let t = mktime(&timeData)
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    private func populate(node: Node) {
        let info = node.jsonPayload
        let entityName = Self.typeName

        let alternativeDate = alternateCreationDate

        if node.created {
            nodeId = node.id
            if !alternativeDate, let created = info.potentialString(named: "createdAt") {
                createdAt = DataItem.parseGH8601(created)!
            }
        }

        if alternativeDate, let created = info.potentialString(named: "completedAt") ?? info.potentialString(named: "startedAt") {
            createdAt = DataItem.parseGH8601(created)
        }

        if let updated = DataItem.parseGH8601(info.potentialString(named: "updatedAt")) {
            if updatedAt != updated {
                updatedAt = updated
                if !node.created {
                    node.updated = true
                }
            }

        } else if node.created {
            updatedAt = createdAt
        }

        if node.forcedUpdate {
            node.updated = true
        }

        if node.created {
            Logging.log("Creating \(entityName) ID: \(node.id) (v4)")
            postSyncAction = PostSyncAction.isNew.rawValue

        } else if node.updated {
            Logging.log("Updating \(entityName) ID: \(node.id) (v4)")
            postSyncAction = PostSyncAction.isUpdated.rawValue

        } else {
            /*
             switch PostSyncAction(rawValue: postSyncAction) {
             case .delete:
                 Logging.log("Keeping %@ ID: %@", entityName, node.id)
             case .doNothing:
                 Logging.log("Ignoring %@ ID: %@", entityName, node.id)
             case .isNew:
                 Logging.log("Is New %@ ID: %@", entityName, node.id)
             case .isUpdated:
                 Logging.log("Is Updated %@ ID: %@", entityName, node.id)
             case .none:
                 Logging.log("Other %@ ID: %@", entityName, node.id)
             }
              */
            if postSyncAction == PostSyncAction.delete.rawValue {
                postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    static func allIds(in server: ApiServer, moc: NSManagedObjectContext) -> [String] {
        let entityName = typeName
        let f = NSFetchRequest<Self>(entityName: entityName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "apiServer == %@", server)
        let existingItems = try! moc.fetch(f)
        return existingItems.compactMap { $0.value(forKey: "nodeId") as? String }
    }

    static func syncItems<T: DataItem>(of _: T.Type, from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache, perItemCallback: (T, Node) -> Void) {
        let validNodes = nodes.filter { !($0.parent?.creationSkipped ?? false) }
        if validNodes.isEmpty {
            return
        }

        let entityName = typeName
        let f = NSFetchRequest<T>(entityName: entityName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "nodeId in %@", validNodes.map(\.id))
        let existingItems = try! moc.fetch(f)
        let existingItemIds = existingItems.map(\.nodeId)
        var itemLookup = Dictionary(zip(existingItemIds, existingItems)) { one, two in
            Logging.log("Warning: Duplicate item of type \(entityName) claiming to be node ID \(one.nodeId ?? "<no node id>") - will discard")
            two.postSyncAction = PostSyncAction.delete.rawValue
            return one
        }

        for node in validNodes {
            if let existingItem = itemLookup[node.id] {
                // there can be multiple updates for an item, because of multiple parents
                existingItem.populate(node: node)
                perItemCallback(existingItem, node)
            } else if shouldCreate(from: node) {
                // but only one creation
                node.created = true
                let item = NSEntityDescription.insertNewObject(forEntityName: entityName, into: moc) as! T
                item.apiServer = server
                item.populate(node: node)
                parentCache[node.id] = item
                itemLookup[node.id] = item
                perItemCallback(item, node)
            }
        }
    }

    class func shouldCreate(from _: Node) -> Bool { true }

    var isPr: Bool {
        false
    }

    var asPr: PullRequest? {
        nil
    }

    var asIssue: Issue? {
        nil
    }

    var asComment: PRComment? {
        nil
    }

    var asReview: Review? {
        nil
    }

    var asRepo: Repo? {
        nil
    }

    var asStatus: PRStatus? {
        nil
    }

    var asReaction: Reaction? {
        nil
    }
}
