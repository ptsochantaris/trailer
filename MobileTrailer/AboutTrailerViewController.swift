
import UIKit

class AboutTrailerViewController: UIViewController {
	@IBOutlet var versionNumber: UILabel!
	@IBOutlet var licenseText: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()
        var buildNumber = NSBundle.mainBundle().infoDictionary!["CFBundleVersion"] as String
		versionNumber.text = "\(currentAppVersion) (\(buildNumber))";
		licenseText.textContainerInset = UIEdgeInsetsMake(0, 10, 10, 10)
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		licenseText.contentOffset = CGPointZero
	}

	@IBAction func linkSelected() {
		UIApplication.sharedApplication().openURL(NSURL(string: "https://github.com/ptsochantaris/trailer")!)
	}

	@IBAction func doneSelected() {
		if app.preferencesDirty { app.startRefresh() }
		dismissViewControllerAnimated(true, completion: nil)
	}
}
