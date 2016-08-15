import Foundation

final class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var targetUrl: String?

	@NSManaged var pullRequest: PullRequest

	class func syncStatuses(from data: [[String : AnyObject]]?, pullRequest: PullRequest) {
		items(with: data, type: "PRStatus", server: pullRequest.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				let s = item as! PRStatus
				s.state = info["state"] as? String
				s.targetUrl = info["target_url"] as? String
				s.pullRequest = pullRequest

				if let ds = info["description"] as? String {
					s.descriptionText = ds.trim
				}
			}
		}
	}

	private let darkStatusRed = COLOR_CLASS(red: 0.8, green: 0.5, blue: 0.5, alpha: 1.0)
	private let darkStatusYellow = COLOR_CLASS(red: 0.9, green: 0.8, blue: 0.3, alpha: 1.0)
	private let darkStatusGreen = COLOR_CLASS(red: 0.6, green: 0.8, blue: 0.6, alpha: 1.0)
	private let lightStatusRed = COLOR_CLASS(red: 0.5, green: 0.2, blue: 0.2, alpha: 1.0)
	private let lightStatusYellow = COLOR_CLASS(red: 0.6, green: 0.5, blue: 0.0, alpha: 1.0)
	private let lightStatusGreen = COLOR_CLASS(red: 0.3, green: 0.5, blue: 0.3, alpha: 1.0)

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
