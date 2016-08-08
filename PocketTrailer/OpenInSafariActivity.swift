import UIKit

// with many thanks to https://github.com/davbeck/TUSafariActivity for the example and the icon

final class OpenInSafariActivity: UIActivity {

	private var _URL: URL?

	override var activityType: String? {
		return "OpenInSafariActivity"
	}

	override var activityTitle: String? {
		return "Open in Safari"
	}

	override var activityImage: UIImage? {
		return UIImage(named: "safariShare")
	}

	override func prepare(withActivityItems activityItems: [AnyObject]) {
		for activityItem in activityItems {
			if let u = activityItem as? URL {
				_URL = u
				break
			}
		}
	}

	override func perform() {
		if let u = _URL {
			UIApplication.shared.open(u, options: [:]) { [weak self] success in
				self?.activityDidFinish(success)
			}
		}
	}

	override func canPerform(withActivityItems activityItems: [AnyObject]) -> Bool {
		for activityItem in activityItems {
			if let u = activityItem as? URL {
				if UIApplication.shared.canOpenURL(u) {
					return true
				}
			}
		}
		return false
	}
}
