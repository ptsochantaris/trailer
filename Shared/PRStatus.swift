import Foundation
import CoreData

final class PRStatus: DataItem {
    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var context: String?
    @NSManaged var targetUrl: String?

    @NSManaged var pullRequest: PullRequest

    override var alternateCreationDate: Bool { true }

    static func syncStatuses(from data: [[AnyHashable: Any]]?, pullRequest: PullRequest) {
        items(with: data, type: PRStatus.self, server: pullRequest.apiServer) { item, info, isNewOrUpdated in
            if isNewOrUpdated {
                item.state = info["state"] as? String
                item.context = info["context"] as? String
                item.targetUrl = info["target_url"] as? String
                item.pullRequest = pullRequest

                if let ds = info["description"] as? String {
                    item.descriptionText = ds.trim
                }
            }
        }
    }

    static func sync(from nodes: ContiguousArray<GQLNode>, on server: ApiServer, moc: NSManagedObjectContext) {
        syncItems(of: PRStatus.self, from: nodes, on: server, moc: moc) { status, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                if let parent = DataItem.item(of: PullRequest.self, with: parentId, in: moc) {
                    status.pullRequest = parent
                } else {
                    DLog("Warning: PRStatus without parent")
                }
            }

            let info = node.jsonPayload
            if node.elementType == "CheckRun" {
                status.state = (info["conclusion"] as? String)?.lowercased()
                status.context = node.id
                status.targetUrl = info["permalink"] as? String
                status.descriptionText = info["name"] as? String
            } else {
                status.state = (info["state"] as? String)?.lowercased()
                status.context = info["context"] as? String
                status.targetUrl = info["targetUrl"] as? String
                status.descriptionText = info["description"] as? String
            }
        }
    }

    var colorForDisplay: COLOR_CLASS {
        switch S(state) {
        case "", "neutral", "skipped":
            return .appSecondaryLabel
        case "expected", "pending":
            return .appYellow
        case "success":
            return .appGreen
        default:
            return .appRed
        }
    }

    var displayText: String {
        var text: String

        switch S(state) {
        case "":
            text = "⏺ "
        case "expected", "pending":
            text = "⚡️ "
        case "skipped":
            text = "⏭ "
        case "neutral":
            text = "ℹ️ "
        case "action_required":
            text = "⚠️ "
        case "cancelled":
            text = "⛔️ "
        case "success":
            text = "✅ "
        default:
            text = "❌ "
        }

        if let c = context, !c.isEmpty {
            if c == nodeId, let createdAt = createdAt {
                text += shortDateFormatter.string(from: createdAt)
            } else {
                text += c
            }
        }

        if let t = descriptionText, !t.isEmpty {
            text += " - \(t)"
        }

        return text
    }
}
