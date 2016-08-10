import Foundation

final class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var targetUrl: String?

	@NSManaged var pullRequest: PullRequest

	class func syncStatusesFromInfo(_ data: [[NSObject : AnyObject]]?, pullRequest: PullRequest) {
		itemsWithInfo(data, type: "PRStatus", server: pullRequest.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				let s = item as! PRStatus
				s.state = info["state"] as? String
				s.targetUrl = info["target_url"] as? String
				s.pullRequest = pullRequest

				if let ds = info["description"] as? String {
					s.descriptionText = ds.trim()
				}
			}
		}
	}

	private let darkStatusRed = MAKECOLOR(0.8, 0.5, 0.5, 1.0)
	private let darkStatusYellow = MAKECOLOR(0.9, 0.8, 0.3, 1.0)
	private let darkStatusGreen = MAKECOLOR(0.6, 0.8, 0.6, 1.0)
	private let lightStatusRed = MAKECOLOR(0.5, 0.2, 0.2, 1.0)
	private let lightStatusYellow = MAKECOLOR(0.6, 0.5, 0.0, 1.0)
	private let lightStatusGreen = MAKECOLOR(0.3, 0.5, 0.3, 1.0)

	var colorForDarkDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return darkStatusYellow
		case "success":
			return darkStatusGreen
		default:
			return darkStatusRed
		}
	}

	var colorForDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return lightStatusYellow
		case "success":
			return lightStatusGreen
		default:
			return lightStatusRed
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
