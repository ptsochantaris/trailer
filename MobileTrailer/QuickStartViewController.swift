
import UIKit

class QuickStartViewController: UIViewController, UITextFieldDelegate {

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

    override func viewDidLoad() {
        super.viewDidLoad()
		normalMode()
		Settings.showIssuesMenu = true
		updateSettings()
    }

	func updateSettings() {
		if Settings.showIssuesMenu {
			trackIssues.title = "Should track issues as well: Yes"
			trackIssues.tintColor = view.tintColor
		} else {
			trackIssues.title = "Should track issues as well: No"
			trackIssues.tintColor = UIColor.lightGrayColor()
		}
	}

	@IBAction func willAlsoTrackSelected(sender: UIBarButtonItem) {
		Settings.showIssuesMenu = !Settings.showIssuesMenu
		updateSettings()
	}

	@IBAction func skipSelected(sender: UIBarButtonItem) {
		self.dismissViewControllerAnimated(true, completion: nil)
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		let targetUrl = "https://github.com/settings/tokens/new"
		if let destination = segue.destinationViewController as? GithubViewController {
			destination.pathToLoad = targetUrl
		} else if let destination = segue.destinationViewController as? UINavigationController {
			(destination.topViewController as? GithubViewController)?.pathToLoad = targetUrl
		}
	}

	@IBAction func testSelected(sender: UIButton) {
		testMode()
		api.testApiToServer(newServer, callback: { [weak self] error in
			if let e = error {
				let a = UIAlertView(
					title: "Testing the token failed - please check that you have pasted your token correctly",
					message: e.localizedDescription,
					delegate: nil,
					cancelButtonTitle: "OK")
				a.show()
				self!.normalMode()
			} else {
				self!.feedback.text = "Syncing your GitHub info for the first time.\n\nThis could take a little while, please wait..."
				Settings.lastSuccessfulRefresh = nil
				app.startRefreshIfItIsDue()
				self!.checkTimer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self!, selector: Selector("checkRefreshDone:"), userInfo: nil, repeats: true)
			}
		})
	}

	func checkRefreshDone(t: NSTimer) {
		if !app.isRefreshing {
			checkTimer?.invalidate()
			checkTimer = nil
			if newServer.lastSyncSucceeded?.boolValue ?? false {
				UIAlertView(
					title: "Setup complete!",
					message: "You can tweak settings & behaviour from the settings.\n\nTrailer will only read from your Github data, so feel free to experiment with settings and options, you can't damage your data or settings on GitHub.",
					delegate: nil,
					cancelButtonTitle: "OK").show()
				dismissViewControllerAnimated(true, completion: nil)
			} else {
				UIAlertView(
					title: "Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly",
					message: nil,
					delegate: nil,
					cancelButtonTitle: "OK").show()
				self.normalMode()
			}
		}
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			view.endEditing(false)
			return false
		}
		token = (textField.text as NSString).stringByReplacingCharactersInRange(range, withString: string)
		token = token.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		testButton.enabled = !token.isEmpty
		link.alpha = testButton.enabled ? 0.5 : 1.0
		return true
	}

	private func testMode() {
		self.view.endEditing(true)

		for v in otherViews {
			v.hidden = true
		}
		skip.enabled = false
		spinner.startAnimating()
		feedback.text = "\nTesting the token..."

		navigationController?.setToolbarHidden(true, animated: true)

		api.resetBadLinks()
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
