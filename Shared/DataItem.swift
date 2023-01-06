import CoreData

typealias FetchCache = NSCache<NSString, NSManagedObject>

class DataItem: NSManagedObject {
    @NSManaged var nodeId: String?
    @NSManaged var postSyncAction: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var apiServer: ApiServer

    var alternateCreationDate: Bool { false }

    class var isParentType: Bool { false }

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

    static func allItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.relationshipKeyPathsForPrefetching = prefetchRelationships
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        return try! moc.fetch(f)
    }

    static func allItems<T: DataItem>(of type: T.Type, in serverId: NSManagedObjectID, moc: NSManagedObjectContext) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = false
        f.predicate = NSPredicate(format: "apiServer == %@", serverId)
        return try! moc.fetch(f)
    }

    static func v3items<T: DataItem>(with data: [[AnyHashable: Any]]?,
                                     type: T.Type,
                                     serverId: NSManagedObjectID,
                                     prefetchRelationships: [String]? = nil,
                                     createNewItems: Bool = true,
                                     moc: NSManagedObjectContext,
                                     postProcessCallback: @escaping (T, [AnyHashable: Any], Bool, NSManagedObjectContext) -> Void) async {
        guard let infos = data, !infos.isEmpty else { return }

        var legacyIdsToNodeIds = [Int64: String]()

        var nodeIdsToInfo = [String: [AnyHashable: Any]]()
        for info in infos {
            let nodeId = info["node_id"] as! String
            nodeIdsToInfo[nodeId] = info
            if let legacyId = info["id"] as? Int64 { // TODO: only do this if migration not yet recorded
                legacyIdsToNodeIds[legacyId] = nodeId
            }
        }

        if nodeIdsToInfo.isEmpty { return }

        await DataManager.runInChild(of: moc) { child in
            let entityName = String(describing: type)
            let f = NSFetchRequest<T>(entityName: entityName)
            f.relationshipKeyPathsForPrefetching = prefetchRelationships
            f.returnsObjectsAsFaults = false
            f.includesSubentities = false

            let legacyServerIds = legacyIdsToNodeIds.map { k, _ in k }
            f.predicate = NSPredicate(format: "serverId in %@ and apiServer == %@", legacyServerIds, serverId)
            for item in try! child.fetch(f) {
                if let legacyId = item.value(forKey: "serverId") as? Int64 {
                    if let nodeId = legacyIdsToNodeIds[legacyId] {
                        item.nodeId = nodeId
                        item.setValue(nil, forKey: "serverId")
                        DLog("Migrated \(entityName) from legacy ID \(legacyId) to node ID \(nodeId)")
                    } else {
                        DLog("Warning: Migration failed for \(entityName) with legacy ID \(legacyId), could not find node ID")
                    }
                } else {
                    DLog("Warning: Migration failed for \(entityName) - could not read legacy ID!")
                }
            }

            var nodeIdsOfItems = Set(nodeIdsToInfo.map { k, _ in k })
            f.predicate = NSPredicate(format: "nodeId in %@ and apiServer == %@", nodeIdsOfItems, serverId)
            let existingItems = try! child.fetch(f)

            let now = Date()

            for i in existingItems {
                if let nodeId = i.nodeId, let info = nodeIdsToInfo[nodeId] {
                    let updatedDate = DataItem.parseGH8601(info["updated_at"] as? String) ?? i.createdAt ?? now
                    if updatedDate != i.updatedAt {
                        DLog("Updating %@: %@ (v3)", entityName, nodeId)
                        i.postSyncAction = PostSyncAction.isUpdated.rawValue
                        i.updatedAt = updatedDate
                        postProcessCallback(i, info, true, child)
                    } else {
                        // DLog("Skipping %@: %@",type,serverId)
                        i.postSyncAction = PostSyncAction.doNothing.rawValue
                        postProcessCallback(i, info, false, child)
                    }
                    nodeIdsOfItems.remove(nodeId)
                }
            }

            if !createNewItems { return }

            for nodeId in nodeIdsOfItems {
                if let info = nodeIdsToInfo[nodeId], let apiServer = try? child.existingObject(with: serverId) as? ApiServer {
                    DLog("Creating %@: %@ (v3)", entityName, nodeId)
                    let i = NSEntityDescription.insertNewObject(forEntityName: entityName, into: child) as! T
                    i.postSyncAction = PostSyncAction.isNew.rawValue
                    i.apiServer = apiServer
                    i.nodeId = nodeId

                    i.createdAt = DataItem.parseGH8601(info["created_at"] as? String) ?? now
                    i.updatedAt = DataItem.parseGH8601(info["updated_at"] as? String) ?? i.createdAt

                    postProcessCallback(i, info, true, child)
                }
            }
        }
    }

    static func parent<T: DataItem>(of type: T.Type, with nodeId: String, in moc: NSManagedObjectContext, parentCache: FetchCache) -> T? {
        if let existingObject = parentCache.object(forKey: nodeId as NSString) as? T {
            return existingObject
        }
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = true
        f.includesSubentities = false
        f.fetchLimit = 1
        f.predicate = NSPredicate(format: "nodeId == %@", nodeId)
        let object = try! moc.fetch(f).first
        if let object {
            parentCache.setObject(object, forKey: nodeId as NSString)
        }
        return object
    }

    static func items<T: DataItem>(of type: T.Type, surviving: Bool, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
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

    static func newOrUpdatedItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext, fromSuccessfulSyncOnly: Bool = false) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        let typePredicate = NSCompoundPredicate(type: .or, subpredicates: [PostSyncAction.isNew.matchingPredicate, PostSyncAction.isUpdated.matchingPredicate])
        if fromSuccessfulSyncOnly {
            f.predicate = NSCompoundPredicate(type: .and, subpredicates: [
                NSPredicate(format: "apiServer.lastSyncSucceeded == YES"),
                typePredicate
            ])
        } else {
            f.predicate = typePredicate
        }
        return try! moc.fetch(f)
    }

    static func updatedItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = PostSyncAction.isUpdated.matchingPredicate
        return try! moc.fetch(f)
    }

    static func newItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> [T] {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = PostSyncAction.isNew.matchingPredicate
        return try! moc.fetch(f)
    }

    static func nukeOrphanedItems(in moc: NSManagedObjectContext) {
        func nuke<T: DataItem>(type: T.Type, query: String) {
            let typeName = String(describing: type)
            let f = NSFetchRequest<T>(entityName: typeName)
            f.includesSubentities = false
            f.predicate = NSPredicate(format: query)
            let orphaned = try! moc.fetch(f)
            if !orphaned.isEmpty {
                DLog("Nuking %@ \(typeName) items that no longer have a parent", orphaned.count)
                for i in orphaned {
                    moc.delete(i)
                }
            }
        }

        nuke(type: PRLabel.self, query: "pullRequests.@count == 0 and issues.@count == 0")
        nuke(type: Review.self, query: "pullRequest == nil")
        nuke(type: PRComment.self, query: "pullRequest == nil and issue == nil and review == nil")
        nuke(type: PRStatus.self, query: "pullRequest == nil")
        nuke(type: Reaction.self, query: "pullRequest == nil and issue == nil and comment == nil")
    }

    static func nukeDeletedItems(in moc: NSManagedObjectContext) {
        func nukeDeletedItems(of type: (some DataItem).Type, in moc: NSManagedObjectContext) -> Int {
            let discarded = items(of: type, surviving: false, in: moc)
            if !discarded.isEmpty {
                DLog("Nuking %@ %@ items marked for deletion", discarded.count, String(describing: type))
                for i in discarded {
                    moc.delete(i)
                }
            }
            return discarded.count
        }

        var count = 0
        count += nukeDeletedItems(of: Repo.self, in: moc)
        count += nukeDeletedItems(of: PullRequest.self, in: moc)
        count += nukeDeletedItems(of: PRStatus.self, in: moc)
        count += nukeDeletedItems(of: PRComment.self, in: moc)
        count += nukeDeletedItems(of: PRLabel.self, in: moc)
        count += nukeDeletedItems(of: Issue.self, in: moc)
        count += nukeDeletedItems(of: Team.self, in: moc)
        count += nukeDeletedItems(of: Review.self, in: moc)
        count += nukeDeletedItems(of: Reaction.self, in: moc)
        DLog("Nuked total \(count) items marked for deletion")
    }

    static func countItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<T>(entityName: String(describing: type))
        f.includesSubentities = false
        return try! moc.count(for: f)
    }

    static func nullNodeIdItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> Int {
        let entityName = String(describing: type)
        let f = NSFetchRequest<T>(entityName: entityName)
        f.fetchLimit = 1
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "nodeId == nil")
        return try! moc.count(for: f)
    }

    @MainActor
    static func add(criterion: GroupingCriterion?, toFetchRequest: NSFetchRequest<some ListableItem>, originalPredicate: NSPredicate, in moc: NSManagedObjectContext, includeAllGroups: Bool = false) {
        var andPredicates = [NSPredicate]()
        if let c = criterion {
            andPredicates.append(c.addCriterion(to: originalPredicate))
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

    // Single-purpose derivation from the excellent SAMAdditions:
    // https://github.com/soffes/SAMCategories/blob/master/SAMCategories/NSDate%2BSAMAdditions.m
    private static let dateParserTemplate = "                   +0000".cString(using: .ascii)!
    static func parseGH8601(_ i: String?) -> Date? {
        guard let i, i.count > 18 else { return nil }

        var buffer = [CChar](repeating: 0, count: 25)
        memcpy(&buffer, dateParserTemplate, 24)
        memcpy(&buffer, i, 19)

        var timeData = tm()
        strptime(buffer, "%FT%T%z", &timeData)

        let t = mktime(&timeData)
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    private func populate(type: (some DataItem).Type, node: GQLNode) {
        let info = node.jsonPayload
        let entityName = String(describing: type)

        let alternativeDate = alternateCreationDate

        if node.created {
            nodeId = node.id
            if !alternativeDate, let created = info["createdAt"] as? String {
                createdAt = DataItem.parseGH8601(created)!
            }
        }

        if alternativeDate, let created = (info["completedAt"] ?? info["startedAt"]) as? String {
            createdAt = DataItem.parseGH8601(created)
        }

        if let updated = DataItem.parseGH8601(info["updatedAt"] as? String) {
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
            DLog("Creating %@ ID: %@ (v4)", entityName, node.id)
            postSyncAction = PostSyncAction.isNew.rawValue

        } else if node.updated {
            DLog("Updating %@ ID: %@ (v4)", entityName, node.id)
            postSyncAction = PostSyncAction.isUpdated.rawValue

        } else {
            /*
             switch PostSyncAction(rawValue: postSyncAction) {
             case .delete:
                 DLog("Keeping %@ ID: %@", entityName, node.id)
             case .doNothing:
                 DLog("Ignoring %@ ID: %@", entityName, node.id)
             case .isNew:
                 DLog("Is New %@ ID: %@", entityName, node.id)
             case .isUpdated:
                 DLog("Is Updated %@ ID: %@", entityName, node.id)
             case .none:
                 DLog("Other %@ ID: %@", entityName, node.id)
             }
              */
            if postSyncAction == PostSyncAction.delete.rawValue {
                postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    static func syncItems<T: DataItem>(of type: T.Type, from nodes: ContiguousArray<GQLNode>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache, perItemCallback: (T, GQLNode) -> Void) {
        let validNodes = nodes.filter { !($0.parent?.creationSkipped ?? false) }
        if nodes.isEmpty {
            return
        }

        let entityName = String(describing: type)
        let f = NSFetchRequest<T>(entityName: entityName)
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "nodeId in %@", validNodes.map(\.id))
        let existingItems = try! moc.fetch(f)
        let existingItemIds = existingItems.map(\.nodeId)
        var itemLookup = Dictionary(zip(existingItemIds, existingItems)) { one, two in
            DLog("Warning: Duplicate item of type \(String(describing: type)) claiming to be node ID \(one.nodeId ?? "<no node id>") - will delete")
            two.postSyncAction = PostSyncAction.delete.rawValue
            return one
        }

        for node in validNodes {
            if let existingItem = itemLookup[node.id] {
                // there can be multiple updates for an item, because of multiple parents
                existingItem.populate(type: T.self, node: node)
                perItemCallback(existingItem, node)
            } else if shouldCreate(from: node) {
                // but only one creation
                node.created = true
                let item = NSEntityDescription.insertNewObject(forEntityName: entityName, into: moc) as! T
                item.apiServer = server
                item.populate(type: T.self, node: node)
                parentCache.setObject(item, forKey: node.id as NSString)
                itemLookup[node.id] = item
                perItemCallback(item, node)
            }
        }
    }

    class func shouldCreate(from _: GQLNode) -> Bool { true }
}
