import CoreData
#if os(iOS)
    import UIKit
#endif

final class PRLabel: DataItem {
    @NSManaged var color: Int64
    @NSManaged var name: String?

    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var issues: Set<Issue>

    static func sync(from nodes: ContiguousArray<GQLNode>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRLabel.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { label, node in
            guard
                let parent = node.parent else { return }

            if parent.updated || parent.created {
                if parent.elementType == "PullRequest", let parentPr = DataItem.parent(of: PullRequest.self, with: parent.id, in: moc, parentCache: parentCache) {
                    label.pullRequests.insert(parentPr)
                } else if parent.elementType == "Issue", let parentIssue = DataItem.parent(of: Issue.self, with: parent.id, in: moc, parentCache: parentCache) {
                    label.issues.insert(parentIssue)
                } else {
                    DLog("Warning: PRLabel without parent")
                }
            }

            if node.created || node.updated {
                let info = node.jsonPayload
                label.name = info["name"] as? String
                if let c = info["color"] as? String {
                    label.color = PRLabel.parse(from: c)
                } else {
                    label.color = 0
                }
            }
        }
    }

    private static func labels(from data: [[AnyHashable: Any]]?, fromParent: ListableItem, postProcessCallback: (PRLabel, [AnyHashable: Any]) -> Void) {
        guard let infos = data, !infos.isEmpty else { return }

        var namesOfItems = [String]()
        var namesToInfo = [String: [AnyHashable: Any]]()
        for info in infos {
            if let name = info["name"] as? String {
                namesOfItems.append(name)
                namesToInfo[name] = info
            }
        }

        if namesOfItems.isEmpty { return }

        let f = NSFetchRequest<PRLabel>(entityName: "PRLabel")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if fromParent is PullRequest {
            f.predicate = NSPredicate(format: "name in %@ and pullRequests contains %@", namesOfItems, fromParent)
        } else {
            f.predicate = NSPredicate(format: "name in %@ and issues contains %@", namesOfItems, fromParent)
        }

        let existingItems = try! fromParent.managedObjectContext?.fetch(f) ?? []
        for i in existingItems {
            if let name = i.name, let idx = namesOfItems.firstIndex(of: name), let info = namesToInfo[name] {
                namesOfItems.remove(at: idx)
                DLog("Updating Label: %@", name)
                if i.nodeId == nil, let nodeId = info["node_id"] as? String { // migrate
                    i.nodeId = nodeId
                    DLog("Migrated label '\(name)' with node ID \(nodeId)")
                }
                postProcessCallback(i, info)
            }
        }

        for name in namesOfItems {
            if let info = namesToInfo[name] {
                DLog("Creating Label: %@", name)
                let i = NSEntityDescription.insertNewObject(forEntityName: "PRLabel", into: fromParent.managedObjectContext!) as! PRLabel
                i.name = name
                i.nodeId = info["node_id"] as? String
                i.updatedAt = .distantPast
                i.createdAt = .distantPast
                i.apiServer = fromParent.apiServer
                fromParent.labels.insert(i)
                postProcessCallback(i, info)
            }
        }
    }

    static func syncLabels(from info: [[AnyHashable: Any]]?, withParent: ListableItem) {
        labels(from: info, fromParent: withParent) { label, info in
            if let c = info["color"] as? String {
                label.color = parse(from: c)
            } else {
                label.color = 0
            }
            label.postSyncAction = PostSyncAction.doNothing.rawValue
        }
    }

    private static func parse(from hex: String) -> Int64 {
        let safe = hex.trim.trimmingCharacters(in: CharacterSet.symbols)
        let s = Scanner(string: safe)
        var result: UInt64 = 0
        s.scanHexInt64(&result)
        return Int64(result)
    }

    var colorForDisplay: COLOR_CLASS {
        let c = UInt32(color)
        let red: UInt32 = (c & 0xFF0000) >> 16
        let green: UInt32 = (c & 0x00FF00) >> 8
        let blue: UInt32 = c & 0x0000FF
        let r = CGFloat(red) / 255.0
        let g = CGFloat(green) / 255.0
        let b = CGFloat(blue) / 255.0
        return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
    }
}
