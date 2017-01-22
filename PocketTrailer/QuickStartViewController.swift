
import SafariServices

final class QuickStartViewController: UIViewController, UITextFieldDelegate {

	@IBOutlet weak var testButton: UIButton!
	@IBOutlet var otherViews: [UIView]!
	@IBOutlet weak var spinner: UIActivityIndicatorView!
	@IBOutlet weak var feedback: UILabel!
	@IBOutlet weak var skip: UIBarButtonItem!
	@IBOutlet weak var link: UIButton!
	@IBOutlet weak var trackIssues: UIBarButtonItem!

	private let newServer = ApiServer.allApiServers(in: DataManager.main).first!
	private var token = ""
	private var checkTimer: Timer?
	private var showIssues = true
	private var importExport: ImportExport!

    override func viewDidLoad() {
        super.viewDidLoad()
		importExport = ImportExport(parent: self)
		normalMode()
		updateSettings()
    }

	@IBAction func importSelected(_ sender: UIBarButtonItem) {
		importExport.importSelected(sender: sender)
	}

	private func updateSettings() {
		if showIssues {
			trackIssues.title = "Should track issues as well: Yes"
			trackIssues.tintColor = GLOBAL_TINT
			Settings.displayPolicyForNewIssues = RepoDisplayPolicy.all.intValue
		} else {
			trackIssues.title = "Should track issues as well: No"
			trackIssues.tintColor = .lightGray
			Settings.displayPolicyForNewIssues = RepoDisplayPolicy.hide.intValue
		}
	}

	@IBAction func willAlsoTrackSelected(_ sender: UIBarButtonItem) {
		showIssues = !showIssues
		updateSettings()
	}

	@IBAction func skipSelected(_ sender: UIBarButtonItem) {
		dismiss(animated: true)
	}

	@IBAction func openGitHubSelected(_ sender: UIButton) {
		let s = SFSafariViewController(url: URL(string: "https://github.com/settings/tokens/new")!)
		s.view.tintColor = self.view.tintColor
		self.present(s, animated: true)
	}

	@IBAction func testSelected(_ sender: UIButton) {
		testMode()
		API.testApi(to: newServer) { [weak self] error in
			guard let s = self else { return }
			if let e = error {
				showMessage("Testing the token failed - please check that you have pasted your token correctly", e.localizedDescription)
				s.normalMode()
			} else {
				s.feedback.text = "Syncing GitHub data for the first time.\n\nThis could take a little while, please wait..."
				Settings.lastSuccessfulRefresh = nil
				app.startRefreshIfItIsDue()
				s.checkTimer = Timer.scheduledTimer(timeInterval: 1.0, target: s, selector: #selector(s.checkRefreshDone), userInfo: nil, repeats: true)
			}
		}
	}

	func checkRefreshDone(t: Timer) {
		if !appIsRefreshing {
			checkTimer?.invalidate()
			checkTimer = nil
			if newServer.lastSyncSucceeded {
                dismiss(animated: true, completion: {
					popupManager.masterController.resetView()
					showMessage("Setup complete!", "You can tweak options & behaviour from the settings.\n\nTrailer has read-only access to your GitHub data, so feel free to experiment, you can't damage your data or settings on GitHub.")
                })
			} else {
				showMessage("Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly", nil)
				normalMode()
			}
		}
	}

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			view.endEditing(false)
			return false
		}
		token = S(textField.text).replacingCharacters(in: range, with: string)
		token = token.trim
		testButton.isEnabled = !token.isEmpty
		link.alpha = testButton.isEnabled ? 0.5 : 1.0
		return true
	}

	private func testMode() {
		view.endEditing(true)

		for v in otherViews {
			v.isHidden = true
		}
		skip.isEnabled = false
		spinner.startAnimating()
		feedback.text = "\nTesting the token..."

		navigationController?.setToolbarHidden(true, animated: true)

		newServer.authToken = token
		newServer.lastSyncSucceeded = true
	}

	private func normalMode() {
		feedback.text = "Quick Start"
		skip.isEnabled = true
		for v in otherViews {
			v.isHidden = false
		}
		spinner.stopAnimating()

		navigationController?.setToolbarHidden(false, animated: true)
	}
}
