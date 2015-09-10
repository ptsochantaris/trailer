
import SafariServices

final class AboutTrailerViewController: UIViewController {
	@IBOutlet weak var versionNumber: UILabel!
	@IBOutlet weak var licenseText: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()
		versionNumber.text = versionString()
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		licenseText.contentOffset = CGPointZero
		licenseText.textContainerInset = UIEdgeInsetsMake(0, 10, 10, 10)
	}

	@IBAction func linkSelected() {
		let s = SFSafariViewController(URL: NSURL(string: "https://github.com/ptsochantaris/trailer")!)
		s.view.tintColor = self.view.tintColor
		self.presentViewController(s, animated: true, completion: nil)
	}

	@IBAction func doneSelected() {
		if app.preferencesDirty { app.startRefresh() }
		dismissViewControllerAnimated(true, completion: nil)
	}
}
