import Foundation

final class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
	@NSManaged var context: String?
    @NSManaged var targetUrl: String?

	@NSManaged var pullRequest: PullRequest

	static func syncStatuses(from data: [[AnyHashable : Any]]?, pullRequest: PullRequest) {
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
    
    static func sync(from nodes: ContiguousArray<GQLNode>, on server: ApiServer) {
        syncItems(of: PRStatus.self, from: nodes, on: server) { status, node in
            guard node.created || node.updated,
                let parentId = node.parent?.id,
                let moc = server.managedObjectContext
                else { return }

            if node.created {
                if let parent = DataItem.item(of: PullRequest.self, with: parentId, in: moc) {
                    status.pullRequest = parent
                } else {
                    DLog("Warning: PRStatus without parent")
                }
            }
            
            let info = node.jsonPayload
            status.state = (info["state"] as? String)?.lowercased()
            status.context = info["context"] as? String
            status.targetUrl = info["targetUrl"] as? String
            if let ds = info["description"] as? String {
                status.descriptionText = ds.trim
            }
        }
    }
    
	var colorForDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending", "expected":
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
		case "pending", "expected":
			text = "⚡️ "
		case "success":
			text = "✅ "
		default:
			text = "❌ "
		}

		if let c = context, !c.isEmpty {
			text += c
		}

		if let t = descriptionText, !t.isEmpty {
			text += " - \(t)"
		}

		return text
	}
}
