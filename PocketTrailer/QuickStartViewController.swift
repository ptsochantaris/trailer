
import SafariServices

final class QuickStartViewController: UIViewController, UITextFieldDelegate {

	@IBOutlet weak var testButton: UIButton!
	@IBOutlet var otherViews: [UIView]!
	@IBOutlet weak var spinner: UIActivityIndicatorView!
	@IBOutlet weak var feedback: UILabel!
	@IBOutlet weak var skip: UIBarButtonItem!
	@IBOutlet weak var link: UIButton!
	@IBOutlet weak var trackIssues: UIBarButtonItem!

	private let newServer = ApiServer.allApiServersInMoc(mainObjectContext).first!
	private var token = ""
	private var checkTimer: NSTimer?
	private var showIssues = true

    override func viewDidLoad() {
        super.viewDidLoad()
		normalMode()
		updateSettings()
    }

	private func updateSettings() {
		if showIssues {
			trackIssues.title = "Should track issues as well: Yes"
			trackIssues.tintColor = GLOBAL_TINT
			Settings.displayPolicyForNewIssues = RepoDisplayPolicy.All.rawValue
		} else {
			trackIssues.title = "Should track issues as well: No"
			trackIssues.tintColor = UIColor.lightGrayColor()
			Settings.displayPolicyForNewIssues = RepoDisplayPolicy.Hide.rawValue
		}
	}

	@IBAction func willAlsoTrackSelected(sender: UIBarButtonItem) {
		showIssues = !showIssues
		updateSettings()
	}

	@IBAction func skipSelected(sender: UIBarButtonItem) {
		dismissViewControllerAnimated(true, completion: nil)
	}

	@IBAction func openGitHubSelected(sender: AnyObject) {
		let s = SFSafariViewController(URL: NSURL(string: "https://github.com/settings/tokens/new")!)
		s.view.tintColor = self.view.tintColor
		self.presentViewController(s, animated: true, completion: nil)
	}

	@IBAction func testSelected(sender: UIButton) {
		testMode()
		api.testApiToServer(newServer) { [weak self] error in
			if let s = self {
				if let e = error {
					showMessage("Testing the token failed - please check that you have pasted your token correctly", e.localizedDescription)
					s.normalMode()
				} else {
					s.feedback.text = "Syncing GitHub data for the first time.\n\nThis could take a little while, please wait..."
					Settings.lastSuccessfulRefresh = nil
					app.startRefreshIfItIsDue()
					s.checkTimer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: s, selector: #selector(QuickStartViewController.checkRefreshDone(_:)), userInfo: nil, repeats: true)
				}
			}
		}
	}

	func checkRefreshDone(t: NSTimer) {
		if !appIsRefreshing {
			checkTimer?.invalidate()
			checkTimer = nil
			if newServer.lastSyncSucceeded?.boolValue ?? false {
                dismissViewControllerAnimated(true, completion: {
                    popupManager.getMasterController().updateTabBarVisibility(true)
					showMessage("Setup complete!", "You can tweak options & behaviour from the settings.\n\nTrailer has read-only access to your GitHub data, so feel free to experiment, you can't damage your data or settings on GitHub.")
                })
			} else {
				showMessage("Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly", nil)
				normalMode()
			}
		}
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			view.endEditing(false)
			return false
		}
		token = S(textField.text).stringByReplacingCharactersInRange(range, withString: string)
		token = token.trim()
		testButton.enabled = !token.isEmpty
		link.alpha = testButton.enabled ? 0.5 : 1.0
		return true
	}

	private func testMode() {
		view.endEditing(true)

		for v in otherViews {
			v.hidden = true
		}
		skip.enabled = false
		spinner.startAnimating()
		feedback.text = "\nTesting the token..."

		navigationController?.setToolbarHidden(true, animated: true)

		newServer.authToken = token
		newServer.lastSyncSucceeded = true
	}

	private func normalMode() {
		feedback.text = "Quick Start"
		skip.enabled = true
		for v in otherViews {
			v.hidden = false
		}
		spinner.stopAnimating()

		navigationController?.setToolbarHidden(false, animated: true)
	}
}
