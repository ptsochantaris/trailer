
import SafariServices

final class AboutTrailerViewController: UIViewController {
	@IBOutlet weak var versionNumber: UILabel!
	@IBOutlet weak var licenseText: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()
		versionNumber.text = versionString()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		licenseText.contentOffset = CGPoint.zero
		licenseText.textContainerInset = UIEdgeInsetsMake(0, 10, 10, 10)
	}

	@IBAction func linkSelected() {
		let s = SFSafariViewController(url: URL(string: "https://github.com/ptsochantaris/trailer")!)
		s.view.tintColor = self.view.tintColor
		present(s, animated: true, completion: nil)
	}

	@IBAction func doneSelected() {
		if preferencesDirty { _ = app.startRefresh() }
		dismiss(animated: true, completion: nil)
	}
}
