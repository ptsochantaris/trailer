import UIKit

// with many thanks to https://github.com/davbeck/TUSafariActivity for the example and the icon

final class OpenInSafariActivity: UIActivity {
    private var _URL: URL?

    override var activityType: UIActivity.ActivityType {
        UIActivity.ActivityType("OpenInSafariActivity")
    }

    override var activityTitle: String? {
        "Open in Safari"
    }

    override var activityImage: UIImage? {
        UIImage(named: "safariShare")
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        for activityItem in activityItems {
            if let u = activityItem as? URL {
                _URL = u
                break
            }
        }
    }

    override func perform() {
        if let _URL {
            UIApplication.shared.open(_URL, options: [:]) { success in
                self.activityDidFinish(success)
            }
        }
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
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
