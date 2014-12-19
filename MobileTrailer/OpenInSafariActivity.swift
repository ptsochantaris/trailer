// with many thanks to https://github.com/davbeck/TUSafariActivity for the example and the icon

class OpenInSafariActivity: UIActivity {

	private var _URL: NSURL?

	override func activityType() -> String? {
		return "OpenInSafariActivity"
	}

	override func activityTitle() -> String? {
		return "Open in Safari"
	}

	override func activityImage() -> UIImage? {
		return UIImage(named: "safariShare")
	}

	override func prepareWithActivityItems(activityItems: [AnyObject]) {
		for activityItem in activityItems {
			if let u = activityItem as? NSURL {
				_URL = u
				break
			}
		}
	}

	override func performActivity() {
		if let u = _URL {
			activityDidFinish(UIApplication.sharedApplication().openURL(u))
		}
	}

	override func canPerformWithActivityItems(activityItems: [AnyObject]) -> Bool {
		for activityItem in activityItems {
			if let u = activityItem as? NSURL {
				if UIApplication.sharedApplication().canOpenURL(u) {
					return true
				}
			}
		}
		return false
	}
}
