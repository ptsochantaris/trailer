import CoreData
import Lista
import TrailerQL
#if os(iOS)
    import UIKit
#endif
import TrailerJson

final class PRLabel: DataItem {
    @NSManaged var color: Int
    @NSManaged var name: String?

    @NSManaged var pullRequests: Set<PullRequest>
    @NSManaged var issues: Set<Issue>

    override static var typeName: String { "PRLabel" }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRLabel.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { label, node in
            guard
                let parent = node.parent else { return }

            if parent.updated || parent.created {
                if parent.elementType == "PullRequest", let parentPr = PullRequest.asParent(with: parent.id, in: moc, parentCache: parentCache) {
                    label.pullRequests.insert(parentPr)
                } else if parent.elementType == "Issue", let parentIssue = Issue.asParent(with: parent.id, in: moc, parentCache: parentCache) {
                    label.issues.insert(parentIssue)
                } else {
                    Task {
                        await Logging.shared.log("Warning: PRLabel without parent")
                    }
                }
            }

            if node.created || node.updated {
                let info = node.jsonPayload
                label.name = info.potentialString(named: "name")
                if let c = info.potentialString(named: "color") {
                    label.color = PRLabel.parse(from: c)
                } else {
                    label.color = 0
                }
            }
        }
    }

    private static func labels(from data: [TypedJson.Entry]?, fromParent: ListableItem, postProcessCallback: (PRLabel, TypedJson.Entry) -> Void) {
        guard let data, !data.isEmpty else { return }

        var namesOfItems = [String]()
        var namesToInfo = [String: TypedJson.Entry]()
        namesToInfo.reserveCapacity(data.count)
        for info in data {
            if let name = info.potentialString(named: "name") {
                namesOfItems.append(name)
                namesToInfo[name] = info
            }
        }

        if namesOfItems.isEmpty { return }

        let f = NSFetchRequest<PRLabel>(entityName: "PRLabel")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        if fromParent.isPr {
            f.predicate = NSPredicate(format: "name in %@ and pullRequests contains %@", namesOfItems, fromParent)
        } else {
            f.predicate = NSPredicate(format: "name in %@ and issues contains %@", namesOfItems, fromParent)
        }

        let existingItems = try! fromParent.managedObjectContext?.fetch(f) ?? []
        for i in existingItems {
            if let name = i.name, let idx = namesOfItems.firstIndex(of: name), let info = namesToInfo[name] {
                namesOfItems.remove(at: idx)
                Task {
                    await Logging.shared.log("Updating Label: \(name)")
                }
                if i.nodeId == nil, let nodeId = info.potentialString(named: "node_id") { // migrate
                    i.nodeId = nodeId
                    Task {
                        await Logging.shared.log("Migrated label '\(name)' with node ID \(nodeId)")
                    }
                }
                postProcessCallback(i, info)
            }
        }

        for name in namesOfItems {
            if let info = namesToInfo[name] {
                Task {
                    await Logging.shared.log("Creating Label: \(name)")
                }
                let i = NSEntityDescription.insertNewObject(forEntityName: "PRLabel", into: fromParent.managedObjectContext!) as! PRLabel
                i.name = name
                i.nodeId = info.potentialString(named: "node_id")
                i.updatedAt = .distantPast
                i.createdAt = .distantPast
                i.apiServer = fromParent.apiServer
                fromParent.labels.insert(i)
                postProcessCallback(i, info)
            }
        }
    }

    static func syncLabels(from info: [TypedJson.Entry]?, withParent: ListableItem) {
        labels(from: info, fromParent: withParent) { label, info in
            if let c = info.potentialString(named: "color") {
                label.color = parse(from: c)
            } else {
                label.color = 0
            }
            label.postSyncAction = PostSyncAction.doNothing.rawValue
        }
    }

    private static func parse(from hex: String) -> Int {
        let safe = hex.trim.trimmingCharacters(in: CharacterSet.symbols)
        let s = Scanner(string: safe)
        var result: UInt64 = 0
        s.scanHexInt64(&result)
        return Int(result)
    }

    var colorForDisplay: COLOR_CLASS {
        let c = UInt32(color)
        let red: UInt32 = (c & 0xFF0000) >> 16
        let green: UInt32 = (c & 0x00FF00) >> 8
        let blue: UInt32 = c & 0x0000FF
        #if os(macOS)
            if red == 255, green == 255, blue == 255 {
                return COLOR_CLASS(deviceRed: 0.9, green: 0.9, blue: 0.9, alpha: 0.6)
            }
        #endif
        let r = CGFloat(red) / 255.0
        let g = CGFloat(green) / 255.0
        let b = CGFloat(blue) / 255.0
        return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
    }
}
