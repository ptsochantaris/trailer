import CoreData
import Foundation
import Lista
import TrailerJson
import TrailerQL

/// What a CI status means, independent of how it's drawn. Kept separate from the asset
/// catalog colours so that filtering logic stays usable off the main actor.
nonisolated enum StatusColour {
    case red, yellow, green, neutral
}

final nonisolated class PRStatus: DataItem {
    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var context: String?
    @NSManaged var targetUrl: String?

    @NSManaged var pullRequest: PullRequest

    override var alternateCreationDate: Bool {
        true
    }

    override static var typeName: String {
        "PRStatus"
    }

    @MainActor
    static func syncStatuses(from data: [TypedJson.Entry]?, pullRequest: PullRequest, moc: NSManagedObjectContext) async {
        let pullRequestId = pullRequest.objectID
        let serverId = pullRequest.apiServer.objectID
        await v3items(with: data, type: PRStatus.self, serverId: serverId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let pr = try? syncMoc.existingObject(with: pullRequestId) as? PullRequest {
                item.state = info.potentialString(named: "state")
                item.context = info.potentialString(named: "context")
                item.targetUrl = info.potentialString(named: "target_url")
                item.pullRequest = pr

                if let ds = info.potentialString(named: "description") {
                    item.descriptionText = ds.trim
                }
            }
        }
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRStatus.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { status, node in
            guard node.created(in: moc) || node.updated(in: moc),
                  let parentId = node.parent?.id
            else { return }

            if node.created(in: moc) {
                if let parent = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    status.pullRequest = parent
                } else {
                    Task {
                        await Logging.shared.log("Warning: PRStatus without parent")
                    }
                }
            }

            let info = node.jsonPayload
            if node.elementType == "CheckRun" {
                status.state = info.potentialString(named: "conclusion")?.lowercased()
                status.context = node.id
                status.targetUrl = info.potentialString(named: "permalink")
                status.descriptionText = info.potentialString(named: "name")
            } else {
                status.state = info.potentialString(named: "state")?.lowercased()
                status.context = info.potentialString(named: "context")
                status.targetUrl = info.potentialString(named: "targetUrl")
                status.descriptionText = info.potentialString(named: "description")
            }
        }
    }

    /// The *meaning* of a status, not its appearance. Filtering logic compares these cases;
    /// only the UI turns one into an actual colour, via `StatusColour.uiColour`. This used to
    /// return a `COLOR_CLASS`, which meant sync-side filtering decided what to show by
    /// comparing colour instances against the asset catalog.
    var displayColour: StatusColour {
        switch state.orEmpty {
        case "", "neutral", "skipped":
            .neutral
        case "expected", "pending":
            .yellow
        case "success":
            .green
        default:
            .red
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
                text += Date.Formatters.shortDateFormat.format(createdAt)
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
