import Foundation

final class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
	@NSManaged var context: String?
    @NSManaged var targetUrl: String?

	@NSManaged var pullRequest: PullRequest

	class func syncStatuses(from data: [[AnyHashable : Any]]?, pullRequest: PullRequest) {
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

	private static let darkStatusRed = COLOR_CLASS(red: 0.8, green: 0.5, blue: 0.5, alpha: 1.0)
	private static let darkStatusYellow = COLOR_CLASS(red: 0.9, green: 0.8, blue: 0.3, alpha: 1.0)
	private static let darkStatusGreen = COLOR_CLASS(red: 0.6, green: 0.8, blue: 0.6, alpha: 1.0)
	var colorForDarkDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return PRStatus.darkStatusYellow
		case "success":
			return PRStatus.darkStatusGreen
		default:
			return PRStatus.darkStatusRed
		}
	}

	private static let lightStatusRed = COLOR_CLASS(red: 0.5, green: 0.2, blue: 0.2, alpha: 1.0)
	private static let lightStatusYellow = COLOR_CLASS(red: 0.6, green: 0.5, blue: 0.0, alpha: 1.0)
	private static let lightStatusGreen = COLOR_CLASS(red: 0.3, green: 0.5, blue: 0.3, alpha: 1.0)
	var colorForDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return PRStatus.lightStatusYellow
		case "success":
			return PRStatus.lightStatusGreen
		default:
			return PRStatus.lightStatusRed
		}
	}

	var displayText: String {
		var text: String

		switch S(state) {
		case "pending":
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
