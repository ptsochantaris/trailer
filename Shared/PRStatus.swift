import Foundation

final class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var targetUrl: String?

	@NSManaged var pullRequest: PullRequest

	class func syncStatuses(from data: [[AnyHashable : Any]]?, pullRequest: PullRequest) {
		items(with: data, type: PRStatus.self, server: pullRequest.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				item.state = info["state"] as? String
				item.targetUrl = info["target_url"] as? String
				item.pullRequest = pullRequest

				if let ds = info["description"] as? String {
					item.descriptionText = ds.trim
				}
			}
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
		if let desc = descriptionText {
			let prefix: String
			switch S(state) {
			case "pending":
				prefix = "⚡️"
			case "success":
				prefix = "✅"
			default:
				prefix = "❌"
			}
			return String(format: "%@ %@ %@", prefix, shortDateFormatter.string(from: createdAt!), desc)
		} else {
			return "(No description)"
		}
	}

	var parentShouldSkipNotifications: Bool {
		return pullRequest.shouldSkipNotifications
	}
}
