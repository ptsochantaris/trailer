import Foundation

let darkModeRed = COLOR_CLASS(red: 0.9, green: 0.5, blue: 0.5, alpha: 1.0)
let darkModeYellow = COLOR_CLASS(red: 0.8, green: 0.8, blue: 0.3, alpha: 1.0)
let darkModeGreen = COLOR_CLASS(red: 0.5, green: 0.8, blue: 0.5, alpha: 1.0)

let lightModeRed = COLOR_CLASS(red: 0.7, green: 0.2, blue: 0.2, alpha: 1.0)
let lightModeYellow = COLOR_CLASS(red: 0.6, green: 0.6, blue: 0.0, alpha: 1.0)
let lightModeGreen = COLOR_CLASS(red: 0.3, green: 0.6, blue: 0.2, alpha: 1.0)

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

	var colorForDarkDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return darkModeYellow
		case "success":
			return darkModeGreen
		default:
			return darkModeRed
		}
	}

	var colorForDisplay: COLOR_CLASS {
		switch S(state) {
		case "pending":
			return lightModeYellow
		case "success":
			return lightModeGreen
		default:
			return lightModeRed
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
