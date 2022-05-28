import SafariServices

final class AboutTrailerViewController: UIViewController {
	@IBOutlet private var versionNumber: UILabel!
	@IBOutlet private var licenseText: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()
        self.navigationItem.largeTitleDisplayMode = .automatic
		versionNumber.text = versionString
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		licenseText.contentOffset = CGPoint.zero
		licenseText.textContainerInset = UIEdgeInsets(top: 0, left: 10, bottom: 10, right: 10)
	}

	@IBAction private func linkSelected() {
		let s = SFSafariViewController(url: URL(string: "https://github.com/ptsochantaris/trailer")!)
		s.view.tintColor = self.view.tintColor
		present(s, animated: true)
	}

	@IBAction private func doneSelected() {
        dismiss(animated: true)
	}
}
