import CoreData
import Foundation
import Lista
import TrailerQL

final class PRStatus: DataItem {
    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var context: String?
    @NSManaged var targetUrl: String?

    @NSManaged var pullRequest: PullRequest

    override var alternateCreationDate: Bool { true }

    override class var typeName: String { "PRStatus" }

    static func syncStatuses(from data: [JSON]?, pullRequest: PullRequest, moc: NSManagedObjectContext) async {
        let pullRequestId = pullRequest.objectID
        let serverId = pullRequest.apiServer.objectID
        await v3items(with: data, type: PRStatus.self, serverId: serverId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let pr = try? syncMoc.existingObject(with: pullRequestId) as? PullRequest {
                item.state = info["state"] as? String
                item.context = info["context"] as? String
                item.targetUrl = info["target_url"] as? String
                item.pullRequest = pr

                if let ds = info["description"] as? String {
                    item.descriptionText = ds.trim
                }
            }
        }
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRStatus.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { status, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                if let parent = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    status.pullRequest = parent
                } else {
                    Logging.log("Warning: PRStatus without parent")
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
        switch state.orEmpty {
        case "", "neutral", "skipped":
            .appSecondaryLabel
        case "expected", "pending":
            .appYellow
        case "success":
            .appGreen
        default:
            .appRed
        }
    }

    override var asStatus: PRStatus? {
        self
    }

    var displayText: String {
        var text = switch state.orEmpty {
        case "":
            "⏺ "
        case "expected", "pending":
            "⚡️ "
        case "skipped":
            "⏭ "
        case "neutral":
            "ℹ️ "
        case "action_required":
            "⚠️ "
        case "cancelled":
            "⛔️ "
        case "success":
            "✅ "
        default:
            "❌ "
        }

        if let context, !context.isEmpty {
            if context == nodeId, let createdAt {
                text += shortDateFormatter.string(from: createdAt)
            } else {
                text += context
            }
        }

        if let descriptionText, !descriptionText.isEmpty {
            text += " - \(descriptionText)"
        }

        return text
    }
}
